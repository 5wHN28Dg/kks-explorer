package kks.explorer.sync

import android.util.Log
import kks.explorer.core.Core
import kks.explorer.core.Net
import kks.explorer.core.WsClient
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.security.SecureRandom
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

/**
 * Sync across the internet (PROTOCOL-v2 §18), the twin of platform/linux/src/kksl/internet.nim: presence in the
 * plant's room on the relay (the hello is signed by the core with the device key), and syncs directly when hole
 * punching works (Direct.kt: STUN, punching, the core's reliable UDP), else through a relay pipe; either way the
 * stream carries the same TLS as on the Wi-Fi. Runs on its own threads.
 */
object Internet {
    @Volatile var state = "off"; private set           // off, connecting, online, or what went wrong
    val online: MutableSet<String> = ConcurrentHashMap.newKeySet()
    private val waiting = ConcurrentHashMap<String, LinkedBlockingQueue<JSONObject>>()
    @Volatile private var ws: WsClient? = null
    @Volatile private var room = ""
    @Volatile private var relay = ""
    @Volatile private var running = false
    private var thread: Thread? = null
    var onSynced: ((String, JSONObject) -> Unit)? = null
    var onChange: (() -> Unit)? = null
    /** automatic use of the network now (metered networks only when the person allowed them; "Sync now" overrides) */
    @Volatile var allowed: () -> Boolean = { true }
    @Volatile private var forced = 0L
    private val rng = SecureRandom()
    @Volatile var direct = true                    // try hole punching first (tests can force the pipe)
    @Volatile var lastHow = ""                     // "direct" or "relay": how the last sync went (the status)

    private fun changed() { runCatching { onChange?.invoke() } }

    @Synchronized fun start() {
        if (running) return
        running = true
        thread = Thread(::presence, "kks-relay").apply { isDaemon = true; start() }
    }

    @Synchronized fun stop() {
        running = false
        ws?.close()
        thread = null
    }

    /** the relay setting changed: leave the room now; the presence loop comes back with the new address */
    fun restart() { ws?.close() }

    fun configured(): Boolean = Sync.config().optString("relay_url").isNotEmpty()

    /** wait up to ms for the room's welcome; true when online */
    fun awaitOnline(ms: Long): Boolean {
        forced = System.currentTimeMillis() + 120_000      // a person asked: stay online a while even on a metered network
        val end = System.currentTimeMillis() + ms
        while (state != "online" && System.currentTimeMillis() < end) Thread.sleep(100)
        return state == "online"
    }

    private fun presence() {
        var pause = 5_000L
        while (running) {
            if (!allowed() && System.currentTimeMillis() > forced) {       // e.g. on mobile data with metered syncs off
                if (state != "off") { state = "off"; online.clear(); changed() }
                sleepWhileRunning(1_000); continue
            }
            val r = try { Core.api("POST", "/native/relay").json } catch (e: Exception) { JSONObject() }
            val url = r.optString("relay")
            if (url.isEmpty()) {
                if (state != "off") { state = "off"; online.clear(); changed() }
                sleepWhileRunning(10_000); continue
            }
            relay = url; room = r.getString("room")
            state = "connecting"
            var w: WsClient? = null
            try {
                w = WsClient("$url/v1/room/$room")
                ws = w
                w.setTimeout(60_000)          // a pong comes every 25 s; silence this long = a dead connection
                w.sendText(r.getJSONObject("hello").toString())
                pause = 5_000
                val pinger = Thread({
                    try { while (!w.closed) { Thread.sleep(25_000); w.sendText("{\"t\":\"ping\"}") } } catch (e: Exception) {}
                }, "kks-relay-ping").apply { isDaemon = true; start() }
                while (running) {
                    val (op, data) = w.recv()
                    if (op == WsClient.TEXT) handle(JSONObject(String(data, Charsets.UTF_8)))
                    if (Sync.config().optString("relay_url") != url) break
                }
                w.close(); pinger.interrupt()
            } catch (e: Exception) {
                if (!running) break
                state = "relay unreachable: ${e.message}"
                Log.w("KKSSync", "relay: ${e.message}")
                online.clear(); changed()
                w?.close()
                sleepWhileRunning(pause)
                pause = minOf(pause * 2, 60_000)
            }
        }
        state = "off"; online.clear(); changed()
    }

    private fun sleepWhileRunning(ms: Long) {
        val end = System.currentTimeMillis() + ms
        while (running && System.currentTimeMillis() < end) Thread.sleep(200)
    }

    private fun handle(m: JSONObject) {
        when (m.optString("t")) {
            "welcome" -> {
                online.clear()
                val a = m.optJSONArray("peers") ?: JSONArray()
                for (i in 0 until a.length()) online.add(a.getString(i))
                state = "online"; Log.i("KKSSync", "relay: online, ${online.size} other devices"); changed()
            }
            "joined" -> { online.add(m.getString("peer")); changed() }
            "left" -> { online.remove(m.getString("peer")); changed() }
            "connect" -> {
                val from = m.optString("from"); val id = m.optString("id")
                if (from.isNotEmpty() && id.isNotEmpty()) Thread({ serve(from, id, cands(m)) }, "kks-relay-in").start()
            }
            "accept", "refuse", "gone" -> waiting.remove(m.optString("id"))?.offer(m)
            "error" -> { state = "relay error: ${m.optString("why")}"; changed() }
        }
    }

    private fun send(j: JSONObject) = (ws ?: throw IllegalStateException("not on the relay")).sendText(j.toString())

    private fun cands(m: JSONObject): List<String> {
        val a = m.optJSONArray("cand") ?: return emptyList()
        return (0 until minOf(a.length(), 8)).mapNotNull { a.opt(it) as? String }.filter { it.length <= 64 }
    }

    private fun ours(tryDirect: Boolean = direct): Pair<Direct.Udp?, List<String>> =
        if (!tryDirect) null to emptyList() else try { Direct.candidates() } catch (e: Exception) { null to emptyList() }

    /** devices the direct path failed with, until when (ms): their syncs go through the pipe meanwhile */
    private val noDirectUntil = ConcurrentHashMap<String, Long>()
    private const val NO_DIRECT_MS = 3600_000L
    private const val MAX_SERVED = 8   // syncs answered through the relay at once (desktop: internet.nim MaxServed)
    private val serving = java.util.concurrent.atomic.AtomicInteger()

    /** a sync that went direct and failed there: its caller retries through the pipe */
    private class DirectFailed(e: Exception) : IOException(e.message, e)

    /** §18: hole punching when both sides offered candidates, else (or when it fails) the relay pipe -> the connection
     *  and how it goes, "direct" or "relay": each sync's own for its fallback (lastHow is the status's, and a sync
     *  answered meanwhile can overwrite it) */
    private fun meet(u: Direct.Udp?, ours: List<String>, theirs: List<String>, id: String, client: Boolean, expect: String,
                     peer: String): Pair<Net.Peer, String> {
        if (u != null && ours.isNotEmpty() && theirs.isNotEmpty()) {
            val session = Direct.session(id)
            val at = Direct.punch(u, session, theirs)
            if (at != null) {
                lastHow = "direct"
                return try { Direct.connect(u, at, session, client, expect) to "direct" } catch (e: Exception) { throw DirectFailed(e) }
            }
            // nothing came through: two NATs that can't be punched (2026-10-04: a carrier NAT with a new port per
            // destination against a home router that only lets in the exact address it sent to). Don't spend the 4 s
            // on this device for an hour.
            if (peer.isNotEmpty()) noDirectUntil[peer] = System.currentTimeMillis() + NO_DIRECT_MS
        }
        u?.close()
        lastHow = "relay"
        return Net.overPipe(WsClient("$relay/v1/pipe/$room/$id/${if (client) "a" else "b"}"), client = client, expectPeer = expect) to "relay"
    }

    /** another device asked for a sync: accept with our candidates, meet it (directly or in the pipe), answer as the TLS server */
    private fun serve(from: String, id: String, theirs: List<String>) {
        // anyone with a key can ask through the relay (issue #67, #30): a few at a time
        if (serving.incrementAndGet() > MAX_SERVED) {
            serving.decrementAndGet()
            runCatching { send(JSONObject().put("t", "refuse").put("to", from).put("id", id)) }
            return
        }
        try {
            val (u, ours) = ours(direct && (noDirectUntil[from] ?: 0L) < System.currentTimeMillis())    // [] = the pipe at once
            send(JSONObject().put("t", "accept").put("to", from).put("id", id).put("cand", JSONArray(ours)))
            val (p, _) = meet(u, ours, theirs, id, client = false, expect = "", peer = from)
            val dog = Net.watch(java.io.Closeable { p.close() })
            try {
                val st = Net.drive(p, false, dog = dog)
                Log.i("KKSSync", "relay sync ($lastHow) from ${p.remote.take(8)}: sent ${st.optInt("sent")}, received ${st.optInt("received")}")
                onSynced?.invoke(p.remote, st)
            } finally { dog.cancel(false); p.close() }
        } catch (e: Exception) { Log.w("KKSSync", "relay: answering ${from.take(8)} failed: ${e.message}") }
        finally { serving.decrementAndGet() }
    }

    /** sync with a device of the plant that is on the relay: connect with our candidates, then direct or the pipe (side a).
     *  A direct path can punch through and then stall (found 2026-10-03 with two phones on mobile data: every sync
     *  died with "the other device stopped answering"). So when a direct sync fails, the same sync runs again at once
     *  through the pipe, and that device gets the pipe for an hour (PROTOCOL-v2 §18: "on failure, the pipe"). */
    fun syncPeer(peer: String): JSONObject {
        val tryDirect = direct && (noDirectUntil[peer] ?: 0L) < System.currentTimeMillis()
        return try { attempt(peer, tryDirect) } catch (e: Exception) {
            if (e !is DirectFailed) throw e
            noDirectUntil[peer] = System.currentTimeMillis() + NO_DIRECT_MS
            Log.w("KKSSync", "direct sync with ${peer.take(8)} failed (${e.message}): the relay pipe for this device for an hour")
            attempt(peer, false)
        }
    }

    private fun attempt(peer: String, tryDirect: Boolean): JSONObject {
        if (state != "online") throw IllegalStateException("not on the relay")
        val id = ByteArray(16).also { rng.nextBytes(it) }.joinToString("") { "%02x".format(it) }
        val q = LinkedBlockingQueue<JSONObject>()
        waiting[id] = q
        val (u, ours) = ours(tryDirect)
        lastHow = ""
        send(JSONObject().put("t", "connect").put("to", peer).put("id", id).put("cand", JSONArray(ours)))
        val a = q.poll(15, TimeUnit.SECONDS)
        waiting.remove(id)
        when (a?.optString("t")) {
            null -> { u?.close(); throw IllegalStateException("no answer through the relay") }
            "gone" -> { u?.close(); throw IllegalStateException("the device is not on the relay") }
            "refuse" -> { u?.close(); throw IllegalStateException("the device refused") }
        }
        val (p, how) = meet(u, ours, cands(a!!), id, client = true, expect = peer, peer = peer)
        try {
            val st = try { Net.drive(p, true) } catch (e: Exception) { throw if (how == "direct") DirectFailed(e) else e }
            Log.i("KKSSync", "relay sync ($how) with ${peer.take(8)}: sent ${st.optInt("sent")}, received ${st.optInt("received")}")
            onSynced?.invoke(peer, st)
            return st
        } finally { p.close() }
    }
}

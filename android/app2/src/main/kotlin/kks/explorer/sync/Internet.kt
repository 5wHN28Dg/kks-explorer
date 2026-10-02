package kks.explorer.sync

import android.util.Log
import kks.explorer.core.Core
import kks.explorer.core.Net
import kks.explorer.core.WsClient
import org.json.JSONArray
import org.json.JSONObject
import java.security.SecureRandom
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

/**
 * Sync across the internet (PROTOCOL-v2 §18), the twin of platform/linux/src/kksl/internet.nim: presence in the
 * plant's room on the relay (the hello is signed by the core with the device key), and syncs through a relay pipe
 * carrying the same TLS as on the Wi-Fi. No hole punching yet: this side offers no candidates, so both go straight
 * to the pipe. Runs on its own threads.
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
                if (from.isNotEmpty() && id.isNotEmpty()) Thread({ serve(from, id) }, "kks-relay-in").start()
            }
            "accept", "refuse", "gone" -> waiting.remove(m.optString("id"))?.offer(m)
            "error" -> { state = "relay error: ${m.optString("why")}"; changed() }
        }
    }

    private fun send(j: JSONObject) = (ws ?: throw IllegalStateException("not on the relay")).sendText(j.toString())

    /** another device asked for a sync: accept with no candidates, meet it in the pipe, answer as the TLS server */
    private fun serve(from: String, id: String) {
        try {
            send(JSONObject().put("t", "accept").put("to", from).put("id", id).put("cand", JSONArray()))
            val p = Net.overPipe(WsClient("$relay/v1/pipe/$room/$id/b"), client = false, expectPeer = "")
            try {
                val st = Net.drive(p, false)
                Log.i("KKSSync", "relay sync from ${p.remote.take(8)}: sent ${st.optInt("sent")}, received ${st.optInt("received")}")
                onSynced?.invoke(p.remote, st)
            } finally { p.close() }
        } catch (e: Exception) { Log.w("KKSSync", "relay: answering ${from.take(8)} failed: ${e.message}") }
    }

    /** sync with a device of the plant that is on the relay: connect (no candidates), then the pipe as side a */
    fun syncPeer(peer: String): JSONObject {
        if (state != "online") throw IllegalStateException("not on the relay")
        val id = ByteArray(16).also { rng.nextBytes(it) }.joinToString("") { "%02x".format(it) }
        val q = LinkedBlockingQueue<JSONObject>()
        waiting[id] = q
        send(JSONObject().put("t", "connect").put("to", peer).put("id", id).put("cand", JSONArray()))
        val a = q.poll(15, TimeUnit.SECONDS)
        waiting.remove(id)
        when (a?.optString("t")) {
            null -> throw IllegalStateException("no answer through the relay")
            "gone" -> throw IllegalStateException("the device is not on the relay")
            "refuse" -> throw IllegalStateException("the device refused")
        }
        val p = Net.overPipe(WsClient("$relay/v1/pipe/$room/$id/a"), client = true, expectPeer = peer)
        try {
            val st = Net.drive(p, true)
            onSynced?.invoke(peer, st)
            return st
        } finally { p.close() }
    }
}

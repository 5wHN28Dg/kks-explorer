package kks.explorer.sync

import android.content.Context
import android.net.ConnectivityManager
import android.os.Build
import android.util.Log
import kks.explorer.App
import kks.explorer.core.Core
import kks.explorer.core.Net
import org.json.JSONArray
import org.json.JSONObject
import java.net.Inet4Address
import java.net.NetworkInterface
import java.net.URI
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

/**
 * The phone's sync service (PROTOCOL-v2 §15/§16; the v1 PhoneSync, rebuilt on the core): joining, the listener,
 * mDNS, remembered addresses, automatic rounds. Network work runs on its own threads; the core is called through Core.
 */
object Sync {
    data class Seen(var host: String, var port: Int, var lastOk: Long = 0, var error: String = "")
    val peers = ConcurrentHashMap<String, Seen>()
    private val pool = Executors.newScheduledThreadPool(2)
    @Volatile var port = 0
    @Volatile private var started = false
    @Volatile var syncing = false
    @Volatile var lastRound = 0L
    private var auto: ScheduledFuture<*>? = null
    private var soon: ScheduledFuture<*>? = null
    const val INTERVAL = 120L          // s between automatic rounds while on screen
    const val AFTER_CHANGE = 5L        // s after a local change

    fun config(): JSONObject = Core.api("GET", "/native/config").json
    fun device(): String = config().optString("device")
    fun joined(): Boolean = config().optJSONObject("node")?.optBoolean("joined") == true
    fun label() = (Build.MODEL ?: "phone").take(80)

    private fun prefs(ctx: Context) = ctx.getSharedPreferences("sync", Context.MODE_PRIVATE)

    fun remember(ctx: Context, host: String, port: Int, peer: String) {
        val p = prefs(ctx)
        val arr = JSONArray(p.getString("peers", "[]"))
        val entry = "$host:$port@$peer"
        val list = (0 until arr.length()).map { arr.getString(it) }.filter { !it.endsWith("@$peer") } + entry
        p.edit().putString("peers", JSONArray(list.takeLast(20)).toString()).apply()
    }

    private fun remembered(ctx: Context): List<Triple<String, Int, String>> {
        val arr = JSONArray(prefs(ctx).getString("peers", "[]"))
        return (0 until arr.length()).mapNotNull {
            val s = arr.getString(it); val at = s.lastIndexOf('@'); val colon = s.lastIndexOf(':', at)
            if (at > 0 && colon > 0) Triple(s.substring(0, colon), s.substring(colon + 1, at).toInt(), s.substring(at + 1)) else null
        }
    }

    /** "host", "host:port" (the sync port) or a web address (its host, the default sync port) */
    fun serverAddress(text: String): Pair<String, Int> {
        val t = text.trim()
        if ("://" in t) return (try { URI(t).host } catch (e: Exception) { null } ?: "") to 8421
        val i = t.lastIndexOf(':')
        val p = if (i > 0) t.substring(i + 1).toIntOrNull() else null
        return if (p != null) t.substring(0, i) to p else t to 8421
    }

    private fun joinedNow(ctx: Context, host: String, port: Int, peer: String) {
        remember(ctx, host, port, peer)
        peers[peer] = Seen(host, port, System.currentTimeMillis())
        App.clearRemovedNote(ctx)
        report(ctx)
    }

    // ------------------------------------------------------------------ joining (§16)

    /** join through the plant's server (the password goes over TLS, never in clear text); "" when joined, else what went wrong */
    fun joinServer(ctx: Context, address: String, username: String, password: String): String {
        if (joined()) return "this phone already belongs to a plant"
        val (host, port) = serverAddress(address)
        if (host.isEmpty()) return "enter the server's address, e.g. 192.168.1.20"
        val req = Core.api("POST", "/native/join-request", JSONObject().put("username", username).put("full_name", username)).json
        val ack = try {
            Net.ask(host, port, "", JSONObject().put("t", "enroll").put("username", username).put("password", password).put("request", req))
        } catch (e: Exception) { return "cannot reach $host:$port: ${e.message}" }
        if (ack.optString("state") != "accepted") return ack.optString("why").ifEmpty { "the server refused" }
        val server = ack.getString("server")
        try {
            Net.syncWith(host, port, server, adoptRoot = if (config().optString("root").isEmpty()) ack.getString("root") else "")
        } catch (e: Exception) {
            return "the server certified this phone, but syncing failed: ${e.message}. Try Sync now later."
        }
        if (!joined()) return "synced, but this phone is not certified in what came back"
        joinedNow(ctx, host, port, server)
        return ""
    }

    /** an invite as an admin's device shows it (QR or text): null if the text isn't one */
    fun parseInvite(text: String): JSONObject? = try {
        JSONObject(text.trim()).takeIf { it.has("kks_invite") && it.has("peer") && it.has("addrs") && it.has("token") && it.has("root") }
    } catch (e: Exception) { null }

    /** one join attempt: by invite (token) or in an admin's lobby (no token, the 6-digit code is compared) */
    class Join(val hosts: List<Pair<String, Int>>, val peer: String, val token: String?, username: String, fullName: String) {
        val request: JSONObject = Core.api("POST", "/native/join-request", JSONObject().put("username", username).put("full_name", fullName)).json
        var host = ""; var port = 0
        var root = ""
        val code: String get() = Core.api("POST", "/native/join-code", JSONObject().put("admin", peer)).json.optString("code")

        private fun ask(h: String, p: Int): JSONObject =
            Net.ask(h, p, peer, JSONObject().put("t", "join").put("token", token ?: JSONObject.NULL).put("request", request))

        /** ask until the admin decides (every 2 s while waiting); status gets what to show. -> the final join_ack */
        fun await(status: (String) -> Unit, cancelled: () -> Boolean): JSONObject {
            var ack: JSONObject? = null
            for ((h, p) in hosts) {
                try { ack = ask(h, p); host = h; port = p; break } catch (e: Exception) { Log.w("KKSSync", "join via $h:$p: ${e.message}") }
            }
            if (ack == null) return JSONObject().put("state", "unreachable").put("why", "None of the device's addresses answered. Are you on the same Wi-Fi?")
            status(if (token == null) "Code $code: tell the admin. Waiting for them to accept…" else "Waiting for the admin to accept…")
            while (ack!!.optString("state") == "waiting") {
                if (cancelled()) return JSONObject().put("state", "cancelled")
                Thread.sleep(2000)
                ack = try { ask(host, port) } catch (e: Exception) { return JSONObject().put("state", "lost").put("why", "Lost the connection: ${e.message}") }
            }
            root = ack.optString("root")
            return ack
        }

        /** after "accepted" (and, in the lobby, after the person confirmed the code): the first sync adopts the plant */
        fun finish(ctx: Context): String {
            try { Net.syncWith(host, port, peer, adoptRoot = if (config().optString("root").isEmpty()) root else "") }
            catch (e: Exception) { return "Accepted, but the first sync failed: ${e.message}. Try again." }
            if (!joined()) return "Synced, but this phone is not certified in what came back."
            joinedNow(ctx, host, port, peer)
            return ""
        }
    }

    fun inviteJoin(inv: JSONObject, username: String, fullName: String): Join {
        val a = inv.getJSONArray("addrs")
        val hosts = (0 until a.length()).mapNotNull { serverAddress(a.getString(it)).takeIf { it.first.isNotEmpty() } }
        return Join(hosts, inv.getString("peer"), inv.getString("token"), username, fullName)
    }

    fun lobbyJoin(f: Discovery.Found, username: String, fullName: String) = Join(listOf(f.host to f.port), f.peer, null, username, fullName)

    /** admins' devices on this Wi-Fi (TXT adm=1) */
    fun adminsNearby(): List<Discovery.Found> { val me = device(); return Discovery.found().filter { it.admin && it.peer.isNotEmpty() && it.peer != me } }

    /** a bundle file from an admin; "" when this phone now belongs to the plant */
    fun importBundle(ctx: Context, raw: ByteArray): String {
        val r = Core.api("POST", "/native/bundle", JSONObject().put("data", android.util.Base64.encodeToString(raw, android.util.Base64.NO_WRAP)))
        if (r.status >= 400) return r.json.optString("error", "not a KKS Explorer bundle")
        if (!joined()) return "The bundle was imported, but this phone is not certified in it yet."
        App.clearRemovedNote(ctx)
        report(ctx)
        return ""
    }

    // ------------------------------------------------------------------ rounds

    /** one round: devices found on the Wi-Fi of this plant, then remembered addresses; returns how many were reached */
    private val round = java.util.concurrent.locks.ReentrantLock()

    /** wait: a person pressed Sync (wait for a running round, then run one); else skip if one is running */
    fun syncAll(ctx: Context, wait: Boolean = false): Int {
        if (!joined()) return 0
        if (wait) round.lock() else if (!round.tryLock()) return 0   // a round runs already (timer, change, discovery, worker)
        syncing = true
        try {
            var n = 0
            val me = device()
            val rootId = config().optJSONObject("txt")?.optString("root") ?: ""
            val targets = Discovery.found().filter { it.root == rootId }.map { Triple(it.host, it.port, it.peer) } + remembered(ctx)
            val done = HashSet<String>()
            val started = System.currentTimeMillis()
            val lan = onLan(ctx)
            for ((host, port, peer) in targets) {
                if (peer.isEmpty() || peer == me || peer in done) continue
                if (!lan && privateAddress(host)) continue      // on mobile data a LAN address can only time out
                val seen = peers.getOrPut(peer) { Seen(host, port) }
                try {
                    val st = Net.syncWith(host, port, peer)
                    seen.lastOk = System.currentTimeMillis(); seen.error = ""; seen.host = host; seen.port = port
                    Log.i("KKSSync", "synced with $host:$port: sent ${st.optInt("sent")}, received ${st.optInt("received")}")
                    done.add(peer)
                    n++
                } catch (e: Exception) {
                    seen.error = e.message ?: "failed"
                    Log.w("KKSSync", "sync with $host:$port: ${e.message}")
                }
            }
            // then the devices on the relay (§18) that no Wi-Fi sync reached and that did not sync with us meanwhile;
            // a person's "Sync now" goes online for it even where automatic syncs stay off (metered networks)
            if (wait && Internet.state != "online" && Internet.configured()) { Internet.start(); Internet.awaitOnline(8_000) }
            if (Internet.state == "online") {
                for (peer in Internet.online.toList()) {
                    if (peer in done || peer == me || (peers[peer]?.lastOk ?: 0) >= started) continue
                    try {
                        val st = Internet.syncPeer(peer)
                        Log.i("KKSSync", "synced through the relay with ${peer.take(8)}: sent ${st.optInt("sent")}, received ${st.optInt("received")}")
                        n++
                    } catch (e: Exception) {
                        peers.getOrPut(peer) { Seen("relay", 0) }.error = e.message ?: "failed"
                        Log.w("KKSSync", "relay sync with ${peer.take(8)}: ${e.message}")
                    }
                }
            }
            lastRound = System.currentTimeMillis()
            return n
        } finally {
            syncing = false
            round.unlock()
            report(ctx)
        }
    }

    private fun addresses(port: Int): List<String> = try {
        NetworkInterface.getNetworkInterfaces().toList().filter { it.isUp && !it.isLoopback }
            .flatMap { it.inetAddresses.toList() }.filterIsInstance<Inet4Address>().map { "${it.hostAddress}:$port" }
    } catch (e: Exception) { emptyList() }

    /** tell the core our port, addresses and status (invites carry the addresses; Manage → Devices shows the status) */
    fun report(ctx: Context) {
        val devs = JSONObject()
        var lastOk = 0L
        for ((d, p) in peers) {
            lastOk = maxOf(lastOk, p.lastOk)
            devs.put(d, JSONObject().put("host", p.host).put("last_ok", p.lastOk / 1000).put("error", p.error.ifEmpty { null } ?: JSONObject.NULL))
        }
        val snap = JSONObject().put("devices", devs).put("last_ok", if (lastOk > 0) lastOk / 1000 else JSONObject.NULL)
            .put("syncing", syncing).put("port", if (port > 0) port else JSONObject.NULL)
            .put("relay", Internet.state).put("relay_online", Internet.online.size)
        Core.api("POST", "/native/net", JSONObject().put("port", port).put("addrs", JSONArray(addresses(port))).put("snapshot", snap))
        announce(ctx)
    }

    private fun announce(ctx: Context) {
        if (port == 0 || !App.visible) return
        val txt = config().optJSONObject("txt") ?: return
        val m = txt.keys().asSequence().associateWith { txt.getString(it) }
        Discovery.announce(ctx, "kks-" + m["peer"].orEmpty().take(12), port, m)
    }

    /** the listener (always, once started) and the change hook */
    fun start(ctx: Context) {
        if (started) return
        started = true
        pool.execute {
            try {
                val server = Net.listen(8421) { remote, _ -> peers.getOrPut(remote) { Seen("", 0) }.lastOk = System.currentTimeMillis(); report(ctx) }
                port = server.localPort
                report(ctx)
            } catch (e: Exception) { Log.w("KKSSync", "listener: ${e.message}") }
        }
        Core.listeners.add { why ->
            if (why == "local" || why == "adopted") {      // received data is passed on by the normal rounds
                soon?.cancel(false)
                soon = pool.schedule({ runCatching { syncAll(ctx) } }, AFTER_CHANGE, TimeUnit.SECONDS)
            }
            pool.execute { runCatching { report(ctx) } }      // a new role or plant changes the TXT
        }
        Internet.allowed = { SyncWorker.metered(ctx) || unmetered(ctx) }
        Internet.onSynced = { remote, _ ->
            peers.getOrPut(remote) { Seen("relay", 0) }.apply { host = "relay"; port = 0; lastOk = System.currentTimeMillis(); error = "" }
            pool.execute { runCatching { report(ctx) } }
        }
        var seenOnline = 0
        Internet.onChange = {
            val n = Internet.online.size
            if (n > seenOnline) pool.schedule({ runCatching { syncAll(ctx) } }, 1, TimeUnit.SECONDS)   // a device came online
            seenOnline = n
            pool.execute { runCatching { report(ctx) } }
        }
        Discovery.onFound = { f ->
            val mine = runCatching { config().optJSONObject("txt")?.optString("root") }.getOrNull()
            if (f.root.isNotEmpty() && f.root == mine && !peers.containsKey(f.peer)) pool.schedule({ runCatching { syncAll(ctx) } }, 1, TimeUnit.SECONDS)
        }
    }

    /** on screen: discovery, announce and rounds every 2 minutes; off screen they stop (SyncWorker runs then) */
    @Synchronized fun foreground(ctx: Context, on: Boolean) {
        start(ctx)
        if (on) {
            Discovery.start(ctx)
            Internet.start()
            pool.execute { runCatching { report(ctx) } }
            if (auto == null) auto = pool.scheduleWithFixedDelay({ runCatching { syncAll(ctx) } }, 3, INTERVAL, TimeUnit.SECONDS)
        } else {
            auto?.cancel(false); auto = null
            Discovery.stop()
            Discovery.unannounce()
            Internet.stop()
        }
    }

    /** on Wi-Fi or Ethernet (where the plant's LAN addresses can answer) */
    private fun onLan(ctx: Context): Boolean {
        val cm = ctx.getSystemService(ConnectivityManager::class.java) ?: return true
        val caps = cm.getNetworkCapabilities(cm.activeNetwork) ?: return false
        return caps.hasTransport(android.net.NetworkCapabilities.TRANSPORT_WIFI) || caps.hasTransport(android.net.NetworkCapabilities.TRANSPORT_ETHERNET)
    }

    private val PRIVATE = Regex("^(10\\.|192\\.168\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.|169\\.254\\.)")
    private fun privateAddress(host: String) = PRIVATE.containsMatchIn(host)

    fun unmetered(ctx: Context): Boolean {
        val cm = ctx.getSystemService(ConnectivityManager::class.java) ?: return false
        return !cm.isActiveNetworkMetered
    }
}

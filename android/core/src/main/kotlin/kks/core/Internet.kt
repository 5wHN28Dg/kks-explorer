package kks.core

import java.net.DatagramSocket
import java.net.Inet4Address
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.SocketAddress
import java.net.SocketTimeoutException
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

/**
 * Sync across the internet (M5, PROTOCOL.md §18); the twin of peer/internet.py. Presence on the plant's relay room
 * (signed with the device key); connecting = STUN + hole punching (Rudp), else a relay pipe; the sync's Noise
 * session runs over either, so the relay only ever passes encrypted bytes.
 */
class Internet(private val node: Node, private val relay: () -> String?,
               private val record: (remote: String?, address: String, ok: Boolean, result: Any?, direction: String) -> Unit,
               var stunServers: List<Pair<String, Int>> = STUN, private val allowed: () -> Boolean = { true },
               private val onChange: () -> Unit = {}) {
    companion object {
        val STUN = listOf("stun.cloudflare.com" to 3478, "stun.l.google.com" to 19302)
        val HELLO_DOMAIN = "kks-relay-hello-v1\n".toByteArray()
        const val PUNCH_TIMEOUT_MS = 4000L

        /** The room of a plant (= relay_server.room_of): nobody learns the root from it. */
        fun roomOf(root: String): String = MessageDigest.getInstance("SHA-256").digest("kks-relay-room-v1\n$root".toByteArray())
            .joinToString("") { "%02x".format(it) }.take(32)
    }

    val online: MutableSet<String> = ConcurrentHashMap.newKeySet()
    /** false: skip hole punching, always use a relay pipe (tests; a network known to block it). */
    @Volatile var tryDirect = true
    private val waiting = ConcurrentHashMap<String, LinkedBlockingQueue<Map<String, Any?>>>()
    @Volatile private var ws: WsClient? = null
    @Volatile var state = "off"; private set
    @Volatile private var running = false
    private val rng = SecureRandom()
    /** Called for an incoming connection once it is up: serve the sync over it (the owner decides how). */
    var serve: (Conn, String) -> Unit = { c, how -> runCatching { val (r, st) = Sync.serveConn(node, c, 60_000); if (st.join == null) record(r, "internet ($how)", true, st, "in") }.onFailure { record(null, "internet ($how)", false, it.message, "in") } }

    @Volatile private var gen = 0                  // a stop() + start() leaves the old presence thread behind: it quits

    @Synchronized fun start() { if (!running) { running = true; val g = ++gen; Thread({ presence(g) }, "kks-relay").apply { isDaemon = true; start() } } }
    @Synchronized fun stop() { running = false; gen++; ws?.close() }

    private fun room(): Pair<String, String>? {
        val url = relay()?.trimEnd('/') ?: return null
        val root = node.root() ?: return null
        return url to roomOf(root)
    }

    private fun presence(g: Int) {
        var backoff = 2000L
        fun live() = running && gen == g
        while (live()) {
            val r = room()
            if (r == null || !allowed()) { state = if (r == null) "off" else "paused (metered network)"; Thread.sleep(5000); continue }
            try {
                val w = WsClient("${r.first}/v1/room/${r.second}", 20_000)
                val key = node.identity(); val ts = System.currentTimeMillis() / 1000
                w.sendText(Json.write(mapOf("t" to "hello", "peer" to key.peerId, "ts" to ts,
                    "sig" to B64u.encode(key.sign(HELLO_DOMAIN + "${r.second}\n$ts".toByteArray())))))
                if (!live()) { w.close(); break }
                ws = w; backoff = 2000; w.setTimeout(25_000)
                while (live()) {
                    val (_, data) = try { w.recv() } catch (e: SocketTimeoutException) { w.sendText("{\"t\":\"ping\"}"); continue }
                    @Suppress("UNCHECKED_CAST") val m = Json.parse(String(data, Charsets.UTF_8)) as? Map<String, Any?> ?: continue
                    when (m["t"]) {
                        "error" -> throw WsError(m["why"]?.toString() ?: "refused")
                        "welcome" -> { online.clear(); (m["peers"] as? List<*>)?.forEach { online.add(it as String) }; state = "connected"; onChange() }
                        "joined" -> { online.add(m["peer"] as String); onChange() }
                        "left" -> { online.remove(m["peer"] as String); onChange() }
                        "connect" -> Thread({ answer(m) }, "kks-relay-in").apply { isDaemon = true; start() }
                        "accept", "gone", "refuse" -> waiting[m["id"] as? String ?: ""]?.offer(m)
                    }
                }
            } catch (e: Exception) {
                state = "not reachable (${e.message})"
            } finally {
                if (gen == g) { online.clear(); ws?.close(); ws = null; onChange() }
            }
            if (live()) { Thread.sleep(backoff); backoff = minOf(backoff * 2, 60_000) }
        }
    }

    private fun send(m: Map<String, Any?>) = (ws ?: throw SyncError("not connected to the relay")).sendText(Json.write(m))

    /** A UDP socket and its candidate addresses: public (STUN) + this device's own network addresses. */
    internal var udp: () -> Pair<DatagramSocket, List<String>> = {
        val u = DatagramSocket(0)
        val port = u.localPort
        val cand = ArrayList<String>()
        Rudp.stun(u, stunServers)?.let { cand.add("${it.address.hostAddress}:${it.port}") }
        runCatching {
            for (ni in NetworkInterface.getNetworkInterfaces()) {
                if (!ni.isUp || ni.isLoopback || ni.isVirtual) continue
                for (a in ni.inetAddresses) if (a is Inet4Address && !a.isLoopbackAddress && !a.isLinkLocalAddress) cand.add("${a.hostAddress}:$port")
            }
        }
        u to cand.take(8)
    }

    private fun addrs(cand: Any?): List<SocketAddress> = (cand as? List<*>).orEmpty().mapNotNull { c ->
        val s = c as? String ?: return@mapNotNull null
        s.substringAfterLast(':').toIntOrNull()?.let { InetSocketAddress(s.substringBeforeLast(':'), it) }
    }

    private fun join(u: DatagramSocket, cid: String, their: Any?, room: Pair<String, String>, side: String): Pair<Conn, String> {
        val session = cid.chunked(2).take(8).map { it.toInt(16).toByte() }.toByteArray()
        val peer = if (their != null && tryDirect) Rudp.punch(u, session, addrs(their), PUNCH_TIMEOUT_MS) else null
        if (peer != null) return Rudp.Stream(u, peer, session) to "direct"
        u.close()
        return PipeConn(WsClient("${room.first}/v1/pipe/${room.second}/$cid/$side", 20_000)) to "relay"
    }

    /** A connection to [peer]: direct if hole punching works, else through a relay pipe. -> (conn, how) */
    fun connect(peer: String, timeoutMs: Long = 10_000): Pair<Conn, String> {
        val r = room() ?: throw SyncError("no relay")
        val cid = ByteArray(16).also { rng.nextBytes(it) }.joinToString("") { "%02x".format(it) }
        val q = LinkedBlockingQueue<Map<String, Any?>>(); waiting[cid] = q
        try {
            val (u, cand) = udp()
            send(mapOf("t" to "connect", "to" to peer, "id" to cid, "cand" to cand))
            val ans = q.poll(timeoutMs, TimeUnit.MILLISECONDS) ?: run { u.close(); throw SyncError("the other device did not answer through the relay") }
            if (ans["t"] != "accept") { u.close(); throw SyncError(if (ans["t"] == "gone") "the other device is not on the relay" else "refused") }
            return join(u, cid, ans["cand"], r, "a")
        } finally { waiting.remove(cid) }
    }

    private fun answer(m: Map<String, Any?>) {
        val peer = m["from"] as? String ?: return; val cid = m["id"] as? String ?: return
        val r = room() ?: return
        val (conn, how) = try {
            val (u, cand) = udp()
            send(mapOf("t" to "accept", "to" to peer, "id" to cid, "cand" to cand))
            join(u, cid, m["cand"], r, "b")
        } catch (e: Exception) { record(null, "internet ${peer.take(12)}", false, e.message, "in"); return }
        serve(conn, how)
    }

    /** Sync with [peer] over the internet. -> (remote, stats); throws on failure (recorded). */
    fun sync(peer: String): Pair<String, SyncStats> {
        val (conn, how) = try { connect(peer) } catch (e: Exception) { record(null, "internet ${peer.take(12)}", false, e.message, "out"); throw e }
        try {
            conn.use { val res = Sync.syncOver(node, it, expectPeer = peer, timeoutMs = 60_000); record(res.first, "internet ($how)", true, res.second, "out"); return res }
        } catch (e: Exception) { record(peer, "internet ($how)", false, e.message, "out"); throw e }
    }

    fun snapshot(): Map<String, Any?> = mapOf("relay" to relay(), "state" to state, "online" to online.sorted())
}

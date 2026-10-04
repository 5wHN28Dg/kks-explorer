package kks.explorer.sync

import android.util.Log
import kks.explorer.core.Core
import kks.explorer.core.Net
import java.io.IOException
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.Inet4Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.nio.ByteBuffer
import java.security.SecureRandom
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * The direct path of PROTOCOL-v2 §18 on the phone, the twin of platform/linux/src/kksl/udp.nim: one UDP socket per
 * attempt, its public address from STUN (RFC 5389), hole punching to the other side's candidates, then the reliable
 * stream. The stream's logic is the core's (core/src/kks/rudp.nim, through Core.rudpStep); this file only moves
 * datagrams and time. The sync's TLS then runs over it as over TCP (Net.overRaw).
 */
object Direct {
    private val STUN = listOf("stun.cloudflare.com" to 3478, "stun.l.google.com" to 19302)
    private const val PUNCH: Byte = 1
    private const val PUNCH_ACK: Byte = 2
    private const val HEAD = 9                    // type + 8-byte session
    private val rng = SecureRandom()

    private fun now() = System.nanoTime() / 1e9

    /** a UDP socket with one receive thread, handing each datagram to the current stage */
    class Udp {
        val sock = DatagramSocket(0)
        @Volatile var onPacket: ((ByteArray, InetSocketAddress) -> Unit)? = null
        @Volatile var closed = false
        init {
            Thread({
                val buf = ByteArray(2048)
                while (!closed) {
                    val p = DatagramPacket(buf, buf.size)
                    try { sock.receive(p) } catch (e: IOException) { if (closed) break else continue }
                    val from = p.socketAddress as? InetSocketAddress ?: continue
                    runCatching { onPacket?.invoke(buf.copyOf(p.length), from) }
                }
            }, "kks-udp").apply { isDaemon = true; start() }
        }
        fun send(to: InetSocketAddress, data: ByteArray) {
            try { sock.send(DatagramPacket(data, data.size, to)) } catch (e: IOException) {}   // unreachable candidates are normal
        }
        fun close() { closed = true; sock.close() }
    }

    /** the public "ip:port" this socket's packets come from, or "" (no STUN answer: no public candidate) */
    fun stun(u: Udp, servers: List<Pair<String, Int>> = STUN, timeoutMs: Long = 1500): String {
        for ((host, port) in servers) {
            val addr = try { InetSocketAddress(InetAddress.getByName(host), port) } catch (e: Exception) { continue }
            val tid = ByteArray(12).also { rng.nextBytes(it) }
            val q = LinkedBlockingQueue<String>()
            u.onPacket = { d, _ -> parseStun(d, tid)?.let { q.offer(it) } }
            u.send(addr, byteArrayOf(0, 1, 0, 0, 0x21, 0x12, 0xa4.toByte(), 0x42) + tid)
            val got = q.poll(timeoutMs, TimeUnit.MILLISECONDS)
            u.onPacket = null
            if (got != null) return got
        }
        return ""
    }

    private fun parseStun(d: ByteArray, tid: ByteArray): String? {
        if (d.size < 20 || !d.copyOfRange(8, 20).contentEquals(tid)) return null
        val n = ((d[2].toInt() and 0xff) shl 8) or (d[3].toInt() and 0xff)
        var i = 20
        while (i + 4 <= minOf(d.size, 20 + n)) {
            val at = ((d[i].toInt() and 0xff) shl 8) or (d[i + 1].toInt() and 0xff)
            val al = ((d[i + 2].toInt() and 0xff) shl 8) or (d[i + 3].toInt() and 0xff)
            if (at == 0x0020 && al >= 8 && i + 12 <= d.size && d[i + 5].toInt() == 1) {     // XOR-MAPPED-ADDRESS, IPv4
                val port = (((d[i + 6].toInt() and 0xff) shl 8) or (d[i + 7].toInt() and 0xff)) xor 0x2112
                val m = intArrayOf(0x21, 0x12, 0xa4, 0x42)
                val ip = (0..3).joinToString(".") { ((d[i + 8 + it].toInt() and 0xff) xor m[it]).toString() }
                return "$ip:$port"
            }
            i += 4 + al + ((4 - al % 4) % 4)
        }
        return null
    }

    /** this phone's IPv4 addresses others on the same network could reach (not loopback, not link-local) */
    fun localIPv4s(): List<String> = try {
        NetworkInterface.getNetworkInterfaces().toList().filter { it.isUp && !it.isLoopback }
            .flatMap { it.inetAddresses.toList() }.filterIsInstance<Inet4Address>()
            .filter { !it.isLinkLocalAddress && !it.isLoopbackAddress }.map { it.hostAddress!! }.distinct()
    } catch (e: Exception) { emptyList() }

    /** a socket and its candidates (at most 8): the public address first, then the phone's own */
    fun candidates(stunServers: List<Pair<String, Int>> = STUN): Pair<Udp, List<String>> {
        val u = Udp()
        val c = ArrayList<String>()
        stun(u, stunServers).takeIf { it.isNotEmpty() }?.let { c.add(it) }
        for (ip in localIPv4s()) if (c.size < 8) c.add("$ip:${u.sock.localPort}")
        return u to c
    }

    private fun parseCand(c: String): InetSocketAddress? {
        val i = c.lastIndexOf(':')
        if (i <= 0) return null
        val port = c.substring(i + 1).toIntOrNull() ?: return null
        return try { InetSocketAddress(InetAddress.getByName(c.substring(0, i)), port) } catch (e: Exception) { null }
    }

    /** the session of a connect id: its first 8 bytes */
    fun session(id: String): ByteArray = ByteArray(8) { id.substring(it * 2, it * 2 + 2).toInt(16).toByte() }

    /** PUNCH to every candidate until the other side is heard and has heard us -> its address, or null */
    fun punch(u: Udp, session: ByteArray, cands: List<String>, timeoutMs: Long = 4000): InetSocketAddress? {
        val peer = AtomicReference<InetSocketAddress?>(null)
        val confirmed = AtomicBoolean(false)
        fun head(t: Byte) = byteArrayOf(t) + session
        u.onPacket = { d, from ->
            if (d.size >= HEAD && d.copyOfRange(1, HEAD).contentEquals(session)) {
                when (d[0]) {
                    PUNCH -> { peer.compareAndSet(null, from); u.send(from, head(PUNCH_ACK)) }
                    PUNCH_ACK -> { peer.set(from); confirmed.set(true) }     // where it heard us from: the best address
                    else -> if (peer.get() != null) confirmed.set(true)    // it already started the stream: it heard us
                }
            }
        }
        val targets = cands.mapNotNull { parseCand(it) }
        val end = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < end && !confirmed.get()) {
            val p = peer.get()
            if (p != null) u.send(p, head(PUNCH)) else targets.forEach { u.send(it, head(PUNCH)) }
            Thread.sleep(100)
        }
        u.onPacket = null
        Log.i("KKSSync", "direct: theirs $cands -> " + (peer.get()?.let { "using $it" + if (confirmed.get()) " (answered)" else " (heard only)" } ?: "no path"))
        return peer.get()
    }

    private class State {
        @Volatile var error = ""
        @Volatile var ended = false
        @Volatile var finished = false
        @Volatile var queued = 0
        @Volatile var stopped = false
    }

    /** one result of Core.rudpStep */
    private class Step(b: ByteArray) {
        val error: String; val ended: Boolean; val finished: Boolean; val queued: Int; val got: ByteArray
        val out = ArrayList<ByteArray>()
        init {
            val r = ByteBuffer.wrap(b)
            val f = r.get().toInt()
            ended = f and 2 != 0; finished = f and 4 != 0
            queued = r.int
            error = ByteArray(r.int).also { r.get(it) }.toString(Charsets.UTF_8).ifEmpty { if (f and 1 != 0) "failed" else "" }
            got = ByteArray(r.int).also { r.get(it) }
            repeat(r.short.toInt() and 0xffff) { out.add(ByteArray(r.short.toInt() and 0xffff).also { r.get(it) }) }
        }
    }

    /** the reliable stream to the punched address, under TLS as client or server (Net.overRaw) */
    /** debug builds only (DebugDirectReceiver): the direct path punches through, then carries nothing, like the stalled
     *  paths seen on mobile data; the e2e test checks that syncs fall back to the pipe */
    @Volatile var testStall = false

    fun connect(u: Udp, at: InetSocketAddress, session: ByteArray, client: Boolean, expectPeer: String, dead: Double = 15.0): Net.Peer {
        if (testStall) { u.onPacket = null; throw IOException("the other device stopped answering (test: stalled direct path)") }
        val to = AtomicReference(at)
        val id = Core.rudpNew(session, dead, now())
        val inbox = LinkedBlockingQueue<ByteArray>()
        val st = State()
        fun step(op: Int, data: ByteArray = ByteArray(0)) = synchronized(st) {
            if (st.stopped) return@synchronized
            val s = Step(Core.rudpStep(id, op, data, now()))
            s.out.forEach { u.send(to.get(), it) }
            if (s.got.isNotEmpty()) inbox.offer(s.got)
            if (s.error.isNotEmpty() && st.error.isEmpty()) st.error = s.error
            st.ended = s.ended; st.finished = s.finished; st.queued = s.queued
            if (s.ended || s.error.isNotEmpty()) inbox.offer(ByteArray(0))      // wake a waiting reader
        }
        // The other side's address can change after punching (NATs that map each destination to its own port, or
        // rebind): packets with our session from another address move the stream there; TLS on top authenticates the
        // peer. Before 2026-10-04 they were dropped, and the stream stalled ("the other device stopped answering").
        var moved = 0
        u.onPacket = { d, from ->
            if (d.size >= HEAD && d.copyOfRange(1, HEAD).contentEquals(session)) {
                val was = to.getAndSet(from)
                if (from != was && moved++ < 4) Log.i("KKSSync", "direct: the other side's address changed from $was to $from")
                step(1, d)
            }
        }
        Thread({ while (!st.stopped && !u.closed) { Thread.sleep(20); runCatching { step(2) } } }, "kks-rudp").apply { isDaemon = true; start() }
        fun free() {
            synchronized(st) { if (!st.stopped) { st.stopped = true; runCatching { Core.rudpStep(id, 5, ByteArray(0), now()) } } }
            u.close()
        }
        val rawIn: () -> ByteArray? = {
            var got: ByteArray? = null
            while (got == null) {
                val b = inbox.poll(200, TimeUnit.MILLISECONDS)
                if (b != null && b.isNotEmpty()) got = b
                else if (st.error.isNotEmpty()) throw IOException(st.error)
                else if (st.ended && inbox.isEmpty()) break
            }
            got
        }
        val rawOut: (ByteArray) -> Unit = { b ->
            step(3, b)
            while (st.queued > 4 * 1024 * 1024 && st.error.isEmpty()) Thread.sleep(20)       // back-pressure
            if (st.error.isNotEmpty()) throw IOException(st.error)
        }
        val onClose: () -> Unit = {
            Thread({
                val t0 = System.currentTimeMillis()
                while (st.queued > 0 && st.error.isEmpty() && System.currentTimeMillis() - t0 < 30_000) Thread.sleep(50)
                step(4)
                val t1 = System.currentTimeMillis()
                while (!st.finished && st.error.isEmpty() && System.currentTimeMillis() - t1 < 20_000) Thread.sleep(50)
                free()
            }, "kks-rudp-close").apply { isDaemon = true; start() }
        }
        return try { Net.overRaw(rawIn, rawOut, onClose, client, expectPeer) }
        catch (e: Exception) { Log.w("KKSSync", "direct: ${e.message}"); free(); throw e }
    }
}

package kks.core

import java.io.Closeable
import java.io.InputStream
import java.io.OutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetSocketAddress
import java.net.Socket
import java.net.SocketAddress
import java.net.SocketTimeoutException
import java.nio.ByteBuffer
import java.security.SecureRandom

/** A connection the sync runs over (§15, §18): TCP, a UDP stream after hole punching, or a relay pipe. */
interface Conn : Closeable {
    val input: InputStream
    val output: OutputStream
    fun setTimeout(ms: Int)
}

class TcpConn(val sock: Socket) : Conn {
    override val input: InputStream get() = sock.getInputStream()
    override val output: OutputStream get() = sock.getOutputStream()
    override fun setTimeout(ms: Int) { sock.soTimeout = ms }
    override fun close() = sock.close()
}

class RudpError(msg: String) : java.io.IOException(msg)

/**
 * A reliable byte stream over UDP after NAT hole punching (M5, PROTOCOL.md §18); the twin of peer/rudp.py, the same
 * datagrams: type (1 byte) + session (8 bytes) + body. PUNCH 1, PUNCH_ACK 2, DATA 3 (seq u32 + payload), ACK 4 (next u32
 * + mask u32), FIN 5 (seq u32), PING 6. Encryption is the sync's own Noise session over this stream.
 */
object Rudp {
    const val PUNCH = 1; const val PUNCH_ACK = 2; const val DATA = 3; const val ACK = 4; const val FIN = 5; const val PING = 6
    const val MSS = 1150
    private val rng = SecureRandom()

    fun newSession() = ByteArray(8).also { rng.nextBytes(it) }

    internal fun packet(type: Int, session: ByteArray, body: ByteArray = ByteArray(0)): ByteArray =
        ByteBuffer.allocate(9 + body.size).put(type.toByte()).put(session).put(body).array()

    /** Send PUNCH to every candidate until the other side is heard (and heard us). -> its address, or null. */
    fun punch(sock: DatagramSocket, session: ByteArray, candidates: List<SocketAddress>, timeoutMs: Long = 4000, intervalMs: Int = 100): SocketAddress? {
        val end = System.currentTimeMillis() + timeoutMs
        var peer: SocketAddress? = null
        var confirmed = false
        val buf = ByteArray(2048)
        sock.soTimeout = intervalMs
        while (System.currentTimeMillis() < end && !confirmed) {
            for (c in if (peer != null) listOf(peer) else candidates) runCatching { sock.send(DatagramPacket(packet(PUNCH, session).let { it }, 9, c)) }
            val next = System.currentTimeMillis() + intervalMs
            while (System.currentTimeMillis() < next) {
                val p = DatagramPacket(buf, buf.size)
                try { sock.receive(p) } catch (e: SocketTimeoutException) { break } catch (e: java.io.IOException) { continue }
                if (p.length < 9 || !buf.copyOfRange(1, 9).contentEquals(session)) continue
                when (buf[0].toInt()) {
                    PUNCH -> { if (peer == null) peer = p.socketAddress; runCatching { sock.send(DatagramPacket(packet(PUNCH_ACK, session), 9, p.socketAddress)) } }
                    PUNCH_ACK -> { if (peer == null) peer = p.socketAddress; confirmed = true }
                    DATA, ACK, FIN, PING -> if (peer != null) confirmed = true
                }
            }
        }
        return if (peer != null) peer else null     // (heard them: they will hear our acks)
    }

    /** A connected stream to [peer] over [sock]. */
    class Stream(private val sock: DatagramSocket, private val peer: SocketAddress, private val session: ByteArray,
                 private val deadMs: Long = 15_000) : Conn {
        private val lock = Object()
        private var nextSeq = 0L; private var base = 0L
        private val unacked = java.util.TreeMap<Long, Rec>()
        private val queue = java.io.ByteArrayOutputStream()
        private var queued = ByteArray(0); private var qpos = 0
        private var cwnd = 8.0; private var ssthresh = 256
        private var srtt = -1.0; private var rttvar = 0.0; private var rto = 0.5
        private var finSeq = -1L; private var recover = 0L
        private var progress = now()
        private var rnext = 0L; private val rbuf = HashMap<Long, ByteArray>(); private val inbox = java.io.ByteArrayOutputStream()
        private var inboxBytes = ByteArray(0); private var ipos = 0
        private var peerFin = -1L
        @Volatile private var error: String? = null
        @Volatile private var closed = false
        private var timeoutMs = 0
        private var lastRx = now(); private var lastTx = now()

        private class Rec(val payload: ByteArray) { var sentAt = 0.0; var retries = 0; var sacked = false }
        private fun now() = System.nanoTime() / 1e9

        init {
            sock.soTimeout = 50
            Thread({ loop() }, "kks-rudp").apply { isDaemon = true; start() }
        }

        override fun setTimeout(ms: Int) { timeoutMs = ms }

        override val output: OutputStream = object : OutputStream() {
            override fun write(b: Int) { write(byteArrayOf(b.toByte()), 0, 1) }
            override fun write(b: ByteArray, off: Int, len: Int): Unit = synchronized(lock) {
                error?.let { throw RudpError(it) }
                if (finSeq >= 0) throw RudpError("stream closed")
                queue.write(b, off, len)
                pump()
                val end = now() + (if (timeoutMs > 0) timeoutMs / 1000.0 else 3600.0)
                while (pending() > 4 * 1024 * 1024 && error == null) {
                    if (now() >= end) throw SocketTimeoutException("send timed out")
                    (lock as Object).wait(100)
                }
                error?.let { throw RudpError(it) }
            }
        }

        override val input: InputStream = object : InputStream() {
            override fun read(): Int { val b = ByteArray(1); return if (read(b, 0, 1) < 0) -1 else b[0].toInt() and 0xff }
            override fun read(b: ByteArray, off: Int, len: Int): Int = synchronized(lock) {
                val end = if (timeoutMs > 0) now() + timeoutMs / 1000.0 else Double.MAX_VALUE
                while (ipos >= inboxBytes.size && inbox.size() == 0) {
                    error?.let { throw RudpError(it) }
                    if (peerFin >= 0 && rnext > peerFin) return -1
                    if (now() >= end) throw SocketTimeoutException("timed out")
                    (lock as Object).wait(200)
                }
                if (ipos >= inboxBytes.size) { inboxBytes = inbox.toByteArray(); inbox.reset(); ipos = 0 }
                val n = minOf(len, inboxBytes.size - ipos)
                System.arraycopy(inboxBytes, ipos, b, off, n); ipos += n
                return n
            }
        }

        private fun pending() = queue.size() + (queued.size - qpos)

        override fun close() {
            synchronized(lock) {
                val end = now() + 30
                while (pending() > 0 && error == null && now() < end) (lock as Object).wait(100)
                if (finSeq < 0 && error == null) {
                    finSeq = nextSeq; unacked[finSeq] = Rec(ByteArray(0)); nextSeq++; sendData(finSeq)
                }
                val end2 = now() + 3
                while (unacked.isNotEmpty() && error == null && now() < end2) (lock as Object).wait(100)
                closed = true; (lock as Object).notifyAll()
            }
            runCatching { sock.close() }
        }

        private fun raw(type: Int, body: ByteArray = ByteArray(0)) {
            runCatching { val p = packet(type, session, body); sock.send(DatagramPacket(p, p.size, peer)); lastTx = now() }
        }

        private fun sendData(seq: Long) {
            val r = unacked[seq] ?: return
            r.sentAt = now()
            val head = ByteBuffer.allocate(4).putInt(seq.toInt()).array()
            if (seq == finSeq) raw(FIN, head) else raw(DATA, head + r.payload)
        }

        private fun pump() {
            if (queue.size() > 0) { queued = queued.copyOfRange(qpos, queued.size) + queue.toByteArray(); qpos = 0; queue.reset() }
            while (qpos < queued.size && nextSeq - base < cwnd.toInt()) {
                val n = minOf(MSS, queued.size - qpos)
                unacked[nextSeq] = Rec(queued.copyOfRange(qpos, qpos + n)); qpos += n
                sendData(nextSeq); nextSeq++
            }
            (lock as Object).notifyAll()
        }

        private fun lost(seq: Long) {
            if (seq >= recover) { ssthresh = maxOf(2, (cwnd / 2).toInt()); cwnd = ssthresh.toDouble(); recover = nextSeq }
        }

        private fun sample(r: Double) {
            if (srtt < 0) { srtt = r; rttvar = r / 2 } else { rttvar = 0.75 * rttvar + 0.25 * Math.abs(srtt - r); srtt = 0.875 * srtt + 0.125 * r }
            rto = minOf(4.0, maxOf(0.2, srtt + 4 * rttvar))
        }

        private fun onAck(nxt: Long, mask: Long) {
            val t = now(); var newly = 0
            for (seq in unacked.headMap(nxt).keys.toList()) {
                val r = unacked.remove(seq)!!; newly++
                if (r.retries == 0 && r.sentAt > 0) sample(t - r.sentAt)
            }
            for (i in 0 until 32) if ((mask shr i) and 1L == 1L) unacked[nxt + 1 + i]?.let { r ->
                if (!r.sacked) { r.sacked = true; if (r.retries == 0 && r.sentAt > 0) sample(t - r.sentAt) }
            }
            if (nxt > base) { base = nxt; progress = t }
            if (newly > 0) cwnd = minOf(cwnd + (if (cwnd < ssthresh) 1.0 else 1.0 / cwnd) * newly, 256.0)
            var later = 0
            for (seq in unacked.descendingKeySet().toList()) {
                val r = unacked[seq]!!
                if (r.sacked) later++
                else if (later >= 3 && r.sentAt > 0 && t - r.sentAt > (if (srtt > 0) srtt else 0.1)) { lost(seq); r.retries++; sendData(seq) }
            }
            pump()
        }

        private fun onData(seq: Long, payload: ByteArray, fin: Boolean = false) {
            if (fin) peerFin = seq
            if (seq >= rnext && !rbuf.containsKey(seq)) {
                rbuf[seq] = payload
                while (rbuf.containsKey(rnext)) { inbox.write(rbuf.remove(rnext)!!); rnext++ }
                (lock as Object).notifyAll()
            }
            var mask = 0L
            for (i in 0 until 32) if (rbuf.containsKey(rnext + 1 + i)) mask = mask or (1L shl i)
            raw(ACK, ByteBuffer.allocate(8).putInt(rnext.toInt()).putInt(mask.toInt()).array())
        }

        private fun timers() {
            val t = now()
            for (seq in unacked.keys.take(cwnd.toInt() + 1)) {
                val r = unacked[seq]!!
                if (!r.sacked && r.sentAt > 0 && t - r.sentAt > minOf(4.0, rto * (1 shl minOf(r.retries, 4)))) { lost(seq); r.retries++; sendData(seq) }
            }
            if (unacked.isNotEmpty() && (t - progress) * 1000 > deadMs) error = "the other device stopped answering"
            if ((t - lastRx) * 1000 > deadMs && !closed) error = error ?: "the other device stopped answering"
            if (t - lastTx > 2.0 && !closed) raw(PING)
            pump()
        }

        private fun loop() {
            val buf = ByteArray(2048)
            while (true) {
                synchronized(lock) { if (closed || error != null) { (lock as Object).notifyAll(); return } }
                val p = DatagramPacket(buf, buf.size)
                val got = try { sock.receive(p); true } catch (e: SocketTimeoutException) { false } catch (e: Exception) {
                    synchronized(lock) { error = error ?: "network: ${e.message}"; (lock as Object).notifyAll() }; return
                }
                synchronized(lock) {
                    if (got && p.length >= 9 && p.socketAddress == peer && buf.copyOfRange(1, 9).contentEquals(session)) {
                        lastRx = now()
                        val body = ByteBuffer.wrap(buf, 9, p.length - 9)
                        when (buf[0].toInt()) {
                            DATA -> if (p.length >= 13) { val seq = body.int.toLong() and 0xffffffffL; onData(seq, ByteArray(p.length - 13).also { body.get(it) }) }
                            FIN -> if (p.length >= 13) onData(body.int.toLong() and 0xffffffffL, ByteArray(0), fin = true)
                            ACK -> if (p.length >= 17) { val n = body.int.toLong() and 0xffffffffL; val m = body.int.toLong() and 0xffffffffL; onAck(n, m) }
                            PUNCH, PUNCH_ACK -> raw(PUNCH_ACK)
                        }
                    }
                    timers()
                }
            }
        }
    }

    /** STUN (RFC 5389): the public address this UDP socket's packets come from, or null. */
    fun stun(sock: DatagramSocket, servers: List<Pair<String, Int>>, timeoutMs: Int = 1500): InetSocketAddress? {
        for ((host, port) in servers) {
            val addr = runCatching { InetSocketAddress(java.net.Inet4Address.getAllByName(host).first { it is java.net.Inet4Address }, port) }.getOrNull() ?: continue
            val tid = ByteArray(12).also { rng.nextBytes(it) }
            val req = ByteBuffer.allocate(20).putShort(1).putShort(0).putInt(0x2112A442).put(tid).array()
            try {
                sock.soTimeout = timeoutMs
                sock.send(DatagramPacket(req, req.size, addr))
                val end = System.currentTimeMillis() + timeoutMs
                val buf = ByteArray(2048)
                while (System.currentTimeMillis() < end) {
                    val p = DatagramPacket(buf, buf.size); sock.receive(p)
                    if (p.socketAddress != addr || p.length < 20 || !buf.copyOfRange(8, 20).contentEquals(tid)) continue
                    val bb = ByteBuffer.wrap(buf, 0, p.length)
                    val n = bb.getShort(2).toInt() and 0xffff
                    var i = 20
                    while (i + 4 <= 20 + n && i + 4 <= p.length) {
                        val at = bb.getShort(i).toInt() and 0xffff; val al = bb.getShort(i + 2).toInt() and 0xffff
                        if (at == 0x0020 && al >= 8 && buf[i + 5].toInt() == 1) {
                            val prt = (bb.getShort(i + 6).toInt() and 0xffff) xor 0x2112
                            val ip = bb.getInt(i + 8) xor 0x2112A442
                            return InetSocketAddress(java.net.InetAddress.getByAddress(ByteBuffer.allocate(4).putInt(ip).array()), prt)
                        }
                        i += 4 + al + ((4 - al % 4) % 4)
                    }
                }
            } catch (e: Exception) { continue }
        }
        return null
    }
}

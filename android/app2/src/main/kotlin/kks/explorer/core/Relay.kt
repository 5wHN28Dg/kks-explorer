package kks.explorer.core

import java.io.Closeable
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.net.URI
import java.nio.ByteBuffer
import java.security.SecureRandom
import javax.net.ssl.SSLEngine
import javax.net.ssl.SSLEngineResult
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory

class WsError(msg: String) : IOException(msg)

/**
 * A small WebSocket client (RFC 6455) for the relay (PROTOCOL-v2 §18), from the v1 app's WsClient. `wss://` uses the
 * platform's TLS with its CA store and host name verification (endpoint identification "HTTPS": a plain layered
 * SSLSocket checks no host name by itself).
 */
class WsClient(url: String, timeoutMs: Int = 15_000) {
    companion object { const val TEXT = 1; const val BINARY = 2; const val CLOSE = 8; const val PING = 9; const val PONG = 10 }
    private val sock: Socket
    private val inp: InputStream
    private val out: OutputStream
    private val sendLock = Object()
    private val rng = SecureRandom()
    @Volatile var closed = false; private set

    init {
        val u = URI(url)
        if (u.scheme != "ws" && u.scheme != "wss") throw WsError("not a ws:// or wss:// address")
        // ws:// (a raw socket, outside Android's cleartext policy) only to this device: the relay twin in tests (#15)
        if (u.scheme == "ws" && u.host !in setOf("127.0.0.1", "localhost", "::1", "[::1]"))
            throw WsError("the relay must be a wss:// address (ws:// only to this device)")
        val port = if (u.port > 0) u.port else if (u.scheme == "wss") 443 else 80
        val raw = Socket().apply { connect(InetSocketAddress(u.host, port), timeoutMs); soTimeout = timeoutMs }
        sock = if (u.scheme == "wss") {
            val s = (SSLSocketFactory.getDefault() as SSLSocketFactory).createSocket(raw, u.host, port, true) as SSLSocket
            s.sslParameters = s.sslParameters.apply { endpointIdentificationAlgorithm = "HTTPS" }
            s.startHandshake()
            s
        } else raw
        inp = sock.getInputStream().buffered(65536); out = sock.getOutputStream()
        val key = java.util.Base64.getEncoder().encodeToString(ByteArray(16).also { rng.nextBytes(it) })
        val path = (u.rawPath?.ifEmpty { "/" } ?: "/") + (u.rawQuery?.let { "?$it" } ?: "")
        out.write(("GET $path HTTP/1.1\r\nHost: ${u.host}${if (u.port > 0) ":${u.port}" else ""}\r\nUpgrade: websocket\r\n" +
                   "Connection: Upgrade\r\nSec-WebSocket-Key: $key\r\nSec-WebSocket-Version: 13\r\n\r\n").toByteArray())
        out.flush()
        val head = StringBuilder()
        while (!head.endsWith("\r\n\r\n")) {
            val c = inp.read(); if (c < 0) throw WsError("the relay closed the connection during the handshake")
            head.append(c.toChar()); if (head.length > 16384) throw WsError("bad handshake")
        }
        val lines = head.split("\r\n")
        if (!lines[0].contains(" 101 ")) throw WsError("the relay refused: ${lines[0]}")
        val want = java.util.Base64.getEncoder().encodeToString(
            java.security.MessageDigest.getInstance("SHA-1").digest((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").toByteArray()))
        if (lines.none { val c = it.indexOf(':'); c > 0 && it.substring(0, c).trim().equals("sec-websocket-accept", true) && it.substring(c + 1).trim() == want })
            throw WsError("bad Sec-WebSocket-Accept")
    }

    fun setTimeout(ms: Int) { sock.soTimeout = ms }

    private fun send(op: Int, data: ByteArray) = synchronized(sendLock) {
        if (closed) throw WsError("closed")
        val mask = ByteArray(4).also { rng.nextBytes(it) }
        val n = data.size
        val head = java.io.ByteArrayOutputStream()
        head.write(0x80 or op)
        when {
            n < 126 -> head.write(0x80 or n)
            n < 65536 -> { head.write(0x80 or 126); head.write(ByteBuffer.allocate(2).putShort(n.toShort()).array()) }
            else -> { head.write(0x80 or 127); head.write(ByteBuffer.allocate(8).putLong(n.toLong()).array()) }
        }
        head.write(mask)
        val body = ByteArray(n) { (data[it].toInt() xor mask[it % 4].toInt()).toByte() }
        out.write(head.toByteArray() + body); out.flush()
    }

    fun sendText(s: String) = send(TEXT, s.toByteArray())
    fun sendBinary(b: ByteArray) = send(BINARY, b)

    private fun readN(n: Int): ByteArray {
        val b = ByteArray(n); var off = 0
        while (off < n) { val r = inp.read(b, off, n - off); if (r < 0) throw WsError("the relay closed the connection"); off += r }
        return b
    }

    /** -> (TEXT | BINARY, payload). Answers pings; throws WsError when closed. */
    fun recv(): Pair<Int, ByteArray> {
        val parts = java.io.ByteArrayOutputStream(); var op0 = 0
        while (true) {
            val h = readN(2)
            val op = h[0].toInt() and 0x0f
            var n = (h[1].toInt() and 0x7f).toLong()
            if (n == 126L) n = (ByteBuffer.wrap(readN(2)).short.toLong() and 0xffff)
            else if (n == 127L) n = ByteBuffer.wrap(readN(8)).long
            if (n > (16 shl 20)) throw WsError("message too large")
            val mask = if (h[1].toInt() and 0x80 != 0) readN(4) else null
            val data = readN(n.toInt())
            if (mask != null) for (i in data.indices) data[i] = (data[i].toInt() xor mask[i % 4].toInt()).toByte()
            when (op) {
                PING -> { send(PONG, data); continue }
                PONG -> continue
                CLOSE -> { closed = true; throw WsError("the relay closed the connection") }
            }
            if (op != 0) op0 = op
            parts.write(data)
            if (h[0].toInt() and 0x80 != 0) return op0 to parts.toByteArray()
        }
    }

    fun close() {
        runCatching { send(CLOSE, byteArrayOf(0x03, 0xe8.toByte())) }
        closed = true
        runCatching { sock.close() }
    }
}

/**
 * TLS through an SSLEngine over any byte transport (here a relay pipe: each binary message carries a piece of the TLS
 * stream). The same SSLContext, profile and peer pinning as the TCP sync (Net); an engine instead of a layered
 * SSLSocket because Android's layered socket wants a real socket's file descriptor underneath.
 */
class EngineTls(private val e: SSLEngine, private val rawIn: () -> ByteArray?, private val rawOut: (ByteArray) -> Unit,
                private val onClose: () -> Unit) : Closeable {
    private val empty = ByteBuffer.allocate(0)
    private var net = ByteBuffer.allocate(e.session.packetBufferSize).also { it.flip() }      // read mode
    private var app = ByteBuffer.allocate(e.session.applicationBufferSize).also { it.flip() }  // read mode
    private var out = ByteBuffer.allocate(e.session.packetBufferSize)
    private var eof = false

    private fun tasks() { while (true) (e.delegatedTask ?: return).run() }

    private fun fill(): Boolean {
        val b = rawIn() ?: return false
        if (net.capacity() - net.remaining() < b.size) {
            val n = ByteBuffer.allocate(net.remaining() + b.size + 4096); n.put(net); n.flip(); net = n
        }
        net.compact(); net.put(b); net.flip()
        return true
    }

    private fun wrap(src: ByteBuffer) {
        do {
            out.clear()
            val r = e.wrap(src, out)
            if (r.status == SSLEngineResult.Status.BUFFER_OVERFLOW) { out = ByteBuffer.allocate(out.capacity() * 2); continue }
            out.flip()
            if (out.hasRemaining()) rawOut(ByteArray(out.remaining()).also { out.get(it) })
            tasks()
            if (r.status == SSLEngineResult.Status.CLOSED) return
        } while (src.hasRemaining() || e.handshakeStatus == SSLEngineResult.HandshakeStatus.NEED_WRAP)
    }

    /** one unwrap; false when the transport ended */
    private fun unwrap(): Boolean {
        app.compact()
        val r = try { e.unwrap(net, app) } finally { app.flip() }
        when (r.status) {
            SSLEngineResult.Status.BUFFER_OVERFLOW -> { val n = ByteBuffer.allocate(app.capacity() * 2); n.put(app); n.flip(); app = n }
            SSLEngineResult.Status.BUFFER_UNDERFLOW -> if (!fill()) return false
            SSLEngineResult.Status.CLOSED -> eof = true
            else -> {}
        }
        tasks()
        return true
    }

    fun handshake() {
        e.beginHandshake()
        while (true) {
            when (e.handshakeStatus) {
                SSLEngineResult.HandshakeStatus.NEED_WRAP -> wrap(empty)
                SSLEngineResult.HandshakeStatus.NEED_TASK -> tasks()
                SSLEngineResult.HandshakeStatus.FINISHED, SSLEngineResult.HandshakeStatus.NOT_HANDSHAKING -> return
                else -> if (!unwrap() || eof) throw IOException("the other side closed the connection during the TLS handshake")
            }
        }
    }

    val input: InputStream = object : InputStream() {
        override fun read(): Int { val b = ByteArray(1); return if (read(b, 0, 1) < 0) -1 else b[0].toInt() and 0xff }
        override fun read(b: ByteArray, off: Int, len: Int): Int {
            while (!app.hasRemaining()) {
                if (eof) return -1
                when (e.handshakeStatus) {
                    SSLEngineResult.HandshakeStatus.NEED_WRAP -> { wrap(empty); continue }
                    SSLEngineResult.HandshakeStatus.NEED_TASK -> { tasks(); continue }
                    else -> {}
                }
                if (!unwrap()) return -1
            }
            val n = minOf(len, app.remaining())
            app.get(b, off, n)
            return n
        }
    }

    val output: OutputStream = object : OutputStream() {
        override fun write(b: Int) { write(byteArrayOf(b.toByte()), 0, 1) }
        override fun write(b: ByteArray, off: Int, len: Int) { wrap(ByteBuffer.wrap(b, off, len)) }
    }

    override fun close() {
        runCatching { e.closeOutbound(); wrap(empty) }
        onClose()
    }
}

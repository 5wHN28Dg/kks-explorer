package kks.core

import java.io.InputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.net.URI
import java.nio.ByteBuffer
import java.security.SecureRandom
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory

class WsError(msg: String) : java.io.IOException(msg)

/** A small WebSocket client (RFC 6455) for the internet relay (M5, PROTOCOL.md §18); the twin of peer/ws.py. */
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
        val port = if (u.port > 0) u.port else if (u.scheme == "wss") 443 else 80
        val raw = Socket().apply { connect(InetSocketAddress(u.host, port), timeoutMs); soTimeout = timeoutMs }
        sock = if (u.scheme == "wss") (SSLSocketFactory.getDefault() as SSLSocketFactory).createSocket(raw, u.host, port, true).also {
            (it as SSLSocket).startHandshake()
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
        val status = head.lineSequence().first()
        if (!status.contains(" 101 ")) throw WsError("the relay refused: $status")
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

/** A relay pipe (§18) as a [Conn]: the sync's framed Noise bytes travel as binary messages. */
class PipeConn(private val ws: WsClient) : Conn {
    private var pending = ByteArray(0); private var pos = 0
    override fun setTimeout(ms: Int) = ws.setTimeout(ms)
    override fun close() = ws.close()
    override val output: OutputStream = object : OutputStream() {
        override fun write(b: Int) { write(byteArrayOf(b.toByte()), 0, 1) }
        override fun write(b: ByteArray, off: Int, len: Int) { ws.sendBinary(b.copyOfRange(off, off + len)) }
    }
    override val input: InputStream = object : InputStream() {
        override fun read(): Int { val b = ByteArray(1); return if (read(b, 0, 1) < 0) -1 else b[0].toInt() and 0xff }
        override fun read(b: ByteArray, off: Int, len: Int): Int {
            while (pos >= pending.size) {
                val (op, data) = try { ws.recv() } catch (e: WsError) { return -1 }
                if (op == WsClient.BINARY) { pending = data; pos = 0 }
            }
            val n = minOf(len, pending.size - pos)
            System.arraycopy(pending, pos, b, off, n); pos += n
            return n
        }
    }
}

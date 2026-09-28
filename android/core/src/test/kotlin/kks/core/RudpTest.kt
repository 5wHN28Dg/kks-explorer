package kks.core

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetSocketAddress
import java.security.MessageDigest
import java.util.Random
import java.util.concurrent.CompletableFuture
import kotlin.concurrent.thread

/** The reliable UDP stream (Rudp.kt, PROTOCOL.md §18): under loss, and against the Python implementation. */
class RudpTest {
    /** Drops and delays (so reorders) outgoing datagrams. */
    class Lossy(private val loss: Double, private val jitterMs: Int, seed: Long) : DatagramSocket(InetSocketAddress("127.0.0.1", 0)) {
        private val rng = Random(seed)
        override fun send(p: DatagramPacket) {
            if (rng.nextDouble() < loss) return
            val copy = DatagramPacket(p.data.copyOfRange(p.offset, p.offset + p.length), p.length, p.socketAddress)
            val d = rng.nextInt(jitterMs + 1)
            if (d < 2) super.send(copy) else thread(isDaemon = true) { Thread.sleep(d.toLong()); runCatching { super.send(copy) } }
        }
    }

    private fun pair(loss: Double, jitter: Int): Pair<Rudp.Stream, Rudp.Stream> {
        val a = Lossy(loss, jitter, 1); val b = Lossy(loss, jitter, 2)
        val sid = Rudp.newSession()
        val fa = CompletableFuture.supplyAsync { Rudp.punch(a, sid, listOf(b.localSocketAddress)) }
        val pb = Rudp.punch(b, sid, listOf(a.localSocketAddress))
        val pa = fa.get()
        assertEquals(b.localSocketAddress, pa); assertEquals(a.localSocketAddress, pb)
        return Rudp.Stream(a, pa!!, sid, 60_000) to Rudp.Stream(b, pb!!, sid, 60_000)
    }

    private fun readExact(c: Conn, n: Int): ByteArray {
        val out = ByteArray(n); var off = 0
        while (off < n) { val r = c.input.read(out, off, n - off); if (r < 0) break; off += r }
        return out.copyOf(off)
    }

    private fun transfer(loss: Double, jitter: Int, size: Int) {
        val (x, y) = pair(loss, jitter)
        x.setTimeout(60_000); y.setTimeout(60_000)
        val d1 = ByteArray(size).also { Random(3).nextBytes(it) }; val d2 = ByteArray(size / 2).also { Random(4).nextBytes(it) }
        val gotY = CompletableFuture.supplyAsync { readExact(y, d1.size) }
        x.output.write(d1); y.output.write(d2)
        assertArrayEquals(d2, readExact(x, d2.size))
        assertArrayEquals(d1, gotY.get())
        x.close()
        assertEquals(-1, y.input.read(ByteArray(10), 0, 10))     // FIN: end of stream
        y.close()
    }

    @Test fun clean() = transfer(0.0, 0, 1_000_000)
    @Test fun lossAndReordering() = transfer(0.1, 30, 150_000)

    /** Kotlin ↔ Python (peer/rudp.py via tools/rudp_peer.py): the same datagrams both ways. */
    @Test fun interopWithPython() {
        val py = File(repo(), ".venv/bin/python")
        assumeTrue("needs the repo's .venv", py.canExecute())
        val sid = Rudp.newSession()
        val proc = ProcessBuilder(py.path, File(repo(), "tools/rudp_peer.py").path, sid.joinToString("") { "%02x".format(it) }).start()
        try {
            val lines = proc.inputStream.bufferedReader()
            val port = lines.readLine().trim().toInt()
            val u = DatagramSocket(InetSocketAddress("127.0.0.1", 0))
            proc.outputStream.write("127.0.0.1:${u.localPort}\n".toByteArray()); proc.outputStream.flush()
            val peer = Rudp.punch(u, sid, listOf(InetSocketAddress("127.0.0.1", port)), 8000)
            assertEquals(InetSocketAddress("127.0.0.1", port), peer)
            val s = Rudp.Stream(u, peer!!, sid, 60_000); s.setTimeout(60_000)
            val data = ByteArray(400_000).also { Random(9).nextBytes(it) }
            s.output.write(java.nio.ByteBuffer.allocate(4).putInt(data.size).array() + data)
            assertArrayEquals(MessageDigest.getInstance("SHA-256").digest(data), readExact(s, 32))
            val expect = ByteArray(300_000)
            val back = readExact(s, 300_000)
            assertEquals(300_000, back.size)
            s.close()
            assertEquals("done", lines.readLine())
            assertTrue(proc.waitFor(10, java.util.concurrent.TimeUnit.SECONDS))
        } finally { proc.destroy() }
    }
}

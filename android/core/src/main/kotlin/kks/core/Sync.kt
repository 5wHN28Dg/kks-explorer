package kks.core

import java.io.DataInputStream
import java.io.EOFException
import java.io.InputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket

/**
 * Sync between two peers (docs/PROTOCOL.md §15), twin of peer/sync.py: a Noise XX connection bound to device keys,
 * then an exchange of the entries (and photos) each side lacks. Transport: any byte streams (TCP on the same Wi-Fi).
 */
class SyncError(msg: String) : Exception(msg)

/** What sync needs from a device's store (server/engine.py and [MemoryNode] implement it). */
interface Node {
    fun identity(): SigningKey
    fun root(): String?
    fun adopt(root: String)
    fun vv(): Map<String, List<Any>>                 // device → [last seq, entry id of it]
    fun entriesFor(vv: Map<*, *>): List<Map<String, Any?>>
    fun ingest(entries: List<Any?>): Int
    fun mayRead(peer: String): Boolean
    fun blobWants(): List<String>
    fun blobGet(sha: String): ByteArray?
    fun blobPut(sha: String, data: ByteArray): Boolean
}

data class SyncStats(var sent: Int = 0, var received: Int = 0, var blobsSent: Int = 0, var blobsReceived: Int = 0,
                     var denied: Boolean = false, var theyDenied: Boolean = false)

object Sync {
    const val VERSION = 1L
    val PROLOGUE = "kks-sync-v1".toByteArray()
    val STATIC_DOMAIN = "kks-noise-static-v1\n".toByteArray()
    const val CHUNK = 65000
    const val MAX_MESSAGE = 64 * 1024 * 1024
    const val TIMEOUT_MS = 30_000

    /** The X25519 key a device uses in Noise, derived from its Ed25519 seed. */
    fun staticKey(identity: SigningKey) = X25519Key(hmacSha256(identity.seed, "kks-noise-static-v1".toByteArray()))

    fun identityPayload(identity: SigningKey, static: X25519Key): ByteArray =
        Canonical.bytes(mapOf("peer" to identity.peerId, "sig" to B64u.encode(identity.sign(STATIC_DOMAIN + static.publicKey))))

    /** -> the peer ID of the device owning `remoteStatic`. */
    fun checkIdentity(payload: ByteArray, remoteStatic: ByteArray): String {
        try {
            val d = Json.parse(payload) as Map<*, *>
            val peer = d["peer"] as String
            if (peer.length == 43 && ed25519Verify(B64u.decode(peer), B64u.decode(d["sig"] as String), STATIC_DOMAIN + remoteStatic)) return peer
        } catch (e: Exception) { /* fall through */ }
        throw SyncError("the other side did not prove its device key")
    }

    // ---------- framing ----------
    private fun sendFrame(out: OutputStream, data: ByteArray) {
        out.write(byteArrayOf((data.size shr 8).toByte(), data.size.toByte()))
        out.write(data)
        out.flush()
    }

    private fun recvFrame(inp: InputStream): ByteArray = try {
        val d = DataInputStream(inp)
        val n = d.readUnsignedShort()
        ByteArray(n).also { d.readFully(it) }
    } catch (e: EOFException) {
        throw SyncError("connection closed")
    }

    class Session(private val inp: InputStream, private val out: OutputStream, private val tx: CipherState,
                  private val rx: CipherState, val remote: String) {
        fun send(obj: Map<String, Any?>) {
            val data = Json.write(obj).toByteArray(Charsets.UTF_8)
            var i = 0
            do {
                val part = data.copyOfRange(i, minOf(i + CHUNK, data.size))
                val more: Byte = if (i + CHUNK < data.size) 1 else 0
                sendFrame(out, tx.encrypt(ByteArray(0), byteArrayOf(more) + part))
                i += CHUNK
            } while (i < data.size)
        }

        @Suppress("UNCHECKED_CAST")
        fun recv(): Map<String, Any?> {
            val buf = java.io.ByteArrayOutputStream()
            while (true) {
                val pt = try { rx.decrypt(ByteArray(0), recvFrame(inp)) } catch (e: NoiseError) { throw SyncError(e.message ?: "noise") }
                buf.write(pt, 1, pt.size - 1)
                if (buf.size() > MAX_MESSAGE) throw SyncError("message too large")
                if (pt[0] == 0.toByte()) break
            }
            val obj = try { Json.parse(buf.toByteArray()) } catch (e: JsonError) { throw SyncError("bad message") }
            if (obj !is Map<*, *> || obj["t"] !is String) throw SyncError("bad message")
            if (obj["t"] == "error") throw SyncError("the other side stopped: ${obj["why"].toString().take(200)}")
            return obj as Map<String, Any?>
        }

        fun expect(t: String): Map<String, Any?> = recv().also { if (it["t"] != t) throw SyncError("expected $t, got ${it["t"]}") }
    }

    fun handshake(inp: InputStream, out: OutputStream, identity: SigningKey, initiator: Boolean): Session {
        val s = staticKey(identity)
        val hs = Handshake(initiator, s, PROLOGUE)
        val remote: String
        try {
            if (initiator) {
                sendFrame(out, hs.write())
                remote = checkIdentity(hs.read(recvFrame(inp)), hs.rs!!)
                sendFrame(out, hs.write(identityPayload(identity, s)))
            } else {
                hs.read(recvFrame(inp))
                sendFrame(out, hs.write(identityPayload(identity, s)))
                remote = checkIdentity(hs.read(recvFrame(inp)), hs.rs!!)
            }
        } catch (e: NoiseError) {
            throw SyncError("handshake failed: ${e.message}")
        }
        val (tx, rx) = hs.split()
        return Session(inp, out, tx, rx, remote)
    }

    // ---------- the exchange ----------
    fun exchange(ses: Session, node: Node, initiator: Boolean, adoptRoot: String? = null): SyncStats {
        fun turn(mine: Map<String, Any?>, t: String): Map<String, Any?> =
            if (initiator) { ses.send(mine); ses.expect(t) } else ses.expect(t).also { ses.send(mine) }

        val root = node.root()
        val hello = turn(mapOf("t" to "hello", "v" to VERSION, "root" to root, "vv" to node.vv()), "hello")
        if (hello["v"] != VERSION) throw SyncError("protocol version ${hello["v"]} (this device speaks $VERSION)")
        val theirs = hello["root"]
        if (root == null) {
            if (theirs == null || theirs != adoptRoot) throw SyncError("this device has no plant yet and the other side's plant was not the expected one")
            node.adopt(theirs as String)
        } else if (theirs != null && theirs != root) throw SyncError("the other device belongs to a different plant")
        val st = SyncStats()
        val vv = hello["vv"] as? Map<*, *> ?: emptyMap<String, Any>()

        fun offer(): Map<String, Any?> {
            if (!node.mayRead(ses.remote)) {
                st.denied = true
                return mapOf("t" to "entries", "entries" to emptyList<Any>(), "denied" to true)
            }
            val out = node.entriesFor(vv)
            st.sent = out.size
            return mapOf("t" to "entries", "entries" to out)
        }

        val got: Map<String, Any?>
        if (initiator) {
            ses.send(offer())
            got = ses.expect("entries")
            st.received = node.ingest(got["entries"] as? List<Any?> ?: emptyList())
        } else {
            got = ses.expect("entries")
            st.received = node.ingest(got["entries"] as? List<Any?> ?: emptyList())
            ses.send(offer())
        }
        st.theyDenied = got["denied"] == true
        val theirWant = (turn(mapOf("t" to "want", "blobs" to node.blobWants()), "want")["blobs"] as? List<*>) ?: emptyList<Any>()

        fun sendBlobs() {
            if (node.mayRead(ses.remote)) for (sha in theirWant.take(10000)) {
                val data = (sha as? String)?.let { node.blobGet(it) } ?: continue
                ses.send(mapOf("t" to "blob", "sha" to sha, "data" to java.util.Base64.getEncoder().encodeToString(data)))
                st.blobsSent++
            }
            ses.send(mapOf("t" to "blobs_end"))
        }

        fun recvBlobs() {
            while (true) {
                val m = ses.recv()
                if (m["t"] == "blobs_end") return
                if (m["t"] != "blob") throw SyncError("expected blob")
                val data = try { java.util.Base64.getDecoder().decode(m["data"] as String) } catch (e: Exception) { throw SyncError("bad blob") }
                if ((m["sha"] as? String)?.let { node.blobPut(it, data) } == true) st.blobsReceived++
            }
        }

        if (initiator) { sendBlobs(); recvBlobs() } else { recvBlobs(); sendBlobs() }
        turn(mapOf("t" to "bye"), "bye")
        return st
    }

    /** Connect, sync, close. -> (remote peer ID, stats) */
    fun syncWith(node: Node, host: String, port: Int, adoptRoot: String? = null, timeoutMs: Int = TIMEOUT_MS): Pair<String, SyncStats> {
        Socket().use { sock ->
            sock.connect(InetSocketAddress(host, port), timeoutMs)
            sock.soTimeout = timeoutMs
            val ses = handshake(sock.getInputStream(), sock.getOutputStream(), node.identity(), true)
            return ses.remote to exchange(ses, node, true, adoptRoot)
        }
    }

    /** Handle one incoming connection. -> (remote, stats); errors propagate after telling the other side. */
    fun serveOne(node: Node, sock: Socket, timeoutMs: Int = TIMEOUT_MS): Pair<String, SyncStats> {
        sock.use {
            it.soTimeout = timeoutMs
            val ses = handshake(it.getInputStream(), it.getOutputStream(), node.identity(), false)
            try {
                return ses.remote to exchange(ses, node, false)
            } catch (e: SyncError) {
                runCatching { ses.send(mapOf("t" to "error", "why" to e.message)) }
                throw e
            }
        }
    }
}

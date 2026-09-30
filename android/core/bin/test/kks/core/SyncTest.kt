package kks.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File
import java.net.ServerSocket
import kotlin.concurrent.thread

@Suppress("UNCHECKED_CAST")
class SyncTest {
    @Test fun noisePublishedVector() {
        val v = (vector("noise-xx.json")["vectors"] as List<Map<String, Any?>>)[0]
        fun b(k: String) = (v[k] as String).unhex()
        val i = Handshake(true, X25519Key(b("init_static")), b("init_prologue"), X25519Key(b("init_ephemeral")))
        val r = Handshake(false, X25519Key(b("resp_static")), b("resp_prologue"), X25519Key(b("resp_ephemeral")))
        val msgs = v["messages"] as List<Map<String, Any?>>
        for (k in 0..2) {
            val (w, rd) = if (k % 2 == 0) i to r else r to i
            val ct = w.write((msgs[k]["payload"] as String).unhex())
            assertEquals(msgs[k]["ciphertext"], ct.hex())
            assertEquals(msgs[k]["payload"], rd.read(ct).hex())
        }
        assertEquals(v["handshake_hash"], i.h.hex())
        val (isend, irecv) = i.split()
        val (rsend, rrecv) = r.split()
        for (k in 3 until msgs.size) {
            val (tx, rx) = if (k % 2 == 1) rsend to irecv else isend to rrecv
            val ct = tx.encrypt(ByteArray(0), (msgs[k]["payload"] as String).unhex())
            assertEquals(msgs[k]["ciphertext"], ct.hex())
            assertEquals(msgs[k]["payload"], rx.decrypt(ByteArray(0), ct).hex())
        }
    }

    @Test fun syncVectors() {
        val v = vector("v3-sync.json")
        for (k in v["static_keys"] as List<Map<String, Any?>>) {
            val id = SigningKey((k["ed25519_seed_hex"] as String).unhex())
            assertEquals(k["peer"], id.peerId)
            assertEquals(k["x25519_private_hex"], Sync.staticKey(id).privateBytes.hex())
            assertEquals(k["x25519_public_hex"], Sync.staticKey(id).publicKey.hex())
        }
        val seeds = (v["static_keys"] as List<Map<String, Any?>>).associate { it["device"] to SigningKey((it["ed25519_seed_hex"] as String).unhex()) }
        val ip = v["identity_payload"] as Map<String, Any?>
        val bob = seeds["bob-phone"]!!
        assertEquals(ip["signed_bytes_hex"], (Sync.STATIC_DOMAIN + Sync.staticKey(bob).publicKey).hex())
        assertEquals(ip["payload_utf8"], String(Sync.identityPayload(bob, Sync.staticKey(bob)), Charsets.UTF_8))
        val hs = v["handshake"] as Map<String, Any?>
        val a = seeds[hs["initiator"]]!!
        val i = Handshake(true, Sync.staticKey(a), Sync.PROLOGUE, X25519Key((hs["initiator_ephemeral_hex"] as String).unhex()))
        val r = Handshake(false, Sync.staticKey(bob), Sync.PROLOGUE, X25519Key((hs["responder_ephemeral_hex"] as String).unhex()))
        val m = hs["messages_hex"] as List<String>
        assertEquals(m[0], i.write().hex()); r.read(m[0].unhex())
        assertEquals(m[1], r.write(Sync.identityPayload(bob, Sync.staticKey(bob))).hex())
        assertEquals(bob.peerId, Sync.checkIdentity(i.read(m[1].unhex()), i.rs!!))
        assertEquals(m[2], i.write(Sync.identityPayload(a, Sync.staticKey(a))).hex())
        assertEquals(a.peerId, Sync.checkIdentity(r.read(m[2].unhex()), r.rs!!))
        assertEquals(hs["handshake_hash_hex"], i.h.hex())
        val ft = hs["first_transport"] as Map<String, Any?>
        assertEquals(ft["ciphertext_hex"], i.split().first.encrypt(ByteArray(0), byteArrayOf(0) + (ft["plaintext_utf8"] as String).toByteArray()).hex())
    }

    /** A plant on node A (manager) and a certified user device B, both Kotlin. */
    private fun plant(): Triple<MemoryNode, MemoryNode, String> {
        val root = SigningKey.generate()
        val mgr = SigningKey.generate()
        val a = MemoryNode(mgr, root.peerId)
        val m = "a".repeat(32)
        val sm = mapOf("kind" to "manager", "person" to m)
        val sd = mapOf("kind" to "device", "device" to mgr.peerId, "person" to m)
        a.append("genesis", mapOf("plant" to "K", "root" to root.peerId,
            "manager" to mapOf("person" to m, "username" to "boss", "full_name" to "Boss Person", "position" to null),
            "stmt_manager" to sm, "stmt_device" to sd, "sig_manager" to Replay.signStatement(root, sm), "sig_device" to Replay.signStatement(root, sd)))
        val bkey = SigningKey.generate()
        val u = "b".repeat(32)
        a.append("person", mapOf("person" to u, "username" to "bob", "full_name" to "Bob Person", "position" to null, "role" to "user"))
        a.append("device_cert", mapOf("device" to bkey.peerId, "person" to u, "label" to "phone"))
        return Triple(a, MemoryNode(bkey), root.peerId)
    }

    private fun listen(node: Node): Int {
        val srv = ServerSocket(0)
        thread(isDaemon = true) { runCatching { Sync.serveOne(node, srv.accept()) }; srv.close() }
        return srv.localPort
    }

    @Test fun kotlinToKotlin() {
        val (a, b, root) = plant()
        val (remote, st) = Sync.syncWith(b, "127.0.0.1", listen(a), adoptRoot = root)
        assertEquals(a.identity().peerId, remote)
        assertEquals(String(Canonical.stateBytes(a.state())), String(Canonical.stateBytes(b.state())))
        assertTrue(st.received > 0)
        val prop = b.append("link", mapOf("proc" to "p", "step" to 1L, "kks" to "11LAB70AA501", "on" to true))
        Sync.syncWith(b, "127.0.0.1", listen(a))
        assertEquals("pending", a.run.proposals[prop])
        // a stranger gets nothing and leaves nothing
        val x = MemoryNode(SigningKey.generate(), root)
        x.append("link", mapOf("proc" to "p", "step" to 2L, "kks" to "11LAB70AA501", "on" to true))
        val before = a.entries.size
        val (_, xs) = Sync.syncWith(x, "127.0.0.1", listen(a))
        assertTrue(xs.theyDenied)
        assertEquals(before, a.entries.size)
    }

    /** The real Python engine (tools/interop_node.py) on the other end, both directions. */
    @Test fun kotlinToPython() {
        val py = File(repo(), ".venv/bin/python")
        assumeTrue("needs the repo's .venv (python3 app.py setup-importer)", py.canExecute())
        val key = SigningKey.generate()
        val proc = ProcessBuilder(py.path, File(repo(), "tools/interop_node.py").path, "--device-seed", key.seed.hex())
            .redirectError(ProcessBuilder.Redirect.INHERIT).start()
        val out = proc.outputStream.bufferedWriter()
        val inp = proc.inputStream.bufferedReader()
        fun ask(cmd: String): Map<String, Any?> { out.write(cmd + "\n"); out.flush(); return Json.parse(inp.readLine()) as Map<String, Any?> }
        try {
            val hello = Json.parse(inp.readLine()) as Map<String, Any?>
            val k = MemoryNode(key)
            // Kotlin connects to Python: joins the plant, gets the log and the photo
            val (_, st) = Sync.syncWith(k, "127.0.0.1", (hello["port"] as Long).toInt(), adoptRoot = hello["root"] as String)
            assertTrue(st.received >= 6)
            assertEquals(1, st.blobsReceived)
            assertEquals(hello["photo_sha"], k.blobs.keys.single())
            assertEquals(ask("state")["state"], String(Canonical.stateBytes(k.state()), Charsets.UTF_8))
            // Kotlin proposes (a link and a photo); Python receives both, approves the link
            val link = k.append("link", mapOf("proc" to "3.6.1", "step" to 2L, "kks" to "11LAB70AA501", "on" to true))
            val jpeg = byteArrayOf(-1, -40, -1, -32) + ByteArray(500) { it.toByte() }
            val sha = sha256(jpeg).hex()
            k.blobs[sha] = jpeg
            k.append("photo", mapOf("photo" to "c".repeat(32), "kks" to "11LAB70AA501", "blob" to sha, "caption" to "from Kotlin ☃"))
            val (_, st2) = Sync.syncWith(k, "127.0.0.1", (hello["port"] as Long).toInt())
            assertEquals(2, st2.sent)
            assertEquals(true, ask("has_blob $sha")["has"])
            assertEquals(null, ask("approve $link")["error"])
            // now Python connects to Kotlin
            val r = ask("sync ${listen(k)}")
            assertEquals(r.toString(), k.identity().peerId, r["remote"])
            assertEquals("approved", k.run.proposals[link])
            assertEquals(ask("state")["state"], String(Canonical.stateBytes(k.state()), Charsets.UTF_8))
        } finally {
            runCatching { out.write("quit\n"); out.flush() }
            proc.waitFor(10, java.util.concurrent.TimeUnit.SECONDS)
            proc.destroy()
        }
    }
}

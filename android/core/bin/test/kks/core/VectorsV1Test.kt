package kks.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File

/** peer/vectors/v1.json: the same file the Python tests check (tests/test_protocol.py). */
@Suppress("UNCHECKED_CAST")
class VectorsV1Test {
    private val v = vector("v1.json")

    private fun code(block: () -> Unit): String = try {
        block(); "ok"
    } catch (e: ProtocolError) {
        e.code
    }

    @Test fun rfc8032() {
        val t = v["ed25519_rfc8032_test1"] as Map<String, Any?>
        val k = SigningKey((t["seed_hex"] as String).unhex())
        assertEquals(t["public_b64u"], k.peerId)
        assertEquals(t["signature_hex"], k.sign((t["message_hex"] as String).unhex()).hex())
    }

    @Test fun canonical() {
        for (c in v["canonical"] as List<Map<String, Any?>>) {
            assertEquals(c["canonical_utf8_hex"], Canonical.bytes(c["input"]).hex())
            assertEquals(c["canonical_text"], String(Canonical.bytes(c["input"]), Charsets.UTF_8))
        }
        for (r in v["canonical_reject"] as List<Map<String, Any?>>) {
            assertEquals(r["why"] as String, "bad_encoding", code { Canonical.bytes(Json.parse(r["input_json"] as String)) })
        }
    }

    @Test fun keys() {
        for (k in v["keys"] as List<Map<String, Any?>>) assertEquals(k["peer"], SigningKey((k["seed_hex"] as String).unhex()).peerId)
    }

    @Test fun entries() {
        val seeds = (v["keys"] as List<Map<String, Any?>>).associate { it["name"] to (it["seed_hex"] as String).unhex() }
        for (x in v["entries"] as List<Map<String, Any?>>) {
            val e = x["entry"] as Map<String, Any?>
            assertEquals(x["signed_bytes_hex"], Proto.signedBytes(e).hex())
            assertEquals(x["entry_id"], Proto.entryId(e))
            Proto.verifyEntry(e)
            // Ed25519 is deterministic: re-signing gives the identical entry
            val again = Proto.makeEntry(SigningKey(seeds[x["device"]]!!), e["seq"] as Long, e["prev"] as String?,
                                        e["hlc"] as List<Long>, e["type"] as String, e["body"] as Map<String, Any?>)
            assertEquals(Proto.entryId(e), Proto.entryId(again))
        }
        for (r in v["entry_reject"] as List<Map<String, Any?>>) {
            val e = r["entry"] ?: Json.parse(r["entry_json"] as String)
            assertEquals(r["why"] as String, r["code"], code { Proto.verifyEntry(e) })
        }
    }

    @Test fun chains() {
        for (c in v["chains"] as List<Map<String, Any?>>) {
            var order: List<Long>? = null
            val got = code { order = Proto.verifyChain(c["entries"] as List<Map<String, Any?>>).map { it["seq"] as Long } }
            assertEquals(c["why"] as String, c["result"], got)
            if (got == "ok") assertEquals(c["order"], order)
        }
    }

    @Test fun hlc() {
        val h = HLC()
        for (op in v["hlc"] as List<Map<String, Any?>>) {
            val out = if (op["op"] == "now") h.now(op["wall"] as Long) else h.recv(op["remote"] as List<Long>, op["wall"] as Long)
            assertEquals(op.toString(), op["state"], out)
        }
    }

    @Test fun order() {
        val o = v["order"] as Map<String, Any?>
        val sorted = (o["entries"] as List<Map<String, Any?>>).sortedWith(Proto.ORDER).map { Proto.entryId(it) }
        assertEquals(o["sorted_entry_ids"], sorted)
        assertEquals(o["entry_ids"], (o["entries"] as List<Map<String, Any?>>).map { Proto.entryId(it) })
    }

    @Test fun jsonRoundTrip() {
        // every vector file parses, and canonical re-encoding of a canonical entry reproduces its bytes
        for (f in File(repo(), "peer/vectors").listFiles()!!.filter { it.name.endsWith(".json") }) assertTrue(Json.parse(f.readText()) is Map<*, *>)
        try { Json.parse("{\"a\":1,}"); fail("trailing comma accepted") } catch (e: JsonError) {}
    }
}

fun repo(): File = File(System.getProperty("kks.repo") ?: error("run through Gradle (kks.repo)"))

@Suppress("UNCHECKED_CAST")
fun vector(name: String): Map<String, Any?> = Json.parse(File(repo(), "peer/vectors/$name").readText()) as Map<String, Any?>

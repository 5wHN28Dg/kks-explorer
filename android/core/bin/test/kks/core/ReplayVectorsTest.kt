package kks.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** peer/vectors/v2-replay.json and v4-malformed.json: states must match the Python replay byte for byte. */
@Suppress("UNCHECKED_CAST")
class ReplayVectorsTest {
    private fun check(file: String) {
        for (s in vector(file)["scenarios"] as List<Map<String, Any?>>) {
            val entries = s["entries"] as List<Any?>
            val want = String(Canonical.stateBytes(s["state"]), Charsets.UTF_8)
            val got = String(Canonical.stateBytes(Replay.replay(entries, s["root"] as String)), Charsets.UTF_8)
            if (got != want) {   // show where they part, not two megabytes
                val i = got.zip(want).indexOfFirst { (a, b) -> a != b }.let { if (it < 0) minOf(got.length, want.length) else it }
                throw AssertionError("${s["why"]}: differs at $i\n want …${want.substring(maxOf(0, i - 200), minOf(want.length, i + 200))}\n got  …${got.substring(maxOf(0, i - 200), minOf(got.length, i + 200))}")
            }
            for (seed in 1..3) {   // any input order gives the same state
                val shuffled = entries.shuffled(java.util.Random(seed.toLong()))
                assertEquals(s["why"] as String, want, String(Canonical.stateBytes(Replay.replay(shuffled, s["root"] as String)), Charsets.UTF_8))
            }
        }
    }

    @Test fun replayScenarios() = check("v2-replay.json")

    @Test fun malformedBodies() = check("v4-malformed.json")

    @Test fun statement() {
        val t = vector("v2-replay.json")["statement"] as Map<String, Any?>
        val root = SigningKey((t["root_seed_hex"] as String).unhex())
        assertEquals(t["root"], root.peerId)
        assertEquals(t["signed_bytes_hex"], (Replay.STMT_DOMAIN + Canonical.bytes(t["stmt"])).hex())
        assertEquals(t["root_sig"], Replay.signStatement(root, t["stmt"] as Map<String, Any?>))
    }

    @Test fun privateEntry() {
        val t = vector("v2-replay.json")["private"] as Map<String, Any?>
        val secret = (t["secret_hex"] as String).unhex()
        val p = t["plaintext"] as Map<String, Any?>
        val body = Replay.privateBody(secret, t["person"] as String, p["type"] as String, p["body"] as Map<String, Any?>,
                                      (t["nonce_hex"] as String).unhex())
        assertEquals(t["body"], body)
        assertEquals(p, Replay.privateOpen(secret, t["body"] as Map<String, Any?>))
        assertTrue(runCatching { Replay.privateOpen(ByteArray(32), t["body"] as Map<String, Any?>) }.isFailure)
    }
}

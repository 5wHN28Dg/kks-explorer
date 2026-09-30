package kks.core

/**
 * Protocol v1 entries (docs/PROTOCOL.md §2–6), the Kotlin twin of peer/proto.py. An entry is a Map with exactly
 * v, peer, seq, prev, hlc, type, body, sig. Every check raises [ProtocolError] with the same code, in the same order,
 * as the Python implementation: the shared vectors (peer/vectors/v1.json) decide.
 */
object Proto {
    const val VERSION = 1L
    val DOMAIN = "kks-log-v1\n".toByteArray()
    const val SKEW_MS = 86_400_000L
    private val FIELDS = setOf("v", "peer", "seq", "prev", "hlc", "type", "body", "sig")
    private val HEX64 = Regex("[0-9a-f]{64}")

    fun signedBytes(e: Map<String, Any?>): ByteArray = DOMAIN + Canonical.bytes(e.filterKeys { it != "sig" })

    fun entryId(e: Map<String, Any?>): String = sha256(Canonical.bytes(e)).hex()

    fun makeEntry(key: SigningKey, seq: Long, prev: String?, hlc: List<Long>, type: String, body: Map<String, Any?>): Map<String, Any?> {
        val e = linkedMapOf<String, Any?>("v" to VERSION, "peer" to key.peerId, "seq" to seq, "prev" to prev, "hlc" to hlc,
                                          "type" to type, "body" to body)
        checkFields(e, signed = false)
        e["sig"] = B64u.encode(key.sign(signedBytes(e)))
        return e
    }

    fun checkFields(e: Any?, signed: Boolean = true) {
        val want = if (signed) FIELDS else FIELDS - "sig"
        if (e !is Map<*, *> || e.keys != want) throw ProtocolError("bad_fields", "field set")
        Canonical.check(e)
        if (e["v"] != VERSION) throw ProtocolError("bad_version")
        val peer = e["peer"]
        if (peer !is String || peer.length != 43) throw ProtocolError("bad_fields", "peer")
        val seq = e["seq"]
        if (seq !is Long || seq < 1) throw ProtocolError("bad_seq")
        val prev = e["prev"]
        if (seq == 1L) {
            if (prev != null) throw ProtocolError("bad_prev", "seq 1 must have prev null")
        } else if (prev !is String || !HEX64.matches(prev)) throw ProtocolError("bad_prev")
        val h = e["hlc"]
        if (h !is List<*> || h.size != 2 || !h.all { it is Long && it >= 0 }) throw ProtocolError("bad_fields", "hlc")
        val t = e["type"]
        if (t !is String || !Canonical.KEY.matches(t)) throw ProtocolError("bad_fields", "type")
        if (e["body"] !is Map<*, *>) throw ProtocolError("bad_fields", "body")
        if (signed && e["sig"] !is String) throw ProtocolError("bad_fields", "sig")
    }

    /** Raises unless `e` is a valid, correctly signed entry. */
    @Suppress("UNCHECKED_CAST")
    fun verifyEntry(e: Any?) {
        checkFields(e)
        val m = e as Map<String, Any?>
        val ok = try {
            ed25519Verify(B64u.decode(m["peer"] as String), B64u.decode(m["sig"] as String), signedBytes(m))
        } catch (x: IllegalArgumentException) {
            false
        }
        if (!ok) throw ProtocolError("bad_sig")
    }

    /** Entries of ONE device, any order. Valid = contiguous from seq 1 with matching prev links. Returns them sorted. */
    fun verifyChain(entries: List<Map<String, Any?>>): List<Map<String, Any?>> {
        val bySeq = HashMap<Long, Map<String, Any?>>()
        for (e in entries) {
            verifyEntry(e)
            val seq = e["seq"] as Long
            val have = bySeq[seq]
            if (have != null && entryId(have) != entryId(e)) throw ProtocolError("fork", "seq $seq")
            bySeq[seq] = e
        }
        if (entries.map { it["peer"] }.toSet().size > 1) throw ProtocolError("bad_fields", "entries from more than one device")
        val chain = bySeq.keys.sorted().map { bySeq[it]!! }
        chain.forEachIndexed { i, e ->
            if (e["seq"] != (i + 1).toLong()) throw ProtocolError("chain_gap", "missing seq ${i + 1}")
            if (i > 0 && e["prev"] != entryId(chain[i - 1])) throw ProtocolError("chain_prev", "seq ${e["seq"]}")
        }
        return chain
    }

    /** Total order (§6): (hlc[0], hlc[1], peer, seq). */
    val ORDER: Comparator<Map<String, Any?>> = Comparator { a, b ->
        val ha = a["hlc"] as List<*>
        val hb = b["hlc"] as List<*>
        compareValuesBy(ha, hb, { it[0] as Long }, { it[1] as Long }).takeIf { it != 0 }
            ?: cmpCodePoints(a["peer"] as String, b["peer"] as String).takeIf { it != 0 }
            ?: (a["seq"] as Long).compareTo(b["seq"] as Long)
    }
}

/** Hybrid logical clock (§5). */
class HLC(var l: Long = 0, var c: Long = 0) {
    fun now(wall: Long): List<Long> {
        if (wall > l) { l = wall; c = 0 } else c++
        return listOf(l, c)
    }

    fun recv(remote: List<Long>, wall: Long): List<Long> {
        val (rl, rc) = remote
        if (rl > wall + Proto.SKEW_MS) return listOf(l, c)   // a device with a wrong date must not drag clocks forward
        val big = maxOf(l, rl, wall)
        val nc = when {
            big == l && big == rl -> maxOf(c, rc) + 1
            big == l -> c + 1
            big == rl -> rc + 1
            else -> 0
        }
        l = big; c = nc
        return listOf(l, c)
    }
}

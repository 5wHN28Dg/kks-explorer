package kks.core

import java.util.IdentityHashMap

/**
 * Replay (docs/PROTOCOL.md §8–14): identity, authority, revocation, approvals, merge, private entries. The Kotlin twin
 * of peer/replay.py, check for check and in the same order: the reason an entry is ignored is part of the state, and
 * the vectors (v2-replay, v4-malformed) compare states byte for byte.
 */
object Replay {
    val STMT_DOMAIN = "kks-root-v1\n".toByteArray()
    val PRIVATE_DOMAIN = "kks-private-v1\n".toByteArray()
    const val MAX_ROUNDS = 8

    internal val ID = Regex("[0-9a-f]{32}")
    internal val HEX64 = Regex("[0-9a-f]{64}")
    internal val PEER = Regex("[A-Za-z0-9_-]{43}")
    internal val B64U = Regex("[A-Za-z0-9_-]*")
    internal val USER = Regex("[A-Za-z0-9_.@-]{2,40}")
    internal val KKS = Regex("[0-9A-Z/]{3,24}")
    internal val CODE = Regex("[0-9]{2}[A-Z]{3}[0-9]{2}[A-Z]{2}[0-9]{3}")
    internal val SUFFIX = Regex("[A-Z0-9]{0,4}")
    internal val ISA = Regex("[A-Z]{1,6}")
    internal val SHEET = Regex("[a-z0-9][a-z0-9-]{0,23}")
    internal val TAGID = Regex("[A-Za-z0-9:_.-]{1,64}")

    val EQ_FIELDS = setOf("area", "floor", "elev", "near", "loc", "notes", "custom")
    val DATA_TYPES = setOf("equipment", "review", "link", "photo", "photo_delete", "tag_add", "tag_remove")
    val BODY: Map<String, Set<String>> = mapOf(
        "genesis" to setOf("plant", "root", "manager", "stmt_manager", "stmt_device", "sig_manager", "sig_device"),
        "root" to setOf("stmt", "root_sig"),
        "person" to setOf("person", "username", "full_name", "position", "role"),
        "device_cert" to setOf("device", "person", "label"),
        "revoke" to setOf("device", "last_seq"),
        "setting" to setOf("key", "value"),
        "equipment" to setOf("kks", "changes", "base"),
        "review" to setOf("tag_id", "data", "base"),
        "link" to setOf("proc", "step", "kks", "on"),
        "photo" to setOf("photo", "kks", "blob", "caption"),
        "photo_delete" to setOf("photo"),
        "tag_add" to setOf("tag", "sheet", "bbox", "kks", "suffix", "isa", "note"),
        "tag_remove" to setOf("tag"),
        "approve" to setOf("entry", "edit"),
        "reject" to setOf("entry", "note"),
        "withdraw" to setOf("entry"),
        "vote" to setOf("entry", "on"),
        "private" to setOf("person", "nonce", "ct"),
    )
    val STMT: Map<String, Set<String>> = mapOf(
        "manager" to setOf("kind", "person"), "device" to setOf("kind", "device", "person"),
        "rotate" to setOf("kind", "root"), "revoke" to setOf("kind", "device", "last_seq"))
    val RANK = mapOf("root" to 0, "manager" to 1, "admin" to 2, "user" to 3)

    // ---------- §8 root statements, §13 private entries ----------
    fun signStatement(root: SigningKey, stmt: Map<String, Any?>): String = B64u.encode(root.sign(STMT_DOMAIN + Canonical.bytes(stmt)))

    fun checkStatement(rootPub: String?, stmt: Any?, sig: Any?) {
        need(stmt is Map<*, *> && stmt["kind"] is String && stmt["kind"] in STMT)
        keys(stmt, STMT[(stmt as Map<*, *>)["kind"]]!!)
        need(match(B64U, sig))
        if (rootPub == null) throw Ignore("bad_body")   // (Python: a type error there, caught as bad_body)
        val ok = try {
            ed25519Verify(B64u.decode(rootPub), B64u.decode(sig as String), STMT_DOMAIN + Canonical.bytes(stmt))
        } catch (e: IllegalArgumentException) {
            false
        }
        if (!ok) throw Ignore("bad_root_sig")
    }

    fun privateBody(secret: ByteArray, person: String, type: String, body: Map<String, Any?>, nonce: ByteArray): Map<String, Any?> {
        val ct = ChaChaPoly.encrypt(secret, nonce, Canonical.bytes(mapOf("type" to type, "body" to body)), PRIVATE_DOMAIN + person.toByteArray())
        return mapOf("person" to person, "nonce" to B64u.encode(nonce), "ct" to B64u.encode(ct))
    }

    fun privateOpen(secret: ByteArray, body: Map<String, Any?>): Any? =
        Json.parse(ChaChaPoly.decrypt(secret, B64u.decode(body["nonce"] as String), B64u.decode(body["ct"] as String),
                                      PRIVATE_DOMAIN + (body["person"] as String).toByteArray()))

    // ---------- helpers ----------
    internal class Ignore(val code: String) : Exception(code, null, false, false)

    internal fun need(c: Boolean, code: String = "bad_body") { if (!c) throw Ignore(code) }
    internal fun text(v: Any?, lo: Int = 0, hi: Int = 4000) = v is String && v.codePointCount(0, v.length) in lo..hi
    internal fun match(r: Regex, v: Any?) = v is String && r.matches(v)
    internal fun keys(o: Any?, ks: Set<String>) = need(o is Map<*, *> && o.keys == ks)

    /** Body rules for the data types (§9a). */
    internal fun checkData(t: String, b: Map<*, *>) {
        when (t) {
            "equipment" -> {
                val ch = b["changes"]; val base = b["base"]
                need(match(KKS, b["kks"]) && ch is Map<*, *> && ch.isNotEmpty() && base is Map<*, *>)
                for (d in listOf(ch as Map<*, *>, base as Map<*, *>)) for ((f, v) in d) {
                    need(f in EQ_FIELDS)
                    if (f == "custom") {
                        need(v is List<*> && v.size <= 100)
                        for (x in v as List<*>) {
                            keys(x, setOf("k", "v"))
                            need(text((x as Map<*, *>)["k"], 0, 200) && text(x["v"], 0, 2000))
                        }
                    } else need(text(v))
                }
            }
            "review" -> need(match(TAGID, b["tag_id"]) && (b["data"] == null || b["data"] is Map<*, *>) && (b["base"] == null || b["base"] is Map<*, *>))
            "link" -> {
                val step = b["step"]
                need(text(b["proc"], 1, 32) && step is Long && step >= 0)
                need(match(KKS, b["kks"]) && b["on"] is Boolean)
            }
            "photo" -> {
                need(match(ID, b["photo"]) && match(HEX64, b["blob"]))
                need(match(KKS, b["kks"]) && text(b["caption"], 0, 500))
            }
            "photo_delete" -> need(match(ID, b["photo"]))
            "tag_remove" -> need(match(ID, b["tag"]))
            "tag_add" -> {
                need(match(ID, b["tag"]) && match(SHEET, b["sheet"]))
                val bb = b["bbox"]
                need(bb is List<*> && bb.size == 4 && bb.all { it is Long })
                val (x0, y0, x1, y1) = (bb as List<*>).map { it as Long }
                need(0 <= x0 && x0 < x1 && x1 <= 200000 && 0 <= y0 && y0 < y1 && y1 <= 200000)
                need(b["kks"] == null || match(CODE, b["kks"]))
                need(match(SUFFIX, b["suffix"]) && (b["isa"] == null || match(ISA, b["isa"])))
                need(text(b["note"], 0, 500))
            }
        }
    }

    // ---------- §4 chains across devices ----------
    class Chains(val usable: List<Map<String, Any?>>, val ignored: Map<String, String>, val forks: Map<String, Long>,
                 val ids: IdentityHashMap<Map<String, Any?>, String>)

    /** trusted = {entry id: entry} already verified when stored (a host's own database): not re-checked. */
    fun chains(entries: List<Any?>?, trusted: Map<String, Map<String, Any?>>? = null): Chains {
        val ignored = HashMap<String, String>()
        val byPeer = LinkedHashMap<String, HashMap<Long, LinkedHashMap<String, Map<String, Any?>>>>()
        val ids = IdentityHashMap<Map<String, Any?>, String>()
        val items: List<Pair<String?, Any?>> = trusted?.map { (k, v) -> k to v } ?: entries!!.map { null to it }
        for ((known, raw) in items) {
            var eid = known
            if (eid == null) {
                try {
                    Proto.verifyEntry(raw)
                    @Suppress("UNCHECKED_CAST")
                    eid = Proto.entryId(raw as Map<String, Any?>)
                } catch (err: ProtocolError) {
                    try {
                        @Suppress("UNCHECKED_CAST")
                        ignored[Proto.entryId(raw as Map<String, Any?>)] = err.code
                    } catch (x: Exception) { /* can't even be hashed: nothing to report it under */ }
                    continue
                }
            }
            @Suppress("UNCHECKED_CAST")
            val e = raw as Map<String, Any?>
            ids[e] = eid
            byPeer.getOrPut(e["peer"] as String) { HashMap() }.getOrPut(e["seq"] as Long) { LinkedHashMap() }[eid] = e
        }
        val usable = ArrayList<Map<String, Any?>>()
        val forks = HashMap<String, Long>()
        for ((peer, seqs) in byPeer) {
            var prev: String? = null
            var why: String? = null
            var seq = 1L
            val top = seqs.keys.max()
            while (seq <= top) {
                val cands = seqs[seq] ?: emptyMap()
                if (cands.size > 1) { forks[peer] = seq - 1; why = "fork"; break }
                if (cands.isEmpty()) { why = "chain_gap"; break }
                val (eid, e) = cands.entries.first()
                if (e["prev"] != prev) { why = "chain_prev"; break }
                usable.add(e)
                prev = eid
                seq++
            }
            if (why != null) for ((s, cands) in seqs) for (eid in cands.keys) if (s >= seq) ignored[eid] = why
        }
        return Chains(usable, ignored, forks, ids)
    }

    // ---------- §10 cuts, then the final pass ----------
    fun cuts(ordered: List<Map<String, Any?>>, root: String?, forks: Map<String, Long>,
             ids: IdentityHashMap<Map<String, Any?>, String>): Pair<Map<String, Long>, Set<String>> {
        var cuts: Map<String, Long> = HashMap(forks)
        var accepted: Set<String> = emptySet()
        repeat(MAX_ROUNDS) {
            val run = Run(root, cuts, null, ids).run(ordered)
            val new = HashMap(forks)
            val acc = HashSet<String>()
            for (r in run.revokes.sortedWith(Revoke.ORDER)) {
                if (r.seq > (new[r.peer] ?: Canonical.MAX_INT)) continue
                new[r.device] = minOf(r.last, new[r.device] ?: r.last)
                acc.add(r.eid)
            }
            if (new == cuts && acc == accepted) return cuts to accepted
            cuts = new; accepted = acc
        }
        return cuts to accepted
    }

    /** For hosts: the run (state + side output) and what the chain checks ignored. */
    fun replayRun(entries: List<Any?>?, root: String?, trusted: Map<String, Map<String, Any?>>? = null): Pair<Run, Map<String, String>> {
        val ch = chains(entries, trusted)
        val ordered = ch.usable.sortedWith(Proto.ORDER)
        val (cuts, accepted) = cuts(ordered, root, ch.forks, ch.ids)
        return Run(root, cuts, accepted, ch.ids).run(ordered) to ch.ignored
    }

    /** The replay state (§14) of `entries`, in any order, from the trust anchor `root`. */
    fun replay(entries: List<Any?>, root: String?): Map<String, Any?> {
        val (run, chainIgnored) = replayRun(entries, root)
        val st = run.state().toMutableMap()
        st["ignored"] = (chainIgnored + run.ignored).toSortedMap()
        return st
    }
}

data class Revoke(val rank: Int, val entry: Map<String, Any?>, val peer: String, val seq: Long, val eid: String, val device: String, val last: Long) {
    companion object {
        val ORDER: Comparator<Revoke> = Comparator { a, b ->
            a.rank.compareTo(b.rank).takeIf { it != 0 }
                ?: Proto.ORDER.compare(a.entry, b.entry).takeIf { it != 0 }
                ?: cmpCodePoints(a.peer, b.peer).takeIf { it != 0 }
                ?: a.seq.compareTo(b.seq).takeIf { it != 0 }
                ?: a.eid.compareTo(b.eid).takeIf { it != 0 }
                ?: cmpCodePoints(a.device, b.device).takeIf { it != 0 }
                ?: a.last.compareTo(b.last)
        }
    }
}

/** One pass in total order (§10–12). Also usable incrementally by a host: run(more) for entries that sort after all. */
@Suppress("UNCHECKED_CAST")
class Run(var root: String?, val cuts: Map<String, Long>, val accepted: Set<String>?, private val ids: IdentityHashMap<Map<String, Any?>, String>) {
    private class Decision(val verdict: String, val manager: Boolean, val edit: Map<String, Any?>?, val note: String, val person: String?) {
        var eid = ""
    }

    var manager: String? = null
    val persons = LinkedHashMap<String, MutableMap<String, Any?>>()
    val devices = LinkedHashMap<String, MutableMap<String, Any?>>()
    val settings = LinkedHashMap<String, Any?>()
    val equipment = LinkedHashMap<String, MutableMap<String, Any?>>()
    val eqBy = HashMap<Pair<String, String>, Pair<Boolean, String?>>()
    val reviews = LinkedHashMap<String, Any?>()
    val reviewBy = HashMap<String, Pair<Boolean, String?>>()
    val links = LinkedHashSet<Triple<String, Long, String>>()
    val photos = LinkedHashMap<String, Map<String, Any?>>()
    val tags = LinkedHashMap<String, Map<String, Any?>>()
    val proposals = LinkedHashMap<String, String>()
    private val pending = HashMap<String, Map<String, Any?>>()
    private val waiting = HashMap<String, MutableList<Decision>>()
    val votes = LinkedHashMap<String, MutableSet<String>>()
    val conflicts = ArrayList<Map<String, Any?>>()
    val private = LinkedHashMap<String, MutableList<String>>()
    val ignored = LinkedHashMap<String, String>()
    val revokes = ArrayList<Revoke>()
    // side output for hosts (not part of the state bytes)
    val authors = HashMap<String, String>()
    val decisions = HashMap<String, Map<String, Any?>>()
    val history = ArrayList<Map<String, Any?>>()
    var at: String? = null

    fun role(person: String): String? = if (person == manager) "manager" else persons[person]?.get("role") as String?

    fun run(ordered: List<Map<String, Any?>>): Run {
        for (e in ordered) {
            val eid = ids[e] ?: Proto.entryId(e)
            try {
                if (e["seq"] as Long > (cuts[e["peer"]] ?: Canonical.MAX_INT)) throw Replay.Ignore("revoked")
                if (e["type"] == "genesis") { genesis(e); continue }
                val dev = devices[e["peer"]]
                Replay.need(dev != null, "not_certified")
                Replay.need(e["type"] in Replay.BODY, "unknown_type")
                Replay.keys(e["body"], Replay.BODY[e["type"]]!!)
                at = eid
                val person = dev!!["person"] as String
                dispatch(e["type"] as String, e, eid, person, role(person))
            } catch (x: Replay.Ignore) {
                ignored[eid] = x.code
            } catch (x: ClassCastException) {   // (Python's safety net: never crash on a body)
                ignored[eid] = "bad_body"
            } catch (x: NullPointerException) {
                ignored[eid] = "bad_body"
            }
        }
        return this
    }

    private fun dispatch(t: String, e: Map<String, Any?>, eid: String, author: String, role: String?) = when (t) {
        "root" -> tRoot(e, eid)
        "person" -> tPerson(e, author, role)
        "device_cert" -> tDeviceCert(e, author, role)
        "revoke" -> tRevoke(e, eid, author, role)
        "setting" -> tSetting(e, role)
        "private" -> tPrivate(e, eid, author)
        "approve" -> {
            val edit = body(e)["edit"]
            if (edit != null) Replay.keys(edit, setOf("kks", "suffix", "isa"))
            decision(e, eid, Decision("approved", role == "manager", edit as Map<String, Any?>?, "", null), role)
        }
        "reject" -> {
            Replay.need(Replay.text(body(e)["note"], 0, 500))
            decision(e, eid, Decision("rejected", role == "manager", null, body(e)["note"] as String, null), role)
        }
        "withdraw" -> decision(e, eid, Decision("withdrawn", false, null, "", author), null)
        "vote" -> tVote(e, author)
        else -> data(e, eid, author, role)
    }

    private fun body(e: Map<String, Any?>) = e["body"] as Map<String, Any?>

    private fun revoke(rank: Int, e: Map<String, Any?>, eid: String, device: String, last: Long) {
        revokes.add(Revoke(rank, e, e["peer"] as String, e["seq"] as Long, eid, device, last))
        if (accepted != null && eid !in accepted) throw Replay.Ignore("overridden")
    }

    // ----- identity -----
    private fun personFields(b: Map<*, *>) {
        Replay.need(Replay.match(Replay.ID, b["person"]) && Replay.match(Replay.USER, b["username"]))
        Replay.need(Replay.text(b["full_name"], 2, 80) && (b["position"] == null || Replay.text(b["position"], 0, 80)))
    }

    private fun genesis(e: Map<String, Any?>) {
        val b = e["body"] as Map<String, Any?>
        Replay.need(manager == null, "second_genesis")
        Replay.keys(b, Replay.BODY["genesis"]!!)
        Replay.need(Replay.text(b["plant"], 1, 80))
        Replay.need(pyEquals(b["root"], root), "bad_genesis")
        val m = b["manager"]
        Replay.keys(m, setOf("person", "username", "full_name", "position"))
        m as Map<String, Any?>
        personFields(m)
        Replay.need(pyEquals(b["stmt_manager"], mapOf("kind" to "manager", "person" to m["person"])), "bad_genesis")
        Replay.need(pyEquals(b["stmt_device"], mapOf("kind" to "device", "device" to e["peer"], "person" to m["person"])), "bad_genesis")
        Replay.checkStatement(root, b["stmt_manager"], b["sig_manager"])
        Replay.checkStatement(root, b["stmt_device"], b["sig_device"])
        // stored role 'admin': 'manager' comes from the manager statement, so after a handover they are an admin
        persons[m["person"] as String] = linkedMapOf("username" to m["username"], "full_name" to m["full_name"],
                                                    "position" to m["position"], "role" to "admin")
        manager = m["person"] as String
        devices[e["peer"] as String] = linkedMapOf("person" to m["person"], "label" to "")
        settings["plant"] = b["plant"]
    }

    private fun tRoot(e: Map<String, Any?>, eid: String) {
        val b = body(e)
        val stmt = b["stmt"]
        Replay.checkStatement(root, stmt, b["root_sig"])
        stmt as Map<String, Any?>
        when (stmt["kind"]) {
            "manager" -> {
                Replay.need(Replay.match(Replay.ID, stmt["person"]) && stmt["person"] in persons)
                manager = stmt["person"] as String
            }
            "device" -> {
                Replay.need(Replay.match(Replay.PEER, stmt["device"]) && Replay.match(Replay.ID, stmt["person"]) && stmt["person"] in persons)
                Replay.need((devices[stmt["device"]]?.get("person") ?: stmt["person"]) == stmt["person"], "not_allowed")
                devices.getOrPut(stmt["device"] as String) { linkedMapOf("person" to stmt["person"], "label" to "") }
            }
            "rotate" -> {
                Replay.need(Replay.match(Replay.PEER, stmt["root"]))
                root = stmt["root"] as String
            }
            else -> {
                val last = stmt["last_seq"]
                Replay.need(Replay.match(Replay.PEER, stmt["device"]) && last is Long && last >= 0)
                revoke(Replay.RANK["root"]!!, e, eid, stmt["device"] as String, last as Long)
            }
        }
    }

    private fun tPerson(e: Map<String, Any?>, author: String, role: String?) {
        val b = body(e)
        personFields(b)
        Replay.need(b["role"] == "user" || b["role"] == "admin")
        val pid = b["person"] as String
        val cur = persons[pid]
        if (cur == null) {
            Replay.need(role == "manager" || (role == "admin" && b["role"] == "user"), "not_allowed")
            val u = (b["username"] as String).lowercase()
            Replay.need(persons.values.all { (it["username"] as String).lowercase() != u }, "username_taken")
            persons[pid] = linkedMapOf("username" to b["username"], "full_name" to b["full_name"], "position" to b["position"], "role" to b["role"])
            return
        }
        Replay.need(b["username"] == cur["username"])
        if (author == pid) {
            Replay.need(b["role"] == cur["role"], "not_allowed")
        } else {
            val target = role(pid)
            Replay.need(target != "manager", "not_allowed")
            Replay.need(role == "manager" || (role == "admin" && target == "user" && b["role"] == "user"), "not_allowed")
        }
        cur["full_name"] = b["full_name"]; cur["position"] = b["position"]; cur["role"] = b["role"]
    }

    private fun tDeviceCert(e: Map<String, Any?>, author: String, role: String?) {
        val b = body(e)
        Replay.need(Replay.match(Replay.PEER, b["device"]) && Replay.match(Replay.ID, b["person"]) && b["person"] in persons &&
                    Replay.text(b["label"], 0, 80))
        Replay.need((devices[b["device"]]?.get("person") ?: b["person"]) == b["person"], "not_allowed")
        Replay.need(role == "manager" || author == b["person"] || (role == "admin" && role(b["person"] as String) == "user"), "not_allowed")
        devices[b["device"] as String] = linkedMapOf("person" to b["person"], "label" to b["label"])
    }

    private fun tRevoke(e: Map<String, Any?>, eid: String, author: String, role: String?) {
        val b = body(e)
        val target = if (Replay.match(Replay.PEER, b["device"])) devices[b["device"]] else null
        val last = b["last_seq"]
        Replay.need(target != null && last is Long && last >= 0)
        val tp = target!!["person"] as String
        Replay.need(role == "manager" || author == tp || (role == "admin" && role(tp) == "user"), "not_allowed")
        revoke(Replay.RANK[role] ?: throw Replay.Ignore("bad_body"), e, eid, b["device"] as String, last as Long)
    }

    private fun tSetting(e: Map<String, Any?>, role: String?) {
        val b = body(e)
        Replay.need(Replay.match(Canonical.KEY, b["key"]))
        Replay.need(role == "manager", "not_allowed")
        settings[b["key"] as String] = b["value"]
    }

    private fun tPrivate(e: Map<String, Any?>, eid: String, author: String) {
        val b = body(e)
        Replay.need(Replay.match(Replay.B64U, b["nonce"]) && (b["nonce"] as String).length == 16)
        Replay.need(Replay.match(Replay.B64U, b["ct"]) && (b["ct"] as String).length in 22..1_400_000)
        Replay.need(b["person"] == author, "not_allowed")
        private.getOrPut(author) { ArrayList() }.add(eid)
    }

    // ----- data: self-approved or proposals -----
    private fun data(e: Map<String, Any?>, eid: String, author: String, role: String?) {
        val t = e["type"] as String
        Replay.checkData(t, body(e))
        if (role == "admin" || role == "manager") {
            apply(t, body(e), eid, role == "manager")
            return
        }
        proposals[eid] = "pending"
        pending[eid] = e
        authors[eid] = author
        for (d in waiting.remove(eid) ?: emptyList()) {   // decided before it came in the order: takes effect here
            try {
                Replay.need(proposals[eid] == "pending", "already_decided")
                Replay.need(d.verdict != "withdrawn" || d.person == author, "not_allowed")
                decide(eid, d)
            } catch (x: Replay.Ignore) {
                ignored[d.eid] = x.code
            }
        }
    }

    private fun tVote(e: Map<String, Any?>, author: String) {
        val b = body(e)
        Replay.need(Replay.match(Replay.HEX64, b["entry"]) && b["on"] is Boolean)
        val voters = votes.getOrPut(b["entry"] as String) { LinkedHashSet() }
        if (b["on"] == true) voters.add(author) else voters.remove(author)
    }

    private fun decision(e: Map<String, Any?>, eid: String, d: Decision, role: String?) {
        val target = body(e)["entry"]
        Replay.need(Replay.match(Replay.HEX64, target))
        if (d.verdict != "withdrawn") Replay.need(role == "admin" || role == "manager", "not_allowed")
        d.eid = eid
        val state = proposals[target]
        if (state == null) {
            waiting.getOrPut(target as String) { ArrayList() }.add(d)
            return
        }
        Replay.need(state == "pending", "already_decided")
        Replay.need(d.verdict != "withdrawn" || d.person == authors[target], "not_allowed")
        decide(target as String, d)
    }

    private fun decide(target: String, d: Decision) {
        val e = pending.remove(target)!!
        var body = body(e)
        var verdict = d.verdict
        if (d.edit != null) {   // only for tag_add, and the edited tag must still be valid; else it counts as rejected
            body = body + d.edit
            try {
                Replay.need(e["type"] == "tag_add")
                Replay.checkData("tag_add", body)
            } catch (x: Replay.Ignore) {
                verdict = "rejected"
            }
        }
        proposals[target] = verdict
        decisions[target] = mapOf("status" to verdict, "by" to d.eid, "note" to d.note)
        if (verdict == "approved") apply(e["type"] as String, body, target, d.manager)
    }

    // ----- §12 merge -----
    private fun merge(entity: String, key: String, field: String?, live: Any?, base: Any?, new: Any?,
                      owner: Pair<Boolean, String?>, by: String, byManager: Boolean): Boolean {
        if (pyEquals(live, base) || pyEquals(live, new)) return true
        if (owner.first && !byManager) {
            conflicts.add(linkedMapOf("entity" to entity, "key" to key, "field" to field, "kept" to live, "lost" to new,
                                      "kept_by" to owner.second, "lost_by" to by))
            return false
        }
        conflicts.add(linkedMapOf("entity" to entity, "key" to key, "field" to field, "kept" to new, "lost" to live,
                                  "kept_by" to by, "lost_by" to owner.second))
        return true
    }

    fun get(entity: String, key: Any?): Any? = when (entity) {
        "equipment" -> equipment[key]?.takeIf { it.isNotEmpty() }?.let { LinkedHashMap(it) }
        "review" -> reviews[key]
        "link" -> if (key in links) true else null
        "photo" -> photos[key]
        else -> tags[key]
    }

    private fun apply(t: String, b: Map<String, Any?>, by: String, byManager: Boolean) {
        val (entity, key) = when (t) {
            "equipment" -> "equipment" to b["kks"]
            "review" -> "review" to b["tag_id"]
            "link" -> "link" to Triple(b["proc"] as String, b["step"] as Long, b["kks"] as String)
            "photo", "photo_delete" -> "photo" to b["photo"]
            else -> "added_tag" to b["tag"]
        }
        val before = get(entity, key)
        applyInner(t, b, by, byManager)
        val after = get(entity, key)
        if (!pyEquals(before, after)) {
            val k = if (key is Triple<*, *, *>) listOf(key.first, key.second, key.third) else key
            history.add(mapOf("at" to at, "source" to by, "entity" to entity, "key" to k, "before" to before, "after" to after))
        }
    }

    private fun applyInner(t: String, b: Map<String, Any?>, by: String, byManager: Boolean) {
        when (t) {
            "equipment" -> {
                val k = b["kks"] as String
                val cur = equipment.getOrPut(k) { LinkedHashMap() }
                val changes = b["changes"] as Map<String, Any?>
                val base = b["base"] as Map<String, Any?>
                for (f in changes.keys.sortedWith(::cmpCodePoints)) {
                    val v = changes[f]
                    val empty = if (f == "custom") emptyList<Any?>() else ""
                    if (merge("equipment", k, f, cur[f] ?: empty, if (base.containsKey(f)) base[f] else empty, v,
                              eqBy[k to f] ?: (false to null), by, byManager)) {
                        if (pyEquals(v, empty)) cur.remove(f) else cur[f] = v
                        eqBy[k to f] = byManager to by
                    }
                }
                if (cur.isEmpty()) equipment.remove(k)
            }
            "review" -> {
                val k = b["tag_id"] as String
                if (merge("review", k, null, reviews[k], b["base"], b["data"], reviewBy[k] ?: (false to null), by, byManager)) {
                    if (b["data"] == null) reviews.remove(k) else reviews[k] = b["data"]
                    reviewBy[k] = byManager to by
                }
            }
            "link" -> {
                val item = Triple(b["proc"] as String, b["step"] as Long, b["kks"] as String)
                if (b["on"] == true) links.add(item) else links.remove(item)
            }
            "photo" -> photos[b["photo"] as String] = linkedMapOf("kks" to b["kks"], "blob" to b["blob"], "caption" to b["caption"])
            "photo_delete" -> photos.remove(b["photo"])
            "tag_add" -> tags[b["tag"] as String] = linkedMapOf("sheet" to b["sheet"], "bbox" to b["bbox"], "kks" to b["kks"],
                                                                "suffix" to b["suffix"], "isa" to b["isa"], "note" to b["note"])
            "tag_remove" -> tags.remove(b["tag"])
        }
    }

    fun state(): Map<String, Any?> = linkedMapOf(
        "root" to root, "manager" to manager, "settings" to settings, "persons" to persons,
        "devices" to devices.mapValues { (d, v) -> v + ("cut" to cuts[d]) },
        "equipment" to equipment, "reviews" to reviews,
        "links" to links.sortedWith { a, b ->
            cmpCodePoints(a.first, b.first).takeIf { it != 0 } ?: a.second.compareTo(b.second).takeIf { it != 0 } ?: cmpCodePoints(a.third, b.third)
        }.map { listOf(it.first, it.second, it.third) },
        "photos" to photos, "added_tags" to tags,
        "proposals" to proposals, "conflicts" to conflicts,
        "votes" to votes.filter { (k, v) -> v.isNotEmpty() && k in proposals }.mapValues { (_, v) -> v.sortedWith(::cmpCodePoints) },
        "private" to private, "ignored" to ignored,
    )
}

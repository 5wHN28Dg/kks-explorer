package kks.core

/**
 * A device's log with the sync-node rules of docs/PROTOCOL.md §15 (twin of the node side of server/engine.py), kept in
 * memory. The Android node (M3b) stores the same things in SQLite; the rules live here once.
 */
open class MemoryNode(protected val key: SigningKey, anchor: String? = null) : Node {
    var anchor: String? = anchor
        protected set
    val entries = LinkedHashMap<String, Map<String, Any?>>()      // entry id → entry (each device's chain)
    val evidence = LinkedHashMap<String, Map<String, Any?>>()     // a second, different entry for a (device, seq) held
    val blobs = HashMap<String, ByteArray>()
    private val heads = HashMap<String, java.util.TreeMap<Long, String>>()   // device → seq → entry id
    val clock = HLC()
    lateinit var run: Run
        private set
    var chainIgnored: Map<String, String> = emptyMap()
        private set

    init { rebuild() }

    fun rebuild() {
        val (r, ci) = Replay.replayRun(null, anchor, trusted = entries + evidence)
        run = r; chainIgnored = ci
    }

    private fun store(eid: String, e: Map<String, Any?>) {
        entries[eid] = e
        heads.getOrPut(e["peer"] as String) { java.util.TreeMap() }[e["seq"] as Long] = eid
    }

    /** Persistence hooks (LocalNode): called for every entry / fork evidence / blob / adopted root kept. */
    protected open fun saved(eid: String, e: Map<String, Any?>, isEvidence: Boolean) {}
    protected open fun savedRoot(root: String) {}

    /** Put back what a store holds (no hooks called). */
    fun load(stored: Map<String, Map<String, Any?>>, forks: Map<String, Map<String, Any?>>) {
        for ((eid, e) in stored) store(eid, e)
        evidence.putAll(forks)
        for (e in stored.values) if (e["peer"] == key.peerId) {
            @Suppress("UNCHECKED_CAST") val h = e["hlc"] as List<Long>
            if (h[0] > clock.l || (h[0] == clock.l && h[1] > clock.c)) { clock.l = h[0]; clock.c = h[1] }
        }
        rebuild()
    }

    /** Write an entry signed by this device. -> its entry ID. */
    @Synchronized
    fun append(type: String, body: Map<String, Any?>, wallMs: Long = System.currentTimeMillis()): String {
        val mine = heads[key.peerId]
        val last = mine?.lastEntry()
        val e = Proto.makeEntry(key, (last?.key ?: 0L) + 1, last?.value, clock.now(wallMs), type, body)
        val eid = Proto.entryId(e)
        store(eid, e)
        saved(eid, e, false)
        rebuild()
        return eid
    }

    // ---------- Node ----------
    override fun identity() = key
    override fun root() = anchor

    @Synchronized
    override fun adopt(root: String) {
        check(anchor == null) { "this node already belongs to a plant" }
        anchor = root
        savedRoot(root)
        rebuild()
    }

    @Synchronized
    override fun vv(): Map<String, List<Any>> = heads.mapValues { (_, m) -> listOf<Any>(m.lastKey(), m.lastEntry().value) }

    @Synchronized
    override fun entriesFor(vv: Map<*, *>): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        for ((peer, m) in heads.toSortedMap()) {
            val have = vv[peer]
            var seq = 0L
            var head: Any? = null
            if (have is List<*> && have.size == 2) { seq = (have[0] as? Long) ?: -1L; head = have[1] }
            for ((s, eid) in m) {
                // what they lack; or a device whose entry at their last seq differs from ours (two copies of one key)
                if (seq < 0 || s > seq || (m[seq] ?: head) != head) out.add(entries[eid]!!)
            }
        }
        out.addAll(evidence.values)
        return out
    }

    /** Join by invite (PROTOCOL.md §16): the invites this device shows; set by the API. */
    @Volatile var invites: Invites? = null
    override fun joinOffer(remote: String, msg: Map<String, Any?>): Map<String, Any?> =
        invites?.offer(remote, msg) ?: mapOf("t" to "join_ack", "state" to "unknown")

    @Synchronized
    override fun mayRead(peer: String): Boolean {
        val d = run.devices[peer] ?: return false
        return peer !in run.cuts && d["person"] in run.persons
    }

    @Suppress("UNCHECKED_CAST")
    @Synchronized
    override fun ingest(entries: List<Any?>): Int {
        val good = LinkedHashMap<String, MutableList<Triple<Long, String, Map<String, Any?>>>>()
        for (raw in entries) {
            try { Proto.verifyEntry(raw) } catch (e: ProtocolError) { continue }
            val e = raw as Map<String, Any?>
            good.getOrPut(e["peer"] as String) { ArrayList() }.add(Triple(e["seq"] as Long, Proto.entryId(e), e))
        }
        // only devices certified once this batch counts are stored (a stranger's entries are not kept)
        val trial = Replay.replayRun(null, anchor, trusted = this.entries + evidence + good.values.flatten().associate { it.second to it.third }).first
        var n = 0
        val taken = ArrayList<Map<String, Any?>>()
        for ((peer, list) in good) {
            if (peer !in trial.devices) continue
            val m = heads[peer]
            var lastSeq = m?.lastKey() ?: 0L
            var lastId = m?.lastEntry()?.value
            for ((seq, eid, e) in list.sortedBy { it.first }) {
                if (eid in this.entries || eid in evidence) continue
                if (seq <= lastSeq) { evidence[eid] = e; saved(eid, e, true); n++; taken.add(e) }   // a different entry there: a fork
                else if (seq == lastSeq + 1 && e["prev"] == lastId) { store(eid, e); saved(eid, e, false); lastSeq = seq; lastId = eid; n++; taken.add(e) }
            }
        }
        if (n > 0) {
            val wall = System.currentTimeMillis()
            for (e in taken) clock.recv(e["hlc"] as List<Long>, wall)
            rebuild()
        }
        return n
    }

    @Synchronized
    override fun blobWants(): List<String> {
        val shas = run.photos.values.map { it["blob"] as String }.toMutableSet()
        for ((eid, st) in run.proposals) {
            val e = entries[eid] ?: continue
            if (st == "pending" && e["type"] == "photo") shas.add((e["body"] as Map<*, *>)["blob"] as String)
        }
        return shas.filter { !haveBlob(it) }.sorted()
    }

    /** Blob storage (LocalNode keeps them as files instead of in memory). */
    open fun haveBlob(sha: String): Boolean = sha in blobs
    protected open fun keepBlob(sha: String, data: ByteArray) { blobs[sha] = data }

    override fun blobGet(sha: String): ByteArray? = blobs[sha]

    @Synchronized
    override fun blobPut(sha: String, data: ByteArray): Boolean {
        if (sha !in blobWants() || sha256(data).hex() != sha) return false
        keepBlob(sha, data)
        return true
    }

    @Synchronized
    fun state(): Map<String, Any?> {
        val st = run.state().toMutableMap()
        st["ignored"] = (chainIgnored + run.ignored).toSortedMap()
        return st
    }
}

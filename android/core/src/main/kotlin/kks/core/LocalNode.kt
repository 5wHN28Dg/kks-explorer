package kks.core

import java.io.ByteArrayOutputStream
import java.util.zip.GZIPInputStream
import java.util.zip.GZIPOutputStream

/**
 * What a device keeps (the phone: SQLite + files, the device key under the Android Keystore; tests: [MemStore]).
 * Mirrors the server's tables: entries, evidence, blobs, subs (submission numbers ↔ entries, held changes),
 * entry_notes, meta.
 */
interface NodeStore {
    fun deviceSeed(): ByteArray?
    fun setDeviceSeed(seed: ByteArray)
    fun meta(k: String): String?
    fun setMeta(k: String, v: String?)
    fun entries(): Map<String, Map<String, Any?>>
    fun evidence(): Map<String, Map<String, Any?>>
    fun putEntry(eid: String, e: Map<String, Any?>, isEvidence: Boolean)
    fun blobName(sha: String): String?
    fun blob(sha: String): ByteArray?
    fun putBlob(sha: String, name: String, data: ByteArray)
    fun subs(): List<Map<String, Any?>>                 // newest first
    fun sub(id: Long): Map<String, Any?>?
    fun subByClientId(clientId: String): Map<String, Any?>?
    fun putSub(row: Map<String, Any?>): Long            // insert when row["id"] is null, else replace; -> id
    fun note(eid: String): String?
    fun notes(): Map<String, String>
    fun putNote(eid: String, note: String)
    fun <T> tx(block: () -> T): T
    /** Person secrets (§13, M4) as JSON {person: [hex, …]}; the phone's store keeps them encrypted. */
    fun personSecrets(): String? = meta("person_secrets")
    fun setPersonSecrets(json: String) = setMeta("person_secrets", json)
    /** The device was removed from its plant: delete everything (entries, subs, notes, blobs, meta incl. the device
     *  seed and person secrets) and keep only `removed` = [note] (JSON) for the setup screen. */
    fun wipe(note: String)
}

class MemStore : NodeStore {
    private var seed: ByteArray? = null
    private val meta = HashMap<String, String>()
    private val entries = LinkedHashMap<String, Map<String, Any?>>()
    private val evidence = LinkedHashMap<String, Map<String, Any?>>()
    private val blobs = HashMap<String, Pair<String, ByteArray>>()
    private val subs = java.util.TreeMap<Long, Map<String, Any?>>()
    private val notes = HashMap<String, String>()
    override fun deviceSeed() = seed
    override fun setDeviceSeed(seed: ByteArray) { this.seed = seed }
    override fun meta(k: String) = meta[k]
    override fun setMeta(k: String, v: String?) { if (v == null) meta.remove(k) else meta[k] = v }
    override fun entries() = entries
    override fun evidence() = evidence
    override fun putEntry(eid: String, e: Map<String, Any?>, isEvidence: Boolean) { (if (isEvidence) evidence else entries)[eid] = e }
    override fun blobName(sha: String) = blobs[sha]?.first
    override fun blob(sha: String) = blobs[sha]?.second
    override fun putBlob(sha: String, name: String, data: ByteArray) { blobs[sha] = name to data }
    override fun subs() = subs.descendingMap().values.toList()
    override fun sub(id: Long) = subs[id]
    override fun subByClientId(clientId: String) = subs.values.firstOrNull { it["client_id"] == clientId }
    override fun putSub(row: Map<String, Any?>): Long {
        val id = (row["id"] as Long?) ?: ((subs.lastEntry()?.key ?: 0L) + 1)
        subs[id] = row + ("id" to id)
        return id
    }
    override fun note(eid: String) = notes[eid]
    override fun notes() = notes
    override fun putNote(eid: String, note: String) { notes[eid] = note }
    @Synchronized override fun <T> tx(block: () -> T): T = block()
    override fun wipe(note: String) {
        seed = null; meta.clear(); entries.clear(); evidence.clear(); blobs.clear(); subs.clear(); notes.clear()
        meta["removed"] = note
    }
}

/** The owner of this device, as far as the log says (peer mode: the only account). */
data class Owner(val person: String, val device: String, val username: String, val fullName: String, val position: String?,
                 val role: String) {
    fun isAdmin() = role == "admin" || role == "manager"
}

/**
 * This device's node: the log + sync rules ([MemoryNode]) kept in a [NodeStore], plus what the local API needs:
 * the owner, change notifications, bundles, conflict planning and restore bodies (twins of server/engine.py).
 */
class LocalNode private constructor(val store: NodeStore, key: SigningKey) : MemoryNode(key, store.meta("root_pub")) {
    companion object {
        fun open(store: NodeStore): LocalNode {
            val seed = store.deviceSeed() ?: SigningKey.generate().seed.also { store.setDeviceSeed(it) }
            return LocalNode(store, SigningKey(seed)).also { it.load(store.entries(), store.evidence()) }
        }

        fun default(field: String): Any = if (field == "custom") emptyList<Any?>() else ""
    }

    val device: String get() = key.peerId
    val listeners = ArrayList<(String) -> Unit>()          // "local" / "received": auto-sync, UI refresh

    override fun saved(eid: String, e: Map<String, Any?>, isEvidence: Boolean) = store.putEntry(eid, e, isEvidence)
    override fun savedRoot(root: String) { store.setMeta("root_pub", root); store.setMeta("log_version", "1") }
    override fun haveBlob(sha: String) = store.blobName(sha) != null
    override fun blobGet(sha: String): ByteArray? = store.blob(sha)
    override fun keepBlob(sha: String, data: ByteArray) = store.putBlob(sha, "$sha.${blobExt(data)}", data)

    private fun changed(why: String) = listeners.toList().forEach { runCatching { it(why) } }

    @Synchronized fun write(type: String, body: Map<String, Any?>): String = store.tx { append(type, body) }.also { changed("local") }

    @Synchronized override fun ingest(entries: List<Any?>): Int {
        val n = store.tx { super.ingest(entries).also { if (it > 0) afterIngest() } }
        if (n > 0) changed("received")
        return n
    }

    /** A submission row for every proposal that came by sync, so it shows in Approvals (server: _after_ingest). */
    private fun afterIngest() {
        val known = store.subs().mapNotNull { it["entry"] }.toSet()
        for (eid in run.proposals.keys) if (eid !in known) {
            val e = entries[eid] ?: continue
            store.putSub(mapOf("id" to null, "client_id" to null, "entry" to eid, "person" to run.authors[eid],
                               "kind" to e["type"], "created" to ((e["hlc"] as List<*>)[0] as Long) / 1000))
        }
    }

    /** Called after a wipe (the app restarts itself: a new device key needs a new node). */
    @Volatile var onWiped: ((Map<String, Any?>) -> Unit)? = null

    override fun acceptRevocation(entry: Any?): Boolean {
        val o = owner() ?: return false
        val e = entry as? Map<String, Any?> ?: return false
        try { Proto.verifyEntry(e) } catch (x: Exception) { return false }
        if (e["type"] != "revoke" || (e["body"] as? Map<*, *>)?.get("device") != device) return false
        val note = synchronized(this) {
            val d = run.devices[e["peer"] as String] ?: return false
            if ((e["peer"] as String) in run.cuts) return false
            val p = d["person"] as String
            val role = if (run.manager == p) "manager" else run.persons[p]?.get("role")
            if (!(role == "admin" || role == "manager" || p == o.person)) return false
            mapOf("by" to (run.persons[p]?.get("full_name") ?: "an admin"), "at" to System.currentTimeMillis() / 1000,
                  "plant" to run.settings["plant"])
        }
        wipe(note)
        return true
    }

    /** Delete the plant here: the store (log, photos, secrets, device key) and what is in memory. */
    fun wipe(note: Map<String, Any?>) {
        synchronized(this) { store.wipe(Json.write(note)); forget() }
        changed("wiped")
        onWiped?.invoke(note)
    }

    /** §17, the listener's side: only with another device of this node's owner. */
    override fun secretsOffer(remote: String, msg: Map<String, Any?>): Map<String, Any?> {
        val none = mapOf("t" to "secrets", "secrets" to emptyList<String>())
        val o = owner() ?: return none
        val same = synchronized(this) { run.devices[remote]?.let { it["person"] == o.person && remote !in run.cuts } == true }
        if (!same || msg["person"] != o.person) return none
        Progress.addSecrets(this, o.person, Sync.decodeSecrets(msg["secrets"]))
        return mapOf("t" to "secrets", "secrets" to Progress.secretsOf(this, o.person).map { B64u.encode(it) })
    }

    fun owner(): Owner? {
        val d = run.devices[device] ?: return null
        if (device in run.cuts) return null
        val pid = d["person"] as String
        val p = run.persons[pid] ?: return null
        return Owner(pid, device, p["username"] as String, p["full_name"] as String, p["position"] as String?,
                     if (run.manager == pid) "manager" else p["role"] as String)
    }

    fun personOf(dev: String): String? = run.devices[dev]?.get("person") as String?
    fun ts(eid: String?): Long? = entries[eid]?.let { ((it["hlc"] as List<*>)[0] as Long) / 1000 }

    /** (status, decision entry, note) of an entry written for a submission (server: Engine.status_of). */
    fun statusOf(eid: String): Triple<String, String?, String> {
        (run.ignored[eid] ?: chainIgnored[eid])?.let { return Triple("rejected", null, "not counted: $it") }
        run.proposals[eid]?.let { st ->
            val d = run.decisions[eid]
            return Triple(st, d?.get("by") as String?, (d?.get("note") as String?) ?: "")
        }
        return Triple("approved", null, "applied directly")
    }

    fun managerOwned(entity: String, key: String, field: String? = null): Boolean = when (entity) {
        "equipment" -> run.eqBy[key to field]?.first ?: false
        "review" -> run.reviewBy[key]?.first ?: false
        else -> false
    }

    /** -> (targets, conflicts) of a change against the live state (server: Engine.plan). */
    @Suppress("UNCHECKED_CAST")
    fun plan(type: String, b: Map<String, Any?>): Pair<List<Pair<String, Any?>>, List<Map<String, Any?>>> = when (type) {
        "equipment" -> {
            val k = b["kks"] as String
            val cur = run.equipment[k] ?: emptyMap()
            val base = b["base"] as Map<String, Any?>
            val out = (b["changes"] as Map<String, Any?>).mapNotNull { (f, v) ->
                val live = cur[f] ?: default(f)
                val bs = if (base.containsKey(f)) base[f] else default(f)
                if (!pyEquals(live, v) && !pyEquals(live, bs)) mapOf("field" to f, "base" to bs, "live" to live, "proposed" to v,
                                                                      "manager" to managerOwned("equipment", k, f)) else null
            }
            listOf("equipment" to k) to out
        }
        "review" -> {
            val k = b["tag_id"] as String
            val live = run.reviews[k]
            val out = if (pyEquals(live, b["base"]) || pyEquals(live, b["data"])) emptyList()
                      else listOf(mapOf("field" to "review", "base" to b["base"], "live" to live, "proposed" to b["data"],
                                        "manager" to managerOwned("review", k)))
            listOf("review" to k) to out
        }
        "link" -> listOf("link" to Triple(b["proc"] as String, b["step"] as Long, b["kks"] as String)) to emptyList()
        "photo", "photo_delete" -> listOf("photo" to b["photo"]) to emptyList()
        else -> listOf("added_tag" to b["tag"]) to emptyList()
    }

    /** (type, body) setting entity `key` to `value` (replay form; null = absent), or null if already so. */
    @Suppress("UNCHECKED_CAST")
    fun restoreBody(entity: String, key: Any?, value: Any?): Pair<String, Map<String, Any?>>? {
        val cur = run.get(entity, key)
        if (pyEquals(cur, value)) return null
        return when (entity) {
            "equipment" -> {
                val c = (cur ?: emptyMap<String, Any?>()) as Map<String, Any?>
                val v = (value ?: emptyMap<String, Any?>()) as Map<String, Any?>
                val changes = (c.keys + v.keys).sorted().filter { !pyEquals(v[it] ?: default(it), c[it] ?: default(it)) }
                    .associateWith { v[it] ?: default(it) }
                "equipment" to mapOf("kks" to key, "changes" to changes, "base" to changes.keys.associateWith { c[it] ?: default(it) })
            }
            "review" -> "review" to mapOf("tag_id" to key, "data" to value, "base" to cur)
            "link" -> { val t = key as Triple<*, *, *>; "link" to mapOf("proc" to t.first, "step" to t.second, "kks" to t.third, "on" to (value != null)) }
            "photo" -> if (value == null) "photo_delete" to mapOf("photo" to key) else "photo" to (mapOf("photo" to key) + (value as Map<String, Any?>))
            else -> if (value == null) "tag_remove" to mapOf("tag" to key) else "tag_add" to (mapOf("tag" to key) + (value as Map<String, Any?>))
        }
    }

    // ---------- bundles (server: Engine.bundle / import_bundle) ----------
    fun bundle(photos: Boolean): ByteArray {
        val out = linkedMapOf<String, Any?>("kks_bundle" to 1L, "root" to anchor, "plant" to run.settings["plant"],
                                             "created" to System.currentTimeMillis() / 1000, "entries" to entriesFor(emptyMap<String, Any>()))
        if (photos) out["blobs"] = run.photos.values.map { it["blob"] as String }.toSortedSet()
            .mapNotNull { sha -> blobGet(sha)?.let { sha to java.util.Base64.getEncoder().encodeToString(it) } }.toMap()
        return ByteArrayOutputStream().also { b -> GZIPOutputStream(b).use { it.write(Json.write(out).toByteArray()) } }.toByteArray()
    }

    @Synchronized fun importBundle(raw: ByteArray): Map<String, Any?> {
        val d = try { Json.parse(GZIPInputStream(raw.inputStream()).readBytes()) as Map<*, *> } catch (e: Exception) { null }
        if (d == null || d["kks_bundle"] != 1L || d["entries"] !is List<*>) throw IllegalArgumentException("not a KKS Explorer bundle")
        var adopted = false
        if (anchor == null) {
            val r = d["root"] as? String
            if (r == null || r.length != 43) throw IllegalArgumentException("the bundle names no plant")
            adopt(r); adopted = true
        } else if (d["root"] != anchor) throw IllegalArgumentException("this bundle is from a different plant")
        val n = ingest(d["entries"] as List<Any?>)
        var got = 0
        (d["blobs"] as? Map<*, *>)?.forEach { (sha, b64) ->
            runCatching { if (blobPut(sha as String, java.util.Base64.getDecoder().decode(b64 as String))) got++ }
        }
        return mapOf("entries" to n.toLong(), "photos" to got.toLong(), "adopted" to adopted)
    }
}

fun blobExt(data: ByteArray): String {
    fun starts(vararg b: Int) = data.size >= b.size && b.indices.all { data[it] == b[it].toByte() }
    return when {
        starts(0xff, 0xd8, 0xff) -> "jpg"
        starts(0x89, 0x50, 0x4e, 0x47) -> "png"
        starts(0x52, 0x49, 0x46, 0x46) -> "webp"
        starts(0xff, 0x0a) || starts(0, 0, 0, 0x0c, 0x4a, 0x58, 0x4c) -> "jxl"
        else -> "bin"
    }
}

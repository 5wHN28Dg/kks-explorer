package kks.core

import java.security.MessageDigest
import java.security.SecureRandom

/**
 * Course progress (M4), the twin of server/progress.py: private entries {type: course_progress, body: {course,
 * items: [[key, localStorage string], …]}} encrypted with a person secret (PROTOCOL.md §13); a person's devices swap
 * their secrets (§17). Reading merges per key: JSON objects → union, `…Best` numbers → the larger, else the later.
 * Secrets are kept in the store ([NodeStore.personSecrets]: on the phone encrypted under the Android Keystore).
 */
@Suppress("UNCHECKED_CAST")
object Progress {
    private val COURSE = Regex("[a-z]{1,16}")
    private val KEY = Regex("[A-Za-z0-9_.-]{1,64}")
    private const val MAX_VALUE = 200_000
    private const val MAX_TOTAL = 600_000
    private val rng = SecureRandom()

    private fun hex(b: ByteArray) = b.joinToString("") { "%02x".format(it) }
    private fun sha(b: ByteArray) = hex(MessageDigest.getInstance("SHA-256").digest(b))
    private fun unhex(s: String) = ByteArray(s.length / 2) { s.substring(2 * it, 2 * it + 2).toInt(16).toByte() }

    private fun all(node: LocalNode): Map<String, List<String>> =
        runCatching { Json.parse(node.store.personSecrets() ?: "{}") as Map<String, List<String>> }.getOrDefault(emptyMap())

    /** This person's secrets known here, the one to write with first (lowest SHA-256, as in Python). */
    fun secretsOf(node: LocalNode, person: String): List<ByteArray> =
        (all(node)[person] ?: emptyList()).map { unhex(it) }.sortedBy { sha(it) }

    @Synchronized fun addSecrets(node: LocalNode, person: String, secrets: List<ByteArray>): Int {
        val m = all(node).toMutableMap()
        val have = (m[person] ?: emptyList()).toMutableList()
        val new = secrets.filter { it.size == 32 && hex(it) !in have }.map { hex(it) }.distinct()
        if (new.isNotEmpty()) { m[person] = have + new; node.store.setPersonSecrets(Json.write(m)) }
        return new.size
    }

    fun ensureSecret(node: LocalNode, person: String): ByteArray =
        secretsOf(node, person).firstOrNull() ?: run { addSecrets(node, person, listOf(ByteArray(32).also { rng.nextBytes(it) })); secretsOf(node, person).first() }

    /** -> the entry body, or IllegalArgumentException. */
    fun check(course: Any?, data: Any?): Map<String, Any?> {
        if (course !is String || !COURSE.matches(course)) throw IllegalArgumentException("bad course")
        if (data !is Map<*, *> || data.isEmpty()) throw IllegalArgumentException("nothing to save")
        var total = 0
        for ((k, v) in data) {
            if (k !is String || !KEY.matches(k) || v !is String || v.length > MAX_VALUE) throw IllegalArgumentException("bad progress value")
            total += v.length
        }
        if (total > MAX_TOTAL) throw IllegalArgumentException("too much at once")
        return mapOf("course" to course, "items" to (data as Map<String, String>).keys.sortedWith(::cmpCodePoints).map { listOf(it, data[it]) })
    }

    fun save(node: LocalNode, owner: Owner, course: Any?, data: Any?) {
        val body = check(course, data)
        val secret = ensureSecret(node, owner.person)
        node.write("private", Replay.privateBody(secret, owner.person, "course_progress", body, ByteArray(12).also { rng.nextBytes(it) }))
    }

    private fun num(v: Any?): Double? = when (v) { is Long -> v.toDouble(); is Double -> v; is JNumber -> v.text.toDoubleOrNull(); else -> null }

    fun merge(key: String, old: String?, new: String): String {
        if (old == null) return new
        val a = runCatching { Json.parse(old) }.getOrNull() ?: return new
        val b = runCatching { Json.parse(new) }.getOrNull() ?: return new
        if (a is Map<*, *> && b is Map<*, *>) return Json.write(LinkedHashMap(a as Map<String, Any?>).apply { putAll(b as Map<String, Any?>) })
        val x = num(a); val y = num(b)
        if (key.endsWith("Best") && x != null && y != null && a !is Boolean) return if (x > y) old else new
        return new
    }

    /** -> {course: {key: localStorage string}} from this person's private entries this device can read. */
    fun load(node: LocalNode, person: String): Map<String, Map<String, String>> {
        val keys = secretsOf(node, person)
        val entries = synchronized(node) { (node.run.private[person] ?: emptyList<String>()).mapNotNull { node.entries[it] } }
        val out = LinkedHashMap<String, LinkedHashMap<String, String>>()
        for (e in entries) {
            val opened = keys.firstNotNullOfOrNull { k -> runCatching { Replay.privateOpen(k, e["body"] as Map<String, Any?>) }.getOrNull() } as? Map<*, *> ?: continue
            if (opened["type"] != "course_progress") continue
            val b = opened["body"] as? Map<*, *> ?: continue
            val data = runCatching { (b["items"] as List<*>).associate { p -> (p as List<*>)[0] as String to p[1] as String } }.getOrNull() ?: continue
            val course = b["course"]
            if (runCatching { check(course, data) }.isFailure) continue
            val cur = out.getOrPut(course as String) { LinkedHashMap() }
            for ((k, v) in data) cur[k] = merge(k, cur[k], v)
        }
        return out
    }

    private val swapped = HashSet<String>()

    /** After a sync with [remote] at host:port: if it is another device of this node's owner, swap person secrets
     *  (§17), once per device and set of secrets. Failures only mean "next time". -> secrets learned */
    fun swapAfterSync(node: LocalNode, host: String, port: Int, remote: String, connect: (() -> Conn)? = null): Int {
        val o = node.owner() ?: return 0
        if (remote == o.device) return 0
        val same = synchronized(node) { node.run.devices[remote]?.let { it["person"] == o.person && remote !in node.run.cuts } == true }
        if (!same) return 0
        val mine = secretsOf(node, o.person)
        val key = remote + mine.joinToString(",") { sha(it) }
        if (synchronized(swapped) { key in swapped }) return 0
        val theirs = try { Sync.secretsSwap(node.identity(), host, port, remote, o.person, mine, 10_000, connect?.invoke()) } catch (e: Exception) { return 0 }
        val n = addSecrets(node, o.person, theirs)
        synchronized(swapped) { swapped.add(remote + secretsOf(node, o.person).joinToString(",") { sha(it) }) }
        return n
    }
}

package kks.core

/**
 * Plant data (drawings, tag lists, procedures, location list) delivered by the log (M5b, PROTOCOL.md §19); the twin of
 * server/plantdata.py. The manager publishes a version as a `setting` entry, key `plant_data`, value
 * {"version": n, "files": [[path, sha256 hex, size], ...]}; the files travel as blobs. A device serves the newest
 * version whose files it holds completely.
 */
object PlantData {
    val PATH = Regex("(sheets/)?[a-z0-9][a-z0-9._-]{0,63}")
    val SHA = Regex("[0-9a-f]{64}")
    const val MAX_FILES = 2000

    data class Manifest(val version: Long, val files: Map<String, Pair<String, Long>>) {
        fun plain(): List<List<Any>> = files.toSortedMap(::cmpCodePoints).map { (p, f) -> listOf(p, f.first, f.second) }
    }

    /** A `plant_data` setting value -> the manifest, or null if it isn't one (same checks as plantdata.manifest). */
    fun manifest(value: Any?): Manifest? {
        val m = value as? Map<*, *> ?: return null
        val version = m["version"] as? Long ?: return null
        if (version < 1) return null
        val files = m["files"] as? List<*> ?: return null
        if (files.size > MAX_FILES) return null
        val out = LinkedHashMap<String, Pair<String, Long>>()
        for (f in files) {
            val l = f as? List<*> ?: return null
            if (l.size != 3) return null
            val path = l[0] as? String ?: return null
            val sha = l[1] as? String ?: return null
            val size = l[2] as? Long ?: return null
            if (!PATH.matches(path) || ".." in path || !SHA.matches(sha) || size < 0 || path in out) return null
            out[path] = sha to size
        }
        return Manifest(version, out)
    }

    fun latest(node: MemoryNode): Manifest? = manifest(node.run.settings["plant_data"])
}

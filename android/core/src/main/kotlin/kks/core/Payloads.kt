package kks.core

/**
 * What the web UI sends and gets back (payloads, in the shapes it has always used) ↔ entry bodies. Twin of
 * server/changes.py (normalize, tag_payload) and the converters in server/engine.py; error messages are the same.
 */
class ApiError(val status: Int, msg: String, val extra: Map<String, Any?> = emptyMap()) : Exception(msg)

object Payloads {
    val KINDS = setOf("equipment", "review", "link", "photo", "photo_delete", "tag_add", "tag_remove")
    private val TAG = Regex("(\\d{2}[A-Z]{3}\\d{2}[A-Z]{2}\\d{3})([A-Z0-9]{0,4})")
    private val KKS = Regex("[0-9A-Z/]{3,24}")
    private val SHEET = Regex("[a-z0-9][a-z0-9-]{0,23}")
    private val HEX32 = Regex("[0-9a-f]{32}")
    private val IMG = Regex("data:image/(jpeg|jpg|png|webp);base64,(.+)", RegexOption.DOT_MATCHES_ALL)

    private fun bad(msg: String): Nothing = throw ApiError(400, msg)

    fun kks(v: Any?): String = if (v is String && KKS.matches(v)) v else bad("bad KKS")

    fun text(v: Any?, n: Int = 4000): String {
        if (v == null) return ""
        if (v !is String || v.codePointCount(0, v.length) > n) bad("bad text field")
        return v.trim { it.isWhitespace() }
    }

    /** Python's int(): numbers, numeric text, booleans. */
    fun int(v: Any?): Long = when (v) {
        is Long -> v
        is Boolean -> if (v) 1 else 0
        is JNumber -> v.text.toDoubleOrNull()?.takeIf { it.isFinite() }?.toLong() ?: bad("bad step")
        is String -> v.trim().toLongOrNull() ?: bad("bad step")
        else -> bad("bad step")
    }

    fun num(v: Any?): Double? = when (v) {
        is Long -> v.toDouble()
        is Double -> v
        is JNumber -> v.text.toDoubleOrNull()
        is String -> v.trim().toDoubleOrNull()
        else -> null
    }

    /** Python truthiness. */
    fun truthy(v: Any?): Boolean = when (v) {
        null -> false
        is Boolean -> v
        is Long -> v != 0L
        is String -> v.isNotEmpty()
        is Collection<*> -> v.isNotEmpty()
        is Map<*, *> -> v.isNotEmpty()
        is JNumber -> v.text.toDoubleOrNull()?.let { it != 0.0 } ?: true
        else -> true
    }

    private fun fields(d: Any?): Map<String, Any?> {
        if (d !is Map<*, *> || !Replay.EQ_FIELDS.containsAll(d.keys)) bad("unknown equipment field")
        return d.entries.associate { (f, v) ->
            f as String to if (f == "custom") {
                if (v !is List<*> || v.size > 100) bad("bad custom fields")
                v.filterIsInstance<Map<*, *>>().map { mapOf("k" to text(it["k"], 200), "v" to text(it["v"], 2000)) }
            } else text(v)
        }
    }

    /** Validate a client payload -> the payload to keep (photos: the image bytes go to `saveBlob`). */
    fun normalize(kind: String?, p: Any?, maxBytes: Int, saveBlob: (String, ByteArray) -> String): Map<String, Any?> {
        if (kind !in KINDS || p !is Map<*, *>) bad("bad submission kind or payload")
        return when (kind) {
            "equipment" -> {
                val k = kks(p["kks"])
                val changes = fields(p["changes"] ?: emptyMap<String, Any>())
                val base = fields(p["base"] ?: emptyMap<String, Any>())
                if (changes.isEmpty()) bad("no changes")
                mapOf("kks" to k, "changes" to changes, "base" to changes.keys.associateWith { base[it] ?: LocalNode.default(it) })
            }
            "review" -> {
                val tag = text(p["tag_id"], 64)
                val d = (p["data"] as? Map<*, *>) ?: emptyMap<String, Any?>()
                if (tag.isEmpty() || d["status"] !in listOf("confirmed", "rejected")) bad("bad review")
                val data = linkedMapOf<String, Any?>("status" to d["status"])
                if (d["status"] == "confirmed") {
                    data["kks"] = kks(d["kks"]); data["suffix"] = text(d["suffix"], 8); data["isa"] = text(d["isa"], 12).ifEmpty { null }
                }
                mapOf("tag_id" to tag, "data" to data, "base" to (p["base"] as? Map<*, *>))
            }
            "link" -> {
                val proc = text(p["proc"], 32)
                val k = kks(p["kks"])
                val step = int(p["step"])
                if (proc.isEmpty()) bad("bad procedure")
                mapOf("proc" to proc, "step" to step, "kks" to k, "on" to (if (p.containsKey("on")) truthy(p["on"]) else true))
            }
            "photo" -> {
                val k = kks(p["kks"])
                val m = IMG.matchEntire((p["dataUrl"] as? String) ?: "") ?: bad("bad image")
                val raw = try { java.util.Base64.getMimeDecoder().decode(m.groupValues[2]) } catch (e: IllegalArgumentException) { bad("bad image") }
                if (raw.size > maxBytes) bad("image too large")
                if (blobExt(raw) !in setOf("jpg", "png", "webp")) bad("not an image")
                val sha = sha256(raw).hex()
                val file = saveBlob(sha, raw)
                mapOf("kks" to k, "photo_id" to newId(), "file" to file, "blob" to sha, "size" to raw.size.toLong(),
                      "caption" to text(p["caption"], 500))
            }
            "tag_add" -> tagPayload(p)
            "tag_remove" -> mapOf("id" to text(p["id"], 64).also { if (!HEX32.matches(it)) bad("bad tag id") })
            else -> mapOf("photo_id" to text(p["photo_id"], 64).also { if (!HEX32.matches(it)) bad("bad photo id") })
        }
    }

    fun newId(): String = ByteArray(16).also { java.security.SecureRandom().nextBytes(it) }.hex()

    /** A hand-marked tag: sheet, box on the sheet image (px), code if readable. */
    fun tagPayload(p: Map<*, *>, keepId: String? = null): Map<String, Any?> {
        val sheet = p["sheet"]
        if (sheet !is String || !SHEET.matches(sheet)) bad("bad sheet")
        val raw = p["bbox"] as? List<*> ?: bad("bad box")
        val bb = raw.map { v -> num(v)?.let { Math.round(it * 10) / 10.0 } ?: bad("bad box") }
        if (bb.size != 4 || !(0 <= bb[0] && bb[0] < bb[2] && bb[2] <= 20000 && 0 <= bb[1] && bb[1] < bb[3] && bb[3] <= 20000) ||
            bb[2] - bb[0] < 4 || bb[3] - bb[1] < 4) bad("bad box")
        val code = text(p["kks"], 32).filter { !it.isWhitespace() }.uppercase()
        val isa = text(p["isa"], 12).uppercase().ifEmpty { null }
        if (isa != null && !Regex("[A-Z]{1,6}").matches(isa)) bad("function letters: 1-6 letters, e.g. PI, TIAC")
        val m = TAG.matchEntire(code)
        if (code.isNotEmpty() && m == null) bad("That is not a valid KKS (e.g. 11LAB70AA501, suffix allowed)")
        return mapOf("id" to (keepId ?: (p["id"] as? String) ?: newId()), "sheet" to sheet, "bbox" to bb,
                     "kks" to m?.groupValues?.get(1), "suffix" to (m?.groupValues?.get(2) ?: ""), "isa" to isa,
                     "kind" to if (isa != null) "instrument" else "equipment",
                     "orient" to if (bb[3] - bb[1] > bb[2] - bb[0]) "v" else "h", "note" to text(p["note"], 500))
    }

    @Suppress("UNCHECKED_CAST")
    fun toBody(kind: String, p: Map<String, Any?>): Map<String, Any?> = when (kind) {
        "photo" -> mapOf("photo" to p["photo_id"], "kks" to p["kks"], "blob" to p["blob"], "caption" to p["caption"])
        "photo_delete" -> mapOf("photo" to p["photo_id"])
        "tag_add" -> mapOf("tag" to p["id"], "sheet" to p["sheet"], "bbox" to (p["bbox"] as List<Double>).map { Math.round(it * 10) },
                           "kks" to p["kks"], "suffix" to p["suffix"], "isa" to p["isa"], "note" to p["note"])
        "tag_remove" -> mapOf("tag" to p["id"])
        else -> p
    }

    fun toPayload(node: LocalNode, kind: String, b: Map<String, Any?>): Map<String, Any?> = when (kind) {
        "photo" -> mapOf("photo_id" to b["photo"], "kks" to b["kks"], "file" to node.store.blobName(b["blob"] as String), "caption" to b["caption"])
        "photo_delete" -> mapOf("photo_id" to b["photo"])
        "tag_add" -> tagOut(b["tag"] as String, b)
        "tag_remove" -> mapOf("id" to b["tag"])
        else -> b
    }

    fun tagOut(id: String, t: Map<String, Any?>): Map<String, Any?> {
        val bb = (t["bbox"] as List<*>).map { (it as Long) / 10.0 }
        return linkedMapOf("id" to id, "sheet" to t["sheet"], "bbox" to bb, "kks" to t["kks"], "suffix" to t["suffix"], "isa" to t["isa"],
                           "kind" to if (t["isa"] != null) "instrument" else "equipment",
                           "orient" to if (bb[3] - bb[1] > bb[2] - bb[0]) "v" else "h", "note" to t["note"])
    }

    /** A replay value in the shape History has always shown. */
    @Suppress("UNCHECKED_CAST")
    fun valueOut(node: LocalNode, entity: String, key: Any?, v: Any?): Any? = when {
        v == null -> null
        entity == "photo" -> (v as Map<String, Any?>).let { mapOf("kks" to it["kks"], "file" to node.store.blobName(it["blob"] as String), "caption" to it["caption"]) }
        entity == "added_tag" -> tagOut(key as String, v as Map<String, Any?>) - "id"
        else -> v
    }

    fun target(kind: String, b: Map<String, Any?>): String = when (kind) {
        "equipment" -> "equipment:${b["kks"]}"
        "review" -> "review:${b["tag_id"]}"
        "link" -> "link:${b["proc"]}|${b["step"]}|${b["kks"]}"
        "photo" -> "photo:${b["kks"]}"
        "photo_delete" -> "photo_delete:${b["photo"]}"
        "tag_add" -> "tag_add:${b["sheet"]}"
        else -> "tag_remove:${b["tag"]}"
    }
}

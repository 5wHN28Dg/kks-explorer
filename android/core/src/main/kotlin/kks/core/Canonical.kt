package kks.core

/** Rejected input; `code` is one of docs/PROTOCOL.md §7. */
class ProtocolError(val code: String, msg: String = "") : Exception(if (msg.isEmpty()) code else "$code: $msg")

/** Canonical JSON (docs/PROTOCOL.md §1): what is hashed and signed. */
object Canonical {
    val KEY = Regex("[a-z_][a-z0-9_]{0,31}")
    private val STATE_KEY = Regex("[\\x20-\\x7e]{1,64}")
    const val MAX_INT = 9007199254740991L

    fun bytes(v: Any?): ByteArray {
        check(v, "value", KEY)
        return StringBuilder().also { encode(v, it, sortKeys = true) }.toString().toByteArray(Charsets.UTF_8)
    }

    /** Replay state (§14): the same, except keys may be any printable ASCII of 1-64 characters. */
    fun stateBytes(v: Any?): ByteArray {
        check(v, "value", STATE_KEY)
        return StringBuilder().also { encode(v, it, sortKeys = true) }.toString().toByteArray(Charsets.UTF_8)
    }

    fun check(v: Any?, where: String = "value", keys: Regex = KEY) {
        when (v) {
            null, is Boolean -> {}
            is Long -> if (v < -MAX_INT || v > MAX_INT) throw ProtocolError("bad_encoding", "integer out of range at $where")
            is Int -> {}
            is JNumber -> throw ProtocolError("bad_encoding", "number ${v.text} at $where")
            is String -> checkString(v, where)
            is List<*> -> v.forEachIndexed { i, x -> check(x, "$where[$i]", keys) }
            is Map<*, *> -> for ((k, x) in v) {
                if (k !is String || !keys.matches(k)) throw ProtocolError("bad_encoding", "bad key $k at $where")
                check(x, "$where.$k", keys)
            }
            else -> throw ProtocolError("bad_encoding", "unsupported type ${v::class.simpleName} at $where")
        }
    }

    private fun checkString(s: String, where: String) {
        var i = 0
        while (i < s.length) {
            val c = s[i]
            if (Character.isHighSurrogate(c)) {
                if (i + 1 >= s.length || !Character.isLowSurrogate(s[i + 1])) throw ProtocolError("bad_encoding", "unpaired surrogate at $where")
                i += 2
                continue
            }
            if (Character.isLowSurrogate(c)) throw ProtocolError("bad_encoding", "unpaired surrogate at $where")
            i++
        }
    }

    /** Python json.dumps(ensure_ascii=False, separators=(',', ':')) (+ sort_keys by code point). */
    fun encode(v: Any?, sb: StringBuilder, sortKeys: Boolean) {
        when (v) {
            null -> sb.append("null")
            is Boolean -> sb.append(if (v) "true" else "false")
            is Long, is Int -> sb.append(v.toString())
            is JNumber -> sb.append(v.text)
            is String -> string(v, sb)
            is List<*> -> {
                sb.append('[')
                v.forEachIndexed { i, x -> if (i > 0) sb.append(','); encode(x, sb, sortKeys) }
                sb.append(']')
            }
            is Map<*, *> -> {
                sb.append('{')
                val ks = v.keys.map { it as String }.let { if (sortKeys) it.sortedWith(::cmpCodePoints) else it }
                ks.forEachIndexed { i, k -> if (i > 0) sb.append(','); string(k, sb); sb.append(':'); encode(v[k], sb, sortKeys) }
                sb.append('}')
            }
            else -> throw ProtocolError("bad_encoding", "unsupported type")
        }
    }

    private fun string(s: String, sb: StringBuilder) {
        sb.append('"')
        for (c in s) {
            when {
                c == '"' -> sb.append("\\\"")
                c == '\\' -> sb.append("\\\\")
                c == '\n' -> sb.append("\\n")
                c == '\r' -> sb.append("\\r")
                c == '\t' -> sb.append("\\t")
                c == '\b' -> sb.append("\\b")
                c == '\u000c' -> sb.append("\\f")
                c < ' ' -> sb.append("\\u00").append(Character.forDigit(c.code shr 4, 16)).append(Character.forDigit(c.code and 15, 16))
                else -> sb.append(c)
            }
        }
        sb.append('"')
    }
}

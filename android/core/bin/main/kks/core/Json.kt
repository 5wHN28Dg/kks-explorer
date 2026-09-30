package kks.core

/**
 * JSON for the protocol (docs/PROTOCOL.md §1). Values are: null, Boolean, Long, String, List<Any?>,
 * Map<String, Any?> (insertion-ordered). A number the protocol can't carry (a fraction, an exponent, or an integer
 * beyond Long) parses to [JNumber], so [Canonical] can reject it with the same error Python gives.
 */
class JsonError(msg: String) : Exception(msg)

/** A number kept as text: never canonical. */
data class JNumber(val text: String)

object Json {
    fun parse(s: String): Any? {
        val p = Parser(s)
        p.ws()
        val v = p.value()
        p.ws()
        if (p.i != s.length) throw JsonError("trailing data at ${p.i}")
        return v
    }

    fun parse(b: ByteArray): Any? = parse(String(b, Charsets.UTF_8))

    /** Compact JSON in insertion order, non-ASCII as-is (sync messages, files). Not for hashing: see [Canonical]. */
    fun write(v: Any?): String = StringBuilder().also { Canonical.encode(v, it, sortKeys = false) }.toString()

    private class Parser(val s: String) {
        var i = 0

        fun ws() {
            while (i < s.length && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r')) i++
        }

        fun value(): Any? {
            if (i >= s.length) throw JsonError("unexpected end")
            return when (val c = s[i]) {
                '{' -> obj()
                '[' -> arr()
                '"' -> str()
                't' -> word("true", true)
                'f' -> word("false", false)
                'n' -> word("null", null)
                'N' -> word("NaN", JNumber("NaN"))
                'I' -> word("Infinity", JNumber("Infinity"))
                else -> if (c == '-' || c in '0'..'9') num() else throw JsonError("unexpected '$c' at $i")
            }
        }

        fun word(w: String, v: Any?): Any? {
            if (!s.startsWith(w, i)) throw JsonError("bad literal at $i")
            i += w.length
            return v
        }

        fun obj(): Map<String, Any?> {
            val m = LinkedHashMap<String, Any?>()
            i++; ws()
            if (i < s.length && s[i] == '}') { i++; return m }
            while (true) {
                ws()
                if (i >= s.length || s[i] != '"') throw JsonError("expected key at $i")
                val k = str()
                ws()
                if (i >= s.length || s[i] != ':') throw JsonError("expected ':' at $i")
                i++; ws()
                m[k] = value()   // a repeated key keeps the last value, as in Python
                ws()
                if (i >= s.length) throw JsonError("unexpected end")
                if (s[i] == ',') { i++; continue }
                if (s[i] == '}') { i++; return m }
                throw JsonError("expected ',' or '}' at $i")
            }
        }

        fun arr(): List<Any?> {
            val l = ArrayList<Any?>()
            i++; ws()
            if (i < s.length && s[i] == ']') { i++; return l }
            while (true) {
                ws(); l.add(value()); ws()
                if (i >= s.length) throw JsonError("unexpected end")
                if (s[i] == ',') { i++; continue }
                if (s[i] == ']') { i++; return l }
                throw JsonError("expected ',' or ']' at $i")
            }
        }

        fun str(): String {
            val sb = StringBuilder()
            i++
            while (true) {
                if (i >= s.length) throw JsonError("unterminated string")
                val c = s[i++]
                when {
                    c == '"' -> return sb.toString()
                    c == '\\' -> {
                        if (i >= s.length) throw JsonError("bad escape")
                        when (val e = s[i++]) {
                            '"' -> sb.append('"'); '\\' -> sb.append('\\'); '/' -> sb.append('/')
                            'b' -> sb.append('\b'); 'f' -> sb.append('\u000c'); 'n' -> sb.append('\n')
                            'r' -> sb.append('\r'); 't' -> sb.append('\t')
                            'u' -> {
                                if (i + 4 > s.length) throw JsonError("bad \\u escape")
                                sb.append(s.substring(i, i + 4).toIntOrNull(16)?.toChar() ?: throw JsonError("bad \\u escape"))
                                i += 4
                            }
                            else -> throw JsonError("bad escape \\$e")
                        }
                    }
                    c < ' ' -> throw JsonError("control character in string")
                    else -> sb.append(c)
                }
            }
        }

        fun num(): Any {
            val m = NUM.find(s, i) ?: throw JsonError("bad number at $i")
            if (m.range.first != i) throw JsonError("bad number at $i")
            val t = m.value
            i += t.length
            if (t == "-") return word("Infinity", JNumber("-Infinity")) as Any
            if (m.groups[1] == null) throw JsonError("bad number at ${i - t.length}")
            if (m.groups[2] != null || m.groups[3] != null) return JNumber(t)
            return t.toLongOrNull() ?: JNumber(t)
        }

        companion object {
            val NUM = Regex("-?(0|[1-9][0-9]*)?(\\.[0-9]+)?([eE][+-]?[0-9]+)?")
        }
    }
}

/** Strings compare by Unicode code point (Python), not UTF-16 unit (Kotlin's default). */
fun cmpCodePoints(a: String, b: String): Int {
    var i = 0
    var j = 0
    while (i < a.length && j < b.length) {
        val x = a.codePointAt(i)
        val y = b.codePointAt(j)
        if (x != y) return x.compareTo(y)
        i += Character.charCount(x); j += Character.charCount(y)
    }
    return (a.length - i).compareTo(b.length - j)
}

/** Python equality on JSON values: dicts by content, and True == 1, False == 0. */
fun pyEquals(a: Any?, b: Any?): Boolean = when {
    a is Boolean && b is Long -> (if (a) 1L else 0L) == b
    a is Long && b is Boolean -> a == (if (b) 1L else 0L)
    a is Map<*, *> && b is Map<*, *> -> a.size == b.size && a.all { (k, v) -> b.containsKey(k) && pyEquals(v, b[k]) }
    a is List<*> && b is List<*> -> a.size == b.size && a.indices.all { pyEquals(a[it], b[it]) }
    else -> a == b
}

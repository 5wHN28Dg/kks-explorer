package kks.explorer.ui

import org.json.JSONObject

/** Errors in plain words (#371, F2 in docs/UI-UX-POLICY.md), the same sentences as the web's common.js K.errorWords
 *  and the desktop apps' errwords.nim: the core sends an error's kind ("code") with its own text. Its text is shown
 *  when it is already a sentence ("Wrong username or password."); a terse one ("not found", "admin only") becomes the
 *  sentence for its kind. The raw text goes to the log. */
object Errors {
    val words = mapOf(
        "sign_in" to "Your sign-in has ended. Sign in again.",
        "not_allowed" to "You don't have the right to do that here. Ask an admin if you need it.",
        "not_found" to "It isn't there any more: someone may have removed it. Open it again to see what is there now.",
        "conflict" to "It was changed meanwhile, so this was not saved. Look at the current value and try again.",
        "too_large" to "That is too large to send. Choose a smaller file or a shorter text.",
        "too_many" to "Too many tries. Wait a few minutes, then try again.",
        "invalid" to "That was not accepted. Check what you entered and try again.",
        "server" to "The server had a problem, so this was not done. Try again in a moment.",
        "unreachable" to "Couldn't reach the server. Check the network and try again.")

    /** terse texts that have a sentence of their own */
    val terse = mapOf(
        "manager only" to "Only the plant's manager can do that.",
        "admin only" to "Only an admin can do that.",
        "cross-origin request refused" to "The request came from another page and was refused. Open Walkdown from its own address.",
        "not saved on this device" to "This isn't saved on this device for offline use. Connect to the server to see it.",
        "method not allowed" to "This needs a newer Walkdown here or on the server.")

    /** a readable text of the core's ("this invite has expired; ask for a new one") as a sentence */
    fun asSentence(t: String) = t.trim().let { if (it.isEmpty()) it else it.replaceFirstChar { c -> c.uppercase() } + if (it.last() in ".!?") "" else "." }

    fun codeOf(status: Int) = when (status) {
        401 -> "sign_in"; 403 -> "not_allowed"; 404 -> "not_found"; 409 -> "conflict"; 413 -> "too_large"; 429 -> "too_many"
        in 400..499 -> "invalid"; else -> "server"
    }

    /** a developer's text, not meant for people ("bad submission kind or payload", "action must be start or confirm") */
    fun devText(t: String) = t.lowercase().let { it.startsWith("bad ") || it.startsWith("unknown ") || "(" in it || " must be " in it || " is required" in it }

    fun isSentence(t: String) = t.trim().let { it.length > 1 && it[0] in 'A'..'Z' && it.last() in ".!?" }

    /** what to say for an error response */
    /** what to say for an error response: a terse text's own sentence; the server's sentence; for a request that was
     *  refused (invalid, too large, too many, not allowed) its specific text of three words or more made a sentence
     *  ("Note: up to 500 characters."); else the sentence for the kind */
    fun text(status: Int, j: JSONObject?): String {
        val raw = j?.optString("error").orEmpty().trim()
        val code = j?.optString("code")?.takeIf { it in words } ?: codeOf(status)
        terse[raw]?.let { return it }
        if (isSentence(raw)) return raw
        if (raw.isNotEmpty()) android.util.Log.i("KKSErrors", "$status $raw")
        if (code in setOf("invalid", "too_large", "too_many", "not_allowed", "conflict") && raw.split(Regex("\\s+")).size >= 3 && !devText(raw))
            return asSentence(raw)
        return words.getValue(code)
    }

    const val LOST_JOIN = "The connection to the admin's device was lost before they decided. Ask again."
    const val FIRST_SYNC_FAILED = "Accepted, but the first sync did not finish. Try again in a moment."

    fun syncFailed(host: String, port: Int, e: Throwable?): String {
        if (e != null) android.util.Log.i("KKSErrors", "sync $host:$port: ${e.message}")
        return "Couldn't sync with $host:$port. Check that the device is on, on this network, and that its address and port are right."
    }

    /** a server this phone could not connect to: plain words; the system's text goes to the log */
    fun unreachable(host: String, port: Int, e: Throwable?): String {
        if (e != null) android.util.Log.i("KKSErrors", "connect $host:$port: ${e.message}")
        return "Couldn't reach the server at $host:$port. Check the address and that this phone is on the plant's network."
    }
}

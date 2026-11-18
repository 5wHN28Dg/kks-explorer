package kks.explorer.ui

import org.json.JSONObject

/** Errors in plain words (#371, F2 in docs/UI-UX-POLICY.md), the same sentences as the web's common.js K.errorWords
 *  and the desktop apps' errwords.nim: the core sends an error's kind ("code") with its own text. Its text is shown
 *  when it is already a sentence ("Wrong username or password."); a terse one ("not found", "admin only") becomes the
 *  sentence for its kind. The raw text goes to the log. */
object Errors {
    val words = mapOf(
        "sign_in" to "Your sign-in has ended. Sign in again; what you typed is kept.",
        "not_allowed" to "You don't have the right to do that. An admin can.",
        "not_found" to "It isn't there any more: someone may have removed it. Reload to see what is there now.",
        "conflict" to "It was changed meanwhile, so this was not saved. Look at the current value and try again.",
        "too_large" to "That is too large to send.",
        "too_many" to "Too many tries. Wait a few minutes, then try again.",
        "invalid" to "That was not accepted. Check what you entered and try again.",
        "server" to "The server had a problem, so this was not done. Try again in a moment.",
        "unreachable" to "Couldn't reach the server. Check the network; what you changed is kept on this device.")

    fun codeOf(status: Int) = when (status) {
        401 -> "sign_in"; 403 -> "not_allowed"; 404 -> "not_found"; 409 -> "conflict"; 413 -> "too_large"; 429 -> "too_many"
        in 400..499 -> "invalid"; else -> "server"
    }

    fun isSentence(t: String) = t.trim().let { it.length > 1 && it[0] in 'A'..'Z' && it.last() in ".!?" }

    /** what to say for an error response */
    fun text(status: Int, j: JSONObject?): String {
        val raw = j?.optString("error").orEmpty()
        if (isSentence(raw)) return raw
        if (raw.isNotEmpty()) android.util.Log.i("KKSErrors", "$status $raw")
        return words[j?.optString("code")?.ifEmpty { null } ?: codeOf(status)] ?: words.getValue("server")
    }

    /** a server this phone could not connect to: plain words; the system's text goes to the log */
    fun unreachable(host: String, port: Int, e: Throwable?): String {
        if (e != null) android.util.Log.i("KKSErrors", "connect $host:$port: ${e.message}")
        return "Couldn't reach the server at $host:$port. Check the address and that this phone is on the plant's network."
    }
}

package kks.explorer.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import kks.explorer.core.Core
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** the data changed underneath (a sync, an approval): screens recompose (R20) */
object Changes { var rev by mutableIntStateOf(0) }

/** a call to the core's local API: the JSON, or the error message */
class Result(val json: JSONObject, val error: String?) {
    val ok get() = error == null
}

fun call(meth: String, path: String, body: JSONObject? = null, query: Map<String, String> = emptyMap()): Result {
    val r = Core.api(meth, path, body, query)
    return if (r.status >= 400) Result(r.json, r.json.optString("error").ifEmpty { "error ${r.status}" }) else Result(r.json, null)
}

fun JSONArray?.objects(): List<JSONObject> = if (this == null) emptyList() else (0 until length()).map { getJSONObject(it) }
fun JSONObject.str(k: String): String = if (has(k) && !isNull(k)) opt(k)?.let { if (it is String) it else it.toString() } ?: "" else ""

fun whenText(sec: Long): String = if (sec <= 0) "" else SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.ROOT).format(Date(sec * 1000))

/** a short, readable form of a payload (the same rule as the GNOME app) */
fun summary(p: JSONObject?): String {
    if (p == null) return ""
    return p.keys().asSequence().filter { it !in setOf("base", "dataUrl", "blob", "photo_id", "id", "file") }.mapNotNull { k ->
        val v = p.opt(k)
        val t = when (v) { null, JSONObject.NULL -> "—"; is String -> v; else -> v.toString() }
        if (t.isEmpty()) null else "$k: " + (if (t.length > 160) t.take(160) + "…" else t)
    }.joinToString(" · ")
}

@Composable
fun Section(title: String, subtitle: String = "", content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(title, style = MaterialTheme.typography.titleMedium)
        if (subtitle.isNotEmpty()) Dim(subtitle)
        content()
    }
}

@Composable
fun Dim(text: String) = Text(text, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)

/** ask before something that can't be undone in one tap */
@Composable
fun Confirm(title: String, text: String, yes: String, onYes: () -> Unit, onDismiss: () -> Unit) {
    AlertDialog(onDismissRequest = onDismiss, title = { Text(title) }, text = { if (text.isNotEmpty()) Text(text) },
        confirmButton = { TextButton(onClick = { onDismiss(); onYes() }) { Text(yes) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } })
}

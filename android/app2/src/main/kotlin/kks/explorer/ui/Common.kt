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
        // act first, then close: closing may clear the state the action reads (a photo delete sent an empty id)
        confirmButton = { TextButton(onClick = { onYes(); onDismiss() }) { Text(yes) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } })
}

/** Material icons (Apache-2.0) as vectors: one look for every icon, unlike text characters, whose glyphs come from
 *  whatever font the phone has (the bottom bar's ☰ and ⚙ looked unlike each other on the Note 9) */
object Glyphs {
    private fun icon(d: String) = androidx.compose.ui.graphics.vector.ImageVector.Builder(defaultWidth = 24.dp, defaultHeight = 24.dp, viewportWidth = 24f, viewportHeight = 24f)
        .addPath(androidx.compose.ui.graphics.vector.PathParser().parsePathString(d).toNodes(), fill = androidx.compose.ui.graphics.SolidColor(androidx.compose.ui.graphics.Color.Black)).build()
    val DRAWINGS = icon("M22 11V3h-7v3H9V3H2v8h7V8h2v10h4v3h7v-8h-7v3h-2V8h2v3z")                       // account_tree
    val PROCEDURES = icon("M4 10.5c-.83 0-1.5.67-1.5 1.5s.67 1.5 1.5 1.5 1.5-.67 1.5-1.5-.67-1.5-1.5-1.5zm0-6c-.83 0-1.5.67-1.5 1.5S3.17 7.5 4 7.5 5.5 6.83 5.5 6 4.83 4.5 4 4.5zm0 12c-.83 0-1.5.68-1.5 1.5s.68 1.5 1.5 1.5 1.5-.68 1.5-1.5-.67-1.5-1.5-1.5zM7 19h14v-2H7v2zm0-6h14v-2H7v2zm0-8v2h14V5H7z")   // format_list_bulleted
    val REVIEW = icon("M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z")   // check_circle
    val LEARNING = icon("M5 13.18v4L12 21l7-3.82v-4L12 17l-7-3.82zM12 3L1 9l11 6 9-4.91V17h2V9L12 3z")    // school
    val MANAGE = icon("M19.14 12.94c.04-.3.06-.61.06-.94 0-.32-.02-.64-.07-.94l2.03-1.58c.18-.14.23-.41.12-.61l-1.92-3.32c-.12-.22-.37-.29-.59-.22l-2.39.96c-.5-.38-1.03-.7-1.62-.94l-.36-2.54c-.04-.24-.24-.41-.48-.41h-3.84c-.24 0-.43.17-.47.41l-.36 2.54c-.59.24-1.13.57-1.62.94l-2.39-.96c-.22-.08-.47 0-.59.22L2.74 8.87c-.12.21-.08.47.12.61l2.03 1.58c-.05.3-.09.63-.09.94s.02.64.07.94l-2.03 1.58c-.18.14-.23.41-.12.61l1.92 3.32c.12.22.37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .44-.17.47-.41l.36-2.54c.59-.24 1.13-.56 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32c.12-.22.07-.47-.12-.61l-2.01-1.58zM12 15.6c-1.98 0-3.6-1.62-3.6-3.6s1.62-3.6 3.6-3.6 3.6 1.62 3.6 3.6-1.62 3.6-3.6 3.6z")   // settings
    val BACK = icon("M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z")                       // arrow_back
    val FIT = icon("M17 4h3c1.1 0 2 .9 2 2v2h-2V6h-3V4zM4 8V6h3V4H4c-1.1 0-2 .9-2 2v2h2zm16 8v2h-3v2h3c1.1 0 2-.9 2-2v-2h-2zM7 18H4v-2H2v2c0 1.1.9 2 2 2h3v-2zM18 8H6v8h12V8z")   // fit_screen
    val UNDO = icon("M12.5 8c-2.65 0-5.05.99-6.9 2.6L2 7v9h9l-3.62-3.62c1.39-1.16 3.16-1.88 5.12-1.88 3.54 0 6.55 2.31 7.6 5.5l2.37-.78C21.08 11.03 17.15 8 12.5 8z")   // undo
    val FULLSCREEN = icon("M7 14H5v5h5v-2H7v-3zm-2-4h2V7h3V5H5v5zm12 7h-3v2h5v-5h-2v3zM14 5v2h3v3h2V5h-5z")   // fullscreen
    val FULLSCREEN_EXIT = icon("M5 16h3v3h2v-5H5v2zm3-8H5v2h5V5H8v3zm6 11h2v-3h3v-2h-5v5zm2-11V5h-2v5h5V8h-3z")   // fullscreen_exit
    val CLOSE = icon("M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z")   // close
}

/** call first inside a full-screen Dialog: its window then covers the screen and its content gets the real insets
 *  (safeDrawing). Without it the window is clipped between the system bars while the content is laid out at the full
 *  screen height: the bottom was cut off (the photo editor on the Honor 600, 2026-10-04). */
@Composable
fun FullScreenDialogWindow() {
    val window = (androidx.compose.ui.platform.LocalView.current.parent as? androidx.compose.ui.window.DialogWindowProvider)?.window
    SideEffect {
        window?.let { w ->
            androidx.core.view.WindowCompat.setDecorFitsSystemWindows(w, false)
            w.setLayout(android.view.ViewGroup.LayoutParams.MATCH_PARENT, android.view.ViewGroup.LayoutParams.MATCH_PARENT)
            if (android.os.Build.VERSION.SDK_INT >= 30) w.attributes = w.attributes.apply { fitInsetsTypes = 0 }
        }
    }
}

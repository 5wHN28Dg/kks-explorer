package kks.explorer.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject

private val PHOTO_KINDS = listOf("both" to "both", "equipment" to "equipment only", "plate" to "tag plate only", "none" to "none")

/** n of [of] (> 0) as a whole percent (core views.coveragePct): to the nearest, but 100 only when all and 0 only when
 *  none (199 of 200 = 99, 1 of 300 = 1): the dashboard is about what is still missing */
internal fun coveragePct(n: Int, of: Int): Int = when {
    n <= 0 -> 0
    n >= of -> 100
    else -> ((200L * n + of) / (2L * of)).toInt().coerceIn(1, 99)
}
private fun pct(n: Int, of: Int) = if (of <= 0) "–" else "${coveragePct(n, of)} %"
/** the same for TalkBack: ", 40 % checked by a person", nothing when there is nothing to count (no "dash") */
private fun pctW(n: Int, of: Int, what: String) = if (of <= 0) "" else ", ${pct(n, of)} $what"
private fun plural(n: Int, one: String, many: String = one + "s") = "$n " + if (n == 1) one else many

/** the photo counts in words (TalkBack, and the totals' legend) */
private fun photoWords(p: JSONObject?): String =
    "photos: " + PHOTO_KINDS.joinToString(", ") { (k, w) -> "${p?.optInt(k) ?: 0} $w" }

/** How complete the plant's record is (core coverageView): totals, then per sheet and per system, each with its photo
 *  coverage as a bar in the drawing's coverage colours. A sheet opens on the drawing with the photo colours on; a
 *  system opens Equipment by system showing that system only. */
@Composable
fun CoverageScreen(onSheet: (String) -> Boolean, onSystem: (String) -> Unit, onClose: () -> Unit) {
    val rev = Changes.rev
    // the dashboard is its own window (a Dialog): a message about it must show here, the app's snackbar is behind it
    val snack = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    var view by remember { mutableStateOf<JSONObject?>(null) }
    LaunchedEffect(rev) { view = withContext(Dispatchers.IO) { call("GET", "/native/coverage").json } }
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        FullScreenDialogWindow()
        Surface(Modifier.fillMaxSize()) { Box(Modifier.fillMaxSize()) {
            Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing)) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = onClose, modifier = Modifier.semantics { contentDescription = "Close" }) { Icon(Glyphs.BACK, contentDescription = null) }
                    Text("Coverage", style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f).semantics { heading() })
                }
                val v = view
                if (v == null) Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                else LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 16.dp)) {
                    item(contentType = "totals") { Totals(v.optJSONObject("total") ?: JSONObject()) }
                    item(contentType = "head") { ListHead("By sheet", "Tap a sheet to see it with the photo colours") }
                    items(v.optJSONArray("sheets").objects(), key = { "s:" + it.str("id") }, contentType = { "row" }) { s ->
                        val codes = s.optInt("codes"); val tags = s.optInt("tags")
                        CoverRow(title = s.str("name"),
                            line = "${plural(codes, "code")} · ${pct(s.optInt("verified"), tags)} of tags checked · ${pct(s.optInt("located"), codes)} placed" +
                                (if (s.optInt("review") > 0) " · ${s.optInt("review")} to review" else "") +
                                (if (s.optInt("marked") > 0) " · ${s.optInt("marked")} marked" else ""),
                            words = "${s.str("name")}: ${plural(codes, "code")} on ${plural(tags, "tag")}${pctW(s.optInt("verified"), tags, "of tags checked by a person")}" +
                                "${pctW(s.optInt("located"), codes, "with a known place")}, ${photoWords(s.optJSONObject("photos"))}, " +
                                "${s.optInt("review")} to review, ${s.optInt("marked")} missed tags marked",
                            photos = s.optJSONObject("photos"), action = "Show the sheet with photo colours") {
                        // a hand-marked tag can outlive its sheet: its row is counted, but there is nothing to open
                        if (!onSheet(s.str("id"))) scope.launch { snack.currentSnackbarData?.dismiss(); snack.showSnackbar("That sheet is no longer in the plant data", duration = SnackbarDuration.Long) }
                    }
                    }
                    item(contentType = "head") { ListHead("By system", "Tap a system to list its equipment") }
                    items(v.optJSONArray("systems").objects(), key = { "y:" + it.str("sys") }, contentType = { "row" }) { y ->
                        val codes = y.optInt("codes")
                        val title = if (y.str("sys").isEmpty()) "Codes that don't decode" else listOf(y.str("sys"), y.str("sys_name")).filter { it.isNotEmpty() }.joinToString(" · ")
                        CoverRow(title = title,
                            line = "${plural(codes, "code")} · ${pct(y.optInt("verified"), codes)} of codes checked · ${pct(y.optInt("located"), codes)} placed",
                            words = "$title: ${plural(codes, "code")}${pctW(y.optInt("verified"), codes, "of codes checked by a person")}" +
                                "${pctW(y.optInt("located"), codes, "with a known place")}, ${photoWords(y.optJSONObject("photos"))}",
                            photos = y.optJSONObject("photos"), action = "List the system's equipment") { onSystem(y.str("sys")) }
                    }
                }
            }
            SnackbarHost(snack, Modifier.align(Alignment.BottomCenter).windowInsetsPadding(WindowInsets.safeDrawing))
        } }
    }
}

@Composable
private fun Totals(t: JSONObject) {
    val codes = t.optInt("codes"); val tags = t.optInt("tags")
    val p = t.optJSONObject("photos")
    Card(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            // each figure is one line for TalkBack ("Checked by a person: 40 %, 2 of 5 tags")
            Fig("Codes on the drawings", "$codes", "on ${plural(tags, "tag")}")
            Fig("Checked by a person", pct(t.optInt("verified"), tags), "${t.optInt("verified")} of ${plural(tags, "tag")}")
            Fig("Known place", pct(t.optInt("located"), codes), "${t.optInt("located")} of ${plural(codes, "code")}")
            Fig("To review", "${t.optInt("review")}", "")
            Fig("Missed tags marked", "${t.optInt("marked")}", "")
            Text("Photos", style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 6.dp))
            PhotoBar(p, Modifier.height(14.dp))
            Column(Modifier.semantics(mergeDescendants = true) {}) {
                for ((k, w) in PHOTO_KINDS) Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(12.dp).background(Color(coverColor(k))))
                    Spacer(Modifier.width(8.dp))
                    Text("${w.replaceFirstChar { it.uppercase() }}: ${p?.optInt(k) ?: 0} (${pct(p?.optInt(k) ?: 0, codes)})", style = MaterialTheme.typography.bodyMedium)
                }
            }
        }
    }
}

@Composable
private fun Fig(label: String, value: String, detail: String) {
    Row(Modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = "$label: $value" + if (detail.isNotEmpty()) " ($detail)" else "" }, verticalAlignment = Alignment.CenterVertically) {
        Text("$label: ", style = MaterialTheme.typography.bodyLarge)
        Text(value, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
        if (detail.isNotEmpty()) Text("  ($detail)", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun ListHead(title: String, hint: String) {
    Column(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 4.dp)) {
        Text(title, style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
        Dim(hint)
    }
}

/** the codes' photo coverage as one bar: both, equipment only, tag plate only, none (the drawing's colours); empty =
 *  grey. Drawn only: the row's words carry the numbers */
@Composable
private fun PhotoBar(p: JSONObject?, modifier: Modifier = Modifier) {
    val n = PHOTO_KINDS.map { (k, _) -> p?.optInt(k) ?: 0 }
    Row(modifier.fillMaxWidth().clip(RoundedCornerShape(3.dp)).background(MaterialTheme.colorScheme.surfaceVariant).clearAndSetSemantics {}) {
        if (n.sum() > 0) for ((i, kw) in PHOTO_KINDS.withIndex()) if (n[i] > 0)
            Box(Modifier.weight(n[i].toFloat()).fillMaxHeight().background(Color(coverColor(kw.first))))
    }
}

@Composable
private fun CoverRow(title: String, line: String, words: String, photos: JSONObject?, action: String, onOpen: () -> Unit) {
    Column(Modifier.fillMaxWidth()
        .clickable(onClickLabel = action, role = Role.Button, onClick = onOpen)
        .clearAndSetSemantics { contentDescription = words; role = Role.Button; onClick(action) { onOpen(); true } }
        .padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(title, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
        Text(line, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        PhotoBar(photos, Modifier.height(8.dp))
    }
}

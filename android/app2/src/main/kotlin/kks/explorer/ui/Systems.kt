package kks.explorer.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import org.json.JSONObject

/** one line of the flattened tree: a group header (block, system, subsystem, kind) or a code */
private sealed class SysRow(val key: String) {
    class Head(key: String, val level: Int, val code: String, val name: String, val count: Int, val open: Boolean) : SysRow(key)
    class Item(key: String, val j: JSONObject) : SysRow(key)
}

/** the core's systemsView as rows: what is open decides what is listed. Searching opens everything; otherwise
 *  blocks are open and systems closed, until the person opens or closes one (`toggled`). `only`: one system's codes
 *  (from Coverage; "" = the codes that don't decode), its system header open */
private fun flatten(v: JSONObject, searching: Boolean, toggled: Map<String, Boolean>, only: String? = null): List<SysRow> {
    val out = ArrayList<SysRow>()
    fun open(key: String, level: Int) = toggled[key] ?: (searching || level == 0 || (only != null && level == 1))
    fun head(key: String, level: Int, code: String, name: String, count: Int): Boolean {
        val o = open(key, level)
        out.add(SysRow.Head(key, level, code, name, count, o))
        return o
    }
    for (b in v.optJSONArray("blocks").objects()) {
        val bk = "b:" + b.str("blk")
        val systems = b.optJSONArray("systems").objects().filter { only == null || it.str("sys") == only }
        if (systems.isEmpty()) continue
        val bCount = systems.sumOf { it.optInt("count") }
        if (!head(bk, 0, b.str("blk"), b.str("blk_name").ifEmpty { "Block " + b.str("blk") }, bCount)) continue
        for (s in systems) {
            val sk = bk + "/" + s.str("sys")
            if (!head(sk, 1, s.str("sys"), s.str("sys_name"), s.optInt("count"))) continue
            for (f in s.optJSONArray("subsystems").objects()) {
                val fk = sk + "/" + f.str("fn")
                if (!head(fk, 2, f.str("code"), "", f.optInt("count"))) continue
                for (k in f.optJSONArray("kinds").objects()) {
                    val kk = fk + "/" + k.str("comp")
                    if (!head(kk, 3, k.str("comp"), k.str("comp_name"), k.optInt("count"))) continue
                    for (it in k.optJSONArray("items").objects()) out.add(SysRow.Item(kk + "/" + it.str("code"), it))
                }
            }
        }
    }
    val other = if (only == null || only == "") v.optJSONArray("other").objects() else emptyList()
    if (other.isNotEmpty() && head("other", 1, "", "Other (codes that don't decode)", other.size))
        for (it in other) out.add(SysRow.Item("other/" + it.str("code"), it))
    return out
}

/** the codes the screen shows: all of the view's, or only one system's (or only the undecoded ones, `only` = "") */
internal fun shownCount(v: JSONObject, only: String?): Int {
    if (only == null) return v.optInt("total")
    if (only == "") return v.optJSONArray("other")?.length() ?: 0
    var n = 0
    for (b in v.optJSONArray("blocks").objects()) for (y in b.optJSONArray("systems").objects()) if (y.str("sys") == only) n += y.optInt("count")
    return n
}

/** every code on the drawings, by block → system → subsystem → component kind (core systemsView); a code opens its
 *  tag the way a search result does */
@Composable
fun SystemsScreen(ui: Ui, sys: String? = null, onClose: () -> Unit) {
    val rev = Changes.rev
    var only by remember { mutableStateOf(sys) }
    var query by rememberSaveable { mutableStateOf("") }
    var view by remember { mutableStateOf<JSONObject?>(null) }
    val toggled = remember { mutableStateMapOf<String, Boolean>() }
    val q = query.trim()
    LaunchedEffect(q, rev) {
        if (q.isNotEmpty()) delay(250)                  // typing: one core call once the person pauses
        view = withContext(Dispatchers.IO) { call("GET", "/native/systems", query = mapOf("q" to q)).json }
    }
    val rows = remember(view, toggled.toMap(), only) { view?.let { flatten(it, q.isNotEmpty(), toggled, only) } ?: emptyList() }
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        FullScreenDialogWindow()
        Surface(Modifier.fillMaxSize()) {
            Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing)) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = onClose, modifier = Modifier.semantics { contentDescription = "Close" }) { Icon(Glyphs.BACK, contentDescription = null) }
                    Text("Equipment by system", style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f).semantics { heading() })
                    view?.let { val n = shownCount(it, only); Dim("$n code" + if (n == 1) "" else "s"); Spacer(Modifier.width(12.dp)) }
                }
                only?.let { o ->
                    Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(if (o.isEmpty()) "Only the codes that don't decode" else "Only system $o", Modifier.weight(1f),
                            style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        TextButton(onClick = { only = null; toggled.clear() }) { Text("Show all systems") }
                    }
                }
                OutlinedTextField(query, { if (it.trim() != q) { toggled.clear(); if (it.isNotBlank()) only = null }; query = it }, placeholder = { Text("Filter: code, system, kind or description") }, singleLine = true,
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp).semantics { contentDescription = "Filter equipment by system" })
                if (view == null) Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                else if (rows.isEmpty()) Dim("  " + if (q.isEmpty()) "No codes on the drawings yet." else "Nothing matches “$q”.")
                else LazyColumn(Modifier.fillMaxSize().padding(top = 4.dp)) {
                    items(rows, key = { it.key }, contentType = { if (it is SysRow.Head) "head" else "item" }) { r ->
                        when (r) {
                            is SysRow.Head -> SysHeader(r) { toggled[r.key] = !r.open }
                            is SysRow.Item -> SysItem(r.j, indent = if (r.key.startsWith("other/")) 2 else 4) {
                                onClose(); ui.show(r.j.str("tag"))
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SysHeader(r: SysRow.Head, onToggle: () -> Unit) {
    val title = listOf(r.code, r.name).filter { it.isNotEmpty() }.joinToString(" · ")
    val style = when (r.level) { 0 -> MaterialTheme.typography.titleMedium; 1 -> MaterialTheme.typography.titleSmall; else -> MaterialTheme.typography.bodyLarge }
    Row(Modifier.fillMaxWidth()
        .clickable(onClickLabel = if (r.open) "Collapse" else "Expand", role = Role.Button, onClick = onToggle)
        .clearAndSetSemantics {
            contentDescription = "$title, ${r.count} code" + if (r.count == 1) "" else "s"
            stateDescription = if (r.open) "Expanded" else "Collapsed"
            role = Role.Button
            onClick(if (r.open) "Collapse" else "Expand") { onToggle(); true }
            if (r.level <= 1) heading()
        }
        .padding(start = (8 + 16 * r.level).dp, end = 16.dp, top = 10.dp, bottom = 10.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Text(if (r.open) "▾" else "▸", Modifier.width(20.dp), color = MaterialTheme.colorScheme.primary)
        Text(title, Modifier.weight(1f), style = style, fontWeight = if (r.level <= 1) FontWeight.SemiBold else null,
            maxLines = 2, overflow = TextOverflow.Ellipsis)
        Text("${r.count}", Modifier.padding(start = 8.dp),
            style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun SysItem(j: JSONObject, indent: Int, onOpen: () -> Unit) {
    val code = j.str("code"); val desc = j.str("desc"); val sheet = j.str("sheet_name"); val n = j.optInt("count", 1)
    val photos = j.str("photos").ifEmpty { "none" }
    val label = listOf(code, desc, sheet).filter { it.isNotEmpty() }.joinToString(", ") +
        (if (n > 1) ", appears $n times" else "") + ", " + coverWords(photos)
    Row(Modifier.fillMaxWidth()
        .clickable(onClickLabel = "Show on the drawing", role = Role.Button, onClick = onOpen)
        .clearAndSetSemantics { contentDescription = label; role = Role.Button; onClick("Show on the drawing") { onOpen(); true } }
        .padding(start = (8 + 16 * indent).dp, end = 16.dp, top = 8.dp, bottom = 8.dp),
        verticalAlignment = Alignment.CenterVertically) {
        PhotoMark(photos)
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(code, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.SemiBold, style = MaterialTheme.typography.bodyLarge)
                if (n > 1) Text("  ×$n", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (desc.isNotEmpty()) Text(desc, style = MaterialTheme.typography.bodyMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Text(sheet, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

/** The photo mark beside a code (search results, equipment by system): the coverage colour of the drawings and a shape
 *  of its own per state, so it reads without colour: none = an empty ring, equipment only = a half-filled disc, tag
 *  plate only = a filled square, both = a filled disc. A thin line in the text colour around it keeps the shape at 3:1
 *  on any theme (amber alone does not reach it on a light background). Drawn only: the row says the same in words
 *  ([coverWords]) unless [named]. */
@Composable
fun PhotoMark(photos: String, modifier: Modifier = Modifier, named: Boolean = false) {
    val hue = Color(markColor(photos, MaterialTheme.colorScheme.surface.luminance() > 0.5f))
    val line = LocalContentColor.current
    val words = coverWords(photos)
    androidx.compose.foundation.Canvas(modifier.size(14.dp).then(if (named) Modifier.semantics { contentDescription = words } else Modifier)) {
        val w = 2.dp.toPx(); val thin = 1.dp.toPx()
        val r = size.minDimension / 2 - thin * 1.5f                    // the coloured shape; the outline runs just outside it
        val inner = androidx.compose.ui.graphics.drawscope.Stroke(w)
        val outer = androidx.compose.ui.graphics.drawscope.Stroke(thin)
        when (photos) {
            "both" -> drawCircle(hue, r)
            "plate" -> drawRect(hue, androidx.compose.ui.geometry.Offset(center.x - r, center.y - r), androidx.compose.ui.geometry.Size(2 * r, 2 * r))
            "equipment" -> {
                drawArc(hue, 90f, 180f, true, androidx.compose.ui.geometry.Offset(center.x - r, center.y - r), androidx.compose.ui.geometry.Size(2 * r, 2 * r))
                drawCircle(hue, r - w / 2, style = inner)
            }
            else -> drawCircle(hue, r - w / 2, style = inner)
        }
        if (photos == "plate") drawRect(line, androidx.compose.ui.geometry.Offset(center.x - r - thin / 2, center.y - r - thin / 2),
            androidx.compose.ui.geometry.Size(2 * r + thin, 2 * r + thin), style = outer)
        else drawCircle(line, r + thin / 2, style = outer)
    }
}

/** the photo mark's fill: the coverage colour, except on a light background, where the green and the amber are darker
 *  (#2EA043 and #E69600 are 2.86:1 and 2.04:1 on the light results' surface; these 3.7:1 and 3.5:1, UI/UX audit of
 *  #401). The same on every client (GNOME systems.markColor, Windows ui.photoRgb). */
fun markColor(photos: String, light: Boolean): Int = when {
    light && photos == "both" -> android.graphics.Color.rgb(0x2B, 0x8A, 0x3E)
    light && photos == "equipment" -> android.graphics.Color.rgb(0xB3, 0x6B, 0x00)
    else -> coverColor(photos)
}

/** what the photo marks mean: the last line under the search results (not a result) */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun PhotoLegend(modifier: Modifier = Modifier) {
    FlowRow(modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text("Photos:", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        for (k in listOf("none", "equipment", "plate", "both")) Row(verticalAlignment = Alignment.CenterVertically) {
            PhotoMark(k)
            Spacer(Modifier.width(6.dp))
            Text(coverWords(k), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

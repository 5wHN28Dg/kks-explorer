package kks.explorer.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.activity.compose.BackHandler
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.focus.onFocusEvent
import androidx.compose.ui.composed
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kks.explorer.core.Core
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

val FIELDS = listOf("area" to "Building / area", "floor" to "Floor", "elev" to "Elevation", "near" to "Near / landmark",
    "loc" to "How to find it", "notes" to "Notes")

/** propose a change (members) or make it (admins): the same /api/submit as every client */
fun submit(kind: String, payload: JSONObject, note: String = ""): Pair<Boolean, String> {
    val body = JSONObject().put("kind", kind).put("payload", payload)
    if (note.isNotBlank()) body.put("note", note.trim())
    val r = Core.api("POST", "/api/submit", body)
    if (r.status >= 400) return false to Errors.text(r.status, r.json)
    Changes.rev++
    return true to when (r.json.optString("status")) { "approved" -> "Saved"; "conflict" -> "Held: it clashes with a pending change"; else -> "Sent for approval" }
}

/** one field of the panel: the label on the left, the value on the right (a code part in monospace before the
 *  meaning), so label and value can't be mistaken for each other (the user, 2026-10-05: "no clear separation") */
private data class Field(val label: String, val value: String, val code: String = "", val by: String = "")

@Composable
private fun Fields(rows: List<Field>) {
    Surface(color = MaterialTheme.colorScheme.surfaceContainerHighest, shape = MaterialTheme.shapes.medium, modifier = Modifier.fillMaxWidth()) {
        Column {
            rows.forEachIndexed { i, f ->
                if (i > 0) HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 10.dp).semantics(mergeDescendants = true) {},
                    verticalAlignment = androidx.compose.ui.Alignment.Top) {
                    Text(f.label, Modifier.weight(0.38f).padding(end = 8.dp), style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Column(Modifier.weight(0.62f)) {
                        Row {
                            if (f.code.isNotEmpty()) Text(f.code + "  ", style = MaterialTheme.typography.bodyLarge, fontFamily = FontFamily.Monospace,
                                fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
                            Text(f.value.ifEmpty { if (f.code.isEmpty()) "—" else "" }, style = MaterialTheme.typography.bodyLarge)
                        }
                        if (f.by.isNotEmpty()) Text(f.by, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}

@Composable
private fun Heading(text: String, modifier: Modifier = Modifier) =
    Text(text, modifier.padding(top = 8.dp), style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary)

/** the panel's height, kept while the app runs: the person sets it once by dragging the handle */
private object PanelSize { var dp = -1f }

/** what is typed and not sent in the open tag's panel, by form ("form", "desc", "review"): Back, Close, another tag or
 *  another sheet ask before it goes (#366, D3). `reset` empties them all (their saved state is keyed by it). */
/** the tag panel's own forms (the question names the panel when only they hold text) */
val PANEL_DRAFTS = setOf("form", "review", "desc")

object PanelDrafts {
    val dirty = mutableStateMapOf<String, Boolean>()
    var reset by mutableIntStateOf(0)
    fun any() = dirty.values.any { it }
    fun drop() { dirty.clear(); reset++ }
}

/** register whether `key`'s form holds typed text, while it is on screen (any screen's form: Back, the bottom tabs and
 *  another tag ask before it goes) */
@Composable
fun DraftFlag(key: String, typed: Boolean) {
    SideEffect { PanelDrafts.dirty[key] = typed }
    DisposableEffect(key) { onDispose { PanelDrafts.dirty.remove(key) } }
}

/** the equipment panel (R3–R6): decoded code, location list, the person's fields (read-only until Edit), review */
@Composable
fun TagPanel(id: String, rev: Int, onClose: () -> Unit, onGo: (String, String, List<Float>?) -> Unit, snack: SnackbarHostState,
             modifier: Modifier = Modifier, link: Pair<String, Int>? = null, overlayOpen: Boolean = false) {
    val scope = rememberCoroutineScope()
    val tNow = remember(id, rev) { Core.api("GET", "/native/tag", query = mapOf("id" to id)).json }
    // the tag removed meanwhile (by another device, arriving by sync, or before the app came back after Android stopped
    // it): the panel goes on showing it as it was last seen (saved with the panel), so what is typed in it stays (D3),
    // with a line saying it is gone; with nothing typed (or once it is sent or discarded) the panel closes
    var lastSeen by rememberSaveable(id) { mutableStateOf(if (tNow.has("sheet")) tNow.toString() else "") }
    val removed = !tNow.has("sheet")
    val last = remember(lastSeen) { if (lastSeen.isEmpty()) JSONObject() else JSONObject(lastSeen) }
    val keptGone = removed && last.has("sheet")
    val t = if (keptGone) last else tNow
    LaunchedEffect(tNow) { if (!removed) tNow.toString().let { if (it != lastSeen) lastSeen = it } }
    val typedAny = PanelDrafts.any()
    LaunchedEffect(removed, typedAny) { if (removed && !PanelDrafts.any()) onClose() }
    val screen = LocalConfiguration.current.screenHeightDp.toFloat()
    // resizable (the user, 2026-10-05: it took most of the screen): drag the handle, or tap it to go between a low
    // panel (the code and Close, the drawing above free to move around) and the usual height
    // low: the grip and the heading as tall as they are (a long code wraps, large text grows): never cut short
    var headDp by remember { mutableFloatStateOf(80f) }
    val low = maxOf(104f, 44f + headDp); val high = maxOf(screen * 0.85f, low); val usual = maxOf(screen * 0.45f, low)
    var height by remember { mutableFloatStateOf(if (PanelSize.dp > 0) PanelSize.dp else usual) }
    val dens = androidx.compose.ui.platform.LocalDensity.current.density
    // the Edit form and what is typed in it come back after the phone is turned or the app was stopped (#366)
    val reset = PanelDrafts.reset
    var editing by rememberSaveable(id, reset) { mutableStateOf(false) }
    val eq0 = t.optJSONObject("equipment") ?: JSONObject()
    var values by rememberSaveable(id, reset) { mutableStateOf(HashMap(FIELDS.associate { (f, _) -> f to eq0.optString(f) })) }
    // what the form was opened on: only what the person typed counts, not a change that arrived meanwhile
    var opened by rememberSaveable(id, reset) { mutableStateOf(HashMap(values)) }
    var note by rememberSaveable(id, reset) { mutableStateOf("") }
    val changed = editing && (FIELDS.any { (f, _) -> (values[f] ?: "").trim() != (opened[f] ?: "").trim() } || note.isNotBlank())
    DraftFlag("form", changed)
    // Back or Close with something typed in any of the panel's forms asks first (D3); without, they close as before
    val typed = PanelDrafts.any()
    var discarding by remember(id) { mutableStateOf<(() -> Unit)?>(null) }
    val leaveForm = { then: () -> Unit -> if (typed) discarding = then else { editing = false; then() } }
    // (not while a layer above the panel is open, the sheet list: Back closes that first, R2)
    BackHandler(enabled = (editing || typed) && !overlayOpen) { leaveForm {} }
    discarding?.let { then ->
        Confirm("Discard your edits?", "What you typed in the panel has not been saved.", "Discard", {
            PanelDrafts.drop(); then()
        }, { discarding = null }, no = "Keep editing")
    }
    // The keyboard (UI/UX audit of #363, R3): while the panel is open the window is not panned up under the status bar
    // (the system's default, which put the heading, Copy and Close under it in landscape); the panel rises above the
    // keyboard and shrinks to what is left (imePadding before height: the height is held within it), the grip giving
    // its place up while the keyboard is shown. Only while the panel is open: the other screens keep the pan. And only
    // for a field of the panel's own: typing in the drawing's search leaves the panel where it is (it would cover the
    // results, and on its side the search field itself).
    val window = (androidx.compose.ui.platform.LocalContext.current as? android.app.Activity)?.window
    DisposableEffect(window) {
        val before = window?.attributes?.softInputMode
        window?.setSoftInputMode(android.view.WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE or
            ((before ?: 0) and android.view.WindowManager.LayoutParams.SOFT_INPUT_MASK_STATE))
        onDispose { if (before != null) window.setSoftInputMode(before) }
    }
    var typingHere by remember { mutableStateOf(false) }
    val keyboard = typingHere && WindowInsets.ime.getBottom(androidx.compose.ui.platform.LocalDensity.current) > 0
    val bars = LocalBottomBars.current
    Surface((if (keyboard) modifier.consumeWindowInsets(PaddingValues(bottom = bars)).imePadding() else modifier).fillMaxWidth().height(maxOf(height, low).dp), tonalElevation = 6.dp, shadowElevation = 8.dp,
        shape = MaterialTheme.shapes.large) {
        Column(Modifier.onFocusChanged { typingHere = it.hasFocus }) {
        if (!keyboard) Box(Modifier.fillMaxWidth()
            .draggable(rememberDraggableState { d -> height = (height - d / dens).coerceIn(low, high); PanelSize.dp = height },
                orientation = androidx.compose.foundation.gestures.Orientation.Vertical)
            .clickable(onClickLabel = if (height > low + 1) "Make the panel small" else "Make the panel bigger") {
                height = if (height > low + 1) low else usual; PanelSize.dp = height
            }
            .semantics { contentDescription = "Panel size: drag to resize" }
            .padding(vertical = 10.dp), contentAlignment = androidx.compose.ui.Alignment.Center) {
            Box(Modifier.size(width = 40.dp, height = 4.dp).background(MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f), MaterialTheme.shapes.small))
        }
        // the heading stays above what scrolls (the user, 2026-11-15: "Close button shouldn't be hidden or move away
        // when I scroll down"): the code (selectable), Copy, Close
        PanelHeading(t.optString("code"), (if (t.optString("isa").isNotEmpty()) t.optString("isa") + " · " else "") + t.optString("kind"),
            { leaveForm(onClose) }, snack, Modifier.onSizeChanged { if (!keyboard) headDp = it.height / dens }, compact = keyboard)
        // (rememberScrollState is saved: the panel opens again where it was scrolled to)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, top = if (keyboard) 0.dp else 8.dp, bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (keptGone) Text("This tag was removed from the drawing meanwhile. What you typed is still here: send it or discard it.",
                color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })      // (TalkBack says it when it comes, F4)
            if (t.optString("status") == "review") ReviewSection(t, snack)
            t.optJSONObject("decoded")?.let { d ->
                Heading("From the drawing")
                Fields(listOfNotNull(
                    Field("Plant unit", d.optString("blk_name"), d.optString("blk")),
                    Field("System", d.optString("sys_name").ifEmpty { "not in the legend" }, d.optString("sys")),
                    Field("Component", d.optString("comp_name"), d.optString("comp")),
                    if (d.optString("isa").isNotEmpty()) Field("Instrument", d.optString("isa")) else null,
                    Field("Reading", t.optString("reading"))))
            }
            // the valve type (core tagView's valve_type), its symbol outlined on the drawing meanwhile (Root.kt)
            t.optJSONObject("valve_type")?.let { ValveSection(it, rev, snack) }
            val rows = t.optJSONArray("location_list") ?: JSONArray()
            if (rows.length() > 0) {
                Heading("Location list")
                Fields((0 until rows.length()).map { i -> rows.getJSONObject(i).let { r ->
                    Field(r.optString("desc").ifEmpty { "Location list" }, listOf("level", "cabinet", "direction").map { r.optString(it) }.filter { it.isNotEmpty() }.joinToString(" · "))
                } })
            }
            // where the instrument itself sits (a maker's list; core tagView's instrument_points): never a conflict
            val points = t.optJSONArray("instrument_points") ?: JSONArray()
            if (points.length() > 0) {
                Heading("Instrument point")
                Fields((0 until points.length()).map { i -> points.getJSONObject(i).let { r ->
                    Field(r.optString("desc").ifEmpty { "Instrument point" }, r.optString("text").ifEmpty { "—" },
                        by = r.optString("source").let { if (it.isNotEmpty()) "Source: $it" else "" })
                } })
            }
            val code = t.optString("code")
            t.optJSONObject("description")?.let { DescriptionSection(code, it, t.optJSONObject("equipment") ?: JSONObject(), snack) }
            if (link != null && code.isNotEmpty()) Button(onClick = {
                val (_, m) = linkSubmit(link.first, link.second, code, true)
                scope.launch { snack.showSnackbar("$code → step ${link.second}: $m") }
            }) { Text("Link to step ${link.second} of ${link.first}") }
            if (code.isNotEmpty()) {
                val eq = t.optJSONObject("equipment") ?: JSONObject()
                Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                    Heading("Location and notes", Modifier.weight(1f))
                    if (!editing) TextButton(onClick = { values = HashMap(FIELDS.associate { (f, _) -> f to eq.optString(f) }); opened = HashMap(values); note = ""; editing = true }) { Text("Edit") }
                }
                val eqBy = t.optJSONObject("equipment_by") ?: JSONObject()
                if (editing) HoldLinks()        // (a link would take the panel, and what was typed, away)
                if (!editing) {
                    // who set each field (the user, 2026-10-08: "show who … and the tag info they add")
                    Fields(FIELDS.map { (f, title) ->
                        Field(title, eq.optString(f).ifEmpty { if (f == "elev" && t.optString("list_elev").isNotEmpty()) t.optString("list_elev") + " (location list)" else "" },
                            by = if (eq.optString(f).isNotEmpty()) credit(eqBy.optJSONObject(f)) else "")
                    } + (eq.optJSONArray("custom")?.objects() ?: emptyList()).filter { it.str("k") != DESCRIPTION }.map { c ->
                        Field(c.str("k"), c.str("v"), by = credit(eqBy.optJSONObject("custom:" + c.str("k"))))
                    })
                } else {
                    for ((f, title) in FIELDS) OutlinedTextField(values[f] ?: "", { values = HashMap(values).apply { put(f, it) } }, label = { Text(title) }, modifier = Modifier.fillMaxWidth().inViewAboveKeyboard())
                    OutlinedTextField(note, { note = it }, label = { Text("Note for the approver (optional)") }, modifier = Modifier.fillMaxWidth().inViewAboveKeyboard())
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(onClick = {
                            val changes = JSONObject(); val base = JSONObject()
                            for ((f, _) in FIELDS) {
                                val nv = (values[f] ?: "").trim()
                                if (nv != eq.optString(f)) { changes.put(f, nv); base.put(f, eq.optString(f)) }
                            }
                            if (changes.length() == 0) { scope.launch { snack.showSnackbar("Nothing changed") }; return@Button }
                            val (ok, m) = submit("equipment", JSONObject().put("kks", code).put("changes", changes).put("base", base), note)
                            scope.launch { snack.showSnackbar(m) }
                            if (ok) editing = false
                        }) { Text("Save") }
                        OutlinedButton(onClick = { leaveForm {} }) { Text("Cancel") }
                    }
                }
                val where = t.optJSONArray("appears_on") ?: JSONArray()
                if (where.length() > 1) {
                    Heading("Appears on")
                    for (i in 0 until where.length()) where.getJSONObject(i).let { w ->
                        AssistChip(onClick = {
                            val tt = Core.api("GET", "/native/tag", query = mapOf("id" to w.getString("tag"))).json
                            onGo(w.getString("tag"), w.getString("sheet"), tt.optJSONArray("box")?.let { a -> (0 until 4).map { a.getDouble(it).toFloat() } })
                        }, label = { Text(w.getString("sheet_name")) })
                    }
                }
                val procs = t.optJSONArray("procedures") ?: JSONArray()
                if (procs.length() > 0) {
                    Heading("Used in procedures")
                    Fields((0 until procs.length()).map { i -> procs.getJSONObject(i).let { Field(it.getString("id"), it.optString("title")) } })
                }
                PhotoStrip(code, t.optJSONArray("photos").objects(), snack, floorNow = eq.optString("floor"))
            }
        }
        }
    }
}

/** The panel's heading, outside its scrolling part: the code (selectable: a long press copies part of it), a Copy
 *  button that puts the whole code on the clipboard and says "Copied", and Close. */
/** the height of the bars under the screen's content (the bottom navigation bar and the system's), set by Root: the
 *  tag panel already stands above them, so it rises only by the rest of the keyboard */
val LocalBottomBars = androidx.compose.runtime.compositionLocalOf { 0.dp }

/** A field of the panel's that keeps itself in view once the keyboard has come up and the panel has shrunk above it
 *  (Compose brings a focused field into view when it gets the focus, before the panel is made smaller: on its side
 *  the field's lower part then stood under the keyboard) */
@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
private fun Modifier.inViewAboveKeyboard(): Modifier = composed {
    val req = remember { androidx.compose.foundation.relocation.BringIntoViewRequester() }
    var focused by remember { mutableStateOf(false) }
    val ime = WindowInsets.ime.getBottom(androidx.compose.ui.platform.LocalDensity.current)
    LaunchedEffect(focused, ime) { if (focused && ime > 0) { kotlinx.coroutines.delay(100); req.bringIntoView() } }
    Modifier.bringIntoViewRequester(req).onFocusEvent { focused = it.isFocused }
}

@Composable
private fun PanelHeading(code: String, sub: String, onClose: () -> Unit, snack: SnackbarHostState, modifier: Modifier = Modifier,
                         compact: Boolean = false) {
    val clip = androidx.compose.ui.platform.LocalClipboardManager.current
    val scope = rememberCoroutineScope()
    var copied by remember(code) { mutableStateOf(false) }
    LaunchedEffect(copied) { if (copied) { kotlinx.coroutines.delay(2500); copied = false } }
    // (16 dp under the grip: its touch area reaches 12 dp below it, and Close, which drops a form being typed, keeps
    // 8 dp from the grip, from Copy and from a field scrolled up to the heading's line: policy T2)
    Row(modifier.fillMaxWidth().padding(start = 16.dp, end = 8.dp, top = if (compact) 4.dp else 16.dp, bottom = 8.dp), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            if (code.isNotEmpty()) androidx.compose.foundation.text.selection.SelectionContainer {
                Text(code, style = MaterialTheme.typography.headlineSmall, fontFamily = FontFamily.Monospace)
            } else Text("Unread tag", style = MaterialTheme.typography.headlineSmall)
            // (while the keyboard is up in the panel's form: one line, so that on its side the field has room above it)
            if (!compact) Text(sub, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (code.isNotEmpty()) TextButton(onClick = {
            clip.setText(androidx.compose.ui.text.AnnotatedString(code))
            copied = true
            // Android 13 and later show their own preview of what was copied: then no second message (the button
            // still says "Copied")
            if (android.os.Build.VERSION.SDK_INT < 33) scope.launch { snack.currentSnackbarData?.dismiss(); snack.showSnackbar("Copied $code") }
        }, modifier = Modifier.semantics { contentDescription = if (copied) "Copied $code" else "Copy $code" }) { Text(if (copied) "Copied" else "Copy") }
        if (code.isNotEmpty()) Spacer(Modifier.width(8.dp))
        TextButton(onClick = onClose) { Text("Close") }
    }
    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
}

@Composable
private fun ReviewSection(t: JSONObject, snack: SnackbarHostState) {
    val scope = rememberCoroutineScope()
    val sug = t.optJSONObject("suggestion")
    // (the reading as the form was first shown: a suggestion that arrives by sync is not something typed)
    val shown by rememberSaveable(t.optString("id"), PanelDrafts.reset) { mutableStateOf(arrayListOf(sug?.optString("kks")?.ifEmpty { null } ?: t.optString("code"),
        sug?.optString("isa")?.ifEmpty { null } ?: t.optString("isa"))) }
    var code by rememberSaveable(t.optString("id"), PanelDrafts.reset) { mutableStateOf(shown[0]) }
    var isa by rememberSaveable(t.optString("id"), PanelDrafts.reset) { mutableStateOf(shown[1]) }
    val correcting = code != shown[0] || isa != shown[1]
    if (correcting) HoldLinks()     // (a correction being typed)
    DraftFlag("review", correcting)
    val read = t.optJSONArray("read")
    var notTag by remember(t.optString("id")) { mutableStateOf(false) }
    Text("Check this tag", style = MaterialTheme.typography.titleMedium)
    Text("The reader saw ${read?.optString(0)} / ${read?.optString(1)}, confidence ${(t.optDouble("conf") * 100).toInt()} %")
    OutlinedTextField(code, { code = it }, label = { Text("KKS (with suffix)") }, modifier = Modifier.fillMaxWidth().inViewAboveKeyboard())
    OutlinedTextField(isa, { isa = it }, label = { Text("Function letters (instruments)") }, modifier = Modifier.fillMaxWidth().inViewAboveKeyboard())
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Button(onClick = {
            val c = code.uppercase().filterNot { it.isWhitespace() }
            val m = Regex("^(\\d{2}[A-Z]{3}\\d{2}[A-Z]{2}\\d{3})([A-Z0-9]*)$").matchEntire(c)
            if (m == null) { scope.launch { snack.showSnackbar("That is not a valid KKS (e.g. 11LAB70AA500)") }; return@Button }
            val data = JSONObject().put("status", "confirmed").put("kks", m.groupValues[1]).put("suffix", m.groupValues[2])
                .put("isa", isa.trim().uppercase().ifEmpty { JSONObject.NULL })
            val (_, msg) = submit("review", JSONObject().put("tag_id", t.getString("id")).put("data", data).put("base", JSONObject.NULL))
            scope.launch { snack.showSnackbar(msg) }
        }) { Text("Confirm") }
        OutlinedButton(onClick = { notTag = true }) { Text("Not a tag") }
    }
    // #365: asked first (the tag leaves the drawing on every device)
    if (notTag) Confirm("Mark this as not a tag?", "It is no longer shown as a tag, on every device.", "Mark as not a tag", {
        val (_, msg) = submit("review", JSONObject().put("tag_id", t.getString("id")).put("data", JSONObject().put("status", "rejected")).put("base", JSONObject.NULL))
        scope.launch { snack.showSnackbar(msg) }
    }, { notTag = false })
}

/** the custom field a confirmed description lives in (core views.nim DescriptionKey) */
const val DESCRIPTION = "Description"

/** "by Ali User, 2026-10-08 09:12" from an equipment_by entry ("" when nobody is known: a v1 import, a cleared field) */
fun credit(w: JSONObject?): String {
    if (w == null) return ""
    val who = w.str("by_name").ifEmpty { w.str("by") }
    if (who.isEmpty()) return ""
    val at = whenText(w.optLong("submitted").takeIf { it > 0 } ?: w.optLong("at"))
    return "by $who" + if (at.isNotEmpty()) ", $at" else ""
}

/** the equipment's description (the user, 2026-10-08: "KKS tag descriptions"): a draft from the plant data is marked
 *  "Draft description (unchecked)" with Confirm (the proposal the core made ready) and Edit; a confirmed one says by whom */
@Composable
private fun DescriptionSection(code: String, d: JSONObject, eq: JSONObject, snack: SnackbarHostState) {
    val scope = rememberCoroutineScope()
    var editing by rememberSaveable(code, PanelDrafts.reset) { mutableStateOf(false) }
    // (the text when editing began: a description that arrives by sync meanwhile does not replace what is typed)
    var opened by rememberSaveable(code, PanelDrafts.reset) { mutableStateOf(d.str("text")) }
    var text by rememberSaveable(code, PanelDrafts.reset) { mutableStateOf(d.str("text")) }
    LaunchedEffect(d.str("text"), editing) { if (!editing) { opened = d.str("text"); text = opened } }
    val typed = editing && text.trim() != opened.trim()
    DraftFlag("desc", typed)
    // Cancel with something typed asks first, as the panel's Close and Back do (#436; D3): Discard drops only this form
    var discarding by remember(code) { mutableStateOf(false) }
    if (discarding) Confirm("Discard your edits?", "The description you typed has not been saved.", "Discard",
        { editing = false; text = d.str("text") }, { discarding = false }, no = "Keep editing")
    val draft = d.str("status") == "draft"
    Heading("Description")
    Surface(color = if (draft) MaterialTheme.colorScheme.tertiaryContainer else MaterialTheme.colorScheme.surfaceContainerHighest,
        shape = MaterialTheme.shapes.medium, modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(if (draft) "Draft description (unchecked)" else "Confirmed" + d.str("by_name").let { if (it.isNotEmpty()) " by $it" else "" } +
                    whenText(d.optLong("at")).let { if (it.isNotEmpty()) ", $it" else "" },
                style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (!editing) Text(d.str("text"), style = MaterialTheme.typography.bodyLarge)
            if (d.str("basis").isNotEmpty() && (draft || editing)) Dim("Basis: " + d.str("basis"))
            if (!draft && d.optBoolean("draft_differs")) Dim("The plant data's draft says something else.")
            if (editing) {
                HoldLinks()
                OutlinedTextField(text, { text = it }, label = { Text("Description") }, modifier = Modifier.fillMaxWidth().inViewAboveKeyboard(), minLines = 2)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = {
                        val v = text.trim()
                        if (v.isEmpty()) { scope.launch { snack.showSnackbar("Write a description first") }; return@Button }
                        if (v.length > 2000) { scope.launch { snack.showSnackbar("Up to 2000 characters") }; return@Button }
                        val base = eq.optJSONArray("custom") ?: JSONArray()
                        val next = JSONArray()
                        var put = false
                        for (c in base.objects()) if (c.str("k") == DESCRIPTION) { if (!put) next.put(JSONObject().put("k", DESCRIPTION).put("v", v)); put = true } else next.put(c)
                        if (!put) next.put(JSONObject().put("k", DESCRIPTION).put("v", v))
                        val (ok, m) = submit("equipment", JSONObject().put("kks", code).put("changes", JSONObject().put("custom", next))
                            .put("base", JSONObject().put("custom", base)))
                        scope.launch { snack.showSnackbar(m) }
                        if (ok) editing = false
                    }) { Text("Save description") }
                    OutlinedButton(onClick = { if (typed) discarding = true else { editing = false; text = d.str("text") } }) { Text("Cancel") }
                }
            } else Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                val confirm = d.optJSONObject("confirm")
                if (draft && confirm != null) Button(onClick = {
                    val (_, m) = submit(confirm.str("kind"), confirm.getJSONObject("payload"))
                    scope.launch { snack.showSnackbar(m) }
                }) { Text("Confirm") }
                // its own label: the panel's "Edit" is the location fields' (and a test or TalkBack user must tell them apart)
                OutlinedButton(onClick = { editing = true }) { Text("Edit description") }
            }
        }
    }
}

/** the custom field a confirmed or corrected valve type lives in (core model.nim ValveTypeKey) */
const val VALVE_TYPE = "Valve type"

/** the valve type (the user, 2026-10-09; GNOME's panel.nim valveSection, the web's valveSec): read from the drawn
 *  symbol, unchecked, with Confirm type (the core's proposal as it is) and Correct type (the same proposal with the
 *  person's value); or the confirmed type, and what the drawing says when that differs */
@Composable
private fun ValveSection(vt: JSONObject, rev: Int, snack: SnackbarHostState) {
    val scope = rememberCoroutineScope()
    val confirm = vt.optJSONObject("confirm")
    val k = confirm?.optJSONObject("payload")?.str("kks").orEmpty()
    // (saved, like the panel's other forms: a type that arrives by sync, a turn of the phone or Android stopping the
    // app leaves what is typed; the panel's Discard starts it again)
    var correcting by rememberSaveable(k, PanelDrafts.reset) { mutableStateOf(false) }
    var opened by rememberSaveable(k, PanelDrafts.reset) { mutableStateOf(vt.str("text")) }
    var value by rememberSaveable(k, PanelDrafts.reset) { mutableStateOf(vt.str("text")) }
    var busy by remember(k, rev) { mutableStateOf(false) }      // one proposal per press: a second tap waits
    if (correcting) HoldLinks()
    // (only while the form is on screen: a type confirmed meanwhile on another device takes the form away)
    val typed = correcting && confirm != null && vt.str("status") != "confirmed" && value.trim() != opened.trim()
    DraftFlag("valve", typed)       // Close, Back and the bottom tabs ask before it goes (D3)
    // Cancel with something typed asks first (#436): Discard drops only this form
    var discarding by remember(k) { mutableStateOf(false) }
    if (discarding) Confirm("Discard your edits?", "The valve type you typed has not been saved.", "Discard",
        { correcting = false }, { discarding = false }, no = "Keep editing")
    Heading("Valve type")
    Surface(color = if (vt.str("status") == "confirmed") MaterialTheme.colorScheme.surfaceContainerHighest else MaterialTheme.colorScheme.tertiaryContainer,
        shape = MaterialTheme.shapes.medium, modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(vt.str("line"), style = MaterialTheme.typography.bodyLarge)
            val mine = remember(k, rev) { if (confirm != null) myValveType(k) else "" }
            fun send(v: String) {
                if (busy || confirm == null) return
                busy = true
                val p = JSONObject(confirm.getJSONObject("payload").toString())
                for (x in p.getJSONObject("changes").getJSONArray("custom").objects()) if (x.str("k") == VALVE_TYPE) x.put("v", v)
                val (ok, m) = submit(confirm.str("kind"), p)     // no note: the approver sees the change itself
                if (ok) correcting = false else busy = false
                scope.launch { snack.showSnackbar(m) }
            }
            if (vt.str("status") == "confirmed") {
                if (vt.optBoolean("drawn_differs")) Dim("The drawing's symbol reads: " + vt.str("drawn"))
            } else {
                Dim("Read from the valve symbol drawn next to the tag (outlined on the drawing)" +
                    (if (vt.opt("conf") is Number) ", " + Math.round(vt.getDouble("conf") * 100) + " % sure" else "") +
                    ". Confirm it, or correct it if the symbol says otherwise.")
                if (confirm == null) Text("This equipment already has 100 custom fields: remove one to save the valve type.",
                    color = MaterialTheme.colorScheme.error)
                // your own proposal of a type, not live yet (a member's waits for approval): said, and no second one offered
                else if (mine.isNotEmpty()) Dim("Your valve type “$mine” is waiting for approval.")
                else if (!correcting) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = { send(vt.str("text")) }, enabled = !busy) { Text("Confirm type") }
                    OutlinedButton(onClick = { correcting = true; value = vt.str("text"); opened = value }, enabled = !busy) { Text("Correct type") }
                } else {
                    OutlinedTextField(value, { value = it }, label = { Text("Valve type (as it really is)") }, singleLine = true, modifier = Modifier.fillMaxWidth().inViewAboveKeyboard())
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(onClick = {
                            val v = value.trim()
                            when {
                                v.isEmpty() -> scope.launch { snack.showSnackbar("Type the valve type first") }
                                v.codePointCount(0, v.length) > 200 -> scope.launch { snack.showSnackbar("At most 200 characters") }
                                else -> send(v)
                            }
                        }, enabled = !busy) { Text("Send") }
                        OutlinedButton(onClick = { if (typed) discarding = true else correcting = false }) { Text("Cancel") }
                    }
                }
            }
        }
    }
}

/** the valve type in this person's own open proposal for the code k ("" = none) */
private fun myValveType(k: String): String {
    val q = mapOf("status" to "open", "mine" to "1", "kind" to "equipment")    // only mine: the list is paged
    for (sub in call("GET", "/api/submissions", query = q).json.optJSONArray("submissions").objects()) {
        val p = sub.optJSONObject("payload") ?: continue
        if (!sub.optBoolean("mine") || sub.str("kind") != "equipment" || p.str("kks") != k) continue
        val c = p.optJSONObject("changes")?.optJSONArray("custom") ?: continue
        for (x in c.objects()) if (x.str("k") == VALVE_TYPE && x.str("v").isNotEmpty()) return x.str("v")
    }
    return ""
}

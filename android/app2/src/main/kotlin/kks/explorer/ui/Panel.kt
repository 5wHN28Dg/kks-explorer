package kks.explorer.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
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
    if (r.status >= 400) return false to r.json.optString("error", "error ${r.status}")
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

/** the equipment panel (R3–R6): decoded code, location list, the person's fields (read-only until Edit), review */
@Composable
fun TagPanel(id: String, rev: Int, onClose: () -> Unit, onGo: (String, String, List<Float>?) -> Unit, snack: SnackbarHostState,
             modifier: Modifier = Modifier, link: Pair<String, Int>? = null) {
    val scope = rememberCoroutineScope()
    val t = remember(id, rev) { Core.api("GET", "/native/tag", query = mapOf("id" to id)).json }
    val screen = LocalConfiguration.current.screenHeightDp.toFloat()
    // resizable (the user, 2026-10-05: it took most of the screen): drag the handle, or tap it to go between a low
    // panel (the code and Close, the drawing above free to move around) and the usual height
    val low = 104f; val high = screen * 0.85f; val usual = screen * 0.45f
    var height by remember { mutableFloatStateOf(if (PanelSize.dp > 0) PanelSize.dp else usual) }
    val dens = androidx.compose.ui.platform.LocalDensity.current.density
    var editing by remember(id) { mutableStateOf(false) }
    Surface(modifier.fillMaxWidth().height(height.dp), tonalElevation = 6.dp, shadowElevation = 8.dp,
        shape = MaterialTheme.shapes.large) {
        Column {
        Box(Modifier.fillMaxWidth()
            .draggable(rememberDraggableState { d -> height = (height - d / dens).coerceIn(low, high); PanelSize.dp = height },
                orientation = androidx.compose.foundation.gestures.Orientation.Vertical)
            .clickable(onClickLabel = if (height > low + 1) "Make the panel small" else "Make the panel bigger") {
                height = if (height > low + 1) low else usual; PanelSize.dp = height
            }
            .semantics { contentDescription = "Panel size: drag to resize" }
            .padding(vertical = 10.dp), contentAlignment = androidx.compose.ui.Alignment.Center) {
            Box(Modifier.size(width = 40.dp, height = 4.dp).background(MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f), MaterialTheme.shapes.small))
        }
        Column(Modifier.verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(t.optString("code").ifEmpty { "Unread tag" }, style = MaterialTheme.typography.headlineSmall, fontFamily = FontFamily.Monospace)
                    Text((if (t.optString("isa").isNotEmpty()) t.optString("isa") + " · " else "") + t.optString("kind"),
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                TextButton(onClick = onClose) { Text("Close") }
            }
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
                    if (!editing) TextButton(onClick = { editing = true }) { Text("Edit") }
                }
                val eqBy = t.optJSONObject("equipment_by") ?: JSONObject()
                if (!editing) {
                    // who set each field (the user, 2026-10-08: "show who … and the tag info they add")
                    Fields(FIELDS.map { (f, title) ->
                        Field(title, eq.optString(f).ifEmpty { if (f == "elev" && t.optString("list_elev").isNotEmpty()) t.optString("list_elev") + " (location list)" else "" },
                            by = if (eq.optString(f).isNotEmpty()) credit(eqBy.optJSONObject(f)) else "")
                    } + (eq.optJSONArray("custom")?.objects() ?: emptyList()).filter { it.str("k") != DESCRIPTION }.map { c ->
                        Field(c.str("k"), c.str("v"), by = credit(eqBy.optJSONObject("custom:" + c.str("k"))))
                    })
                } else {
                    val values = remember(id) { mutableStateMapOf<String, String>().apply { FIELDS.forEach { (f, _) -> put(f, eq.optString(f)) } } }
                    var note by remember(id) { mutableStateOf("") }
                    for ((f, title) in FIELDS) OutlinedTextField(values[f] ?: "", { values[f] = it }, label = { Text(title) }, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(note, { note = it }, label = { Text("Note for the approver (optional)") }, modifier = Modifier.fillMaxWidth())
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
                        OutlinedButton(onClick = { editing = false }) { Text("Cancel") }
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

@Composable
private fun ReviewSection(t: JSONObject, snack: SnackbarHostState) {
    val scope = rememberCoroutineScope()
    val sug = t.optJSONObject("suggestion")
    var code by remember(t.optString("id")) { mutableStateOf(sug?.optString("kks")?.ifEmpty { null } ?: t.optString("code")) }
    var isa by remember(t.optString("id")) { mutableStateOf(sug?.optString("isa")?.ifEmpty { null } ?: t.optString("isa")) }
    val read = t.optJSONArray("read")
    Text("Check this tag", style = MaterialTheme.typography.titleMedium)
    Text("The reader saw ${read?.optString(0)} / ${read?.optString(1)}, confidence ${(t.optDouble("conf") * 100).toInt()} %")
    OutlinedTextField(code, { code = it }, label = { Text("KKS (with suffix)") }, modifier = Modifier.fillMaxWidth())
    OutlinedTextField(isa, { isa = it }, label = { Text("Function letters (instruments)") }, modifier = Modifier.fillMaxWidth())
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Button(onClick = {
            val c = code.uppercase().filterNot { it.isWhitespace() }
            val m = Regex("^(\\d{2}[A-Z]{3}\\d{2}[A-Z]{2}\\d{3})([A-Z0-9]*)$").matchEntire(c)
            if (m == null) { scope.launch { snack.showSnackbar("That is not a valid KKS (e.g. 11LAB70AA501)") }; return@Button }
            val data = JSONObject().put("status", "confirmed").put("kks", m.groupValues[1]).put("suffix", m.groupValues[2])
                .put("isa", isa.trim().uppercase().ifEmpty { JSONObject.NULL })
            val (_, msg) = submit("review", JSONObject().put("tag_id", t.getString("id")).put("data", data).put("base", JSONObject.NULL))
            scope.launch { snack.showSnackbar(msg) }
        }) { Text("Confirm") }
        OutlinedButton(onClick = {
            val (_, msg) = submit("review", JSONObject().put("tag_id", t.getString("id")).put("data", JSONObject().put("status", "rejected")).put("base", JSONObject.NULL))
            scope.launch { snack.showSnackbar(msg) }
        }) { Text("Not a tag") }
    }
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
    var editing by remember(code) { mutableStateOf(false) }
    var text by remember(code, d.str("text")) { mutableStateOf(d.str("text")) }
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
                OutlinedTextField(text, { text = it }, label = { Text("Description") }, modifier = Modifier.fillMaxWidth(), minLines = 2)
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
                    OutlinedButton(onClick = { editing = false; text = d.str("text") }) { Text("Cancel") }
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
    var correcting by remember(k) { mutableStateOf(false) }
    var value by remember(k, vt.str("text")) { mutableStateOf(vt.str("text")) }
    var busy by remember(k, rev) { mutableStateOf(false) }      // one proposal per press: a second tap waits
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
                    OutlinedButton(onClick = { correcting = true; value = vt.str("text") }, enabled = !busy) { Text("Correct type") }
                } else {
                    OutlinedTextField(value, { value = it }, label = { Text("Valve type (as it really is)") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(onClick = {
                            val v = value.trim()
                            when {
                                v.isEmpty() -> scope.launch { snack.showSnackbar("Type the valve type first") }
                                v.codePointCount(0, v.length) > 200 -> scope.launch { snack.showSnackbar("At most 200 characters") }
                                else -> send(v)
                            }
                        }, enabled = !busy) { Text("Send") }
                        OutlinedButton(onClick = { correcting = false }) { Text("Cancel") }
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

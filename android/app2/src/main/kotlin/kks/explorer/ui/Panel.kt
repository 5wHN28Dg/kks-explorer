package kks.explorer.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import kks.explorer.core.Core
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

private val FIELDS = listOf("area" to "Building / area", "floor" to "Floor", "elev" to "Elevation", "near" to "Near / landmark",
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

@Composable
private fun Row2(title: String, value: String) {
    Column(Modifier.padding(vertical = 4.dp)) {
        Text(title, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value.ifEmpty { "—" }, style = MaterialTheme.typography.bodyLarge)
    }
}

/** the equipment panel (R3–R6): decoded code, location list, the person's fields (read-only until Edit), review */
@Composable
fun TagPanel(id: String, rev: Int, onClose: () -> Unit, onGo: (String, String, List<Float>?) -> Unit, snack: SnackbarHostState,
             modifier: Modifier = Modifier, link: Pair<String, Int>? = null) {
    val scope = rememberCoroutineScope()
    val t = remember(id, rev) { Core.api("GET", "/native/tag", query = mapOf("id" to id)).json }
    val maxH = (LocalConfiguration.current.screenHeightDp * 0.55f).dp
    var editing by remember(id) { mutableStateOf(false) }
    Surface(modifier.fillMaxWidth().heightIn(max = maxH), tonalElevation = 6.dp, shadowElevation = 8.dp,
        shape = MaterialTheme.shapes.large) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
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
                Text("From the drawing", style = MaterialTheme.typography.titleMedium)
                Row2("Plant unit", d.optString("blk") + "  " + d.optString("blk_name"))
                Row2("System", d.optString("sys") + "  " + d.optString("sys_name").ifEmpty { "not in the legend" })
                Row2("Component", d.optString("comp") + "  " + d.optString("comp_name"))
                if (d.optString("isa").isNotEmpty()) Row2("Instrument", d.optString("isa"))
                Row2("Reading", t.optString("reading"))
            }
            val rows = t.optJSONArray("location_list") ?: JSONArray()
            if (rows.length() > 0) {
                Text("Location list", style = MaterialTheme.typography.titleMedium)
                for (i in 0 until rows.length()) rows.getJSONObject(i).let { r ->
                    Row2(r.optString("desc").ifEmpty { "Location list" }, listOf("level", "cabinet", "direction").map { r.optString(it) }.filter { it.isNotEmpty() }.joinToString(" · "))
                }
            }
            val code = t.optString("code")
            if (link != null && code.isNotEmpty()) Button(onClick = {
                val (_, m) = linkSubmit(link.first, link.second, code, true)
                scope.launch { snack.showSnackbar("$code → step ${link.second}: $m") }
            }) { Text("Link to step ${link.second} of ${link.first}") }
            if (code.isNotEmpty()) {
                val eq = t.optJSONObject("equipment") ?: JSONObject()
                Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                    Text("Location and notes", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                    if (!editing) TextButton(onClick = { editing = true }) { Text("Edit") }
                }
                if (!editing) {
                    for ((f, title) in FIELDS) {
                        val v = eq.optString(f).ifEmpty { if (f == "elev" && t.optString("list_elev").isNotEmpty()) t.optString("list_elev") + " (location list)" else "" }
                        Row2(title, v)
                    }
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
                    Text("Appears on", style = MaterialTheme.typography.titleMedium)
                    for (i in 0 until where.length()) where.getJSONObject(i).let { w ->
                        AssistChip(onClick = {
                            val tt = Core.api("GET", "/native/tag", query = mapOf("id" to w.getString("tag"))).json
                            onGo(w.getString("tag"), w.getString("sheet"), tt.optJSONArray("box")?.let { a -> (0 until 4).map { a.getDouble(it).toFloat() } })
                        }, label = { Text(w.getString("sheet_name")) })
                    }
                }
                val procs = t.optJSONArray("procedures") ?: JSONArray()
                if (procs.length() > 0) {
                    Text("Used in procedures", style = MaterialTheme.typography.titleMedium)
                    for (i in 0 until procs.length()) procs.getJSONObject(i).let { Row2(it.getString("id"), it.optString("title")) }
                }
                PhotoStrip(code, t.optJSONArray("photos").objects(), snack)
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

package kks.explorer.ui

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import kks.explorer.core.Core
import kks.explorer.sync.PhotoQueue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/** codes in one selection: the server takes up to 200 per submit-many (core api.submitMany) */
const val MAX_PICK = 200

/** `sel` (codes, in the order picked) with `add` added while it stays within MAX_PICK; true = some were left out */
fun addCapped(sel: Set<String>, add: List<String>): Pair<Set<String>, Boolean> {
    val out = LinkedHashSet(sel)
    for (c in add) {
        if (c in out) continue
        if (out.size >= MAX_PICK) return out to true
        out.add(c)
    }
    return out to false
}

/** one place a code is drawn: its tag, on which drawing */
data class Drawn(val tag: String, val sheet: String, val sheetName: String)

/** every code that is on a drawing, with where (the sheets' order): what a selection across drawings is checked
 *  against and what its List shows. One core call per sheet: off the main thread. */
fun codeIndex(): Map<String, List<Drawn>> {
    val out = LinkedHashMap<String, MutableList<Drawn>>()
    for (s in sheets()) for (t in call("GET", "/native/tags", query = mapOf("sheet" to s.id)).json.optJSONArray("tags").objects()) {
        val c = t.optString("code")
        if (c.isNotEmpty()) out.getOrPut(c) { mutableListOf() }.add(Drawn(t.optString("id"), s.id, s.name))
    }
    return out
}

/** the codes typed or pasted into Add codes: split at spaces, commas, semicolons and new lines; upper case; each once */
fun typedCodes(text: String): List<String> =
    text.split(Regex("[\\s,;]+")).map { it.trim().uppercase() }.filter { it.isNotEmpty() }.distinct()

/** what the equipment says now for each code (the approved state): {} for a code nothing is known about. One core
 *  call for all of them: off the main thread. */
fun equipmentOf(codes: List<String>): Map<String, JSONObject> {
    val eq = Core.api("GET", "/api/state").json.optJSONObject("equipment")
    return codes.associateWith { eq?.optJSONObject(it) ?: JSONObject() }
}

/** One photo, place or note for several codes (core submitMany, /api/submit-many): an ordinary submission per code,
 *  `client_id` a fresh prefix per action so a retry can't send anything twice. Returns (ok, the snackbar's words). */
fun submitMany(kind: String, codes: List<String>, payload: JSONObject, note: String = "", shown: Map<String, JSONObject>? = null): Pair<Boolean, String> {
    // the values the person was shown for the fields that are replaced: a value changed meanwhile is then a clash
    // (core submitMany `bases`), not overwritten silently. An appended note can't lose anything: none needed.
    val changes = payload.optJSONObject("changes")
    if (shown != null && changes != null) {
        val bases = JSONObject()
        for (c in codes) { val e = shown[c] ?: JSONObject(); val b = JSONObject(); for (f in changes.keys()) b.put(f, e.optString(f, "")); bases.put(c, b) }
        payload.put("bases", bases)
    }
    val body = JSONObject().put("kind", kind).put("kks", JSONArray(codes)).put("payload", payload)
        .put("client_id", "many-" + java.util.UUID.randomUUID().toString().replace("-", ""))
    if (note.isNotBlank()) body.put("note", note.trim())
    val r = Core.api("POST", "/api/submit-many", body)
    if (r.status >= 400) return false to r.json.optString("error", "error ${r.status}")
    Changes.rev++
    val res = r.json.optJSONArray("results").objects()
    val waiting = res.count { it.optString("status") == "pending" }
    val held = res.count { it.optString("status") == "conflict" }
    val n = codes.distinct().size
    return true to "Sent for $n code" + (if (n == 1) "" else "s") +
        (if (waiting > 0) ", $waiting waiting for approval" else "") + (if (held > 0) ", $held held (a pending change clashes)" else "")
}

/** the bar under the drawing while tags are being selected */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun SelectBar(n: Int, modifier: Modifier, onList: () -> Unit, onPhoto: () -> Unit, onPlace: () -> Unit, onNote: () -> Unit, onDone: () -> Unit) {
    Surface(modifier.fillMaxWidth(), tonalElevation = 6.dp, shadowElevation = 6.dp) {
        Column(Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                // a live region: TalkBack says the new count after each tap or box
                Text("$n selected", style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.weight(1f).semantics { liveRegion = LiveRegionMode.Polite })
                TextButton(onClick = onDone) { Text("Done") }
            }
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                // always on: its Add codes can start a selection
                OutlinedButton(onClick = onList) { Text("List") }
                OutlinedButton(onClick = onPhoto, enabled = n > 0) { Text("Photo for all") }
                OutlinedButton(onClick = onPlace, enabled = n > 0) { Text("Place for all") }
                OutlinedButton(onClick = onNote, enabled = n > 0) { Text("Note for all") }
            }
        }
    }
}

/** the selected codes, each with the drawing(s) it is on and a checkbox to leave a mistaken one out; and Add codes:
 *  codes typed or pasted, for tags that are in the same place but on other drawings. `places` is null while the
 *  drawings' codes are being read. `onAdd` gets the codes that are on a drawing and returns the ones the cap left out. */
@Composable
fun SelectList(selected: List<String>, places: Map<String, List<Drawn>>?, onUntick: (String) -> Unit,
               onAdd: (List<String>) -> List<String>, onClose: () -> Unit) {
    var typed by remember { mutableStateOf("") }
    var said by remember { mutableStateOf("") }
    AlertDialog(onDismissRequest = onClose, title = { Text("Selected tags") }, text = {
        // scrolls as a whole: with the keyboard up on a small phone the field and Add must still be reachable
        Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (selected.isEmpty()) Dim("Nothing selected.")
            else LazyColumn(Modifier.heightIn(max = 260.dp)) {
                items(selected, key = { it }) { code ->
                    val on = places?.get(code)?.map { it.sheetName }?.distinct()
                    // one switch per row: the whole row toggles, TalkBack says "11LAB70AA501, Sample sheet, checkbox, checked"
                    Row(Modifier.fillMaxWidth().toggleable(value = true, role = Role.Checkbox, onValueChange = { onUntick(code) })
                        .padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                        Checkbox(checked = true, onCheckedChange = null)
                        Spacer(Modifier.width(12.dp))
                        Column {
                            Text(code, fontFamily = FontFamily.Monospace)
                            if (places != null) Text(if (on.isNullOrEmpty()) "Not on a drawing any more" else on.joinToString(", "),
                                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
            OutlinedTextField(typed, { typed = it; said = "" }, label = { Text("Add codes") }, maxLines = 4, modifier = Modifier.fillMaxWidth(),
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters, autoCorrectEnabled = false),
                supportingText = { Text("KKS codes from any drawing, with spaces, commas or new lines between them.") })
            if (places == null) Dim("Reading the drawings' codes…")
            if (said.isNotEmpty()) Text(said, color = MaterialTheme.colorScheme.error, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
            OutlinedButton(enabled = typed.isNotBlank() && places != null, onClick = {
                val index = places ?: return@OutlinedButton
                val (known, unknown) = typedCodes(typed).partition { it in index }
                val over = if (known.isEmpty()) emptyList() else onAdd(known)
                // what could not be added stays in the field: to be corrected, or sent after these
                typed = (unknown + over).joinToString(" ")
                said = listOf(if (unknown.isEmpty()) "" else "Not on any drawing, not added: " + unknown.joinToString(", ") + ".",
                    if (over.isEmpty()) "" else "At most $MAX_PICK tags at once, not added: " + over.joinToString(", ") + ". Send these first.")
                    .filter { it.isNotEmpty() }.joinToString(" ")
            }) { Text("Add") }
        }
    }, confirmButton = { TextButton(onClick = onClose) { Text("Close") } })
}

private val PLACE = FIELDS.filter { it.first != "notes" }

/** the same place fields for every code; only filled fields are sent. Says first how many codes already have another
 *  value in a filled field (it will be replaced). */
@Composable
fun PlaceForAll(codes: List<String>, onSent: (String) -> Unit, onClose: () -> Unit) {
    val values = remember { mutableStateMapOf<String, String>() }
    var note by remember { mutableStateOf("") }
    // the values shown (the bases): Send waits for them, or every code with a value would be sent as a clash
    var current by remember { mutableStateOf<Map<String, JSONObject>?>(null) }
    var sending by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(codes) { current = withContext(Dispatchers.IO) { equipmentOf(codes) } }
    val filled = PLACE.map { it.first }.filter { (values[it] ?: "").isNotBlank() }
    val replaced = codes.count { c -> val e = current?.get(c); e != null && filled.any { f -> e.optString(f).isNotBlank() && e.optString(f) != values[f]!!.trim() } }
    AlertDialog(onDismissRequest = onClose, title = { Text("Place for ${codes.size} code" + if (codes.size == 1) "" else "s") }, text = {
        Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Dim("Only the fields you fill are sent; the others stay as they are.")
            for ((f, title) in PLACE) OutlinedTextField(values[f] ?: "", { values[f] = it }, label = { Text(title) }, singleLine = true, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(note, { note = it }, label = { Text("Note for the approver (optional)") }, modifier = Modifier.fillMaxWidth())
            if (replaced > 0) Text("$replaced of ${codes.size} codes already have another value here: it will be replaced.",
                color = MaterialTheme.colorScheme.error, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
        }
    }, confirmButton = { TextButton(enabled = filled.isNotEmpty() && current != null && !sending, onClick = {
        val changes = JSONObject(); for (f in filled) changes.put(f, values[f]!!.trim())
        val shown = current ?: return@TextButton
        sending = true
        scope.launch {   // up to 200 submissions: off the main thread
            val (ok, m) = withContext(Dispatchers.IO) { submitMany("equipment", codes, JSONObject().put("changes", changes), note, shown = shown) }
            sending = false; onSent(m); if (ok) onClose()
        }
    }) { Text("Send") } }, dismissButton = { TextButton(onClick = onClose) { Text("Cancel") } })
}

/** one note added under each code's own notes (never replacing them) */
@Composable
fun NoteForAll(codes: List<String>, onSent: (String) -> Unit, onClose: () -> Unit) {
    var text by remember { mutableStateOf("") }
    var note by remember { mutableStateOf("") }
    var sending by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    AlertDialog(onDismissRequest = onClose, title = { Text("Note for ${codes.size} code" + if (codes.size == 1) "" else "s") }, text = {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Dim("Added under each code's notes; what is there stays.")
            OutlinedTextField(text, { text = it }, label = { Text("Note to add") }, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(note, { note = it }, label = { Text("Note for the approver (optional)") }, modifier = Modifier.fillMaxWidth())
        }
    }, confirmButton = { TextButton(enabled = text.isNotBlank() && !sending, onClick = {
        sending = true
        scope.launch {   // up to 200 submissions: off the main thread
            val (ok, m) = withContext(Dispatchers.IO) { submitMany("equipment", codes, JSONObject().put("append", JSONObject().put("notes", text.trim())), note) }
            sending = false; onSent(m); if (ok) onClose()
        }
    }) { Text("Send") } }, dismissButton = { TextButton(onClick = onClose) { Text("Cancel") } })
}

/** the selected codes that have no floor yet (none on the equipment, none queued with a photo): a photo needs its
 *  floor (the user, 2026-10-08), so Photo for all asks for it first, for these codes. Off the main thread. */
internal fun codesWithoutFloor(codes: List<String>): List<String> {
    val eq = equipmentOf(codes)
    return codes.filter { c -> eq[c]?.optString("floor").orEmpty().isBlank() && PhotoQueue.queuedFloor[c].isNullOrEmpty() }
}

/** Photo for all asks for the floor before the camera opens, as one photo of one tag does (the user, 2026-10-10: a
 *  member can't set floors by Place for all first, that needs approval). `missing`: the codes without one; the floor
 *  goes with the photo and the core writes it as a proposal for those codes only. */
@Composable
fun FloorForAll(missing: List<String>, total: Int, onPick: (String) -> Unit, onClose: () -> Unit) {
    val names = missing.joinToString(", ")       // all of them: the dialog's text scrolls
    FloorDialog(if (missing.size == 1) "Which floor is it on?" else "Which floor are they on?",
        (if (missing.size == 1) "$names has no floor yet." else "No floor yet: $names.") +
            " Every photo needs it first: it is sent with the photo" + (if (missing.size == 1) "" else ", for these codes") + "." +
            (if (missing.size < total) " The other codes keep the floor they have." else ""),
        onPick, onClose)
}

/** one photo for every code: the panel's camera (or gallery) → mark-up editor → the photo queue (PhotoQueue: sealed on
 *  disk, encoded and sent in the background as one /api/submit-many, kept if the app is killed). `floor`: the one
 *  asked for first when a code had none, else empty; `floorCodes`: the codes it was asked for. */
@Composable
fun PhotoForAll(codes: List<String>, floor: String, floorCodes: List<String>, onSaid: (String) -> Unit, onQueued: () -> Unit, onClose: () -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var picked by remember { mutableStateOf<Bitmap?>(null) }
    var fromCamera by remember { mutableStateOf(true) }
    val camFile = remember { File(ctx.cacheDir, "camera/shot.jpg").also { it.parentFile?.mkdirs() } }
    val camUri = remember { FileProvider.getUriForFile(ctx, "io.github.walkdown.files", camFile) }
    fun load(uri: Uri) = scope.launch {
        picked = withContext(Dispatchers.IO) {
            val raw = ctx.contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: return@withContext null
            if (uri == camUri) camFile.delete()
            orientedBitmap(raw)
        }
        if (picked == null) onSaid("Could not read that picture")
    }
    val gallery = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { u: Uri? -> if (u != null) load(u) }
    val camera = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { ok -> if (ok) load(camUri) }
    val perm = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok ->
        if (ok) camera.launch(camUri) else onSaid("Without the camera permission, pick a photo from the gallery")
    }
    fun shoot() {
        fromCamera = true
        if (ctx.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) camera.launch(camUri) else perm.launch(Manifest.permission.CAMERA)
    }
    val title = "Photo for ${codes.size} code" + if (codes.size == 1) "" else "s"
    if (picked == null) AlertDialog(onDismissRequest = onClose, title = { Text(title) }, text = {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Dim("One picture showing all of them; each code gets it.")
            Button(onClick = { shoot() }, modifier = Modifier.fillMaxWidth()) { Text("Take a photo") }
            OutlinedButton(onClick = { fromCamera = false; gallery.launch("image/*") }, modifier = Modifier.fillMaxWidth()) { Text("From the gallery") }
        }
    }, confirmButton = { TextButton(onClick = onClose) { Text("Cancel") } })
    picked?.let { bmp ->
        Annotate(bmp, false, retake = if (fromCamera) "Retake" else "Choose another", onCancel = { picked = null },
            onRetake = { picked = null; if (fromCamera) shoot() else gallery.launch("image/*") }) { out, caption, note ->
            picked = null
            // the queue encodes and sends it in the background, like any other photo, whether or not the app stays open
            if (codes.isEmpty()) { onClose(); return@Annotate }
            PhotoQueue.add(ctx, out, codes.first(), caption, note, floor, codes = if (codes.size > 1) codes else emptyList(), floorCodes = floorCodes)
            onQueued(); onClose()
        }
    }
}

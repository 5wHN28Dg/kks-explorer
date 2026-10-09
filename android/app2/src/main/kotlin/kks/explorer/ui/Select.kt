package kks.explorer.ui

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.net.Uri
import android.util.Base64
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import kks.explorer.Jxl
import kks.explorer.core.Core
import kks.explorer.sync.PhotoQueue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/** codes in one selection: the server takes up to 200 per submit-many (core api.submitMany) */
const val MAX_PICK = 200

/** `sel` with the tag ids `add` added in order while the distinct codes stay within MAX_PICK; true = some were left out */
fun addCapped(sel: Set<String>, add: List<String>, codeOf: (String) -> String): Pair<Set<String>, Boolean> {
    val out = LinkedHashSet(sel)
    val codes = sel.map(codeOf).toMutableSet()
    for (id in add) {
        val c = codeOf(id)
        if (c !in codes && codes.size >= MAX_PICK) return out to true
        out.add(id); codes.add(c)
    }
    return out to false
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
                OutlinedButton(onClick = onList, enabled = n > 0) { Text("List") }
                OutlinedButton(onClick = onPhoto, enabled = n > 0) { Text("Photo for all") }
                OutlinedButton(onClick = onPlace, enabled = n > 0) { Text("Place for all") }
                OutlinedButton(onClick = onNote, enabled = n > 0) { Text("Note for all") }
            }
        }
    }
}

/** the selected tags, each with a checkbox to leave a mistaken one out */
@Composable
fun SelectList(selected: List<SheetView.TagBox>, onUntick: (String) -> Unit, onClose: () -> Unit) {
    AlertDialog(onDismissRequest = onClose, title = { Text("Selected tags") }, text = {
        if (selected.isEmpty()) Dim("Nothing selected.")
        else LazyColumn(Modifier.heightIn(max = 420.dp)) {
            items(selected, key = { it.id }) { t ->
                // one switch per row: the whole row toggles, TalkBack says "11LAB70AA501, checkbox, checked"
                Row(Modifier.fillMaxWidth().toggleable(value = true, role = Role.Checkbox, onValueChange = { onUntick(t.id) })
                    .padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Checkbox(checked = true, onCheckedChange = null)
                    Spacer(Modifier.width(12.dp))
                    Text(t.code, fontFamily = FontFamily.Monospace)
                }
            }
        }
    }, confirmButton = { TextButton(onClick = onClose) { Text("Close") } })
}

private val PLACE = FIELDS.filter { it.first != "notes" }

/** the same place fields for every code; only filled fields are sent. Says first how many codes already have another
 *  value in a filled field (it will be replaced). */
@Composable
fun PlaceForAll(tagIds: List<String>, codes: List<String>, onSent: (String) -> Unit, onClose: () -> Unit) {
    val values = remember { mutableStateMapOf<String, String>() }
    var note by remember { mutableStateOf("") }
    // the values shown (the bases): Send waits for them, or every code with a value would be sent as a clash
    var current by remember { mutableStateOf<Map<String, JSONObject>?>(null) }
    var sending by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(tagIds) {
        current = withContext(Dispatchers.IO) {
            tagIds.associate { id -> call("GET", "/native/tag", query = mapOf("id" to id)).json.let { it.optString("code") to (it.optJSONObject("equipment") ?: JSONObject()) } }
        }
    }
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
 *  floor (the user, 2026-10-08), and one dialog can't ask for several, so Photo for all names them instead. Off the
 *  main thread: one core call per tag. */
internal fun codesWithoutFloor(tagIds: List<String>): List<String> = tagIds.mapNotNull { id ->
    val t = Core.api("GET", "/native/tag", query = mapOf("id" to id)).json
    val code = t.optString("code")
    val floor = t.optJSONObject("equipment")?.optString("floor").orEmpty()
    if (code.isNotEmpty() && floor.isBlank() && PhotoQueue.queuedFloor[code].isNullOrEmpty()) code else null
}.distinct()

/** one photo for every code: the panel's camera (or gallery) → mark-up editor → JPEG XL, sent once (the core keeps
 *  the image once and points every code's entry to it) */
@Composable
fun PhotoForAll(codes: List<String>, onSent: (String) -> Unit, onClose: () -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var picked by remember { mutableStateOf<Bitmap?>(null) }
    var fromCamera by remember { mutableStateOf(true) }
    var busy by remember { mutableFloatStateOf(-1f) }
    val camFile = remember { File(ctx.cacheDir, "camera/shot.jpg").also { it.parentFile?.mkdirs() } }
    val camUri = remember { FileProvider.getUriForFile(ctx, "io.github.walkdown.files", camFile) }
    fun load(uri: Uri) = scope.launch {
        picked = withContext(Dispatchers.IO) {
            val raw = ctx.contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: return@withContext null
            if (uri == camUri) camFile.delete()
            orientedBitmap(raw)
        }
        if (picked == null) onSent("Could not read that picture")
    }
    val gallery = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { u: Uri? -> if (u != null) load(u) }
    val camera = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { ok -> if (ok) load(camUri) }
    val perm = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok ->
        if (ok) camera.launch(camUri) else onSent("Without the camera permission, pick a photo from the gallery")
    }
    fun shoot() {
        fromCamera = true
        if (ctx.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) camera.launch(camUri) else perm.launch(Manifest.permission.CAMERA)
    }
    val title = "Photo for ${codes.size} code" + if (codes.size == 1) "" else "s"
    if (picked == null) AlertDialog(onDismissRequest = { if (busy < 0f) onClose() }, title = { Text(title) }, text = {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (busy >= 0f) {
                Text("Compressing…")
                LinearProgressIndicator(progress = { busy }, modifier = Modifier.fillMaxWidth())
            } else {
                Dim("One picture showing all of them; each code gets it.")
                Button(onClick = { shoot() }, modifier = Modifier.fillMaxWidth()) { Text("Take a photo") }
                OutlinedButton(onClick = { fromCamera = false; gallery.launch("image/*") }, modifier = Modifier.fillMaxWidth()) { Text("From the gallery") }
            }
        }
    }, confirmButton = { if (busy < 0f) TextButton(onClick = onClose) { Text("Cancel") } })
    picked?.let { bmp ->
        Annotate(bmp, false, retake = if (fromCamera) "Retake" else "Choose another", onCancel = { picked = null },
            onRetake = { picked = null; if (fromCamera) shoot() else gallery.launch("image/*") }) { out, caption, note ->
            picked = null
            scope.launch {
                val mp = out.width.toLong() * out.height / 1e6
                val expect = (Jxl.msPerMp * mp).toLong().coerceAtLeast(500)
                val t0 = System.currentTimeMillis()
                busy = 0f
                val tick = launch { while (true) { busy = ((System.currentTimeMillis() - t0).toFloat() / expect).coerceAtMost(0.95f); delay(100) } }
                val jxl = withContext(Dispatchers.Default) { runCatching { Jxl.fromBitmap(out) }.getOrNull() }
                tick.cancel(); busy = -1f
                if (jxl == null) { onSent("Could not compress the photo"); return@launch }
                val (ok, m) = withContext(Dispatchers.IO) {
                    submitMany("photo", codes, JSONObject().put("caption", caption)
                        .put("dataUrl", "data:image/jxl;base64," + Base64.encodeToString(jxl, Base64.NO_WRAP)), note)
                }
                onSent(m); if (ok) onClose()
            }
        }
    }
}

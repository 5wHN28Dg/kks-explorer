package kks.explorer.ui

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.net.Uri
import android.util.Base64
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculateCentroid
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.FileProvider
import kks.explorer.Jxl
import kks.explorer.core.Core
import kks.explorer.sync.PhotoQueue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sin

/** a photo's pixels, decoded from its JPEG XL blob; null while this phone doesn't hold it yet (on-demand photos) */
private fun photoBitmap(file: String): Bitmap? = Core.file("photos/$file")?.let { Jxl.bitmap(it) }

@Composable
fun PhotoOf(file: String, caption: String = "", height: Int = 90) {
    if (file.isEmpty()) return
    val bmp by produceState<ImageBitmap?>(null, file) { value = withContext(Dispatchers.IO) { photoBitmap(file)?.asImageBitmap() } }
    var open by remember { mutableStateOf(false) }
    val b = bmp
    if (b == null) { Dim("Not on this phone yet (it arrives with the next sync)"); return }
    Image(b, "Open photo" + if (caption.isNotEmpty()) ": $caption" else "", Modifier.height(height.dp).clickable { open = true }, contentScale = ContentScale.Fit)
    if (open) PhotoViewer(b, caption) { open = false }
}

/** pinch to zoom, drag to pan (R6) */
@Composable
fun PhotoViewer(b: ImageBitmap, caption: String, onClose: () -> Unit) {
    var scale by remember { mutableFloatStateOf(1f) }
    var off by remember { mutableStateOf(Offset.Zero) }
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        FullScreenDialogWindow()
        Surface(Modifier.fillMaxSize(), color = Color.Black) {
            Box(Modifier.fillMaxSize().pointerInput(Unit) {
                detectTransformGestures { _, pan, zoom, _ -> scale = (scale * zoom).coerceIn(1f, 8f); off = if (scale == 1f) Offset.Zero else off + pan }
            }) {
                Image(b, caption.ifEmpty { "Photo" }, Modifier.fillMaxSize().graphicsLayer(scaleX = scale, scaleY = scale, translationX = off.x, translationY = off.y))
                Row(Modifier.fillMaxWidth().align(Alignment.TopCenter).windowInsetsPadding(WindowInsets.safeDrawing).padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(caption, color = Color.White, modifier = Modifier.weight(1f))
                    TextButton(onClick = onClose) { Text("Close") }
                }
            }
        }
    }
}

/** the panel's photos of one KKS: thumbnails (the tag plate first), delete, add (camera or gallery → annotate → JPEG XL →
 *  submit), and the tag plate's photo */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun PhotoStrip(kks: String, photos: List<JSONObject>, snack: SnackbarHostState, floorNow: String = "") {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var picked by remember { mutableStateOf<Bitmap?>(null) }
    var fromCamera by remember { mutableStateOf(true) }       // for Retake: the camera again, or the gallery
    var plate by remember { mutableStateOf(false) }           // this picture is of the equipment's tag plate
    var askPlate by remember { mutableStateOf(false) }
    var delete by remember { mutableStateOf("") }
    // the floor comes first when the code has none (the user, 2026-10-08): asked before the camera opens, sent with the
    // photo (the core writes it as its own change); a floor already queued with a photo of this code is used again
    var floor by rememberSaveable(kks) { mutableStateOf("") }
    var askFloor by remember { mutableStateOf<(() -> Unit)?>(null) }
    val sendFloor = if (floorNow.isNotBlank()) "" else floor.ifEmpty { PhotoQueue.queuedFloor[kks].orEmpty() }
    fun withFloor(then: () -> Unit) { if (floorNow.isBlank() && sendFloor.isEmpty()) askFloor = then else then() }
    val camFile = remember { File(ctx.cacheDir, "camera/shot.jpg").also { it.parentFile?.mkdirs() } }
    val camUri = remember { FileProvider.getUriForFile(ctx, "io.github.walkdown.files", camFile) }
    fun load(uri: Uri) = scope.launch {
        picked = withContext(Dispatchers.IO) {
            val raw = ctx.contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: return@withContext null
            if (uri == camUri) camFile.delete()
            orientedBitmap(raw)
        }
        if (picked == null) snack.showSnackbar("Could not read that picture")
    }
    val gallery = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { u: Uri? -> if (u != null) load(u) }
    val camera = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { ok -> if (ok) load(camUri) }
    // the CAMERA permission is declared (QR scanning), so the camera app may only be asked once it is granted
    val perm = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok ->
        if (ok) camera.launch(camUri) else scope.launch { snack.showSnackbar("Without the camera permission, pick a photo from the gallery") }
    }
    fun shoot(ofPlate: Boolean) {
        plate = ofPlate; fromCamera = true
        if (ctx.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) camera.launch(camUri) else perm.launch(Manifest.permission.CAMERA)
    }
    val hasPlate = photos.any { isPlate(it.str("caption")) }
    if (delete.isNotEmpty()) Confirm("Delete this photo?", "It is removed for everyone once approved.", "Delete", {
        val (_, m) = submit("photo_delete", JSONObject().put("photo_id", delete)); scope.launch { snack.showSnackbar(m) }
    }, { delete = "" })
    Text("Photos", style = MaterialTheme.typography.titleMedium)
    if (photos.isNotEmpty()) Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        // the tag plate first: it is how the equipment is recognised in the field
        for (p in photos.sortedBy { if (isPlate(it.str("caption"))) 0 else 1 }) Column {
            if (isPlate(p.str("caption"))) Text("Tag plate", style = MaterialTheme.typography.labelMedium)
            PhotoOf(p.str("file"), p.str("caption"))
            photoCredit(p).let { if (it.isNotEmpty()) Text(it, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            TextButton(onClick = { delete = p.str("id") }) { Text("Delete") }
        }
    }
    askFloor?.let { then ->
        FloorDialog("Which floor is it on?", "$kks has no floor yet. Every photo needs it first: it is sent with the photo.",
            onPick = { floor = it; askFloor = null; then() }, onClose = { askFloor = null })
    }
    if (askPlate) AlertDialog(onDismissRequest = { askPlate = false }, title = { Text("And its tag plate?") },
        text = { Text("A photo of the metal plate with the KKS code helps the next person find this equipment.") },
        confirmButton = { TextButton(onClick = { askPlate = false; shoot(true) }) { Text("Take it") } },
        dismissButton = { TextButton(onClick = { askPlate = false }) { Text("Not now") } })
    val queued = PhotoQueue.pendingByCode[kks] ?: 0
    if (queued > 0) {
        Text(if (queued == 1) "1 photo of this tag is being prepared" else "$queued photos of this tag are being prepared")
        LinearProgressIndicator(Modifier.fillMaxWidth())
    }
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        OutlinedButton(onClick = { withFloor { shoot(false) } }) { Text("Take a photo") }
        OutlinedButton(onClick = { withFloor { shoot(true) } }) { Text(if (hasPlate) "New tag plate photo" else "Photo of the tag plate") }
        OutlinedButton(onClick = { withFloor { plate = false; fromCamera = false; gallery.launch("image/*") } }) { Text("From the gallery") }
    }
    picked?.let { bmp ->
        Annotate(bmp, plate, retake = if (fromCamera) "Retake" else "Choose another", onCancel = { picked = null },
            onRetake = { picked = null; if (fromCamera) shoot(plate) else gallery.launch("image/*") }) { out, caption0, note ->
            picked = null
            val caption = if (plate) plateCaption(caption0) else caption0
            // the queue encodes and sends it in the background, in order, whether or not this panel stays open
            PhotoQueue.add(ctx, out, kks, caption, note, sendFloor)
            if (!plate && fromCamera && !hasPlate) askPlate = true
            scope.launch { snack.showSnackbar("Photo queued: it is compressed and sent in the background") }
        }
    }
}

/** the floor asked for before a photo of a code (or codes) without one: a whole number 0 to 10 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun FloorDialog(title: String, text: String, onPick: (String) -> Unit, onClose: () -> Unit) {
    var chosen by remember { mutableStateOf("") }
    AlertDialog(onDismissRequest = onClose, title = { Text(title) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                // a long list of codes (Photo for all) scrolls; the floors stay in view
                Box(Modifier.heightIn(max = 160.dp).verticalScroll(rememberScrollState())) { Text(text) }
                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    for (f in 0..10) FilterChip(chosen == "$f", { chosen = "$f" }, label = { Text("$f") },
                        modifier = Modifier.semantics { contentDescription = "Floor $f" + if (chosen == "$f") ", chosen" else "" })
                }
                Dim("A whole number from 0 to 10; the height in metres goes in Elevation.")
            }
        },
        confirmButton = { TextButton(onClick = { onPick(chosen) }, enabled = chosen.isNotEmpty()) { Text("Continue") } },
        dismissButton = { TextButton(onClick = onClose) { Text("Cancel") } })
}

/** who took a photo and when ("by Ali User, 2026-10-08 09:12"): sent (submitted), else when it took effect */
fun photoCredit(p: JSONObject): String {
    val who = p.str("by_name").ifEmpty { p.str("by") }
    val at = whenText(p.optLong("submitted").takeIf { it > 0 } ?: p.optLong("created"))
    return listOf(if (who.isNotEmpty()) "by $who" else "", at).filter { it.isNotEmpty() }.joinToString(", ")
}

/** decoded, turned upright (EXIF), and at most 1600 px on the longer side (the size the other clients send) */
internal fun orientedBitmap(raw: ByteArray): Bitmap? {
    val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeByteArray(raw, 0, raw.size, opts)
    var sample = 1
    while (maxOf(opts.outWidth, opts.outHeight) / (sample * 2) >= 1600) sample *= 2
    var bmp = BitmapFactory.decodeByteArray(raw, 0, raw.size, BitmapFactory.Options().apply { inSampleSize = sample; inPreferredConfig = Bitmap.Config.ARGB_8888 }) ?: return null
    val turn = runCatching {
        when (android.media.ExifInterface(raw.inputStream()).getAttributeInt(android.media.ExifInterface.TAG_ORIENTATION, 1)) {
            android.media.ExifInterface.ORIENTATION_ROTATE_90 -> 90; android.media.ExifInterface.ORIENTATION_ROTATE_180 -> 180
            android.media.ExifInterface.ORIENTATION_ROTATE_270 -> 270; else -> 0
        }
    }.getOrDefault(0)
    if (turn != 0) bmp = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, android.graphics.Matrix().apply { postRotate(turn.toFloat()) }, true)
    val side = maxOf(bmp.width, bmp.height)
    if (side > 1600) bmp = Bitmap.createScaledBitmap(bmp, bmp.width * 1600 / side, bmp.height * 1600 / side, true)
    return bmp
}

/** A photo of the equipment's tag plate (the metal plate with its KKS code) is a photo whose caption starts with
 *  "Tag plate": a convention, not a field, so the apps before 0.9.3 (which reject unknown photo fields) still take it
 *  and simply show the caption (PROTOCOL-v2 §9). */
const val PLATE = "Tag plate"
fun isPlate(caption: String) = caption.startsWith(PLATE)
private fun plateCaption(extra: String) = if (extra.isBlank()) PLATE else "$PLATE · ${extra.trim()}"

private data class Mark(val kind: String, val color: Int, val a: Offset, val b: Offset, val size: Float = 1f)   // size: × the base line width
private val COLORS = listOf(0xFFE53935.toInt(), 0xFFFDD835.toInt(), 0xFF1E88E5.toInt(), 0xFFFFFFFF.toInt())

/** the annotation editor (v1 K.annotate, GNOME annotate): arrow / box / circle in 4 colours, 3 line sizes, undo,
 *  retake; burned into the image. Zoom with +/−/Fit or two fingers (pinch and pan); while a finger draws, a loupe shows
 *  the area under it magnified, above the finger (touch only). Its window covers the screen and it pads itself by its
 *  own insets (bars, keyboard): before, the dialog's window was clipped between the system bars while its content was
 *  laid out at the screen's full height, so the last row (Send, Cancel) was cut off on the Honor 600 (2026-10-04); and
 *  Undo sat at the end of a row wider than the screen. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun Annotate(src: Bitmap, plate: Boolean, retake: String, onCancel: () -> Unit, onRetake: () -> Unit,
                     onDone: (Bitmap, String, String) -> Unit) {
    val marks = remember { mutableStateListOf<Mark>() }
    var kind by remember { mutableStateOf("arrow") }
    var color by remember { mutableIntStateOf(COLORS[0]) }
    var lineSize by remember { mutableFloatStateOf(1f) }
    var drawing by remember { mutableStateOf<Mark?>(null) }
    var finger by remember { mutableStateOf<Offset?>(null) }       // where a finger draws (view px): the loupe
    var caption by remember { mutableStateOf("") }
    var note by remember { mutableStateOf("") }
    var box by remember { mutableStateOf(IntSize.Zero) }
    var zoom by remember { mutableFloatStateOf(1f) }
    var centre by remember { mutableStateOf(Offset(src.width / 2f, src.height / 2f)) }   // the image point at the view's centre
    val img = remember(src) { src.asImageBitmap() }
    val fit = if (box.width == 0) 1f else minOf(box.width / src.width.toFloat(), box.height / src.height.toFloat())
    fun clamp(c: Offset, z: Float): Offset {
        val s = fit * z; val hw = box.width / 2f / s; val hh = box.height / 2f / s
        return Offset(if (hw * 2 >= src.width) src.width / 2f else c.x.coerceIn(hw, src.width - hw),
                      if (hh * 2 >= src.height) src.height / 2f else c.y.coerceIn(hh, src.height - hh))
    }
    fun toImg(p: Offset): Offset { val s = fit * zoom; return Offset(centre.x + (p.x - box.width / 2f) / s, centre.y + (p.y - box.height / 2f) / s) }
    fun zoomAt(p: Offset, z: Float) {
        val nz = z.coerceIn(1f, 8f); val ip = toImg(p); val s = fit * nz
        zoom = nz; centre = clamp(Offset(ip.x - (p.x - box.width / 2f) / s, ip.y - (p.y - box.height / 2f) / s), nz)
    }
    val baseW = maxOf(3f, src.width / 200f)                 // image px, × the mark's size
    Dialog(onDismissRequest = onCancel, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        FullScreenDialogWindow()
        Surface(Modifier.fillMaxSize()) {
            Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing).padding(8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                if (plate) Text("Tag plate", style = MaterialTheme.typography.titleMedium)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalArrangement = Arrangement.Center) {
                    for ((k, lab) in listOf("arrow" to "Arrow", "box" to "Box", "circle" to "Circle"))
                        FilterChip(kind == k, { kind = k }, label = { Text(lab) })
                    for ((i, c) in COLORS.withIndex()) Box(Modifier.align(Alignment.CenterVertically).size(36.dp).padding(4.dp)
                        .clickable { color = c }.semantics { contentDescription = listOf("Red", "Yellow", "Blue", "White")[i] + if (color == c) ", chosen" else "" }) {
                        Canvas(Modifier.fillMaxSize()) {
                            drawCircle(Color(c)); if (color == c) drawCircle(Color.Black, style = Stroke(3f))
                        }
                    }
                }
                FlowRow(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    for ((f, lab, desc) in listOf(Triple(0.6f, "S", "Thin lines"), Triple(1f, "M", "Medium lines"), Triple(1.8f, "L", "Thick lines")))
                        FilterChip(lineSize == f, { lineSize = f }, label = { Text(lab) }, modifier = Modifier.semantics { contentDescription = desc })
                    Spacer(Modifier.width(8.dp))
                    OutlinedButton(onClick = { zoomAt(Offset(box.width / 2f, box.height / 2f), zoom / 1.5f) }, Modifier.semantics { contentDescription = "Zoom out" }) { Text("−") }
                    OutlinedButton(onClick = { zoomAt(Offset(box.width / 2f, box.height / 2f), zoom * 1.5f) }, Modifier.semantics { contentDescription = "Zoom in" }) { Text("+") }
                    OutlinedButton(onClick = { zoom = 1f; centre = Offset(src.width / 2f, src.height / 2f) }) { Text("Fit") }
                }
                Box(Modifier.weight(1f).fillMaxWidth().clipToBounds().onSizeChanged { box = it }.pointerInput(kind, color, lineSize, fit) {
                    // one finger draws; a second finger turns it into zoom and pan (and drops the mark being drawn)
                    awaitEachGesture {
                        val down = awaitFirstDown()
                        val touch = down.type == androidx.compose.ui.input.pointer.PointerType.Touch
                        drawing = Mark(kind, color, toImg(down.position), toImg(down.position), lineSize)
                        if (touch) finger = down.position
                        var pinching = false
                        while (true) {
                            val ev = awaitPointerEvent()
                            val pressed = ev.changes.filter { it.pressed }
                            if (pressed.isEmpty()) {
                                val m = drawing
                                if (!pinching && m != null && hypot(m.b.x - m.a.x, m.b.y - m.a.y) * fit * zoom > 12f) marks.add(m)
                                drawing = null; finger = null
                                break
                            }
                            if (pressed.size >= 2) {
                                pinching = true; drawing = null; finger = null
                                val z = ev.calculateZoom(); val pan = ev.calculatePan(); val c = ev.calculateCentroid()
                                if (c != Offset.Unspecified) zoomAt(c, zoom * z)
                                val s = fit * zoom
                                centre = clamp(Offset(centre.x - pan.x / s, centre.y - pan.y / s), zoom)
                            } else if (!pinching) {
                                val p = pressed[0].position
                                drawing = drawing?.copy(b = toImg(p))
                                if (touch) finger = p
                            }
                            ev.changes.forEach { it.consume() }
                        }
                    }
                }) {
                    Canvas(Modifier.fillMaxSize()) {
                        // the scene: the photo and the marks, in image px through the view's transform
                        fun DrawScope.scene(s: Float, ox: Float, oy: Float) {
                            drawImage(img, dstOffset = androidx.compose.ui.unit.IntOffset(ox.toInt(), oy.toInt()),
                                dstSize = IntSize((src.width * s).toInt(), (src.height * s).toInt()))
                            for (m in marks + listOfNotNull(drawing)) {
                                val a = Offset(ox + m.a.x * s, oy + m.a.y * s); val b = Offset(ox + m.b.x * s, oy + m.b.y * s)
                                val w = baseW * m.size * s
                                when (m.kind) {
                                    "box" -> drawRect(Color(m.color), Offset(minOf(a.x, b.x), minOf(a.y, b.y)),
                                        androidx.compose.ui.geometry.Size(kotlin.math.abs(b.x - a.x), kotlin.math.abs(b.y - a.y)), style = Stroke(w))
                                    "circle" -> drawOval(Color(m.color), Offset(minOf(a.x, b.x), minOf(a.y, b.y)),
                                        androidx.compose.ui.geometry.Size(kotlin.math.abs(b.x - a.x), kotlin.math.abs(b.y - a.y)), style = Stroke(w))
                                    else -> {
                                        drawLine(Color(m.color), a, b, w)
                                        val ang = atan2(b.y - a.y, b.x - a.x); val head = w * 5
                                        for (d in listOf(-0.5f, 0.5f)) drawLine(Color(m.color), b, Offset(b.x - head * cos(ang + d), b.y - head * sin(ang + d)), w)
                                    }
                                }
                            }
                        }
                        val s = fit * zoom
                        scene(s, size.width / 2 - centre.x * s, size.height / 2 - centre.y * s)
                        // the loupe: 2.5× the view around the finger, a circle above it (below it near the top edge)
                        finger?.let { f ->
                            val r = 70.dp.toPx(); val k = 2.5f; val gap = 40.dp.toPx()
                            val lc = Offset(f.x.coerceIn(r, size.width - r), if (f.y - gap - 2 * r >= 0) f.y - gap - r else f.y + gap + r)
                            val ip = toImg(f); val ls = s * k
                            val circle = androidx.compose.ui.graphics.Path().apply { addOval(androidx.compose.ui.geometry.Rect(lc, r)) }
                            clipPath(circle) {
                                drawRect(Color.Black, lc - Offset(r, r), androidx.compose.ui.geometry.Size(2 * r, 2 * r))
                                scene(ls, lc.x - ip.x * ls, lc.y - ip.y * ls)
                                drawLine(Color(0xFFFF7A1A), lc - Offset(12f, 0f), lc + Offset(12f, 0f), 2f)
                                drawLine(Color(0xFFFF7A1A), lc - Offset(0f, 12f), lc + Offset(0f, 12f), 2f)
                            }
                            drawCircle(Color(0xFFFF7A1A), r, lc, style = Stroke(3.dp.toPx()))
                        }
                    }
                }
                OutlinedTextField(caption, { caption = it }, label = { Text(if (plate) "Caption (optional; it says Tag plate)" else "Caption (optional)") },
                    singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(note, { note = it }, label = { Text("Note for the approver (optional)") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = { if (marks.isNotEmpty()) marks.removeAt(marks.size - 1) }, enabled = marks.isNotEmpty()) {
                        Icon(Glyphs.UNDO, contentDescription = null, Modifier.size(18.dp)); Spacer(Modifier.width(6.dp)); Text("Undo")
                    }
                    OutlinedButton(onClick = onRetake) { Text(retake) }
                    OutlinedButton(onClick = onCancel) { Text("Cancel") }
                    Button(onClick = { onDone(burn(src, marks), caption.trim(), note.trim()) }) { Text("Send") }
                }
            }
        }
    }
}

/** the marks drawn into a copy of the photo, in image pixels */
private fun burn(src: Bitmap, marks: List<Mark>): Bitmap {
    if (marks.isEmpty()) return src
    val out = src.copy(Bitmap.Config.ARGB_8888, true)
    val c = Canvas(out)
    val w0 = maxOf(3f, src.width / 200f)
    val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeCap = Paint.Cap.ROUND }
    for (m in marks) {
        val w = w0 * m.size
        p.color = m.color; p.strokeWidth = w
        val l = minOf(m.a.x, m.b.x); val t = minOf(m.a.y, m.b.y); val r = maxOf(m.a.x, m.b.x); val bt = maxOf(m.a.y, m.b.y)
        when (m.kind) {
            "box" -> c.drawRect(l, t, r, bt, p)
            "circle" -> c.drawOval(l, t, r, bt, p)
            else -> {
                if (hypot(m.b.x - m.a.x, m.b.y - m.a.y) < 1f) continue
                val ang = atan2(m.b.y - m.a.y, m.b.x - m.a.x); val head = w * 5
                c.drawPath(Path().apply {
                    moveTo(m.a.x, m.a.y); lineTo(m.b.x, m.b.y)
                    moveTo(m.b.x - head * cos(ang - 0.5f), m.b.y - head * sin(ang - 0.5f)); lineTo(m.b.x, m.b.y)
                    lineTo(m.b.x - head * cos(ang + 0.5f), m.b.y - head * sin(ang + 0.5f))
                }, p)
            }
        }
    }
    return out
}

/** the photo queue on every screen: how many are being prepared, and what failed (kept until dismissed) */
@Composable
fun PhotoQueueBar() {
    val ctx = LocalContext.current
    val n = PhotoQueue.pending
    if (n > 0) Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp).semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically) {
        CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
        Spacer(Modifier.width(8.dp))
        Text(if (n == 1) "1 photo being prepared" else "$n photos being prepared", style = MaterialTheme.typography.labelLarge)
    }
    if (PhotoQueue.failures.isNotEmpty()) Card(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer)) {
        Column(Modifier.padding(start = 16.dp, end = 8.dp, top = 8.dp)) {
            Text(if (PhotoQueue.failures.size == 1) "A photo was not sent" else "${PhotoQueue.failures.size} photos were not sent",
                style = MaterialTheme.typography.titleSmall)
            for (f in PhotoQueue.failures.takeLast(5)) Text(f, style = MaterialTheme.typography.bodySmall)
            TextButton(onClick = { PhotoQueue.dismissFailures(ctx) }, Modifier.align(Alignment.End)) { Text("Dismiss") }
        }
    }
}

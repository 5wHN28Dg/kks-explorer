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
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.*
import androidx.compose.runtime.*
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
fun PhotoStrip(kks: String, photos: List<JSONObject>, snack: SnackbarHostState) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var picked by remember { mutableStateOf<Bitmap?>(null) }
    var fromCamera by remember { mutableStateOf(true) }       // for Retake: the camera again, or the gallery
    var plate by remember { mutableStateOf(false) }           // this picture is of the equipment's tag plate
    var askPlate by remember { mutableStateOf(false) }
    var delete by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(-1f) }
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
            TextButton(onClick = { delete = p.str("id") }) { Text("Delete") }
        }
    }
    if (askPlate) AlertDialog(onDismissRequest = { askPlate = false }, title = { Text("And its tag plate?") },
        text = { Text("A photo of the metal plate with the KKS code helps the next person find this equipment.") },
        confirmButton = { TextButton(onClick = { askPlate = false; shoot(true) }) { Text("Take it") } },
        dismissButton = { TextButton(onClick = { askPlate = false }) { Text("Not now") } })
    if (busy >= 0f) {
        Text("Compressing…")
        LinearProgressIndicator(progress = { busy }, modifier = Modifier.fillMaxWidth())
    } else FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        OutlinedButton(onClick = { shoot(false) }) { Text("Take a photo") }
        OutlinedButton(onClick = { shoot(true) }) { Text(if (hasPlate) "New tag plate photo" else "Photo of the tag plate") }
        OutlinedButton(onClick = { plate = false; fromCamera = false; gallery.launch("image/*") }) { Text("From the gallery") }
    }
    picked?.let { bmp ->
        Annotate(bmp, plate, retake = if (fromCamera) "Retake" else "Choose another", onCancel = { picked = null },
            onRetake = { picked = null; if (fromCamera) shoot(plate) else gallery.launch("image/*") }) { out, caption0, note ->
            picked = null
            val caption = if (plate) plateCaption(caption0) else caption0
            val offerPlate = !plate && fromCamera && !hasPlate
            scope.launch {
                // libjxl has no progress callback: estimate from the measured time per megapixel, capped at 95 % until done
                val mp = out.width.toLong() * out.height / 1e6
                val expect = (Jxl.msPerMp * mp).toLong().coerceAtLeast(500)
                val t0 = System.currentTimeMillis()
                busy = 0f
                val tick = launch { while (true) { busy = ((System.currentTimeMillis() - t0).toFloat() / expect).coerceAtMost(0.95f); delay(100) } }
                val jxl = withContext(Dispatchers.Default) { runCatching { Jxl.fromBitmap(out) }.getOrNull() }
                tick.cancel(); busy = -1f
                if (jxl == null) { snack.showSnackbar("Could not compress the photo"); return@launch }
                val (_, m) = submit("photo", JSONObject().put("kks", kks).put("caption", caption)
                    .put("dataUrl", "data:image/jxl;base64," + Base64.encodeToString(jxl, Base64.NO_WRAP)), note)
                if (offerPlate) askPlate = true
                snack.showSnackbar(m)
            }
        }
    }
}

/** decoded, turned upright (EXIF), and at most 1600 px on the longer side (the size the other clients send) */
private fun orientedBitmap(raw: ByteArray): Bitmap? {
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

private data class Mark(val kind: String, val color: Int, val a: Offset, val b: Offset)
private val COLORS = listOf(0xFFE53935.toInt(), 0xFFFDD835.toInt(), 0xFF1E88E5.toInt(), 0xFFFFFFFF.toInt())

/** the annotation editor (v1 K.annotate, GNOME annotate): arrow / box / circle in 4 colours, undo, retake; burned into
 *  the image. Its window covers the screen and it pads itself by its own insets (bars, keyboard): before, the dialog's
 *  window was clipped between the system bars while its content was laid out at the screen's full height, so the last
 *  row (Send, Cancel) was cut off on the Honor 600 (2026-10-04); and Undo sat at the end of a row wider than the screen. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Annotate(src: Bitmap, plate: Boolean, retake: String, onCancel: () -> Unit, onRetake: () -> Unit,
                     onDone: (Bitmap, String, String) -> Unit) {
    val marks = remember { mutableStateListOf<Mark>() }
    var kind by remember { mutableStateOf("arrow") }
    var color by remember { mutableIntStateOf(COLORS[0]) }
    var drawing by remember { mutableStateOf<Mark?>(null) }
    var caption by remember { mutableStateOf("") }
    var note by remember { mutableStateOf("") }
    var box by remember { mutableStateOf(IntSize.Zero) }
    val img = remember(src) { src.asImageBitmap() }
    // image ↔ view: the image is fitted (contain) and centred
    val fit = if (box.width == 0) 1f else minOf(box.width / src.width.toFloat(), box.height / src.height.toFloat())
    val ox = (box.width - src.width * fit) / 2; val oy = (box.height - src.height * fit) / 2
    fun toImg(p: Offset) = Offset((p.x - ox) / fit, (p.y - oy) / fit)
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
                Box(Modifier.weight(1f).fillMaxWidth().onSizeChanged { box = it }.pointerInput(kind, color, fit) {
                    detectDragGestures(onDragStart = { p -> drawing = Mark(kind, color, toImg(p), toImg(p)) },
                        onDragEnd = { drawing?.let { marks.add(it) }; drawing = null },
                        onDragCancel = { drawing = null }) { change, _ -> drawing = drawing?.copy(b = toImg(change.position)) }
                }) {
                    Canvas(Modifier.fillMaxSize()) {
                        drawImage(img, dstOffset = androidx.compose.ui.unit.IntOffset(ox.toInt(), oy.toInt()),
                            dstSize = IntSize((src.width * fit).toInt(), (src.height * fit).toInt()))
                        for (m in marks + listOfNotNull(drawing)) {
                            val a = Offset(ox + m.a.x * fit, oy + m.a.y * fit); val b = Offset(ox + m.b.x * fit, oy + m.b.y * fit)
                            val w = maxOf(3f, src.width * fit / 200f)
                            when (m.kind) {
                                "box" -> drawRect(Color(m.color), Offset(minOf(a.x, b.x), minOf(a.y, b.y)),
                                    androidx.compose.ui.geometry.Size(kotlin.math.abs(b.x - a.x), kotlin.math.abs(b.y - a.y)), style = Stroke(w))
                                "circle" -> drawOval(Color(m.color), Offset(minOf(a.x, b.x), minOf(a.y, b.y)),
                                    androidx.compose.ui.geometry.Size(kotlin.math.abs(b.x - a.x), kotlin.math.abs(b.y - a.y)), style = Stroke(w))
                                else -> {
                                    drawLine(Color(m.color), a, b, w)
                                    val ang = atan2(b.y - a.y, b.x - a.x); val head = w * 5
                                    for (s in listOf(-0.5f, 0.5f)) drawLine(Color(m.color), b, Offset(b.x - head * cos(ang + s), b.y - head * sin(ang + s)), w)
                                }
                            }
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
    val w = maxOf(3f, src.width / 200f)
    val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeWidth = w; strokeCap = Paint.Cap.ROUND }
    for (m in marks) {
        p.color = m.color
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

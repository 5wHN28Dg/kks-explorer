package kks.explorer.ui

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraExtensionCharacteristics
import android.hardware.camera2.CameraManager
import android.graphics.ImageFormat
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContract
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.compose.CameraXViewfinder
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.FocusMeteringAction
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.Preview
import androidx.camera.core.SurfaceOrientedMeteringPointFactory
import androidx.camera.core.SurfaceRequest
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.extensions.ExtensionMode
import androidx.camera.extensions.ExtensionsManager
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.viewfinder.compose.MutableCoordinateTransformer
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.ui.draw.drawBehind
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.windowInsetsEndWidth
import androidx.compose.foundation.layout.windowInsetsStartWidth
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat

/**
 * The in-app camera (decision 0075): CameraX at the highest quality and the largest normal size, with the phone's
 * Extensions (Auto, HDR, Night: the maker's own multi-frame processing) where it offers them. The shot is written in
 * full to the caller's Uri, then goes the way every picture goes (0074: 2560 px, Lanczos, the editor). The phone's own
 * camera app stays one tap away ("Use the camera app"), and a setting (Manage → Account → Photos) chooses which of
 * the two "Take a photo" opens.
 */
object InAppCamera {
    /** the modes offered, in the order shown; Standard = no Extension */
    val MODES = listOf(ExtensionMode.AUTO to "Auto", ExtensionMode.HDR to "HDR", ExtensionMode.NIGHT to "Night")
    const val STANDARD = ExtensionMode.NONE
    const val EXTRA_MODE = "mode"

    private fun prefs(ctx: Context) = ctx.getSharedPreferences("app", Context.MODE_PRIVATE)

    /** the Extensions the back camera offers (CameraX), as found by the last [probe]; null before the first */
    fun offered(ctx: Context): List<Int>? =
        prefs(ctx).getString("camera_ext", null)?.split(',')?.mapNotNull { it.toIntOrNull() }

    /** whether "Take a photo" opens this camera: the person's choice, else on where the phone offers an Extension */
    fun chosen(ctx: Context): Boolean =
        if (prefs(ctx).contains("camera_in_app")) prefs(ctx).getBoolean("camera_in_app", false) else !offered(ctx).isNullOrEmpty()

    fun choose(ctx: Context, on: Boolean) = prefs(ctx).edit().putBoolean("camera_in_app", on).apply()

    fun lastMode(ctx: Context): Int? = prefs(ctx).getInt("camera_mode", -1).takeIf { it >= 0 }
    fun keepMode(ctx: Context, m: Int) = prefs(ctx).edit().putInt("camera_mode", m).apply()

    fun modeName(m: Int) = MODES.firstOrNull { it.first == m }?.second ?: "Standard"

    /** "Take a photo": this camera or the phone's camera app (as the setting says), writing the full picture to the Uri */
    class TakePhoto : ActivityResultContract<Uri, Boolean>() {
        override fun createIntent(context: Context, input: Uri): Intent =
            if (chosen(context)) Intent(context, CameraActivity::class.java).putExtra(MediaStore.EXTRA_OUTPUT, input)
            else Intent(MediaStore.ACTION_IMAGE_CAPTURE).putExtra(MediaStore.EXTRA_OUTPUT, input)
        override fun parseResult(resultCode: Int, intent: Intent?) = resultCode == Activity.RESULT_OK
    }

    /**
     * What this phone's cameras offer, for the setting's default and for diagnostics: the Extensions CameraX finds on
     * the back camera, the Camera2 Extensions (Android 12+) per camera, and the largest JPEG sizes. Runs on the main
     * thread's executor (CameraX does its own work on its threads); [done] gets a readable text.
     */
    fun probe(ctx: Context, done: (String, Boolean) -> Unit) {
        val app = ctx.applicationContext
        val main = ContextCompat.getMainExecutor(app)
        val lines = mutableListOf("Camera on ${Build.MANUFACTURER} ${Build.MODEL}, Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})")
        runCatching {
            val cm = app.getSystemService(CameraManager::class.java)
            for (id in cm.cameraIdList) {
                val ch = cm.getCameraCharacteristics(id)
                val facing = when (ch.get(CameraCharacteristics.LENS_FACING)) {
                    CameraCharacteristics.LENS_FACING_BACK -> "back"; CameraCharacteristics.LENS_FACING_FRONT -> "front"; else -> "external"
                }
                val map = ch.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
                val jpeg = map?.getOutputSizes(ImageFormat.JPEG)?.maxByOrNull { it.width.toLong() * it.height }
                val high = map?.getHighResolutionOutputSizes(ImageFormat.JPEG)?.maxByOrNull { it.width.toLong() * it.height }
                var line = "Camera $id ($facing): JPEG up to ${jpeg ?: "?"}" + (if (high != null) ", high resolution up to $high" else "")
                if (Build.VERSION.SDK_INT >= 31) {
                    val ext = runCatching { cm.getCameraExtensionCharacteristics(id).supportedExtensions }.getOrDefault(emptyList())
                    val names = mapOf(CameraExtensionCharacteristics.EXTENSION_AUTOMATIC to "Auto", CameraExtensionCharacteristics.EXTENSION_HDR to "HDR",
                        CameraExtensionCharacteristics.EXTENSION_NIGHT to "Night", CameraExtensionCharacteristics.EXTENSION_BOKEH to "Bokeh",
                        CameraExtensionCharacteristics.EXTENSION_FACE_RETOUCH to "Face retouch")
                    line += "; Camera2 Extensions: " + (ext.map { names[it] ?: "#$it" }.ifEmpty { listOf("none") }.joinToString(", "))
                }
                lines += line
            }
        }.onFailure { lines += "Camera2: ${it.javaClass.simpleName}: ${it.message}" }
        val pf = ProcessCameraProvider.getInstance(app)
        pf.addListener({
            runCatching {
                val provider = pf.get()
                val ef = ExtensionsManager.getInstanceAsync(app, provider)
                ef.addListener({
                    val all = listOf(ExtensionMode.AUTO to "Auto", ExtensionMode.HDR to "HDR", ExtensionMode.NIGHT to "Night",
                        ExtensionMode.BOKEH to "Bokeh", ExtensionMode.FACE_RETOUCH to "Face retouch")
                    val found = runCatching {
                        val em = ef.get()
                        all.filter { em.isExtensionAvailable(CameraSelector.DEFAULT_BACK_CAMERA, it.first) }
                    }
                    found.onSuccess { f ->
                        lines += "CameraX Extensions on the back camera: " + f.joinToString(", ") { it.second }.ifEmpty { "none" }
                        prefs(app).edit().putString("camera_ext", f.map { it.first }.filter { m -> MODES.any { it.first == m } }.joinToString(",")).apply()
                    }.onFailure { lines += "CameraX Extensions: ${it.javaClass.simpleName}: ${it.message}" }
                    done(lines.joinToString("\n"), found.isSuccess)
                }, main)
            }.onFailure { lines += "CameraX: ${it.javaClass.simpleName}: ${it.message}"; done(lines.joinToString("\n"), false) }
        }, main)
    }

    /** once per app version: what the phone offers goes into the diagnostics log. A probe that failed (CameraX did
     *  not answer) is recorded too, and tried again at the next start until one succeeds and is recorded. */
    fun probeForDiagnostics(ctx: Context) {
        val version = runCatching { ctx.packageManager.getPackageInfo(ctx.packageName, 0).versionName }.getOrNull() ?: "?"
        if (prefs(ctx).getString("camera_probed", "") == version) return
        probe(ctx) { text, ok ->
            kotlin.concurrent.thread {
                val saved = kks.explorer.sync.Diagnostics.record("device", text)
                if (ok && saved) prefs(ctx).edit().putString("camera_probed", version).apply()
            }
        }
    }
}

private val BAR = Color(0xCC000000)

class CameraActivity : ComponentActivity() {
    private var out: Uri? = null
    private var provider: ProcessCameraProvider? = null
    private var extensions: ExtensionsManager? = null
    private var camera: Camera? = null
    private var capture: ImageCapture? = null
    private var preview: Preview? = null
    /** the last rotation the sensor gave (kept for a capture bound later: a mode change binds a new one) */
    private var heldAs: Int? = null
    /** the shot's rotation follows how the phone is held, not the screen (which stays upright when auto-rotate is
     *  off): CameraX's advice for still capture */
    private val held by lazy {
        object : android.view.OrientationEventListener(this) {
            override fun onOrientationChanged(deg: Int) {
                if (deg == ORIENTATION_UNKNOWN) return
                val rot = when (deg) {
                    in 45 until 135 -> android.view.Surface.ROTATION_270
                    in 135 until 225 -> android.view.Surface.ROTATION_180
                    in 225 until 315 -> android.view.Surface.ROTATION_90
                    else -> android.view.Surface.ROTATION_0
                }
                heldAs = rot
                capture?.targetRotation = rot
            }
        }
    }
    private var request by mutableStateOf<SurfaceRequest?>(null)
    private var modes by mutableStateOf(listOf(InAppCamera.STANDARD))
    private var mode by mutableStateOf(InAppCamera.STANDARD)
    private var busy by mutableStateOf(false)
    private var error by mutableStateOf("")
    private var ready by mutableStateOf(false)

    // Back from the camera app returns to this screen; a photo taken there ends it
    private val system = registerForActivityResult(ActivityResultContracts.TakePicture()) { ok ->
        if (ok) { setResult(RESULT_OK, Intent().putExtra(InAppCamera.EXTRA_MODE, -1)); finish() }
    }
    private val ask = registerForActivityResult(ActivityResultContracts.RequestPermission()) { ok ->
        if (ok) start() else { setResult(RESULT_CANCELED); finish() }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(androidx.activity.SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
            androidx.activity.SystemBarStyle.dark(android.graphics.Color.TRANSPARENT))   // (its scrim is drawn below: Android 15 ignores a colour)
        @Suppress("DEPRECATION")
        out = if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(MediaStore.EXTRA_OUTPUT, Uri::class.java) else intent.getParcelableExtra(MediaStore.EXTRA_OUTPUT)
        if (out == null) { setResult(RESULT_CANCELED); finish(); return }
        setContent { MaterialTheme(colorScheme = darkColorScheme()) { Screen() } }
        if (checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) start()
        else if (savedInstanceState == null) ask.launch(Manifest.permission.CAMERA)   // (a recreated screen's request is still open)
    }

    /** a turn by 180° changes no configuration: the preview follows the display itself */
    private val turned = object : android.hardware.display.DisplayManager.DisplayListener {
        override fun onDisplayAdded(id: Int) {}
        override fun onDisplayRemoved(id: Int) {}
        override fun onDisplayChanged(id: Int) {
            @Suppress("DEPRECATION")
            preview?.targetRotation = (if (Build.VERSION.SDK_INT >= 30) display?.rotation else windowManager.defaultDisplay.rotation) ?: return
        }
    }

    override fun onResume() {
        super.onResume()
        if (held.canDetectOrientation()) held.enable()
        getSystemService(android.hardware.display.DisplayManager::class.java).registerDisplayListener(turned, null)
        turned.onDisplayChanged(0)   // (turned while away)
    }
    override fun onPause() {
        held.disable()
        getSystemService(android.hardware.display.DisplayManager::class.java).unregisterDisplayListener(turned)
        super.onPause()
    }

    /** Cancel and Back wait while a shot is being written into the caller's file */
    private fun cancel() { if (!busy) { setResult(RESULT_CANCELED); finish() } }

    /** the screen turned (this activity handles the change itself): the preview follows the display */
    override fun onConfigurationChanged(newConfig: android.content.res.Configuration) {
        super.onConfigurationChanged(newConfig)
        @Suppress("DEPRECATION")
        preview?.targetRotation = (if (Build.VERSION.SDK_INT >= 30) display?.rotation else windowManager.defaultDisplay.rotation) ?: 0
    }

    private fun log(what: String, e: Throwable) = android.util.Log.w("KKS", "camera: $what", e)

    private fun useCameraApp() {
        val o = out ?: return
        runCatching { system.launch(o) }.onFailure { log("camera app", it); error = "The camera app could not be opened on this phone." + if (ready) " Take the photo here instead." else "" }
    }

    private fun start() {
        val main = ContextCompat.getMainExecutor(this)
        val pf = ProcessCameraProvider.getInstance(this)
        pf.addListener({
            val p = runCatching { pf.get() }.getOrElse {
                log("open", it); error = "The camera could not be opened. Use the camera app instead, below."; return@addListener
            }
            provider = p
            val ef = ExtensionsManager.getInstanceAsync(this, p)
            ef.addListener({
                extensions = runCatching { ef.get() }.getOrNull()
                val em = extensions
                modes = listOf(InAppCamera.STANDARD) + InAppCamera.MODES.map { it.first }.filter { m ->
                    em != null && runCatching { em.isExtensionAvailable(CameraSelector.DEFAULT_BACK_CAMERA, m) }.getOrDefault(false)
                }
                // the last one used, else Auto where offered (the maker's own choice of processing), else Standard
                mode = InAppCamera.lastMode(this)?.takeIf { it in modes } ?: if (ExtensionMode.AUTO in modes) ExtensionMode.AUTO else modes.last()
                bind()
            }, main)
        }, main)
    }

    private fun bind(why: String = "") {
        val p = provider ?: return
        ready = false
        error = why
        runCatching {
            p.unbindAll()
            val em = extensions
            val selector = if (mode != InAppCamera.STANDARD && em != null) em.getExtensionEnabledCameraSelector(CameraSelector.DEFAULT_BACK_CAMERA, mode)
                           else CameraSelector.DEFAULT_BACK_CAMERA
            val preview = Preview.Builder().build().also { it.setSurfaceProvider { r -> request = r }; this.preview = it }
            val best = ResolutionSelector.Builder().setResolutionStrategy(ResolutionStrategy.HIGHEST_AVAILABLE_STRATEGY).build()
            capture = ImageCapture.Builder().setCaptureMode(ImageCapture.CAPTURE_MODE_MAXIMIZE_QUALITY).setResolutionSelector(best).build()
                .also { c -> heldAs?.let { c.targetRotation = it } }
            camera = p.bindToLifecycle(this, selector, preview, capture)
            ready = true
        }.onFailure {
            log("bind ${InAppCamera.modeName(mode)}", it)
            if (mode != InAppCamera.STANDARD) {
                val failed = InAppCamera.modeName(mode)
                mode = InAppCamera.STANDARD
                bind("$failed mode did not start on this phone; using Standard.")
            } else error = "The camera could not be started. Use the camera app instead, below."
        }
    }

    private fun shoot() {
        if (busy) return
        val c = capture ?: return
        val target = out ?: return
        val stream = runCatching { contentResolver.openOutputStream(target, "wt") }.getOrNull()
        if (stream == null) { error = "The photo could not be saved. Try again, or use the camera app."; return }
        busy = true
        error = ""
        if (!held.canDetectOrientation()) {   // (no sensor: the screen's rotation)
            @Suppress("DEPRECATION")
            c.targetRotation = (if (Build.VERSION.SDK_INT >= 30) display?.rotation else windowManager.defaultDisplay.rotation) ?: 0
        }
        runCatching { c.takePicture(ImageCapture.OutputFileOptions.Builder(stream).build(), ContextCompat.getMainExecutor(this),
            object : ImageCapture.OnImageSavedCallback {
                override fun onImageSaved(r: ImageCapture.OutputFileResults) {
                    runCatching { stream.close() }
                    InAppCamera.keepMode(this@CameraActivity, mode)
                    setResult(RESULT_OK, Intent().putExtra(InAppCamera.EXTRA_MODE, mode)); finish()
                }
                override fun onError(e: ImageCaptureException) {
                    runCatching { stream.close() }
                    log("shot", e)
                    busy = false
                    error = "The photo was not taken. Try again, or use the camera app."
                }
            }) }.onFailure {
            runCatching { stream.close() }
            log("shot", it)
            busy = false
            error = "The photo was not taken. Try again, or use the camera app."
        }
    }

    private var focusAt by mutableStateOf<androidx.compose.ui.geometry.Offset?>(null)

    private fun focus(x: Float, y: Float) {
        val r = request ?: return
        val pt = SurfaceOrientedMeteringPointFactory(r.resolution.width.toFloat(), r.resolution.height.toFloat()).createPoint(x, y)
        camera?.cameraControl?.startFocusAndMetering(FocusMeteringAction.Builder(pt).build())
    }

    @OptIn(ExperimentalLayoutApi::class)
    @Composable
    private fun Screen() {
        val transform = androidx.compose.runtime.remember { MutableCoordinateTransformer() }
        androidx.activity.compose.BackHandler(enabled = busy) {}   // (Back waits for the shot, as Cancel does)
        Surface(Modifier.fillMaxSize(), color = Color.Black) {
            Box(Modifier.fillMaxSize()) {
                request?.let { r ->
                    CameraXViewfinder(r, Modifier.fillMaxSize().semantics { contentDescription = "Camera preview" }
                        .pointerInput(r) {
                            detectTapGestures { o -> focusAt = o; with(transform) { val p = o.transform(); focus(p.x, p.y) } }
                        }, coordinateTransformer = transform)
                }
                // the navigation bar on its side lies over the preview: a dark scrim under it (Android 15+ draws none)
                Box(Modifier.align(Alignment.CenterStart).fillMaxHeight().windowInsetsStartWidth(WindowInsets.navigationBars).background(BAR))
                Box(Modifier.align(Alignment.CenterEnd).fillMaxHeight().windowInsetsEndWidth(WindowInsets.navigationBars).background(BAR))
                // a ring where the person tapped, for a second: focusing there
                focusAt?.takeIf { ready }?.let { at ->
                    androidx.compose.runtime.LaunchedEffect(at) { kotlinx.coroutines.delay(1000); if (focusAt == at) focusAt = null }
                    val d = androidx.compose.ui.platform.LocalDensity.current
                    Box(Modifier.offset { androidx.compose.ui.unit.IntOffset(at.x.toInt() - with(d) { 32.dp.roundToPx() }, at.y.toInt() - with(d) { 32.dp.roundToPx() }) }
                        .size(64.dp).drawBehind {   // a white ring with black on both sides: seen over a bright scene and a dark one
                            val c = center; val rad = size.minDimension / 2 - 3.dp.toPx()
                            drawCircle(Color.Black, rad, c, style = androidx.compose.ui.graphics.drawscope.Stroke(5.dp.toPx()))
                            drawCircle(Color.White, rad, c, style = androidx.compose.ui.graphics.drawscope.Stroke(2.dp.toPx()))
                        }.clearAndSetSemantics {})
                }
                // the bars are dark enough for white text over the brightest scene (a tag plate in the sun): over white
                // 80 % black leaves #333, 12.6:1 for white; they reach under the system bars, which are dark too
                val onBar = ButtonDefaults.textButtonColors(contentColor = Color.White)
                val live = Modifier.semantics { liveRegion = LiveRegionMode.Polite }
                Row(Modifier.fillMaxWidth().align(Alignment.TopCenter).pointerInput(Unit) {}.background(BAR).windowInsetsPadding(WindowInsets.safeDrawing)
                    .padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(if (ready) "Walkdown camera · ${InAppCamera.modeName(mode)}" else "Opening the camera…", color = Color.White,
                        modifier = Modifier.weight(1f).then(live))
                    TextButton(onClick = { cancel() }, enabled = !busy, colors = onBar) { Text("Cancel") }
                }
                Column(Modifier.fillMaxWidth().align(Alignment.BottomCenter).pointerInput(Unit) {}.background(BAR).windowInsetsPadding(WindowInsets.safeDrawing)
                    .padding(12.dp), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    // one status line, always there, so that what it says next is announced
                    val status = error.ifEmpty { if (busy) "Taking the photo: hold still" else "" }
                    Text(status, color = Color.White, modifier = live)   // (an empty line keeps its height: a node of no size leaves the tree)
                    if (modes.size > 1) FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        for (m in modes) FilterChip(m == mode, { if (m != mode && !busy) { mode = m; bind() } }, enabled = !busy,
                            label = { Text(InAppCamera.modeName(m) + " mode") },
                            leadingIcon = if (m == mode) { { Text("✓", color = Color.White, modifier = Modifier.clearAndSetSemantics {}) } } else null,
                            colors = FilterChipDefaults.filterChipColors(labelColor = Color.White, selectedLabelColor = Color.White,
                                selectedContainerColor = Color(0xFF555555)),
                            border = FilterChipDefaults.filterChipBorder(!busy, m == mode, borderColor = Color.White, selectedBorderColor = Color.White,
                                selectedBorderWidth = 2.dp))
                    }
                    Box(Modifier.size(80.dp), contentAlignment = Alignment.Center) {
                        if (busy) CircularProgressIndicator(Modifier.size(56.dp), color = Color.White)
                        else Button(onClick = { shoot() }, enabled = ready, shape = CircleShape,
                            colors = ButtonDefaults.buttonColors(containerColor = Color.White, contentColor = Color.Black),
                            modifier = Modifier.size(76.dp).border(4.dp, Color(0xFF9E9E9E), CircleShape)
                                .semantics { contentDescription = "Take the photo" }) {}
                    }
                    TextButton(onClick = { useCameraApp() }, enabled = !busy, colors = onBar) { Text("Use the camera app instead") }
                }
            }
        }
    }
}

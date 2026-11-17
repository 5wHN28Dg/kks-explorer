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
import androidx.compose.ui.semantics.contentDescription
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
    fun probe(ctx: Context, done: (String) -> Unit) {
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
                    }.getOrElse { lines += "CameraX Extensions: ${it.javaClass.simpleName}: ${it.message}"; emptyList() }
                    lines += "CameraX Extensions on the back camera: " + found.joinToString(", ") { it.second }.ifEmpty { "none" }
                    prefs(app).edit().putString("camera_ext", found.map { it.first }.filter { m -> MODES.any { it.first == m } }.joinToString(",")).apply()
                    done(lines.joinToString("\n"))
                }, main)
            }.onFailure { lines += "CameraX: ${it.javaClass.simpleName}: ${it.message}"; done(lines.joinToString("\n")) }
        }, main)
    }

    /** once per app version (and when asked): what the phone offers goes into the diagnostics log */
    fun probeForDiagnostics(ctx: Context) {
        val version = runCatching { ctx.packageManager.getPackageInfo(ctx.packageName, 0).versionName }.getOrNull() ?: "?"
        if (prefs(ctx).getString("camera_probed", "") == version) return
        probe(ctx) { text ->
            kotlin.concurrent.thread { kks.explorer.sync.Diagnostics.record("device", text) }
            prefs(ctx).edit().putString("camera_probed", version).apply()
        }
    }
}

class CameraActivity : ComponentActivity() {
    private var out: Uri? = null
    private var provider: ProcessCameraProvider? = null
    private var extensions: ExtensionsManager? = null
    private var camera: Camera? = null
    private var capture: ImageCapture? = null
    private var request by mutableStateOf<SurfaceRequest?>(null)
    private var modes by mutableStateOf(listOf(InAppCamera.STANDARD))
    private var mode by mutableStateOf(InAppCamera.STANDARD)
    private var busy by mutableStateOf(false)
    private var error by mutableStateOf("")
    private var ready by mutableStateOf(false)

    private val system = registerForActivityResult(ActivityResultContracts.TakePicture()) { ok ->
        setResult(if (ok) RESULT_OK else RESULT_CANCELED, Intent().putExtra(InAppCamera.EXTRA_MODE, -1)); finish()
    }
    private val ask = registerForActivityResult(ActivityResultContracts.RequestPermission()) { ok ->
        if (ok) start() else { setResult(RESULT_CANCELED); finish() }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        @Suppress("DEPRECATION")
        out = if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(MediaStore.EXTRA_OUTPUT, Uri::class.java) else intent.getParcelableExtra(MediaStore.EXTRA_OUTPUT)
        if (out == null) { setResult(RESULT_CANCELED); finish(); return }
        setContent { MaterialTheme(colorScheme = darkColorScheme()) { Screen() } }
        if (checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) start() else ask.launch(Manifest.permission.CAMERA)
    }

    private fun useCameraApp() { out?.let { system.launch(it) } }

    private fun start() {
        val main = ContextCompat.getMainExecutor(this)
        val pf = ProcessCameraProvider.getInstance(this)
        pf.addListener({
            val p = runCatching { pf.get() }.getOrElse { error = "The camera could not be opened (${it.message})."; return@addListener }
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

    private fun bind() {
        val p = provider ?: return
        ready = false
        error = ""
        runCatching {
            p.unbindAll()
            val em = extensions
            val selector = if (mode != InAppCamera.STANDARD && em != null) em.getExtensionEnabledCameraSelector(CameraSelector.DEFAULT_BACK_CAMERA, mode)
                           else CameraSelector.DEFAULT_BACK_CAMERA
            val preview = Preview.Builder().build().also { it.setSurfaceProvider { r -> request = r } }
            val best = ResolutionSelector.Builder().setResolutionStrategy(ResolutionStrategy.HIGHEST_AVAILABLE_STRATEGY).build()
            capture = ImageCapture.Builder().setCaptureMode(ImageCapture.CAPTURE_MODE_MAXIMIZE_QUALITY).setResolutionSelector(best).build()
            camera = p.bindToLifecycle(this, selector, preview, capture)
            ready = true
        }.onFailure {
            error = "The camera could not start in ${InAppCamera.modeName(mode)} mode (${it.message})."
            if (mode != InAppCamera.STANDARD) { mode = InAppCamera.STANDARD; bind() }
        }
    }

    private fun shoot() {
        val c = capture ?: return
        val target = out ?: return
        val stream = runCatching { contentResolver.openOutputStream(target, "wt") }.getOrNull()
        if (stream == null) { error = "The photo could not be written."; return }
        busy = true
        @Suppress("DEPRECATION")
        c.targetRotation = (if (Build.VERSION.SDK_INT >= 30) display?.rotation else windowManager.defaultDisplay.rotation) ?: 0
        c.takePicture(ImageCapture.OutputFileOptions.Builder(stream).build(), ContextCompat.getMainExecutor(this),
            object : ImageCapture.OnImageSavedCallback {
                override fun onImageSaved(r: ImageCapture.OutputFileResults) {
                    runCatching { stream.close() }
                    InAppCamera.keepMode(this@CameraActivity, mode)
                    setResult(RESULT_OK, Intent().putExtra(InAppCamera.EXTRA_MODE, mode)); finish()
                }
                override fun onError(e: ImageCaptureException) {
                    runCatching { stream.close() }
                    busy = false
                    error = "The photo was not taken (${e.message}). Try again, or use the camera app."
                }
            })
    }

    private fun focus(x: Float, y: Float) {
        val r = request ?: return
        val pt = SurfaceOrientedMeteringPointFactory(r.resolution.width.toFloat(), r.resolution.height.toFloat()).createPoint(x, y)
        camera?.cameraControl?.startFocusAndMetering(FocusMeteringAction.Builder(pt).build())
    }

    @OptIn(ExperimentalLayoutApi::class)
    @Composable
    private fun Screen() {
        val transform = androidx.compose.runtime.remember { MutableCoordinateTransformer() }
        Surface(Modifier.fillMaxSize(), color = Color.Black) {
            Box(Modifier.fillMaxSize()) {
                request?.let { r ->
                    CameraXViewfinder(r, Modifier.fillMaxSize().semantics { contentDescription = "Camera preview: tap to focus there" }
                        .pointerInput(r) {
                            detectTapGestures { o -> with(transform) { val p = o.transform(); focus(p.x, p.y) } }
                        }, coordinateTransformer = transform)
                }
                Row(Modifier.fillMaxWidth().align(Alignment.TopCenter).windowInsetsPadding(WindowInsets.safeDrawing)
                    .background(Color(0x99000000)).padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(if (ready) "Walkdown camera · ${InAppCamera.modeName(mode)}" else "Opening the camera…", color = Color.White, modifier = Modifier.weight(1f))
                    TextButton(onClick = { setResult(RESULT_CANCELED); finish() }) { Text("Cancel") }
                }
                Column(Modifier.fillMaxWidth().align(Alignment.BottomCenter).windowInsetsPadding(WindowInsets.safeDrawing)
                    .background(Color(0x99000000)).padding(12.dp), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (error.isNotEmpty()) Text(error, color = Color.White)
                    if (modes.size > 1) FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        for (m in modes) FilterChip(m == mode, { if (m != mode && !busy) { mode = m; bind() } }, label = { Text(InAppCamera.modeName(m)) },
                            modifier = Modifier.semantics { contentDescription = InAppCamera.modeName(m) + " mode" + if (m == mode) ", chosen" else "" })
                    }
                    Box(Modifier.size(80.dp), contentAlignment = Alignment.Center) {
                        if (busy) CircularProgressIndicator(Modifier.size(56.dp), color = Color.White)
                        else Button(onClick = { shoot() }, enabled = ready, shape = CircleShape,
                            colors = ButtonDefaults.buttonColors(containerColor = Color.White, contentColor = Color.Black),
                            modifier = Modifier.size(76.dp).border(4.dp, Color(0xFF9E9E9E), CircleShape)
                                .semantics { contentDescription = "Take the photo" }) {}
                    }
                    if (busy) Text("Taking the photo: hold still", color = Color.White)
                    TextButton(onClick = { useCameraApp() }, enabled = !busy) { Text("Use the camera app instead") }
                }
            }
        }
    }
}

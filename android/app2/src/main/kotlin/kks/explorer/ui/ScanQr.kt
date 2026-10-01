package kks.explorer.ui

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.ImageFormat
import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.media.ImageReader
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.util.Size
import android.view.Gravity
import android.view.Surface
import android.view.TextureView
import android.widget.FrameLayout
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContract
import kks.explorer.Qr
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Scan an invite QR code (R13): the platform's Camera2 preview, grayscale frames (the Y plane) read by zxing-cpp.
 * No camera library (decision 0032: Camera2 is enough for a preview and frames). Returns the text, or null.
 */
object ScanQr {
    class Contract : ActivityResultContract<Unit, String?>() {
        override fun createIntent(context: Context, input: Unit) = Intent(context, ScanActivity::class.java)
        override fun parseResult(resultCode: Int, intent: Intent?) = if (resultCode == Activity.RESULT_OK) intent?.getStringExtra("text") else null
    }
}

class ScanActivity : ComponentActivity() {
    private lateinit var preview: TextureView
    private lateinit var hint: TextView
    private val thread = HandlerThread("kks-scan").apply { start() }
    private val bg = Handler(thread.looper)
    private var camera: CameraDevice? = null
    private var reader: ImageReader? = null
    private val found = AtomicBoolean(false)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        preview = TextureView(this)
        hint = TextView(this).apply {
            text = "Point the camera at the QR code on the admin's screen"
            setTextColor(-1); setBackgroundColor(0x99000000.toInt()); setPadding(32, 24, 32, 24); gravity = Gravity.CENTER
        }
        setContentView(FrameLayout(this).apply {
            addView(preview)
            addView(hint, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.BOTTOM))
        })
        if (checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) whenReady()
        else ask.launch(Manifest.permission.CAMERA)
    }

    private val ask = registerForActivityResult(androidx.activity.result.contract.ActivityResultContracts.RequestPermission()) { ok ->
        if (ok) whenReady()
        else { hint.text = "Without the camera, paste the invite's text instead."; preview.postDelayed({ finish() }, 2000) }
    }

    private fun whenReady() {
        if (preview.isAvailable) open() else preview.surfaceTextureListener = object : TextureView.SurfaceTextureListener {
            override fun onSurfaceTextureAvailable(s: SurfaceTexture, w: Int, h: Int) = open()
            override fun onSurfaceTextureSizeChanged(s: SurfaceTexture, w: Int, h: Int) {}
            override fun onSurfaceTextureDestroyed(s: SurfaceTexture) = true
            override fun onSurfaceTextureUpdated(s: SurfaceTexture) {}
        }
    }

    @SuppressLint("MissingPermission")   // checked in onCreate / onRequestPermissionsResult
    private fun open() {
        val cm = getSystemService(CameraManager::class.java)
        val id = cm.cameraIdList.firstOrNull { cm.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK }
            ?: cm.cameraIdList.firstOrNull() ?: run { hint.text = "This device has no camera."; return }
        val map = cm.getCameraCharacteristics(id).get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP) ?: return
        // frames of about 1280×720: enough for a phone-sized QR at arm's length, light on the decoder
        val size = map.getOutputSizes(ImageFormat.YUV_420_888).minByOrNull { Math.abs(it.width * it.height - 1280 * 720) } ?: Size(640, 480)
        val r = ImageReader.newInstance(size.width, size.height, ImageFormat.YUV_420_888, 2)
        reader = r
        r.setOnImageAvailableListener({ ir ->
            val img = ir.acquireLatestImage() ?: return@setOnImageAvailableListener
            try {
                if (found.get()) return@setOnImageAvailableListener
                val y = img.planes[0]
                val buf = y.buffer
                val bytes = ByteArray(buf.remaining()).also { buf.get(it) }
                val text = Qr.read(bytes, img.width, img.height, y.rowStride)
                if (text != null && found.compareAndSet(false, true)) runOnUiThread {
                    setResult(Activity.RESULT_OK, Intent().putExtra("text", text)); finish()
                }
            } finally { img.close() }
        }, bg)
        cm.openCamera(id, object : CameraDevice.StateCallback() {
            override fun onOpened(c: CameraDevice) {
                camera = c
                val tex = preview.surfaceTexture ?: return
                tex.setDefaultBufferSize(size.width, size.height)
                val view = Surface(tex)
                @Suppress("DEPRECATION")
                c.createCaptureSession(listOf(view, r.surface), object : CameraCaptureSession.StateCallback() {
                    override fun onConfigured(s: CameraCaptureSession) {
                        val req = c.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply {
                            addTarget(view); addTarget(r.surface)
                            set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
                        }
                        runCatching { s.setRepeatingRequest(req.build(), null, bg) }
                    }
                    override fun onConfigureFailed(s: CameraCaptureSession) { runOnUiThread { hint.text = "The camera could not start." } }
                }, bg)
            }
            override fun onDisconnected(c: CameraDevice) { c.close() }
            override fun onError(c: CameraDevice, e: Int) { c.close(); runOnUiThread { hint.text = "The camera could not start ($e)." } }
        }, bg)
    }

    override fun onDestroy() {
        camera?.close(); reader?.close(); thread.quitSafely()
        super.onDestroy()
    }
}

package kks.explorer

import android.app.Activity
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.media.ExifInterface
import android.net.Uri
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContract
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import kks.explorer.ui.CameraActivity
import kks.explorer.ui.InAppCamera
import kks.explorer.ui.orientedBitmap
import java.io.File

/**
 * The camera trial (decision 0075), only in the `camtest` build ("Walkdown camera test", its own application ID):
 * the same scene taken with Walkdown's own camera and with the phone's camera app, each kept twice in
 * Downloads/Walkdown camera test: the full picture as the camera wrote it, and the photo as Walkdown would store it
 * (2560 px, Lanczos, JPEG XL d1.9 e7; decision 0074), with a text file of what each one is. No server, no account.
 */
class CamTestActivity : ComponentActivity() {
    private val folder = Environment.DIRECTORY_DOWNLOADS + "/Walkdown camera test"
    private var phone by mutableStateOf("Looking at the camera…")
    private var working by mutableStateOf("")
    private val done = mutableStateListOf<String>()
    private val saved = mutableListOf<Uri>()
    private lateinit var shot: File
    private lateinit var shotUri: Uri

    /** Walkdown's camera, told to write to the Uri; the result says which mode it used (-1: it sent the person to
     *  the camera app) */
    private class Ours : ActivityResultContract<Uri, Int?>() {
        override fun createIntent(context: Context, input: Uri) =
            Intent(context, CameraActivity::class.java).putExtra(MediaStore.EXTRA_OUTPUT, input)
        override fun parseResult(resultCode: Int, intent: Intent?) =
            if (resultCode == Activity.RESULT_OK) intent?.getIntExtra(InAppCamera.EXTRA_MODE, InAppCamera.STANDARD) else null
    }
    private val ours = registerForActivityResult(Ours()) { mode ->
        if (mode != null) keep(if (mode < 0) "camera-app" else "walkdown-" + InAppCamera.modeName(mode).lowercase())
    }
    private val system = registerForActivityResult(ActivityResultContracts.TakePicture()) { ok -> if (ok) keep("camera-app") }
    private val ask = registerForActivityResult(ActivityResultContracts.RequestPermission()) {}

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        shot = File(cacheDir, "camera/test.jpg").also { it.parentFile?.mkdirs() }
        shotUri = FileProvider.getUriForFile(this, "$packageName.files", shot)
        if (checkSelfPermission(android.Manifest.permission.CAMERA) != android.content.pm.PackageManager.PERMISSION_GRANTED)
            ask.launch(android.Manifest.permission.CAMERA)
        InAppCamera.probe(this) { text ->
            phone = text
            if (!getSharedPreferences("camtest", MODE_PRIVATE).getBoolean("phone_saved", false)) {
                kotlin.concurrent.thread {
                    write("00-phone.txt", "text/plain", (text + "\n").toByteArray())
                    getSharedPreferences("camtest", MODE_PRIVATE).edit().putBoolean("phone_saved", true).apply()
                }
            }
        }
        setContent {
            MaterialTheme(colorScheme = if (isSystemInDarkTheme()) darkColorScheme() else lightColorScheme()) {
                Surface(Modifier.fillMaxSize()) { Screen() }
            }
        }
    }

    private fun next(): Int {
        val p = getSharedPreferences("camtest", MODE_PRIVATE)
        val n = p.getInt("n", 0) + 1
        p.edit().putInt("n", n).apply()
        return n
    }

    /** a file in Downloads/Walkdown camera test (MediaStore: no permission needed); null if it could not be written */
    private fun write(name: String, mime: String, bytes: ByteArray): Uri? {
        val v = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, folder)
        }
        val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, v) ?: return null
        contentResolver.openOutputStream(uri)?.use { it.write(bytes) } ?: return null
        synchronized(saved) { saved += uri }
        return uri
    }

    private fun keep(how: String) {
        working = "Saving the photo ($how)…"
        kotlin.concurrent.thread {
            val msg = runCatching {
                val raw = shot.readBytes()
                val n = "%02d".format(next())
                val base = "$n-$how"
                write("$base-original.jpg", "image/jpeg", raw)
                val ex = runCatching { ExifInterface(raw.inputStream()) }.getOrNull()
                fun t(tag: String) = ex?.getAttribute(tag) ?: "?"
                val opts = android.graphics.BitmapFactory.Options().apply { inJustDecodeBounds = true }
                android.graphics.BitmapFactory.decodeByteArray(raw, 0, raw.size, opts)
                val t0 = System.nanoTime()
                val bmp = orientedBitmap(raw) ?: error("the picture could not be read")
                val t1 = System.nanoTime()
                val jxl = Jxl.fromBitmap(bmp)
                val t2 = System.nanoTime()
                write("$base-stored-${bmp.width}.jxl", "application/octet-stream", jxl)
                val info = """
                    |$base
                    |taken with: ${if (how == "camera-app") "the phone's camera app (through the request other apps use)" else "Walkdown's camera, ${how.removePrefix("walkdown-")} mode"}
                    |original: ${opts.outWidth} x ${opts.outHeight} px, ${raw.size / 1024} KB; EXIF orientation ${t(ExifInterface.TAG_ORIENTATION)}
                    |EXIF: make ${t(ExifInterface.TAG_MAKE)}, model ${t(ExifInterface.TAG_MODEL)}, software ${t(ExifInterface.TAG_SOFTWARE)},
                    |      ISO ${t(ExifInterface.TAG_ISO_SPEED_RATINGS)}, exposure ${t(ExifInterface.TAG_EXPOSURE_TIME)} s, f/${t(ExifInterface.TAG_F_NUMBER)}, focal length ${t(ExifInterface.TAG_FOCAL_LENGTH)}
                    |stored: ${bmp.width} x ${bmp.height} px, ${jxl.size / 1024} KB JPEG XL; scaling ${(t1 - t0) / 1_000_000} ms, encoding ${(t2 - t1) / 1_000_000} ms
                    |""".trimMargin()
                write("$base-info.txt", "text/plain", info.toByteArray())
                shot.delete()
                "$base: ${opts.outWidth} x ${opts.outHeight} px (${raw.size / 1024} KB) → ${bmp.width} x ${bmp.height} px (${jxl.size / 1024} KB)"
            }.getOrElse { "Not saved: ${it.message}" }
            runOnUiThread { done.add(0, msg); working = "" }
        }
    }

    private fun shareAll() {
        val list = synchronized(saved) { ArrayList(saved) }
        if (list.isEmpty()) return
        val send = Intent(Intent.ACTION_SEND_MULTIPLE).setType("*/*").putParcelableArrayListExtra(Intent.EXTRA_STREAM, list)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        startActivity(Intent.createChooser(send, "Send the test photos"))
    }

    @androidx.compose.runtime.Composable
    private fun Screen() {
        Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing).verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Walkdown camera test", style = MaterialTheme.typography.headlineSmall)
            Text("Photograph the same tag plate both ways, from the same spot: once with each button. In Walkdown's camera, " +
                 "take one in each mode it shows. Each photo is kept in Downloads › Walkdown camera test, as the camera " +
                 "took it and as Walkdown would store it. This test app is separate from Walkdown: it has no account and " +
                 "sends nothing by itself.")
            Button(onClick = { ours.launch(shotUri) }, enabled = working.isEmpty(), modifier = Modifier.fillMaxWidth()) { Text("Take with Walkdown's camera") }
            OutlinedButton(onClick = { system.launch(shotUri) }, enabled = working.isEmpty(), modifier = Modifier.fillMaxWidth()) { Text("Take with the camera app") }
            if (working.isNotEmpty()) { Text(working); LinearProgressIndicator(Modifier.fillMaxWidth()) }
            OutlinedButton(onClick = { shareAll() }, enabled = done.isNotEmpty() && working.isEmpty(), modifier = Modifier.fillMaxWidth()) {
                Text("Send the files taken now")
            }
            for (d in done) Text(d, style = MaterialTheme.typography.bodyMedium)
            Text("What this phone's camera offers", style = MaterialTheme.typography.titleMedium)
            Text(phone, style = MaterialTheme.typography.bodySmall)
        }
    }
}

package kks.explorer

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebView
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.FileProvider
import com.journeyapps.barcodescanner.ScanContract
import com.journeyapps.barcodescanner.ScanOptions
import java.io.File
import java.util.concurrent.Executors

/** What the native screens show, refreshed from the local API whenever the log changes. */
class ShellState {
    var joined by mutableStateOf(false)
    var fullName by mutableStateOf("")
    var username by mutableStateOf("")
    var role by mutableStateOf("")
    var plant by mutableStateOf("")
    var queue by mutableIntStateOf(0)
    var device by mutableStateOf("")
    var syncs by mutableStateOf<List<Map<String, Any?>>>(emptyList())
    var discovery by mutableStateOf("")
    var found by mutableStateOf<List<String>>(emptyList())
    var syncPort by mutableStateOf<Long?>(null)
    var meteredAllowed by mutableStateOf(false)
    var paused by mutableStateOf(false)             // automatic sync paused: metered network, not allowed
    var tab by mutableIntStateOf(0)                 // 0 P&ID, 1 Learning, 2 Account & settings
    var manage by mutableStateOf<String?>(null)     // an admin.html section shown full screen, or null
    var busy by mutableStateOf(false)
    var message by mutableStateOf<String?>(null)
}

class MainActivity : ComponentActivity() {
    val state = ShellState()
    lateinit var host: WebHost
    lateinit var pidWeb: WebView                    // the P&ID viewer: one instance, kept across tab switches
    lateinit var manageWeb: WebView                 // admin.html sections (Approvals, Users, …)
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var fileCallback: ValueCallback<Array<Uri>>? = null
    private var cameraUri: Uri? = null
    private var pendingSave: Pair<ByteArray, WebView>? = null

    private val pick = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { r ->
        val picked = WebChromeClient.FileChooserParams.parseResult(r.resultCode, r.data)
        val cam = cameraUri?.takeIf { r.resultCode == RESULT_OK && picked == null && File(cacheDir, "camera/${it.lastPathSegment}").length() > 0 }
        fileCallback?.onReceiveValue(picked ?: cam?.let { arrayOf(it) })
        fileCallback = null
    }

    private val saveDoc = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { r ->
        val (bytes, web) = pendingSave ?: return@registerForActivityResult
        pendingSave = null
        val uri = r.data?.data
        if (r.resultCode == RESULT_OK && uri != null) io.execute {
            runCatching { contentResolver.openOutputStream(uri)!!.use { it.write(bytes) } }
                .onSuccess { host.toast(web, "Saved") }.onFailure { host.toast(web, "Could not save: ${it.message}") }
        }
    }

    private var scanDone: ((String?) -> Unit)? = null
    private val scan = registerForActivityResult(ScanContract()) { r -> scanDone?.invoke(r.contents); scanDone = null }

    /** Scan a QR code with the camera (join by invite). -> its text, or null if cancelled. */
    fun scanQr(done: (String?) -> Unit) {
        scanDone?.invoke(null)
        scanDone = done
        scan.launch(ScanOptions().setDesiredBarcodeFormats(ScanOptions.QR_CODE).setPrompt("Scan the admin's QR code")
            .setBeepEnabled(false).setOrientationLocked(false))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        App.start(this)
        host = WebHost(this)
        pidWeb = host.make { url ->          // the viewer's "Manage" links open the native Manage screen instead
            if (url.path == "/admin.html") { openManage(url.fragment ?: "account"); true } else false
        }
        manageWeb = host.make { url ->       // admin.html's "← Drawings" goes back to the P&ID tab
            if (url.path == "/" || url.path == "/index.html") { state.manage = null; state.tab = 0; true } else false
        }
        pidWeb.loadUrl("https://${WebHost.HOST}/")
        App.node.listeners.add(onChange)
        refresh()
        setContent { Shell(this) }
    }

    private val onChange: (String) -> Unit = { changed() }

    override fun onDestroy() {
        App.node.listeners.remove(onChange)      // (an activity recreated on rotation must not leave its listener behind)
        super.onDestroy()
    }

    override fun onStart() {
        super.onStart()
        App.visible = true
        App.sync.start()          // find devices and sync while the app is on screen
        refresh()
    }

    override fun onStop() {
        super.onStop()
        App.visible = false
        App.sync.stop()           // the background job takes over (every 15 min on Wi-Fi)
    }

    fun openManage(section: String) {
        state.manage = section
        manageWeb.loadUrl("https://${WebHost.HOST}/admin.html#$section")
    }

    /** The log or the account changed (here or by sync): refresh the native screens. */
    fun changed() = main.post { refresh() }

    @Suppress("UNCHECKED_CAST")
    fun refresh() = io.execute {
        val api = App.api
        val cfg = api.handle("GET", "/api/config", emptyMap(), null).json as Map<String, Any?>
        val node = cfg["node"] as Map<String, Any?>
        val joined = node["joined"] == true
        val me = if (joined) api.handle("GET", "/api/me", emptyMap(), null).json as Map<String, Any?> else null
        val st = if (joined) api.handle("GET", "/api/state", emptyMap(), null).json as Map<String, Any?> else null
        val dev = if (joined) api.handle("GET", "/api/devices", emptyMap(), null).json as Map<String, Any?> else null
        main.post {
            val wasJoined = state.joined
            state.joined = joined
            state.plant = (cfg["plant_name"] as String?) ?: ""
            state.device = (node["device"] as String?) ?: ""
            (me?.get("user") as Map<String, Any?>?)?.let {
                state.fullName = it["full_name"] as String? ?: ""; state.username = it["username"] as String? ?: ""; state.role = it["role"] as String? ?: ""
            }
            state.queue = ((st?.get("queue") as Long?) ?: 0L).toInt()
            (dev?.get("sync") as Map<String, Any?>?)?.let { s ->
                state.syncs = ((s["syncs"] as Map<String, Map<String, Any?>>?) ?: emptyMap()).values.sortedByDescending { (it["at"] as Long?) ?: 0 }
                state.discovery = s["discovery"] as String? ?: ""
                state.found = ((s["found"] as List<Map<String, Any?>>?) ?: emptyList()).map { (it["name"] as String?) ?: "${it["host"]}" }
                state.meteredAllowed = s["metered_allowed"] == true
                state.paused = s["paused"] == true
            }
            state.syncPort = dev?.get("sync_port") as Long?
            if (joined && !wasJoined) state.tab = 0
        }
    }

    fun setMetered(on: Boolean) {
        state.meteredAllowed = on
        io.execute { App.setMeteredAllowed(this, on); refresh() }
    }

    fun syncNow(address: String?) {
        state.busy = true; state.message = null
        io.execute {
            val r = App.api.handle("POST", "/api/sync/now", emptyMap(), mapOf("address" to (address ?: "")))
            @Suppress("UNCHECKED_CAST")
            val msg = if (r.status < 400) {
                val res = (r.json as Map<String, Any?>)["result"] as Map<String, Any?>?
                if (res != null) "Synced: received ${res["received"]}, sent ${res["sent"]}" + (if (res["they_denied"] == true) " (that device doesn't know this phone yet)" else "")
                else "Synced with the devices this phone knows"
            } else (r.json as Map<*, *>)["error"].toString()
            main.post { state.busy = false; state.message = msg; refresh() }
        }
    }

    // ---------- pickers for the web pages ----------
    /** "+ Add photo" and file inputs: the camera or the gallery / files, whichever the person picks. */
    fun chooseFile(cb: ValueCallback<Array<Uri>>, params: WebChromeClient.FileChooserParams): Boolean {
        fileCallback?.onReceiveValue(null)
        fileCallback = cb
        cameraUri = null
        val chooser = Intent.createChooser(params.createIntent(), null)
        if (params.acceptTypes.any { it.startsWith("image") }) {
            val f = File(cacheDir, "camera/photo-${System.currentTimeMillis()}.jpg").also { it.parentFile!!.mkdirs() }
            cameraUri = FileProvider.getUriForFile(this, "kks.explorer.files", f)
            val cam = Intent(MediaStore.ACTION_IMAGE_CAPTURE).putExtra(MediaStore.EXTRA_OUTPUT, cameraUri)
                .addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION)
            chooser.putExtra(Intent.EXTRA_INITIAL_INTENTS, arrayOf(cam))
        }
        return try { pick.launch(chooser); true } catch (e: Exception) { fileCallback = null; false }
    }

    fun save(name: String, mime: String, bytes: ByteArray, web: WebView) {
        pendingSave = bytes to web
        saveDoc.launch(Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType(mime).putExtra(Intent.EXTRA_TITLE, name))
    }
}

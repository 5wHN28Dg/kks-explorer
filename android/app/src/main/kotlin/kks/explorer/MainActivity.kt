package kks.explorer

import android.app.Activity
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.WindowInsets
import android.webkit.JavascriptInterface
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import kks.core.Json
import kks.core.LocalApi
import kks.core.LocalNode
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.util.concurrent.Executors
import java.util.zip.GZIPInputStream

/** One node + API per process (they outlive the activity across rotations). */
object App {
    lateinit var node: LocalNode
    lateinit var api: LocalApi
    lateinit var sync: PhoneSync
    lateinit var store: SqliteStore

    @Synchronized fun start(a: Activity) {
        if (::node.isInitialized) return
        store = SqliteStore(a.applicationContext)
        node = LocalNode.open(store)
        sync = PhoneSync(node).also { it.listen() }
        api = LocalApi(node, sync).also { it.deviceLabel = "${Build.MANUFACTURER} ${Build.MODEL}".trim().take(80) }
    }
}

/**
 * The P&ID viewer (the same index.html / admin.html as on laptops) in a WebView at the private origin
 * https://kks.app/. Pages, drawings and photos are answered from the app itself (no network, no open port); API calls
 * go through the KKSNative bridge (WebView doesn't hand POST bodies to the app); files open and save through
 * Android's own pickers.
 */
class MainActivity : Activity() {
    private val host = "kks.app"
    private lateinit var web: WebView
    private val io = Executors.newFixedThreadPool(4)
    private val main = Handler(Looper.getMainLooper())
    private var fileCallback: ValueCallback<Array<Uri>>? = null
    private var pendingSave: ByteArray? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        App.start(this)
        if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) WebView.setWebContentsDebuggingEnabled(true)
        web = WebView(this)
        // Android 15+ draws apps behind the status and navigation bars: keep the page clear of them (and of the keyboard).
        // The padding goes on a frame around the WebView (a WebView ignores its own padding).
        val frame = android.widget.FrameLayout(this).apply { setBackgroundColor(0xff1c2730.toInt()); addView(web) }
        setContentView(frame)
        frame.setOnApplyWindowInsetsListener { v, insets ->
            if (Build.VERSION.SDK_INT >= 30) {
                val bars = insets.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout())
                val ime = insets.getInsets(WindowInsets.Type.ime())
                v.setPadding(bars.left, bars.top, bars.right, maxOf(bars.bottom, ime.bottom))
            } else {
                @Suppress("DEPRECATION")
                v.setPadding(insets.systemWindowInsetLeft, insets.systemWindowInsetTop, insets.systemWindowInsetRight, insets.systemWindowInsetBottom)
            }
            insets
        }
        web.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true          // common.js: IndexedDB / localStorage
            allowFileAccess = false
            allowContentAccess = false
        }
        web.addJavascriptInterface(Bridge(), "KKSNative")
        web.webViewClient = object : WebViewClient() {
            override fun shouldInterceptRequest(view: WebView, req: WebResourceRequest): WebResourceResponse? =
                if (req.url.host == host) serve(req) else notFound()      // nothing is fetched from the internet

            override fun shouldOverrideUrlLoading(view: WebView, req: WebResourceRequest): Boolean {
                if (req.url.host == host) return false
                runCatching { startActivity(Intent(Intent.ACTION_VIEW, req.url)) }
                return true
            }
        }
        web.webChromeClient = object : WebChromeClient() {
            override fun onShowFileChooser(view: WebView, cb: ValueCallback<Array<Uri>>, params: FileChooserParams): Boolean {
                fileCallback?.onReceiveValue(null)
                fileCallback = cb
                return try { startActivityForResult(params.createIntent(), PICK); true } catch (e: Exception) { fileCallback = null; false }
            }
        }
        if (savedInstanceState != null) web.restoreState(savedInstanceState) else web.loadUrl("https://$host/")
    }

    override fun onSaveInstanceState(out: Bundle) { super.onSaveInstanceState(out); web.saveState(out) }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() { if (web.canGoBack()) web.goBack() else super.onBackPressed() }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            PICK -> { fileCallback?.onReceiveValue(WebChromeClient.FileChooserParams.parseResult(resultCode, data)); fileCallback = null }
            SAVE -> {
                val bytes = pendingSave; pendingSave = null
                val uri = data?.data
                if (resultCode == RESULT_OK && uri != null && bytes != null) io.execute {
                    runCatching { contentResolver.openOutputStream(uri)!!.use { it.write(bytes) } }
                        .onSuccess { toast("Saved") }.onFailure { toast("Could not save: ${it.message}") }
                }
            }
        }
    }

    private fun toast(msg: String) = main.post { web.evaluateJavascript("window.K&&K.toast&&K.toast(${JSONObject.quote(msg)})", null) }

    // ---------- the app's own origin ----------
    private fun notFound() = WebResourceResponse("text/plain", "utf-8", 404, "Not Found", emptyMap(), ByteArrayInputStream(ByteArray(0)))

    private fun ok(type: String, data: ByteArray, cache: String = "no-cache") =
        WebResourceResponse(type, if (type.startsWith("text/") || type.endsWith("json") || type.endsWith("javascript")) "utf-8" else null,
                            200, "OK", mapOf("Cache-Control" to cache), ByteArrayInputStream(data))

    private fun asset(path: String): ByteArray? = runCatching { assets.open(path).use { it.readBytes() } }.getOrNull()

    private fun type(path: String) = when (path.substringAfterLast('.', "")) {
        "html" -> "text/html"; "js" -> "text/javascript"; "json" -> "application/json"; "svg" -> "image/svg+xml"
        "png" -> "image/png"; "jpg", "jpeg" -> "image/jpeg"; "webp" -> "image/webp"; "jxl" -> "image/jxl"
        "webmanifest" -> "application/manifest+json"; else -> "application/octet-stream"
    }

    private fun serve(req: WebResourceRequest): WebResourceResponse {
        val path = req.url.path ?: "/"
        if (path.startsWith("/api/")) {           // GETs from links and images; JSON calls come through the bridge
            val q = req.url.queryParameterNames.associateWith { req.url.getQueryParameter(it) ?: "" }
            val r = App.api.handle(req.method, path, q, null)
            val body = r.bytes ?: Json.write(r.json).toByteArray()
            return WebResourceResponse(r.contentType, null, r.status, if (r.status < 400) "OK" else "Error",
                                       r.headers + ("Cache-Control" to "no-store"), ByteArrayInputStream(body))
        }
        if (path.startsWith("/photos/")) {
            val f = App.store.photoFile(path.removePrefix("/photos/")) ?: return notFound()
            return ok(type(f.name), f.readBytes(), "private, max-age=31536000, immutable")
        }
        val file = when (path) {
            "/", "/index.html" -> "index.html"
            "/admin.html", "/common.js", "/manifest.webmanifest", "/icon.svg", "/icon-192.png", "/icon-512.png" -> path.removePrefix("/")
            else -> if (path.startsWith("/data/") && ".." !in path) path.removePrefix("/") else return notFound()   // (no sw.js: nothing to cache)
        }
        asset(file)?.let { return ok(type(file), it) }
        if (file.endsWith(".svg")) asset("$file.gz")?.let { gz -> return ok("image/svg+xml", GZIPInputStream(gz.inputStream()).readBytes()) }
        return notFound()
    }

    // ---------- the bridge (window.KKSNative), used by common.js ----------
    inner class Bridge {
        private fun reply(id: String, status: Int, text: String) = main.post {
            web.evaluateJavascript("K.nativeReply(${JSONObject.quote(id)},$status,${JSONObject.quote(text)})", null)
        }

        @JavascriptInterface fun request(id: String, method: String, url: String, body: String?) = io.execute {
            val u = Uri.parse("https://$host$url")
            val q = u.queryParameterNames.associateWith { u.getQueryParameter(it) ?: "" }
            val r = runCatching { App.api.handle(method, u.path ?: "/", q, body?.let { Json.parse(it) }) }
                .getOrElse { kks.core.ApiResponse(500, mapOf("error" to "internal error: ${it.message}")) }
            reply(id, r.status, if (r.bytes != null) "{}" else Json.write(r.json))
        }

        @JavascriptInterface fun requestBytes(id: String, url: String, base64: String) = io.execute {
            val bytes = android.util.Base64.decode(base64, android.util.Base64.DEFAULT)
            val r = runCatching { App.api.handle("POST", url, emptyMap(), bytes) }
                .getOrElse { kks.core.ApiResponse(500, mapOf("error" to "internal error: ${it.message}")) }
            reply(id, r.status, Json.write(r.json))
        }

        /** Save text (a join request) or a GET API result (a bundle) where the person chooses. */
        @JavascriptInterface fun saveFile(name: String, mime: String, text: String) = main.post { save(name, mime, text.toByteArray()) }

        @JavascriptInterface fun saveApi(name: String, url: String) = io.execute {
            val u = Uri.parse("https://$host$url")
            val r = App.api.handle("GET", u.path ?: "/", u.queryParameterNames.associateWith { u.getQueryParameter(it) ?: "" }, null)
            if (r.bytes == null) { toast((r.json as? Map<*, *>)?.get("error")?.toString() ?: "failed"); return@execute }
            val fname = Regex("filename=\"([^\"]+)\"").find(r.headers["Content-Disposition"] ?: "")?.groupValues?.get(1) ?: name
            main.post { save(fname, r.contentType, r.bytes!!) }
        }

        @JavascriptInterface fun platform() = "android"
    }

    private fun save(name: String, mime: String, bytes: ByteArray) {
        pendingSave = bytes
        startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE)
            .setType(mime).putExtra(Intent.EXTRA_TITLE, name), SAVE)
    }

    companion object {
        const val PICK = 1
        const val SAVE = 2
    }
}

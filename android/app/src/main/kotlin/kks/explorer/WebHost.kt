package kks.explorer

import android.annotation.SuppressLint
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.webkit.JavascriptInterface
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import kks.core.ApiResponse
import kks.core.Json
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.util.concurrent.Executors
import java.util.zip.GZIPInputStream

/**
 * The web viewer (index.html / admin.html, the same as on laptops) at the private origin https://kks.app/. Pages,
 * drawings and photos are answered from the app itself (nothing from the internet, no open port); API calls go
 * through the KKSNative bridge (a WebView doesn't hand POST bodies to the app). The activity supplies the pickers.
 */
class WebHost(private val act: MainActivity) {
    companion object { const val HOST = "kks.app" }

    private val io = Executors.newFixedThreadPool(4)
    private val main = Handler(Looper.getMainLooper())

    /** A WebView on the app's origin. `onNavigate` may take over a navigation (e.g. admin.html → the Manage screen). */
    @SuppressLint("SetJavaScriptEnabled")
    fun make(onNavigate: (Uri) -> Boolean = { false }): WebView {
        if (act.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) WebView.setWebContentsDebuggingEnabled(true)
        val web = WebView(act)
        web.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true          // common.js: IndexedDB / localStorage
            allowFileAccess = false
            allowContentAccess = false
        }
        web.addJavascriptInterface(Bridge(web), "KKSNative")
        web.webViewClient = object : WebViewClient() {
            override fun shouldInterceptRequest(view: WebView, req: WebResourceRequest): WebResourceResponse? =
                if (req.url.host == HOST) serve(req) else notFound()      // nothing is fetched from the internet

            override fun shouldOverrideUrlLoading(view: WebView, req: WebResourceRequest): Boolean {
                if (req.url.host == HOST) return onNavigate(req.url)
                runCatching { act.startActivity(Intent(Intent.ACTION_VIEW, req.url)) }
                return true
            }
        }
        web.webChromeClient = object : WebChromeClient() {
            override fun onShowFileChooser(view: WebView, cb: ValueCallback<Array<Uri>>, params: FileChooserParams) = act.chooseFile(cb, params)
        }
        return web
    }

    fun toast(web: WebView, msg: String) = main.post { web.evaluateJavascript("window.K&&K.toast&&K.toast(${JSONObject.quote(msg)})", null) }

    // ---------- the app's own origin ----------
    private fun notFound() = WebResourceResponse("text/plain", "utf-8", 404, "Not Found", emptyMap(), ByteArrayInputStream(ByteArray(0)))

    private fun ok(type: String, data: ByteArray, cache: String = "no-cache") =
        WebResourceResponse(type, if (type.startsWith("text/") || type.endsWith("json") || type.endsWith("javascript")) "utf-8" else null,
                            200, "OK", mapOf("Cache-Control" to cache), ByteArrayInputStream(data))

    private fun asset(path: String): ByteArray? = runCatching { act.assets.open(path).use { it.readBytes() } }.getOrNull()

    private fun type(path: String) = when (path.substringAfterLast('.', "")) {
        "html" -> "text/html"; "js" -> "text/javascript"; "json" -> "application/json"; "svg" -> "image/svg+xml"
        "png" -> "image/png"; "jpg", "jpeg" -> "image/jpeg"; "webp" -> "image/webp"; "jxl" -> "image/jxl"
        "css" -> "text/css"; "woff2" -> "font/woff2"
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
            if (f.extension == "jxl") {           // the WebView can't show JPEG XL: libjxl decodes it, the page gets the pixels
                val bmp = runCatching { Jxl.toBmp(f.readBytes()) }.getOrNull() ?: return notFound()
                return ok("image/bmp", bmp, "private, max-age=31536000, immutable")
            }
            return ok(type(f.name), f.readBytes(), "private, max-age=31536000, immutable")
        }
        if (path.startsWith("/data/")) {         // the plant data version this phone serves (§19), else the app's own data/
            val rel = path.removePrefix("/data/")
            App.node.plantFile(rel)?.let { return ok(type(rel), it) }
            App.node.plantFile("$rel.gz")?.let { gz -> return ok(type(rel), GZIPInputStream(gz.inputStream()).readBytes()) }
        }
        val file = when (path) {
            "/", "/index.html" -> "index.html"
            "/admin.html", "/common.js", "/qrcodegen.js", "/course-bridge.js", "/manifest.webmanifest", "/icon.svg", "/icon-192.png", "/icon-512.png" -> path.removePrefix("/")
            else -> if ((path.startsWith("/data/") || path.startsWith("/vendor/fonts/")) && ".." !in path) path.removePrefix("/")
                    else return notFound()   // (no sw.js: nothing to cache)
        }
        asset(file)?.let { return ok(type(file), it) }
        if (file.endsWith(".svg")) asset("$file.gz")?.let { gz -> return ok("image/svg+xml", GZIPInputStream(gz.inputStream()).readBytes()) }
        return notFound()
    }

    // ---------- the bridge (window.KKSNative), used by common.js ----------
    inner class Bridge(private val web: WebView) {
        private fun reply(id: String, status: Int, text: String) = main.post {
            web.evaluateJavascript("K.nativeReply(${JSONObject.quote(id)},$status,${JSONObject.quote(text)})", null)
        }

        private fun call(method: String, url: String, body: Any?): ApiResponse {
            val u = Uri.parse("https://$HOST$url")
            val q = u.queryParameterNames.associateWith { u.getQueryParameter(it) ?: "" }
            return runCatching { App.api.handle(method, u.path ?: "/", q, body) }
                .getOrElse { ApiResponse(500, mapOf("error" to "internal error: ${it.message}")) }
        }

        @JavascriptInterface fun request(id: String, method: String, url: String, body: String?) = io.execute {
            val r = call(method, url, body?.let { Json.parse(it) })
            reply(id, r.status, if (r.bytes != null) "{}" else Json.write(r.json))
            if (method == "POST" && r.status < 400) act.changed()
        }

        @JavascriptInterface fun requestBytes(id: String, url: String, base64: String) = io.execute {
            val r = call("POST", url, android.util.Base64.decode(base64, android.util.Base64.DEFAULT))
            reply(id, r.status, Json.write(r.json))
            if (r.status < 400) act.changed()
        }

        /** Save text (a join request) where the person chooses. */
        @JavascriptInterface fun saveFile(name: String, mime: String, text: String) = main.post { act.save(name, mime, text.toByteArray(), web) }

        /** Save a GET API result (a bundle) where the person chooses. */
        @JavascriptInterface fun saveApi(name: String, url: String) = io.execute {
            val r = call("GET", url, null)
            if (r.bytes == null) { toast(web, (r.json as? Map<*, *>)?.get("error")?.toString() ?: "failed"); return@execute }
            val fname = Regex("filename=\"([^\"]+)\"").find(r.headers["Content-Disposition"] ?: "")?.groupValues?.get(1) ?: name
            main.post { act.save(fname, r.contentType, r.bytes!!, web) }
        }

        /** Scan a QR code; the text comes back as K.nativeReply(id, 200, text), or status 499 if cancelled. */
        @JavascriptInterface fun scanQr(id: String) = main.post { act.scanQr { text -> reply(id, if (text != null) 200 else 499, text ?: "") } }

        /** Course progress (course-bridge.js): read synchronously before the course's script runs; save. */
        @JavascriptInterface fun progress(course: String): String {
            val r = call("GET", "/api/progress?course=${Uri.encode(course)}", null)
            return if (r.status < 400) Json.write((r.json as Map<*, *>)["data"]) else "null"
        }

        @JavascriptInterface fun progressSave(course: String, data: String): Int =
            call("POST", "/api/progress", mapOf("course" to course, "data" to runCatching { Json.parse(data) }.getOrNull())).status
                .also { if (it < 400) act.changed() }

        @JavascriptInterface fun platform() = "android"
    }
}

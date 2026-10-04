package kks.explorer.sync

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build
import android.util.Base64
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URI
import java.security.KeyFactory
import java.security.MessageDigest
import java.security.Signature
import java.security.spec.X509EncodedKeySpec

/**
 * Walkdown's self-updates (decision 0044): once a day the newest GitHub release is checked. Its release.json must carry
 * our P-256 signature (release.json.p256 over "kks-release-v2\n" + the manifest, the key pinned below), and
 * walkdown.apk must match its SHA-256 and size there. Nothing installs without the person's tap; Android's installer
 * then asks too, and checks the APK is signed like this app.
 */
object Updates {
    private const val TAG = "KKSUpdate"
    const val REPO = "5wHN28Dg/kks-explorer"
    const val APK = "walkdown.apk"
    private const val ACTION = "kks.explorer.WALKDOWN_UPDATE_STATUS"
    private const val DAY = 24 * 3600 * 1000L
    private val DOMAIN = "kks-release-v2\n".toByteArray()
    /** the release key's public half (X.509 DER, base64); tools/release.py checks its private half against it */
    const val RELEASE_P256_PUB = "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE5zNac3d7S/F5haZ7vi8BwMQ8Cv5Ee20FeaIKZO6CJIUYh21F1gjQe0XZI6yiV7wEsvBgVptuyJe62eHcJ99p9A=="

    data class Release(val version: String, val notes: String, val sha: String, val size: Long, val url: String)

    // what the screens show
    var latest by mutableStateOf<Release?>(null); private set
    var busy by mutableStateOf<String?>(null); private set
    var error by mutableStateOf<String?>(null); private set
    var checked by mutableStateOf(0L); private set
    @Volatile internal var api = "https://api.github.com/repos/$REPO/releases/latest"   // debug builds: a test release (DebugUpdateReceiver)
    @Volatile internal var pub = RELEASE_P256_PUB      // volatile: R8 inlined the constant and ignored the test override

    fun current(ctx: Context): String =
        (runCatching { ctx.packageManager.getPackageInfo(ctx.packageName, 0).versionName }.getOrNull() ?: "0.0.0").substringBefore('-')

    private fun parts(v: String) = v.split('.').map { it.toIntOrNull() ?: 0 } + listOf(0, 0, 0)
    fun newer(a: String, b: String): Boolean {
        val x = parts(a); val y = parts(b)
        for (i in 0..2) if (x[i] != y[i]) return x[i] > y[i]
        return false
    }

    fun available(ctx: Context) = latest?.let { newer(it.version, current(ctx)) } == true

    private fun get(url: String, timeoutMs: Int = 30_000): ByteArray {
        var u = url
        repeat(6) {                                       // GitHub's asset links redirect to another host
            val c = URI(u).toURL().openConnection() as HttpURLConnection
            c.instanceFollowRedirects = false
            c.connectTimeout = timeoutMs; c.readTimeout = timeoutMs
            c.setRequestProperty("User-Agent", "walkdown-updater")
            c.setRequestProperty("Accept", "application/octet-stream, application/json")
            when (val code = c.responseCode) {
                in 200..299 -> return c.inputStream.use { it.readBytes() }
                301, 302, 303, 307, 308 -> u = URI(u).resolve(c.getHeaderField("Location")).toString()
                else -> throw java.io.IOException("HTTP $code from ${URI(u).host}")
            }
        }
        throw java.io.IOException("too many redirects")
    }

    /** the manifest if our release key signed it; throws otherwise */
    fun verify(manifest: ByteArray, sigB64: String, pubB64: String = pub): JSONObject {
        val key = KeyFactory.getInstance("EC").generatePublic(X509EncodedKeySpec(Base64.decode(pubB64, Base64.DEFAULT)))
        val ok = runCatching {
            Signature.getInstance("SHA256withECDSA").run { initVerify(key); update(DOMAIN + manifest); verify(Base64.decode(sigB64.trim(), Base64.DEFAULT)) }
        }.getOrDefault(false)
        if (!ok) throw IllegalArgumentException("the release is not signed by the Walkdown release key")
        val m = JSONObject(String(manifest, Charsets.UTF_8))
        if (m.optString("app") != "kks-explorer" || !Regex("\\d{1,4}\\.\\d{1,4}\\.\\d{1,4}").matches(m.optString("version")))
            throw IllegalArgumentException("not a Walkdown release manifest")
        return m
    }

    /** the newest release, verified (null when it has no Walkdown APK) */
    fun fetchLatest(): Release? {
        val rel = JSONObject(String(get(api), Charsets.UTF_8))
        val urls = HashMap<String, String>()
        val assets = rel.optJSONArray("assets")
        for (i in 0 until (assets?.length() ?: 0)) assets!!.getJSONObject(i).let { urls[it.optString("name")] = it.optString("browser_download_url") }
        val mu = urls["release.json"]; val su = urls["release.json.p256"]
        if (mu == null || su == null) throw IllegalArgumentException("the latest release has no manifest signed for Walkdown")
        val m = verify(get(mu), String(get(su), Charsets.UTF_8))
        val f = m.optJSONObject("files")?.optJSONObject(APK) ?: return null
        val sha = f.optString("sha256"); val size = f.optLong("size")
        if (!Regex("[0-9a-f]{64}").matches(sha) || urls[APK] == null) return null
        return Release(m.getString("version"), m.optString("notes").take(4000), sha, size, urls[APK]!!)
    }

    private fun prefs(ctx: Context) = ctx.getSharedPreferences("updates", Context.MODE_PRIVATE)

    /** on start: check if the last check is a day old (off the main thread) */
    fun maybeCheck(ctx: Context) {
        if (checked == 0L) checked = prefs(ctx).getLong("checked", 0L)
        if (System.currentTimeMillis() - checked >= DAY) check(ctx)
    }

    fun check(ctx: Context) {
        try { latest = fetchLatest(); error = null }
        catch (e: Exception) { error = e.message ?: e.javaClass.simpleName; Log.i(TAG, "check failed: $error") }
        checked = System.currentTimeMillis()
        prefs(ctx).edit().putLong("checked", checked).apply()
    }

    /** download, check against the signed manifest, hand to Android's installer (which asks the person) */
    fun install(ctx: Context) {
        val r = latest ?: return
        if (busy != null) return
        busy = "Downloading…"; error = null
        try {
            val apk = get(r.url, 300_000)
            val sha = MessageDigest.getInstance("SHA-256").digest(apk).joinToString("") { "%02x".format(it) }
            if (apk.size.toLong() != r.size || sha != r.sha)
                throw IllegalArgumentException("the download does not match the signed release (corrupted or tampered): not installed")
            busy = "Installing…"
            val pi = ctx.packageManager.packageInstaller
            val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
                setAppPackageName(ctx.packageName); setSize(apk.size.toLong())
            }
            val id = pi.createSession(params)
            pi.openSession(id).use { s ->
                s.openWrite(APK, 0, apk.size.toLong()).use { out -> out.write(apk); s.fsync(out) }
                val flags = PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
                s.commit(PendingIntent.getBroadcast(ctx, id, Intent(ACTION).setPackage(ctx.packageName), flags).intentSender)
            }
        } catch (e: Exception) {
            error = e.message ?: e.javaClass.simpleName; Log.w(TAG, "install failed: $error")
        } finally { busy = null }
    }

    /** the installer's answers: ask the person (the system's own dialog), or say how it ended */
    class Receiver : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            when (val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
                PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                    @Suppress("DEPRECATION") val ask = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT) ?: return
                    ctx.startActivity(ask.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                }
                PackageInstaller.STATUS_SUCCESS -> Log.i(TAG, "installed")
                else -> {
                    val msg = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
                    error = if (status == PackageInstaller.STATUS_FAILURE_ABORTED) "Install cancelled." else "Install failed: $msg"
                    Log.w(TAG, "install status $status: $msg")
                }
            }
        }
    }
}

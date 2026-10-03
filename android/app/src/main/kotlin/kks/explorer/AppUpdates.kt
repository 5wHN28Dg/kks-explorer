package kks.explorer

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build
import android.util.Log
import kks.core.Updates

/**
 * Self-updates on the phone (M5b): once a day the app looks at the newest GitHub release (verified against the pinned
 * release key, kks.core.Updates) and the Account tab offers it. Nothing is installed without a tap; the APK must match
 * the signed manifest, then Android's installer asks the person and checks the APK is signed with this app's key.
 */
object AppUpdates {
    private const val TAG = "KKSUpdate"
    private const val ACTION = "kks.explorer.UPDATE_STATUS"
    private const val DAY = 24 * 3600 * 1000L

    @Volatile var latest: Updates.Release? = null; private set
    @Volatile var error: String? = null; private set
    @Volatile var busy: String? = null; private set
    @Volatile var checked = 0L; private set
    @Volatile var installed = false                       // the last install finished (the bridge then opens the new app)
    var onChange: () -> Unit = {}
    internal var api: String? = null                     // (debug builds: a test release server, DebugUpdateReceiver)
    internal var pub = Updates.RELEASE_PUB

    fun current(context: Context): String =
        runCatching { context.packageManager.getPackageInfo(context.packageName, 0).versionName }.getOrNull() ?: "0.0.0"

    fun available(context: Context) = latest?.let { Updates.newer(it.version, current(context)) && Updates.APK in it.files } == true

    private fun prefs(context: Context) = context.getSharedPreferences("updates", Context.MODE_PRIVATE)

    /** On start: check if the last check is a day old. Run off the main thread. */
    fun maybeCheck(context: Context) {
        if (checked == 0L) checked = prefs(context).getLong("checked", 0L)
        if (System.currentTimeMillis() - checked >= DAY) check(context)
    }

    fun check(context: Context) {
        try { latest = api?.let { Updates.fetchLatest(it, pub) } ?: Updates.fetchLatest(); error = null }
        catch (e: Exception) { error = e.message ?: e.javaClass.simpleName; Log.i(TAG, "check failed: $error") }
        checked = System.currentTimeMillis()
        prefs(context).edit().putLong("checked", checked).apply()
        onChange()
    }

    /** Download, check against the signed manifest, hand to Android's installer (it asks the person). The bridge
     *  (decision 0042) installs the new app the same way: another file of the same signed release, another package. */
    fun install(context: Context, file: String = Updates.APK, pkg: String = context.packageName) {
        if (latest == null && file != Updates.APK) check(context)
        val r = latest ?: return
        if (busy != null) return
        busy = "Downloading…"; error = null; onChange()
        try {
            val apk = Updates.download(r, file)
            busy = "Installing…"; onChange()
            val pi = context.packageManager.packageInstaller
            val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
                setAppPackageName(pkg)
                setSize(apk.size.toLong())
            }
            val id = pi.createSession(params)
            pi.openSession(id).use { s ->
                s.openWrite("kks-explorer.apk", 0, apk.size.toLong()).use { out -> out.write(apk); s.fsync(out) }
                val flags = PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
                val pending = PendingIntent.getBroadcast(context, id, Intent(ACTION).setPackage(context.packageName), flags)
                s.commit(pending.intentSender)
            }
        } catch (e: Exception) {
            error = e.message ?: e.javaClass.simpleName; Log.w(TAG, "install failed: $error")
        } finally { busy = null; onChange() }
    }

    /** The installer's answers: ask the person (the system's own dialog), or report how it ended. */
    class Receiver : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
                PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                    @Suppress("DEPRECATION") val ask = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT) ?: return
                    context.startActivity(ask.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                }
                PackageInstaller.STATUS_SUCCESS -> { Log.i(TAG, "installed"); installed = true; onChange() }
                else -> {
                    val msg = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
                    error = if (status == PackageInstaller.STATUS_FAILURE_ABORTED) "Install cancelled."
                            else if (status == PackageInstaller.STATUS_FAILURE_CONFLICT || status == PackageInstaller.STATUS_FAILURE_INCOMPATIBLE)
                                "Android refused it: the update isn't signed like this copy of the app ($msg)."
                            else "Install failed: $msg"
                    Log.w(TAG, "install status $status: $msg"); onChange()
                }
            }
        }
    }
}

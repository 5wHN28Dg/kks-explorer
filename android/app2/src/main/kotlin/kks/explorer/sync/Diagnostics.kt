package kks.explorer.sync

import android.content.Context
import android.os.Build
import android.util.Log
import kks.explorer.core.Core
import org.json.JSONObject
import java.io.File

/**
 * Diagnostics reports (PROTOCOL-v2 §13a, decision 0040): events go to the core, which seals a report to the manager
 * while reports are on. A crash is written to a file by the uncaught-exception handler (the process is dying; the core
 * may not answer) and handed to the core at the next start.
 */
object Diagnostics {
    private fun crashFile(ctx: Context) = File(ctx.filesDir, "crash.txt")

    fun install(ctx: Context) {
        val before = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { t, e ->
            runCatching { crashFile(ctx).writeText("${e.javaClass.name}: ${e.message}\n" + Log.getStackTraceString(e).take(3800)) }
            before?.uncaughtException(t, e)
        }
        val f = crashFile(ctx)
        // the last crash goes to the core off the main thread (the core opens in the background meanwhile), and the
        // file only once the core took it: a core that did not open keeps it for a start that works
        if (f.exists()) Thread {
            val text = runCatching { f.readText() }.getOrDefault("crash")
            val took = runCatching { Core.api("POST", "/native/diag-record", JSONObject().put("kind", "crash").put("text", text.take(4000))).status < 400 }.getOrDefault(false)
            if (took) f.delete()
        }.start()
    }

    fun record(kind: String, text: String) {
        runCatching { Core.api("POST", "/native/diag-record", JSONObject().put("kind", kind).put("text", text.take(4000))) }
    }

    /** a report if the manager has them on and something new happened (at most every 6 h) */
    fun report(ctx: Context, force: Boolean = false) {
        val version = runCatching { ctx.packageManager.getPackageInfo(ctx.packageName, 0).versionName }.getOrNull() ?: "?"
        runCatching {
            Core.api("POST", "/native/diag-report", JSONObject().put("version", version)
                .put("platform", "Android ${Build.VERSION.RELEASE}").put("model", Build.MODEL ?: "").put("force", force))
        }
    }

    /** a device that is simply off or out of reach: normal, not worth a report */
    fun expected(msg: String?): Boolean {
        val m = (msg ?: "").lowercase()
        return listOf("failed to connect", "timed out", "timeout", "refused", "unreachable", "no route", "not on the relay",
                      "no answer", "closed the connection", "network is unreachable").any { it in m }
    }
}

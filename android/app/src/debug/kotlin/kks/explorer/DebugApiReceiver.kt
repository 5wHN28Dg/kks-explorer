package kks.explorer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Base64
import android.util.Log
import kks.core.Json

/** Debug builds only: one call of the app's local API, for the move rehearsal (decision 0042,
 *  android/app2/e2e/test_move.py). `req` = base64 of {"method", "path", "body"} (adb splits plain text at spaces):
 *  adb shell am broadcast -a kks.explorer.DEBUG_API -p kks.explorer --es req BASE64
 *  The answer goes to logcat, tag KKSDebug: "result <n> <status> <json>". */
class DebugApiReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        val raw = String(Base64.decode(intent.getStringExtra("req") ?: return, Base64.DEFAULT), Charsets.UTF_8)
        val n = intent.getStringExtra("n") ?: "0"
        val pending = goAsync()
        Thread {
            try {
                App.start(ctx)
                @Suppress("UNCHECKED_CAST") val r = Json.parse(raw) as Map<String, Any?>
                val res = App.api.handle(r["method"] as String, r["path"] as String, emptyMap(), r["body"])
                Log.i("KKSDebug", "result $n ${res.status} ${Json.write(res.json)}")
            } catch (e: Exception) {
                Log.w("KKSDebug", "result $n 0 {\"error\":\"${e.message?.replace("\"", "'")}\"}")
            } finally { pending.finish() }
        }.start()
    }
}

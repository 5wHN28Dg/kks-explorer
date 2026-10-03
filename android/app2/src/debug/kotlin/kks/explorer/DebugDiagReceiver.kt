package kks.explorer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import kks.explorer.sync.Diagnostics

/** Debug builds only: `adb shell am broadcast -a kks.explorer.DEBUG_DIAG -p kks.explorer.v2 --es text "…"` records an
 *  error event and writes a report now (decision 0040's e2e test; a real report waits for a real error and 6 hours). */
class DebugDiagReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        val r = goAsync()
        Thread {
            Diagnostics.record("error", intent.getStringExtra("text") ?: "debug test event")
            Diagnostics.report(ctx, force = true)
            r.finish()
        }.start()
    }
}

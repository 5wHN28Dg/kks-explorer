package kks.explorer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import kks.explorer.sync.Updates

/** Debug builds only: point the updater at a test release and key, then check now (android/app2/e2e/test_update.py):
 *  adb shell am broadcast -f 32 -a kks.explorer.DEBUG_UPDATE -p io.github.walkdown --es api URL --es pub KEY */
class DebugUpdateReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        intent.getStringExtra("api")?.let { Updates.api = it }
        intent.getStringExtra("pub")?.let { Updates.pub = it }
        val done = goAsync()
        Thread { try { Updates.check(ctx) } finally { done.finish() } }.start()
    }
}

package kks.explorer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Debug builds only: point the updater at a test release server and key, then check now (M5b emulator test):
 *  adb shell am broadcast -a kks.explorer.DEBUG_UPDATE -p kks.explorer --es api URL --es pub KEY */
class DebugUpdateReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        AppUpdates.api = intent.getStringExtra("api")
        intent.getStringExtra("pub")?.let { AppUpdates.pub = it }
        Thread { AppUpdates.check(ctx) }.start()
    }
}

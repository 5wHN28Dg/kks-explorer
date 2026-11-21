package kks.explorer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Debug builds only: turn switched changes on for the e2e and the owner's check (ui/Status.kt Ux):
 *  `adb shell am broadcast -f 32 -a kks.explorer.DEBUG_UX -p io.github.walkdown --es on offline-state` ("" = all off).
 *  Takes effect at the app's next start. */
class DebugUxReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        ctx.getSharedPreferences("ux", Context.MODE_PRIVATE).edit().putString("on", intent.getStringExtra("on") ?: "").commit()
    }
}

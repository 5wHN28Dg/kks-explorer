package kks.explorer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import kks.explorer.sync.Direct

/** Debug builds only: make the direct path stall after punching (android/app2/e2e/test_direct.py, the fallback test):
 *  adb shell am broadcast -f 32 -a kks.explorer.DEBUG_DIRECT -p io.github.walkdown --ez stall true */
class DebugDirectReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) { Direct.testStall = intent.getBooleanExtra("stall", false) }
}

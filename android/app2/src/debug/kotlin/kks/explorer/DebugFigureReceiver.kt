package kks.explorer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Debug builds only: course figures are not made in the core while held (e2e test_course_figures: a figure opened
 *  over the whole screen before the core has made it). `--ez hold true`, then `false`; the answer says what was set,
 *  so a test knows the hook is there. A figure waits a minute at most.
 *  `adb shell am broadcast -a kks.explorer.DEBUG_FIGURE -p io.github.walkdown --ez hold true` */
class DebugFigureReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        kks.explorer.ui.figNewHold = intent.getBooleanExtra("hold", false)
        resultData = "figures held: ${kks.explorer.ui.figNewHold}"
    }
}

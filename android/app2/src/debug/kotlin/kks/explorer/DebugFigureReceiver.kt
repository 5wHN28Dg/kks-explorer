package kks.explorer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Debug builds only: a course figure is made in the core after a wait (e2e test_course_figures: a figure opened
 *  over the whole screen, or its row gone, before the core has made it). `--el delay MS`, 0 to end it; the answer
 *  says what was set, so a test knows the hook is there.
 *  `adb shell am broadcast -a kks.explorer.DEBUG_FIGURE -p io.github.walkdown --el delay 15000` */
class DebugFigureReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        kks.explorer.ui.figNewDelayMs = intent.getLongExtra("delay", 0L).coerceIn(0L, 60_000L)
        resultData = "figure delay ${kks.explorer.ui.figNewDelayMs}"
    }
}

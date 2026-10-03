package kks.explorer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import kks.explorer.sync.SyncWorker

/** Debug builds only: `adb shell am broadcast -a kks.explorer.DEBUG_SYNC -p io.github.walkdown` runs the worker once now
 *  (WorkManager doesn't run a periodic job before its period, even with `cmd jobscheduler run -f`). */
class DebugSyncReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        WorkManager.getInstance(ctx).enqueue(OneTimeWorkRequestBuilder<SyncWorker>().build())
    }
}

package kks.explorer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager

/** Debug builds only: run the background sync worker once, now (the periodic one waits 15 minutes). */
class DebugSyncReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        WorkManager.getInstance(ctx).enqueue(OneTimeWorkRequestBuilder<SyncWorker>().build())
    }
}

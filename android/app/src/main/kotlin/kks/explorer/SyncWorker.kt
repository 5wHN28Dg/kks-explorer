package kks.explorer

import android.content.Context
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit

/**
 * Sync while the app is closed: every 15 minutes (Android's minimum for periodic work), only on an unmetered network
 * (in practice the plant Wi-Fi), look for devices for a few seconds, sync with them and with remembered addresses.
 * Android may run it later than asked (Doze, battery saver); nothing depends on its timing.
 */
class SyncWorker(ctx: Context, params: WorkerParameters) : Worker(ctx, params) {
    companion object {
        const val NAME = "kks-sync"
        const val LOOK_MS = 8_000L

        fun schedule(ctx: Context) {
            val req = PeriodicWorkRequestBuilder<SyncWorker>(15, TimeUnit.MINUTES)
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.UNMETERED).build())
                .build()
            WorkManager.getInstance(ctx).enqueueUniquePeriodicWork(NAME, ExistingPeriodicWorkPolicy.KEEP, req)
        }
    }

    override fun doWork(): Result {
        App.start(applicationContext)
        if (App.node.owner() == null) return Result.success()   // not joined yet: nothing to sync
        if (App.visible) { App.sync.syncAll(); return Result.success() }   // the app is on screen: its own loop runs
        App.sync.start()
        Thread.sleep(LOOK_MS)
        App.sync.syncAll()
        if (!App.visible) App.sync.stop()
        return Result.success()
    }
}

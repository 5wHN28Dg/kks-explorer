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
 * (in practice the plant Wi-Fi) unless metered networks are allowed (Account → Sync), look for devices for a few
 * seconds, sync with them and with remembered addresses.
 * Android may run it later than asked (Doze, battery saver); nothing depends on its timing.
 */
class SyncWorker(ctx: Context, params: WorkerParameters) : Worker(ctx, params) {
    companion object {
        const val NAME = "kks-sync"
        const val LOOK_MS = 8_000L

        /** (Re)schedule; UPDATE keeps the timing of an already scheduled job and only changes its network rule. */
        fun schedule(ctx: Context, metered: Boolean) {
            val net = if (metered) NetworkType.CONNECTED else NetworkType.UNMETERED
            val req = PeriodicWorkRequestBuilder<SyncWorker>(15, TimeUnit.MINUTES)
                .setConstraints(Constraints.Builder().setRequiredNetworkType(net).build())
                .build()
            WorkManager.getInstance(ctx).enqueueUniquePeriodicWork(NAME, ExistingPeriodicWorkPolicy.UPDATE, req)
        }
    }

    override fun doWork(): Result {
        App.start(applicationContext)
        if (App.node.owner() == null) return Result.success()   // not joined yet: nothing to sync
        if (!App.sync.autoAllowed()) return Result.success()     // metered now, not allowed (the setting just changed)
        if (App.visible) { App.sync.syncAll(); return Result.success() }   // the app is on screen: its own loop runs
        App.sync.start()
        Thread.sleep(LOOK_MS)
        App.sync.syncAll()
        if (!App.visible) App.sync.stop()
        return Result.success()
    }
}

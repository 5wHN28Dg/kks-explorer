package kks.explorer.sync

import android.content.Context
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import kks.explorer.App
import java.util.concurrent.TimeUnit

/**
 * Sync while the app is closed (the v1 SyncWorker): every 15 minutes (Android's minimum for periodic work), only on an
 * unmetered network unless metered networks are allowed (Manage → Account), look for devices for a few seconds, sync
 * with them and with remembered addresses. Android may run it later than asked (Doze); nothing depends on its timing.
 */
class SyncWorker(ctx: Context, params: WorkerParameters) : Worker(ctx, params) {
    companion object {
        const val NAME = "kks-sync"
        const val LOOK_MS = 8_000L

        fun metered(ctx: Context) = ctx.getSharedPreferences("app", Context.MODE_PRIVATE).getBoolean("sync_metered", false)

        /** (Re)schedule; UPDATE keeps the timing of a scheduled job and only changes its network rule. */
        fun schedule(ctx: Context) {
            val net = if (metered(ctx)) NetworkType.CONNECTED else NetworkType.UNMETERED
            val req = PeriodicWorkRequestBuilder<SyncWorker>(15, TimeUnit.MINUTES)
                .setConstraints(Constraints.Builder().setRequiredNetworkType(net).build())
                .build()
            WorkManager.getInstance(ctx).enqueueUniquePeriodicWork(NAME, ExistingPeriodicWorkPolicy.UPDATE, req)
        }

        fun setMetered(ctx: Context, on: Boolean) {
            ctx.getSharedPreferences("app", Context.MODE_PRIVATE).edit().putBoolean("sync_metered", on).apply()
            schedule(ctx)
        }
    }

    override fun doWork(): Result {
        val ctx = applicationContext
        if (!Sync.joined()) return Result.success()                              // not joined yet: nothing to sync
        if (!metered(ctx) && !Sync.unmetered(ctx)) return Result.success()      // the setting just changed
        Sync.start(ctx)
        if (App.visible) { Sync.syncAll(ctx); return Result.success() }        // on screen: its own loop runs too
        Discovery.start(ctx)
        Internet.start()
        Thread.sleep(LOOK_MS)
        Sync.syncAll(ctx)
        if (!App.visible) { Discovery.stop(); Internet.stop() }
        return Result.success()
    }
}

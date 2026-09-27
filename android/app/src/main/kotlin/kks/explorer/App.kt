package kks.explorer

import android.content.Context
import android.os.Build
import kks.core.LocalApi
import kks.core.LocalNode

/** One node, API and sync service per process: they outlive activities (rotation, tab switches). */
object App {
    lateinit var node: LocalNode
    lateinit var api: LocalApi
    lateinit var sync: PhoneSync
    lateinit var store: SqliteStore
    @Volatile var visible = false        // an activity is on screen (discovery + auto sync run while it is)

    fun setMeteredAllowed(context: Context, on: Boolean) {
        sync.meteredAllowed = on
        SyncWorker.schedule(context.applicationContext, on)
    }

    @Synchronized fun start(context: Context) {
        if (::node.isInitialized) return
        store = SqliteStore(context.applicationContext)
        node = LocalNode.open(store)
        sync = PhoneSync(context.applicationContext, node).also { it.listen() }
        SyncWorker.schedule(context.applicationContext, sync.meteredAllowed)
        api = LocalApi(node, sync).also {
            it.deviceLabel = "${Build.MANUFACTURER} ${Build.MODEL}".trim().take(80)
            it.photoEncoder = Jxl::fromImage          // photos are kept as JPEG XL
        }
    }
}

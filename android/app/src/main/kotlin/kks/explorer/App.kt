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
        val app = context.applicationContext
        node.onWiped = {   // removed from the plant (§15): start over with a new device key, back at the setup screen
            if (visible) runCatching {
                app.startActivity(app.packageManager.getLaunchIntentForPackage(app.packageName)!!
                    .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK or android.content.Intent.FLAG_ACTIVITY_CLEAR_TASK))
            }
            Runtime.getRuntime().exit(0)
        }
        sync = PhoneSync(context.applicationContext, node).also { it.listen() }
        SyncWorker.schedule(context.applicationContext, sync.meteredAllowed)
        api = LocalApi(node, sync).also {
            it.deviceLabel = "${Build.MANUFACTURER} ${Build.MODEL}".trim().take(80)
            it.photoEncoder = { b -> Jxl.fromImage(b).also { store.setMeta("jxl_ms_per_mp", Jxl.msPerMp.toString()) } }   // photos are kept as JPEG XL
            store.meta("jxl_ms_per_mp")?.toLongOrNull()?.let { v -> Jxl.msPerMp = v }
            it.photoMsPerMp = { Jxl.msPerMp }
        }
    }
}

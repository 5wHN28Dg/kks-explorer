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

    @Synchronized fun start(context: Context) {
        if (::node.isInitialized) return
        store = SqliteStore(context.applicationContext)
        node = LocalNode.open(store)
        sync = PhoneSync(node).also { it.listen() }
        api = LocalApi(node, sync).also { it.deviceLabel = "${Build.MANUFACTURER} ${Build.MODEL}".trim().take(80) }
    }
}

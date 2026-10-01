package kks.explorer

import android.app.Application
import android.content.Context
import android.content.Intent
import android.util.Log
import kks.explorer.core.Core
import kks.explorer.core.Keys
import java.io.File

/** Opens the core once per process (Keystore keys, the sealed store), and starts over when an admin removed this phone. */
class App : Application() {
    override fun onCreate() {
        super.onCreate()
        Core.open(this)
        Core.listeners.add { why -> if (why.startsWith("wiped:")) removed(this, why.removePrefix("wiped:")) }
        kks.explorer.sync.SyncWorker.schedule(this)
    }

    companion object {
        /** an activity is on screen: discovery and the automatic rounds run only then (the worker covers the rest) */
        @Volatile var visible = false

        /** PROTOCOL-v2 §15: the core has emptied the store; delete the keys and the database, then start fresh */
        fun removed(ctx: Context, note: String) {
            Log.w("KKSSync", "removed from the plant: $note")
            ctx.getSharedPreferences("app", Context.MODE_PRIVATE).edit().putString("removed", note).commit()
            ctx.getSharedPreferences("sync", Context.MODE_PRIVATE).edit().clear().commit()
            Keys.wipe(ctx)
            File(ctx.filesDir, "core").deleteRecursively()
            if (visible) ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)?.let {
                ctx.startActivity(it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK))
            }
            Runtime.getRuntime().exit(0)
        }

        fun removedNote(ctx: Context): String = ctx.getSharedPreferences("app", Context.MODE_PRIVATE).getString("removed", "") ?: ""
        fun clearRemovedNote(ctx: Context) = ctx.getSharedPreferences("app", Context.MODE_PRIVATE).edit().remove("removed").apply()
    }
}

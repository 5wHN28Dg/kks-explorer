package kks.explorer

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.util.Log
import kks.core.B64u
import kks.core.Canonical
import kks.core.Json
import kks.core.ed25519Verify
import kks.core.sha256
import java.io.File

/**
 * The bridge release (decision 0042, PROTOCOL-v2 §21a): this v1 app installs the new app and hands over to
 * it. The new app calls [Handover] (only apps signed with our key may: a signature permission); everything the
 * handover gives away waits until the plant's v1 root key has vouched for the new server (the succession statement).
 */
object Bridge {
    /** the new app (its package ID changes with the new name: the one place to change it here) */
    const val NEW_APP = "kks.explorer.v2"
    /** its APK in the bridge's signed release */
    const val NEW_APK = "kks-explorer-2.apk"
    private val DATA = setOf("equipment", "review", "link", "photo", "photo_delete", "tag_add", "tag_remove")
    private val NOT_CARRIED = setOf("vote", "approve", "reject", "withdraw")

    @Volatile var handedOver: Set<String> = emptySet()      // blobs the new app may read (the last handover's)

    fun newAppInstalled(ctx: Context) = try { ctx.packageManager.getPackageInfo(NEW_APP, 0); true } catch (e: Exception) { false }

    fun done(ctx: Context) = ctx.getSharedPreferences("bridge", Context.MODE_PRIVATE).getBoolean("done", false)

    fun openNewApp(ctx: Context) {
        ctx.packageManager.getLaunchIntentForPackage(NEW_APP)?.let { ctx.startActivity(it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
    }

    /** Android's own dialog for removing this (old) app */
    fun removeSelf(ctx: Context) {
        ctx.startActivity(Intent(Intent.ACTION_DELETE, Uri.parse("package:${ctx.packageName}")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    /** what this phone knows about its plant; no secrets */
    fun info(): Map<String, Any?> {
        val node = App.node
        val o = node.owner() ?: return mapOf("v1_root" to "")
        val addrs = ((runCatching { Json.parse(App.store.meta("sync_peers") ?: "[]") as List<*> }.getOrNull() ?: emptyList<Any?>()) +
                     App.sync.foundAddresses()).filterIsInstance<String>().distinct()
        return mapOf("v1_root" to (node.root() ?: ""), "v1_device" to node.device, "person" to o.person, "name" to o.fullName,
                     "plant" to synchronized(node) { node.run.settings["plant"] }, "addrs" to addrs,
                     "relay" to synchronized(node) { node.run.settings["relay"] })
    }

    /** Check the statement against our v1 root, then sign the move to the new device and list what to hand over. */
    @Suppress("UNCHECKED_CAST")
    fun handover(stmtText: String, sig: String, device: String, key: String, label: String): Map<String, Any?> {
        val node = App.node
        val root = node.root() ?: return mapOf("ok" to false, "why" to "The old app has no plant.")
        val stmt = Json.parse(stmtText) as? Map<String, Any?> ?: return mapOf("ok" to false, "why" to "bad statement")
        val good = stmt["kind"] == "succession" && stmt["v1_root"] == root &&
            runCatching { ed25519Verify(B64u.decode(root), B64u.decode(sig), "kks-succession-v1\n".toByteArray() + Canonical.bytes(stmt)) }.getOrDefault(false)
        if (!good) return mapOf("ok" to false, "why" to "That server could not prove it is this plant's: the move was stopped.")
        // the new device's peer ID is the first 24 bytes of SHA-256 of its key (PROTOCOL-v2 §2)
        if (runCatching { B64u.encode(sha256(B64u.decode(key)).copyOf(24)) }.getOrNull() != device)
            return mapOf("ok" to false, "why" to "The new app's key does not match its device.")
        val me = node.device
        val archived = (stmt["archived"] as? List<*>).orEmpty().firstOrNull { (it as? List<*>)?.getOrNull(0) == me }
            ?.let { ((it as List<*>)[1] as? Long) } ?: 0L
        val proof = linkedMapOf<String, Any?>("kks_migrate" to 1L, "v1_root" to root, "v1_device" to me, "v2_root" to stmt["v2_root"],
            "device" to device, "key" to key, "label" to label.take(80), "created" to System.currentTimeMillis() / 1000)
        proof["sig"] = B64u.encode(App.node.signRaw("kks-migrate-v1\n".toByteArray() + Canonical.bytes(proof)))
        val out = ArrayList<Map<String, Any?>>()
        val blobs = HashSet<String>()
        val skipped = HashMap<String, Long>()
        synchronized(node) {
            val person = node.owner()?.person
            val mine = node.entries.toList().filter { it.second["peer"] == me && (it.second["seq"] as Long) > archived }
                .sortedBy { it.second["seq"] as Long }
            for ((eid, e) in mine) {
                val type = e["type"] as String
                if (type in NOT_CARRIED) { skipped[type] = (skipped[type] ?: 0L) + 1; continue }
                if (type !in DATA) continue
                val st = node.statusOf(eid).first
                if (st == "rejected" || st == "withdrawn") continue
                val body = e["body"] as Map<String, Any?>
                val note = node.run.comments[eid]?.firstOrNull { it["person"] == person }?.get("text") as String? ?: ""
                val bl = if (type == "photo") listOf(body["blob"] as String).filter { App.store.blobName(it) != null } else emptyList()
                blobs += bl
                out.add(mapOf("v1" to eid, "type" to type, "body" to body, "note" to note, "blobs" to bl))
            }
        }
        handedOver = blobs
        val progress = runCatching { App.node.owner()?.let { kks.core.Progress.load(App.node, it.person) } }.getOrNull() ?: emptyMap<String, Any?>()
        Log.i("KKSBridge", "handover to ${device.take(8)}: ${out.size} changes, ${blobs.size} photos, skipped $skipped")
        return mapOf("ok" to true, "proof" to proof, "entries" to out, "skipped" to skipped, "progress" to progress)
    }

    fun markDone(ctx: Context) = ctx.getSharedPreferences("bridge", Context.MODE_PRIVATE).edit().putBoolean("done", true).apply()

    /** The provider the new app calls: info, handover, done, and the handed-over photo files. */
    class Handover : ContentProvider() {
        override fun onCreate() = true

        override fun call(method: String, arg: String?, extras: Bundle?): Bundle {
            val ctx = context!!
            App.start(ctx)
            val r: Map<String, Any?> = try {
                when (method) {
                    "info" -> if (done(ctx)) mapOf("v1_root" to "", "done" to true) else info()   // moved once: nothing left
                    "handover" -> handover(extras!!.getString("stmt")!!, extras.getString("sig")!!, extras.getString("device")!!,
                                           extras.getString("key")!!, extras.getString("label") ?: "")
                    "done" -> { markDone(ctx); mapOf("ok" to true) }
                    else -> mapOf("ok" to false, "why" to "unknown request")
                }
            } catch (e: Exception) { Log.w("KKSBridge", "$method failed", e); mapOf("ok" to false, "why" to (e.message ?: "failed")) }
            return Bundle().apply { putString("json", Json.write(r)) }
        }

        override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor? {
            val ctx = context!!
            App.start(ctx)
            val sha = uri.lastPathSegment ?: return null
            if (mode != "r" || sha !in handedOver) throw SecurityException("not handed over")
            val name = App.store.blobName(sha) ?: return null
            return ParcelFileDescriptor.open(File(App.store.photosDir, name), ParcelFileDescriptor.MODE_READ_ONLY)
        }

        override fun query(u: Uri, p: Array<out String>?, s: String?, a: Array<out String>?, o: String?) = null
        override fun getType(uri: Uri): String? = null
        override fun insert(uri: Uri, values: ContentValues?): Uri? = null
        override fun delete(uri: Uri, s: String?, a: Array<out String>?) = 0
        override fun update(uri: Uri, v: ContentValues?, s: String?, a: Array<out String>?) = 0
    }
}

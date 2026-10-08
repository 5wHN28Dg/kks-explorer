package kks.explorer.sync

import android.content.Context
import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.setValue
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import kks.explorer.Jxl
import kks.explorer.core.Core
import kks.explorer.ui.Changes
import org.json.JSONArray
import org.json.JSONObject
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.util.UUID
import java.util.concurrent.Executors

/**
 * The photo queue (decision 0049; the user, 2026-10-08: compression stopped when the panel closed, and photos for
 * several tags should be taken one after another and processed in order). Send hands the annotated picture over here:
 * its pixels and what goes with it are written to the app's files (`photo-queue/`), and one WorkManager job per photo
 * encodes it to JPEG XL and submits it through the core. The jobs form one unique chain (APPEND_OR_REPLACE), so they
 * run one at a time, in the order sent; WorkManager keeps them across the app closing, the process dying and a restart.
 * A job never fails the chain: a photo that can't be encoded or is refused is recorded in [failures] and dropped.
 */
object PhotoQueue {
    const val WORK = "kks-photos"
    private const val TAG = "KKSPhotos"
    /** staging files are written here, one at a time and in order, off the main thread and outside any screen */
    private val io = Executors.newSingleThreadExecutor { Thread(it, "kks-photo-queue") }
    private val main = Handler(Looper.getMainLooper())

    /** photos waiting or being prepared (all of them, and per code) */
    var pending by mutableIntStateOf(0)
        private set
    val pendingByCode = mutableStateMapOf<String, Int>()
    /** the floor sent with a queued photo, per code: the next photo of that code doesn't ask again */
    val queuedFloor = mutableStateMapOf<String, String>()
    /** what went wrong, newest last ("11LAB70AA501: Could not compress the photo"); kept until dismissed */
    val failures = mutableStateListOf<String>()

    private fun dir(ctx: Context) = File(ctx.filesDir, "photo-queue").also { it.mkdirs() }
    private fun prefs(ctx: Context) = ctx.getSharedPreferences("photo_queue", Context.MODE_PRIVATE)

    /** at start: count what is left from before, bring back the failures, and requeue jobs whose work was lost */
    fun init(ctx: Context) {
        val app = ctx.applicationContext
        runCatching { JSONArray(prefs(app).getString("failures", "[]")) }.getOrNull()?.let { a ->
            failures.clear(); for (i in 0 until a.length()) failures.add(a.getString(i))
        }
        io.execute {
            refresh(app)
            // a job file whose work isn't known any more (written just before the process died, before it was enqueued)
            val infos = runCatching { WorkManager.getInstance(app).getWorkInfosForUniqueWork(WORK).get() }.getOrNull() ?: return@execute
            val live = infos.filter { !it.state.isFinished }.mapNotNull { w -> w.tags.firstOrNull { it.startsWith("job:") }?.removePrefix("job:") }.toSet()
            for (id in jobs(app).map { it.first }.filter { it !in live }) enqueue(app, id)
        }
    }

    /** the queued jobs, oldest first: (id, its JSON) */
    private fun jobs(ctx: Context): List<Pair<String, JSONObject>> =
        (dir(ctx).listFiles { f -> f.name.endsWith(".json") } ?: emptyArray())
            .mapNotNull { f -> runCatching { f.name.removeSuffix(".json") to JSONObject(f.readText()) }.getOrNull() }
            .sortedBy { it.second.optLong("at") }

    /** synchronized: the counts are posted in the order the folder was read */
    @Synchronized private fun refresh(ctx: Context) {
        val js = jobs(ctx)
        val by = js.groupingBy { it.second.optString("kks") }.eachCount()
        val floors = js.filter { it.second.optString("floor").isNotEmpty() }.associate { it.second.optString("kks") to it.second.optString("floor") }
        main.post {
            pending = js.size
            pendingByCode.keys.retainAll(by.keys); pendingByCode.putAll(by)
            queuedFloor.keys.retainAll(floors.keys); queuedFloor.putAll(floors)
        }
    }

    /** queue one photo: returns at once; the pixels are written and the job enqueued on the queue's own thread */
    fun add(ctx: Context, bmp: Bitmap, kks: String, caption: String, note: String, floor: String) {
        val app = ctx.applicationContext
        val id = UUID.randomUUID().toString().replace("-", "")       // also the submission's client_id: a rerun can't add it twice
        main.post { pending += 1; pendingByCode[kks] = (pendingByCode[kks] ?: 0) + 1; if (floor.isNotEmpty()) queuedFloor[kks] = floor }
        io.execute {
            try {
                val px = File(dir(app), "$id.px")
                val argb = if (bmp.config == Bitmap.Config.ARGB_8888) bmp else bmp.copy(Bitmap.Config.ARGB_8888, false)
                val buf = ByteBuffer.allocate(argb.width * argb.height * 4)
                argb.copyPixelsToBuffer(buf)        // memory order R, G, B, A (as Jxl.fromBitmap reads it back)
                DataOutputStream(px.outputStream().buffered()).use { o -> o.writeInt(argb.width); o.writeInt(argb.height); o.write(buf.array()) }
                val job = JSONObject().put("kks", kks).put("caption", caption).put("note", note).put("floor", floor)
                    .put("at", System.currentTimeMillis())
                // the JSON last, through a rename: a job file is never seen half written
                val tmp = File(dir(app), "$id.json.tmp"); tmp.writeText(job.toString()); tmp.renameTo(File(dir(app), "$id.json"))
                enqueue(app, id)
                refresh(app)
            } catch (e: Throwable) {
                Log.w(TAG, "could not queue a photo of $kks", e)
                File(dir(app), "$id.px").delete()
                fail(app, kks, "Could not keep the photo for sending (${e.message ?: e.javaClass.simpleName})")
                refresh(app)
            }
        }
    }

    private fun enqueue(ctx: Context, id: String) {
        val req = OneTimeWorkRequestBuilder<PhotoWorker>().setInputData(workDataOf("job" to id)).addTag("job:$id").build()
        WorkManager.getInstance(ctx).enqueueUniqueWork(WORK, ExistingWorkPolicy.APPEND_OR_REPLACE, req)
    }

    private fun fail(ctx: Context, kks: String, why: String) {
        val line = "$kks: $why"
        val p = prefs(ctx)
        synchronized(failures) {
            val a = runCatching { JSONArray(p.getString("failures", "[]")) }.getOrDefault(JSONArray())
            a.put(line)
            while (a.length() > 20) a.remove(0)
            p.edit().putString("failures", a.toString()).apply()
        }
        main.post { failures.add(line); while (failures.size > 20) failures.removeAt(0) }
    }

    fun dismissFailures(ctx: Context) {
        failures.clear()
        prefs(ctx).edit().remove("failures").apply()
    }

    /** a removed phone (App.removed): the queued photos are plant data too */
    fun wipe(ctx: Context) {
        runCatching { WorkManager.getInstance(ctx).cancelUniqueWork(WORK) }
        dir(ctx).deleteRecursively()
        prefs(ctx).edit().clear().commit()
    }

    /** one job: encode, submit, forget (sent, refused or unreadable: each ends it) */
    internal fun run(ctx: Context, id: String) {
        val jf = File(dir(ctx), "$id.json"); val px = File(dir(ctx), "$id.px")
        if (!jf.exists()) { px.delete(); refresh(ctx); return }      // already done (a rerun)
        val job = runCatching { JSONObject(jf.readText()) }.getOrNull()
        val kks = job?.optString("kks").orEmpty()
        try {
            if (job == null || !px.exists()) { fail(ctx, kks.ifEmpty { "photo" }, "The queued photo was lost"); return }
            val bmp = DataInputStream(px.inputStream().buffered()).use { i ->
                val w = i.readInt(); val h = i.readInt()
                val bytes = ByteArray(w * h * 4); i.readFully(bytes)
                Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888).also { it.copyPixelsFromBuffer(ByteBuffer.wrap(bytes)) }
            }
            val jxl = try { Jxl.fromBitmap(bmp) } catch (e: Throwable) {
                Log.w(TAG, "encode $kks", e); fail(ctx, kks, "Could not compress the photo"); return
            }
            bmp.recycle()
            val payload = JSONObject().put("kks", kks).put("caption", job.optString("caption"))
                .put("dataUrl", "data:image/jxl;base64," + Base64.encodeToString(jxl, Base64.NO_WRAP))
            job.optString("floor").takeIf { it.isNotEmpty() }?.let { payload.put("floor", it) }
            val body = JSONObject().put("kind", "photo").put("payload", payload).put("client_id", id)
            job.optString("note").takeIf { it.isNotBlank() }?.let { body.put("note", it.trim()) }
            val r = Core.api("POST", "/api/submit", body)
            if (r.status >= 400) fail(ctx, kks, r.json.optString("error", "error ${r.status}"))
            else main.post { Changes.rev++ }
        } finally {
            jf.delete(); px.delete()
            refresh(ctx)
        }
    }
}

/** one queued photo (PhotoQueue): runs in the background, in order, also after the app closed or restarted */
class PhotoWorker(ctx: Context, params: WorkerParameters) : Worker(ctx, params) {
    override fun doWork(): Result {
        val id = inputData.getString("job") ?: return Result.success()
        PhotoQueue.run(applicationContext, id)
        return Result.success()       // never fail the chain: the next photos must still go
    }
}

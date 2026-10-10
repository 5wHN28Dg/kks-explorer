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
import kks.explorer.core.Keys
import kks.explorer.ui.Changes
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.nio.ByteBuffer
import java.util.UUID
import java.util.concurrent.Executors

/**
 * The photo queue (decision 0049; the user, 2026-10-08: compression stopped when the panel closed, and photos for
 * several tags should be taken one after another and processed in order). Send hands the annotated picture over here:
 * its pixels and what goes with it are sealed (Keys.seal: a Keystore-wrapped key per file) into the app's files
 * (`photo-queue/`), and one WorkManager job per photo
 * encodes it to JPEG XL and submits it through the core. The jobs form one unique chain (APPEND_OR_REPLACE), so they
 * run one at a time, in the order sent; WorkManager keeps them across the app closing, the process dying and a restart.
 * A job never fails the chain. A photo the core refuses, or whose files are damaged, is recorded in [failures] and
 * dropped; any other failure (out of memory while encoding, the Keystore, the core throwing) keeps the photo: it goes to
 * the end of the queue and is tried again a minute later, and after [TRIES] tries it waits for the next app start.
 *
 * One photo of several codes ("Photo for all") is a job like any other, with `codes` (2 to 200; `kks` is the first):
 * sent as one /api/submit-many with the job ID as the `client_id` prefix, so a rerun sends no code twice; its `floor`
 * is written by the core only for the codes that have none.
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

    /** what a sealed file is bound to: its kind and job ID (a file can't stand in for another) */
    private fun aad(kind: String, id: String) = "kks-photo-queue/$kind/$id".toByteArray()

    private fun readJob(f: File, id: String) = JSONObject(Keys.open(f.readBytes(), aad("job", id)).toString(Charsets.UTF_8))

    /** the queued jobs, oldest first: (id, its JSON) */
    private fun jobs(ctx: Context): List<Pair<String, JSONObject>> =
        (dir(ctx).listFiles { f -> f.name.endsWith(".json") } ?: emptyArray())
            .mapNotNull { f -> runCatching { f.name.removeSuffix(".json").let { id -> id to readJob(f, id) } }.getOrNull() }
            .sortedBy { it.second.optLong("at") }

    /** synchronized: the counts are posted in the order the folder was read */
    @Synchronized private fun refresh(ctx: Context) {
        val js = jobs(ctx)
        val by = js.flatMap { codesOf(it.second) }.groupingBy { it }.eachCount()
        val floors = js.filter { it.second.optString("floor").isNotEmpty() }
            .flatMap { j -> codesOf(j.second).map { it to j.second.optString("floor") } }.toMap()
        main.post {
            pending = js.size
            pendingByCode.keys.retainAll(by.keys); pendingByCode.putAll(by)
            queuedFloor.keys.retainAll(floors.keys); queuedFloor.putAll(floors)
        }
    }

    /** the codes a job's photo is of: its `codes` (one photo of several codes), else the one `kks` */
    private fun codesOf(job: JSONObject): List<String> =
        job.optJSONArray("codes")?.let { a -> (0 until a.length()).map { a.optString(it) }.filter { it.isNotEmpty() } }
            ?.takeIf { it.isNotEmpty() } ?: listOf(job.optString("kks"))

    /** how a job is named where it failed: "11LAB70AA501", or "11LAB70AA501 and 2 more" */
    private fun nameOf(codes: List<String>) = codes.first() + if (codes.size > 1) " and ${codes.size - 1} more" else ""

    /** queue one photo: returns at once; the pixels are written and the job enqueued on the queue's own thread.
     *  `codes`: one photo of several codes (Photo for all; `kks` is then the first of them) */
    fun add(ctx: Context, bmp: Bitmap, kks: String, caption: String, note: String, floor: String, codes: List<String> = emptyList()) {
        val app = ctx.applicationContext
        val id = UUID.randomUUID().toString().replace("-", "")       // also the submission's client_id: a rerun can't add it twice
        val all = codes.distinct().ifEmpty { listOf(kks) }
        main.post { pending += 1; for (c in all) { pendingByCode[c] = (pendingByCode[c] ?: 0) + 1; if (floor.isNotEmpty()) queuedFloor[c] = floor } }
        io.execute {
            if (wiped) return@execute
            try {
                val px = File(dir(app), "$id.px")
                val argb = if (bmp.config == Bitmap.Config.ARGB_8888) bmp else bmp.copy(Bitmap.Config.ARGB_8888, false)
                // width, height, then the pixels in memory order R, G, B, A (as Jxl.fromBitmap reads them back); sealed
                val buf = ByteBuffer.allocate(8 + argb.width * argb.height * 4)
                buf.putInt(argb.width).putInt(argb.height)
                argb.copyPixelsToBuffer(buf)
                px.writeBytes(Keys.seal(buf.array(), aad("px", id)))
                val job = JSONObject().put("kks", all.first()).put("caption", caption).put("note", note).put("floor", floor)
                    .put("at", System.currentTimeMillis())
                if (all.size > 1) job.put("codes", JSONArray(all))
                // the JSON last, through a rename: a job file is never seen half written
                val tmp = File(dir(app), "$id.json.tmp"); tmp.writeBytes(Keys.seal(job.toString().toByteArray(), aad("job", id)))
                if (!tmp.renameTo(File(dir(app), "$id.json"))) { tmp.delete(); throw java.io.IOException("could not write the job") }
                enqueue(app, id)
                refresh(app)
            } catch (e: Throwable) {
                Log.w(TAG, "could not queue a photo of $kks", e)
                File(dir(app), "$id.px").delete()
                fail(app, nameOf(all), "Could not keep the photo for sending (${e.message ?: e.javaClass.simpleName})")
                refresh(app)
            }
        }
    }

    private const val TRIES = 5

    private fun enqueue(ctx: Context, id: String, delaySeconds: Long = 0) {
        val req = OneTimeWorkRequestBuilder<PhotoWorker>().setInputData(workDataOf("job" to id)).addTag("job:$id")
            .setInitialDelay(delaySeconds, java.util.concurrent.TimeUnit.SECONDS).build()
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
    @Volatile private var wiped = false

    fun wipe(ctx: Context) {
        wiped = true
        // wait for a photo being written now, so nothing is left behind it
        runCatching { io.submit {}.get(5, java.util.concurrent.TimeUnit.SECONDS) }
        runCatching { WorkManager.getInstance(ctx).cancelUniqueWork(WORK) }
        dir(ctx).deleteRecursively()
        prefs(ctx).edit().clear().commit()
    }

    /** set only by the debug builds' test receiver: jobs wait while it is on (at most 2 minutes) */
    @Volatile var holdForTest = false
    /** set only by the debug builds' test receiver: the next this many encodes fail as if out of memory */
    @Volatile var failEncodesForTest = 0

    /** a failure that may pass later: keep the photo, count the try, and queue it again (true = keep the files) */
    private fun retry(ctx: Context, id: String, jf: File, job: JSONObject, kks: String, why: String): Boolean {
        val tries = job.optInt("tries") + 1
        job.put("tries", tries)
        val tmp = File(dir(ctx), "$id.json.tmp")
        tmp.writeBytes(Keys.seal(job.toString().toByteArray(), aad("job", id)))
        if (!tmp.renameTo(jf)) { tmp.delete(); fail(ctx, kks, "$why (the photo was lost)"); return false }
        if (tries < TRIES) enqueue(ctx, id, 60)
        else fail(ctx, kks, "$why. The photo is kept on this phone and tried again when the app next starts")
        return true
    }

    /** one job: encode, submit, forget (sent, refused or unreadable: each ends it; anything else retries) */
    internal fun run(ctx: Context, id: String) {
        val until = System.currentTimeMillis() + 120_000
        while (holdForTest && System.currentTimeMillis() < until) Thread.sleep(200)
        val jf = File(dir(ctx), "$id.json"); val px = File(dir(ctx), "$id.px")
        if (!jf.exists()) { px.delete(); refresh(ctx); return }      // already done (a rerun)
        val job = runCatching { readJob(jf, id) }.getOrNull()
        val codes = job?.let { codesOf(it) } ?: emptyList()
        val kks = if (codes.isEmpty()) "" else nameOf(codes)      // for the log and the failures
        // a job file the Keystore can't open now may open after a restart: kept, and init() queues it again then
        if (job == null && px.exists()) { Log.w(TAG, "job $id unreadable, kept"); return }
        var keep = false
        try {
            if (job == null || !px.exists()) { fail(ctx, kks.ifEmpty { "photo" }, "The queued photo was lost"); return }
            val plain = Keys.open(px.readBytes(), aad("px", id))
            val head = ByteBuffer.wrap(plain, 0, 8)
            val w = head.getInt(); val h = head.getInt()
            require(w > 0 && h > 0 && plain.size == 8 + w * h * 4) { "the queued photo is damaged" }
            val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888).also { it.copyPixelsFromBuffer(ByteBuffer.wrap(plain, 8, w * h * 4)) }
            val jxl = try {
                if (failEncodesForTest > 0) { failEncodesForTest--; throw OutOfMemoryError("test") }
                Jxl.fromBitmap(bmp)
            } catch (e: Throwable) {
                Log.w(TAG, "encode $kks", e); bmp.recycle()
                keep = retry(ctx, id, jf, job, kks, "Could not compress the photo"); return
            }
            bmp.recycle()
            val payload = JSONObject().put("caption", job.optString("caption"))
                .put("dataUrl", "data:image/jxl;base64," + Base64.encodeToString(jxl, Base64.NO_WRAP))
            job.optString("floor").takeIf { it.isNotEmpty() }?.let { payload.put("floor", it) }
            val body = JSONObject().put("kind", "photo").put("payload", payload).put("client_id", id)
            job.optString("note").takeIf { it.isNotBlank() }?.let { body.put("note", it.trim()) }
            // several codes: one submit-many (the image kept once; the job ID is the client_id prefix, so a rerun
            // after a crash sends no code twice); else the one submission it always was
            val r = if (codes.size > 1) Core.api("POST", "/api/submit-many", body.put("kks", JSONArray(codes)))
                    else { payload.put("kks", codes.first()); Core.api("POST", "/api/submit", body) }
            if (r.status >= 400) fail(ctx, kks, r.json.optString("error", "error ${r.status}"))
            else main.post { Changes.rev++ }
        } catch (e: IllegalArgumentException) {
            // a damaged file (the size check above): it won't get better
            Log.w(TAG, "photo of $kks", e)
            fail(ctx, kks.ifEmpty { "photo" }, "Could not send the photo (${e.message ?: e.javaClass.simpleName})")
        } catch (e: Throwable) {
            // anything else (out of memory, the Keystore, the core throwing): kept and tried again; the next photos still go
            Log.w(TAG, "photo of $kks", e)
            keep = job != null && runCatching {
                retry(ctx, id, jf, job, kks, "Could not send the photo (${e.message ?: e.javaClass.simpleName})")
            }.getOrDefault(false)
        } finally {
            if (!keep) { jf.delete(); px.delete() }
            refresh(ctx)
        }
    }
}

/** one queued photo (PhotoQueue): runs in the background, in order, also after the app closed or restarted */
class PhotoWorker(ctx: Context, params: WorkerParameters) : Worker(ctx, params) {
    override fun doWork(): Result {
        val id = inputData.getString("job") ?: return Result.success()
        try { PhotoQueue.run(applicationContext, id) } catch (e: Throwable) { android.util.Log.w("KKSPhotos", "job $id", e) }
        return Result.success()       // never fail the chain: the next photos must still go
    }
}

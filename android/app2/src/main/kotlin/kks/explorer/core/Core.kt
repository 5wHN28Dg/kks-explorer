package kks.explorer.core

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import org.json.JSONObject
import java.util.concurrent.Callable
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.Executors

/**
 * The Nim core (libkks.so, decision 0032). Every call runs on one thread ("kks-core"): the core is single-threaded.
 * Answers are the same JSON as the web pages get from the server.
 */
object Core {
    init { System.loadLibrary("kks") }

    @JvmStatic private external fun nInit()
    @JvmStatic private external fun nOpen(dir: ByteArray, key: ByteArray, handle: ByteArray, pub: ByteArray, label: ByteArray): Long
    @JvmStatic private external fun nApi(h: Long, meth: ByteArray, path: ByteArray, query: ByteArray, body: ByteArray): ByteArray
    @JvmStatic private external fun nFile(h: Long, path: ByteArray): ByteArray?
    @JvmStatic private external fun nSyncStart(h: Long, initiator: Boolean, remote: ByteArray, adopt: ByteArray): Long
    @JvmStatic private external fun nSyncFeed(s: Long, data: ByteArray): ByteArray
    @JvmStatic private external fun nSyncInfo(s: Long): ByteArray
    @JvmStatic private external fun nSyncEnd(s: Long)
    @JvmStatic private external fun nSheet(h: Long, id: ByteArray): ByteArray?
    @JvmStatic private external fun nFig(h: Long, id: Int, cmd: ByteArray): ByteArray?
    @JvmStatic private external fun nRudpNew(session: ByteArray, dead: Double, now: Double): Long
    @JvmStatic private external fun nRudpStep(id: Long, op: Int, data: ByteArray, now: Double): ByteArray

    private val thread = Executors.newSingleThreadExecutor { Thread(it, "kks-core") }
    private val main = Handler(Looper.getMainLooper())
    private var h = 0L
    val listeners = CopyOnWriteArrayList<(String) -> Unit>()

    /** the core's change notice (called on the core thread, from C) */
    @JvmStatic fun changed(why: ByteArray) {
        val w = why.toString(Charsets.UTF_8)
        main.post { listeners.forEach { it(w) } }
    }

    private fun <T> onCore(f: () -> T): T = thread.submit(Callable(f)).get()
    private fun b(s: String) = s.toByteArray(Charsets.UTF_8)

    fun open(ctx: Context) = onCore {
        nInit()
        if (h == 0L) {
            val dir = ctx.filesDir.resolve("core").absolutePath
            val t0 = android.os.SystemClock.elapsedRealtime()
            h = nOpen(b(dir), Keys.storageKey(ctx), b("ks:" + Keys.DEVICE), Keys.devicePublic(), b(Build.MODEL ?: "phone"))
            // measurements (docs/m6/MEASUREMENTS.md): the core's open, which replays the whole log
            android.util.Log.i("KKSTime", "core open + replay ${android.os.SystemClock.elapsedRealtime() - t0} ms")
            // the program's KKS decode tables (data/kks.json, shipped in the app)
            val tables = ctx.assets.open("data/kks.json").readBytes()
            nApi(h, b("POST"), b("/native/tables"), b("{}"), tables)
            // the app's own courses (data/courses, used when the plant has published none): JSON in, pictures by name
            val names = ctx.assets.list("data/courses")?.toList() ?: emptyList()
            val files = org.json.JSONArray()
            for (n in names.filter { it.endsWith(".json") })
                files.put(org.json.JSONArray().put(n).put(ctx.assets.open("data/courses/$n").readBytes().toString(Charsets.UTF_8)))
            val body = JSONObject().put("files", files).put("images", org.json.JSONArray(names.filter { it.endsWith(".jxl") }))
            nApi(h, b("POST"), b("/native/course-files"), b("{}"), b(body.toString()))
        }
    }

    data class Answer(val status: Int, val json: JSONObject, val bytes: ByteArray? = null)

    /** a request to the local API (or /native/… for the phone's own needs) */
    fun api(meth: String, path: String, body: JSONObject? = null, query: Map<String, String> = emptyMap()): Answer = onCore {
        val q = JSONObject(query)
        val raw = nApi(h, b(meth), b(path), b(q.toString()), b(body?.toString() ?: ""))
        val r = JSONObject(raw.toString(Charsets.UTF_8))
        val j = r.opt("json") as? JSONObject ?: JSONObject()
        Answer(r.getInt("status"), j, r.optString("bytes", "").takeIf { it.isNotEmpty() }?.let { android.util.Base64.decode(it, 0) })
    }

    fun file(path: String): ByteArray? = onCore { nFile(h, b(path)) }

    /** the reliable UDP stream of the direct path (core/src/kks/rudp.nim; the socket is sync/Direct.kt's) */
    fun rudpNew(session: ByteArray, dead: Double, now: Double): Long = onCore { nRudpNew(session, dead, now) }
    /** op 1 datagram in, 2 timers, 3 bytes out, 4 finish, 5 free → the packed result (Direct.Step) */
    fun rudpStep(id: Long, op: Int, data: ByteArray, now: Double): ByteArray = onCore { nRudpStep(id, op, data, now) }
    /** one frame of a course figure: u32 + state JSON + drawing ops (kksa/figops.nim); null when it is gone */
    fun fig(id: Int, cmd: JSONObject): ByteArray? = onCore { nFig(h, id, b(cmd.toString())) }
    /** a sheet's path store, decoded (views.flat layout) */
    fun sheet(id: String): ByteArray? = onCore { nSheet(h, b(id)) }

    // §15 sessions: the Kotlin side owns the TLS connection and feeds the plaintext through
    fun syncStart(initiator: Boolean, remote: String, adoptRoot: String = ""): Long = onCore { nSyncStart(h, initiator, b(remote), b(adoptRoot)) }
    fun syncFeed(s: Long, data: ByteArray): ByteArray = onCore { nSyncFeed(s, data) }
    fun syncInfo(s: Long): JSONObject = onCore { JSONObject(nSyncInfo(s).toString(Charsets.UTF_8)) }
    fun syncEnd(s: Long) = onCore { nSyncEnd(s) }
}

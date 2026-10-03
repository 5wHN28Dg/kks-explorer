package kks.explorer.sync

import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.util.Base64
import android.util.Log
import kks.explorer.App
import kks.explorer.core.Core
import kks.explorer.core.Net
import kks.explorer.core.WsClient
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.security.SecureRandom

/**
 * Moving from the v1 app on this phone (PROTOCOL-v2 §21a, decision 0042). The v1 app's bridge release (package
 * kks.explorer) answers through a provider only apps signed with our key may call. This side finds the
 * plant's v2 server with what the old app knew (its addresses, mDNS `prev`, the v1 relay room), gets the succession
 * statement, has the bridge check it and sign the move, sends that proof, syncs, and writes the old app's open
 * changes as this phone's own. All Ed25519 work stays in the bridge and on the server.
 */
object Migrate {
    const val OLD = "kks.explorer"
    private val HANDOVER = Uri.parse("content://kks.explorer.handover")

    /** where the server answered: an address on the Wi-Fi, or the relay's v1 room (with the server's peer ID) */
    private class Route(val host: String, val port: Int, val room: V1Room?, val peer: String) {
        fun ask(msg: JSONObject, expect: String): JSONObject =
            if (room != null) Net.askOver(room.open(peer, expect), msg) else Net.ask(host, port, expect, msg)
        fun sync(expect: String, adoptRoot: String): JSONObject =
            if (room != null) { val p = room.open(peer, expect); try { Net.drive(p, true, adoptRoot) } finally { p.close() } }
            else Net.syncWith(host, port, expect, adoptRoot)
        override fun toString() = if (room != null) "the internet relay" else "$host:$port"
    }

    /** the old app, installed and signed with the same key as this one (else nothing to move from) */
    fun oldAppPresent(ctx: Context): Boolean = try {
        ctx.packageManager.getPackageInfo(OLD, 0)
        ctx.packageManager.checkSignatures(ctx.packageName, OLD) == PackageManager.SIGNATURE_MATCH
    } catch (e: PackageManager.NameNotFoundException) { false }

    private fun call(ctx: Context, method: String, extras: Bundle? = null): JSONObject {
        val b = ctx.contentResolver.call(HANDOVER, method, null, extras)
            ?: throw IllegalStateException("KKS Explorer did not answer (is it the latest version?)")
        return JSONObject(b.getString("json") ?: "{}")
    }

    /** what the old app knows (no secrets): null when it has nothing to move (never joined a plant) */
    fun info(ctx: Context): JSONObject? = try {
        call(ctx, "info").takeIf { it.optString("v1_root").isNotEmpty() && it.optString("v1_device").isNotEmpty() }
    } catch (e: Exception) { Log.w("KKSSync", "move: no answer from the old app: ${e.message}"); null }

    /** the whole move; status gets what to show. "" = done, else what went wrong (the person can try again) */
    fun run(ctx: Context, status: (String) -> Unit): String {
        val inf = info(ctx) ?: return "KKS Explorer has no plant to move."
        val v1root = inf.getString("v1_root")
        status("Looking for the plant's server…")
        Discovery.start(ctx)
        if (Discovery.found().none { it.prev == v1root.take(16) }) Thread.sleep(3_000)     // a moment for mDNS answers
        var route: Route? = null
        var succ: JSONObject? = null
        var room: V1Room? = null
        try {
            for ((host, port) in candidates(inf)) {
                val a = try { Net.ask(host, port, "", JSONObject().put("t", "succession")) } catch (e: Exception) { Log.i("KKSSync", "move: $host:$port: ${e.message}"); continue }
                if (good(a, v1root)) { route = Route(host, port, null, a.getJSONObject("stmt").getString("server")); succ = a; break }
            }
            if (route == null && inf.optString("relay").isNotEmpty()) {
                status("Looking for the server through the internet…")
                room = V1Room(inf.getString("relay"), v1room(v1root))
                for (peer in room.peers()) {
                    if (peer.length != 32) continue          // v1 devices (43 characters) can't answer this
                    val a = try { Net.askOver(room.open(peer, ""), JSONObject().put("t", "succession")) } catch (e: Exception) { continue }
                    if (good(a, v1root) && a.getJSONObject("stmt").getString("server") == peer) { route = Route("", 0, room, peer); succ = a; break }
                }
            }
            if (route == null || succ == null)
                return "The plant's server didn't answer. Connect to the plant's Wi-Fi (or the internet) and try again."
            val stmt = succ.getJSONObject("stmt")
            val server = stmt.getString("server")
            // the bridge checks the statement against the v1 root it trusts, then signs the move and hands over
            status("Checking the server with KKS Explorer…")
            val cfg = Sync.config()
            val key = cfg.getString("key")
            val ho = call(ctx, "handover", Bundle().apply {
                putString("stmt", stmt.toString()); putString("sig", succ.getString("sig"))
                putString("device", cfg.getString("device")); putString("key", key); putString("label", Sync.label())
            })
            if (!ho.optBoolean("ok")) return ho.optString("why").ifEmpty { "KKS Explorer refused the move." }
            status("Moving this phone into the plant…")
            val ack = route.ask(JSONObject().put("t", "migrate").put("proof", ho.getJSONObject("proof")), server)
            if (ack.optString("state") != "accepted") return ack.optString("why").ifEmpty { "The server refused the move." }
            route.sync(server, if (cfg.optString("root").isEmpty()) stmt.getString("v2_root") else "")
            if (!Sync.joined()) return "Synced, but this phone is not certified in what came back. Try again."
            if (route.room == null) Sync.remember(ctx, route.host, route.port, server)
            // the old app's open changes, written as this phone's own (each once: client_id = the v1 entry ID)
            val entries = ho.optJSONArray("entries") ?: JSONArray()
            for (i in 0 until entries.length()) {
                val e = entries.getJSONObject(i)
                status("Bringing over your open changes (${i + 1} of ${entries.length()})…")
                val blobs = JSONObject()
                val shas = e.optJSONArray("blobs") ?: JSONArray()
                for (k in 0 until shas.length()) blobs.put(shas.getString(k), Base64.encodeToString(blob(ctx, shas.getString(k)), Base64.NO_WRAP))
                val r = Core.api("POST", "/native/v1-entry", JSONObject().put("v1", e.getString("v1")).put("type", e.getString("type"))
                    .put("body", e.getJSONObject("body")).put("note", e.optString("note")).put("blobs", blobs))
                if (r.status >= 400) Log.w("KKSSync", "move: change ${e.getString("v1").take(8)} not written: ${r.json.optString("error")}")
            }
            val prog = ho.optJSONObject("progress") ?: JSONObject()
            for (c in prog.keys()) runCatching { Core.api("POST", "/api/progress", JSONObject().put("course", c).put("data", prog.getJSONObject(c))) }
            status("Sending your changes to the server…")
            runCatching { route.sync(server, "") }
            runCatching { call(ctx, "done") }
            App.clearRemovedNote(ctx)
            Sync.report(ctx)
            return ""
        } catch (e: Exception) {
            Log.w("KKSSync", "move failed", e)
            return "The move stopped: ${e.message}. Nothing is lost; try again."
        } finally { room?.close() }
    }

    private fun good(a: JSONObject, v1root: String): Boolean {
        val st = a.optJSONObject("stmt") ?: return false
        return st.optString("kind") == "succession" && st.optString("v1_root") == v1root && a.optString("sig").isNotEmpty()
    }

    private fun blob(ctx: Context, sha: String): ByteArray {
        val b = ctx.contentResolver.openInputStream(Uri.withAppendedPath(HANDOVER, "blob/$sha"))!!.use { it.readBytes() }
        val got = MessageDigest.getInstance("SHA-256").digest(b).joinToString("") { "%02x".format(it) }
        if (got != sha) throw IllegalStateException("a photo from KKS Explorer does not match its hash")
        return b
    }

    /** the old app's remembered addresses, then servers on this Wi-Fi announcing the same v1 plant (TXT prev) */
    private fun candidates(inf: JSONObject): List<Pair<String, Int>> {
        val out = LinkedHashSet<Pair<String, Int>>()
        val prev = inf.getString("v1_root").take(16)
        Discovery.found().filter { it.prev == prev }.forEach { out.add(it.host to it.port) }
        val a = inf.optJSONArray("addrs") ?: JSONArray()
        for (i in 0 until a.length()) Sync.serverAddress(a.getString(i)).takeIf { it.first.isNotEmpty() }?.let { out.add(it) }
        return out.toList()
    }

    private fun v1room(v1root: String): String =
        MessageDigest.getInstance("SHA-256").digest("kks-relay-room-v1\n$v1root".toByteArray()).joinToString("") { "%02x".format(it) }.take(32)

    /** presence in the v1 plant's relay room, long enough to reach the server there (PROTOCOL-v2 §21a, §18) */
    private class V1Room(val relay: String, val room: String) {
        private val ws = WsClient("$relay/v1/room/$room")
        private val rng = SecureRandom()
        private val peers = ArrayList<String>()
        init {
            ws.setTimeout(15_000)
            ws.sendText(Core.api("POST", "/native/relay-hello", JSONObject().put("room", room)).json.getJSONObject("hello").toString())
            while (true) {
                val (op, data) = ws.recv()
                if (op != WsClient.TEXT) continue
                val m = JSONObject(String(data, Charsets.UTF_8))
                if (m.optString("t") == "error") throw IllegalStateException("relay: ${m.optString("why")}")
                if (m.optString("t") == "welcome") {
                    val a = m.optJSONArray("peers") ?: JSONArray()
                    for (i in 0 until a.length()) peers.add(a.getString(i))
                    break
                }
            }
        }
        fun peers(): List<String> = peers.toList()

        /** connect (no candidates: the pipe), then TLS as the client */
        fun open(peer: String, expect: String): Net.Peer {
            val id = ByteArray(16).also { rng.nextBytes(it) }.joinToString("") { "%02x".format(it) }
            ws.sendText(JSONObject().put("t", "connect").put("to", peer).put("id", id).put("cand", JSONArray()).toString())
            while (true) {
                val (op, data) = ws.recv()
                if (op != WsClient.TEXT) continue
                val m = JSONObject(String(data, Charsets.UTF_8))
                if (m.optString("id") != id) continue
                when (m.optString("t")) {
                    "accept" -> return Net.overPipe(WsClient("$relay/v1/pipe/$room/$id/a"), client = true, expectPeer = expect)
                    "gone", "refuse" -> throw IllegalStateException("the server left the relay")
                }
            }
        }
        fun close() = ws.close()
    }
}

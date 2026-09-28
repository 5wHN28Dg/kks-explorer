package kks.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File
import java.net.HttpURLConnection
import java.net.ServerSocket
import java.net.URI
import java.util.zip.GZIPInputStream
import kotlin.concurrent.thread

/** The phone's local API (peer mode), exercised the way the web UI calls it. */
@Suppress("UNCHECKED_CAST")
class LocalApiTest {
    /** Sync through the real protocol (TCP on localhost). */
    class TcpSync(private val node: () -> LocalNode) : SyncControl {
        override val port: Int? = null
        override fun syncOne(host: String, port: Int, adoptRoot: String?) = Sync.syncWith(node(), host, port, adoptRoot).second
        override fun syncAll() {}
        override fun snapshot() = mapOf<String, Any?>("discovery" to "off", "found" to emptyList<Any>(), "syncs" to emptyMap<String, Any>())
        override fun joined() {}
    }

    class Phone(label: String = "phone") {
        val node = LocalNode.open(MemStore())
        val api = LocalApi(node, TcpSync { node }).also { it.deviceLabel = label }
        fun get(path: String): Pair<Int, Map<String, Any?>> {
            val (p, qs) = path.split("?", limit = 2).let { it[0] to (it.getOrNull(1) ?: "") }
            val q = qs.split("&").filter { "=" in it }.associate { it.substringBefore("=") to it.substringAfter("=") }
            val r = api.handle("GET", p, q, null)
            return r.status to (r.json as Map<String, Any?>? ?: emptyMap())
        }
        fun post(path: String, body: Any? = emptyMap<String, Any?>()): Pair<Int, Map<String, Any?>> {
            val r = api.handle("POST", path, emptyMap(), if (body is ByteArray) body else Json.parse(Json.write(body)))
            return r.status to (r.json as Map<String, Any?>)
        }
    }

    /** A plant made by a manager laptop (MemoryNode), with the phone certified for a person of `role`. */
    class Plant(role: String = "admin") {
        val root = SigningKey.generate()
        val mgrKey = SigningKey.generate()
        val mgr = MemoryNode(mgrKey, root.peerId)
        val m = Payloads.newId()
        val phone = Phone()
        val person = Payloads.newId()
        val userKey = SigningKey.generate()
        val user = MemoryNode(userKey, root.peerId)
        val userPerson = Payloads.newId()
        init {
            val sm = mapOf("kind" to "manager", "person" to m)
            val sd = mapOf("kind" to "device", "device" to mgrKey.peerId, "person" to m)
            mgr.append("genesis", mapOf("plant" to "Test plant", "root" to root.peerId,
                "manager" to mapOf("person" to m, "username" to "boss", "full_name" to "Boss Person", "position" to null),
                "stmt_manager" to sm, "stmt_device" to sd, "sig_manager" to Replay.signStatement(root, sm), "sig_device" to Replay.signStatement(root, sd)))
            mgr.append("person", mapOf("person" to person, "username" to "me", "full_name" to "Me Myself", "position" to null, "role" to role))
            mgr.append("device_cert", mapOf("device" to phone.node.device, "person" to person, "label" to "phone"))
            mgr.append("person", mapOf("person" to userPerson, "username" to "usr", "full_name" to "Usr Person", "position" to null, "role" to "user"))
            mgr.append("device_cert", mapOf("device" to userKey.peerId, "person" to userPerson, "label" to "laptop"))
            val bundle = phone.node.let { mgr.entriesFor(emptyMap<String, Any>()) }
            phone.node.adopt(root.peerId)
            phone.node.ingest(bundle)
            user.ingest(mgr.entriesFor(emptyMap<String, Any>()))
        }
        /** Hand entries both ways, as a sync would. */
        fun exchange(a: Node, b: Node) { b.ingest(a.entriesFor(b.vv())); a.ingest(b.entriesFor(a.vv())) }
    }

    @Test fun beforeJoining() {
        val p = Phone()
        val (_, cfg) = p.get("/api/config")
        assertEquals(false, (cfg["node"] as Map<*, *>)["joined"])
        assertEquals(false, (cfg["node"] as Map<*, *>)["can_create"])
        assertEquals(401, p.get("/api/state").first)
        assertEquals(400, p.post("/api/node/new-plant", mapOf("username" to "x", "full_name" to "X Person")).first)   // root keys stay off phones
        val (s, r) = p.post("/api/node/join-request", mapOf("username" to "carol", "full_name" to "Carol Person", "position" to "Technician"))
        assertEquals(200, s)
        val req = r["request"] as Map<String, Any?>
        assertEquals(p.node.device, req["device"])
        p.api.checkJoinRequest(req)   // signed by the phone's own key
        assertEquals(400, runCatching { p.api.checkJoinRequest(req + ("username" to "boss")) }.fold({ 200 }, { (it as ApiError).status }))
    }

    @Test fun joinWithBundleThenWork() {
        val pl = Plant("admin")
        val admin = pl.phone
        // a second phone joins through admin: join request → import on the admin phone → bundle → import
        val newbie = Phone("carol-phone")
        val req = newbie.post("/api/node/join-request", mapOf("username" to "carol", "full_name" to "Carol Person"))
        assertEquals(200, admin.post("/api/devices/import-request", mapOf("request" to req.second["request"])).first)
        val bundle = admin.api.handle("GET", "/api/bundle", mapOf("photos" to "1"), null)
        assertEquals("application/gzip", bundle.contentType)
        assertTrue(Json.parse(GZIPInputStream(bundle.bytes!!.inputStream()).readBytes()) is Map<*, *>)
        val (s, r) = newbie.post("/api/bundle/import", bundle.bytes!!)
        assertEquals(200, s); assertEquals(true, r["joined"])
        assertEquals("carol", (newbie.get("/api/me").second["user"] as Map<*, *>)["username"])
        // the user phone proposes; the proposal reaches the admin phone and shows in Approvals by name
        assertEquals("pending", newbie.post("/api/submit", mapOf("kind" to "link", "client_id" to "c-00000001",
            "payload" to mapOf("proc" to "3.6.1", "step" to 2, "kks" to "11LAB70AA501"))).second["status"])
        assertEquals(true, newbie.post("/api/submit", mapOf("kind" to "link", "client_id" to "c-00000001",
            "payload" to mapOf("proc" to "3.6.1", "step" to 2, "kks" to "11LAB70AA501"))).second["duplicate"])
        pl.exchange(newbie.node, admin.node)
        val subs = admin.get("/api/submissions").second["submissions"] as List<Map<String, Any?>>
        assertEquals(listOf("Carol Person"), subs.map { it["by_name"] })
        assertEquals(200, admin.post("/api/submissions/${subs[0]["id"]}/approve").first)
        pl.exchange(newbie.node, admin.node)
        assertEquals(1, (newbie.get("/api/state").second["links"] as List<*>).size)
        val mine = newbie.get("/api/submissions?status=all").second["submissions"] as List<Map<String, Any?>>
        assertEquals("approved", mine.single()["status"])
        // users list shows carol (own device, no account here)
        val users = admin.get("/api/users").second["users"] as List<Map<String, Any?>>
        assertEquals(true, users.first { it["username"] == "carol" }["no_account"])
    }

    @Test fun mergeConflictsForceAndHistory() {
        val pl = Plant("admin")
        val a = pl.phone
        val k = "11LAB70AA501"
        assertEquals("approved", a.post("/api/submit", mapOf("kind" to "equipment", "payload" to mapOf("kks" to k,
            "changes" to mapOf("floor" to "6", "notes" to "n")))).second["status"])
        // the user (another device) edits floor from a stale base while the admin changes it
        val prop = pl.user.let { pl.exchange(it, a.node); it.append("equipment", mapOf("kks" to k, "changes" to mapOf("floor" to "9"), "base" to mapOf("floor" to "6"))) }
        a.post("/api/submit", mapOf("kind" to "equipment", "payload" to mapOf("kks" to k, "changes" to mapOf("floor" to "7"), "base" to mapOf("floor" to "6"))))
        pl.exchange(pl.user, a.node)
        val sub = (a.get("/api/submissions").second["submissions"] as List<Map<String, Any?>>).single()
        assertEquals("conflict", sub["status"])
        val (s, r) = a.post("/api/submissions/${sub["id"]}/approve")
        assertEquals(409, s); assertEquals("7", (r["conflicts"] as List<Map<*, *>>)[0]["live"])
        assertEquals(200, a.post("/api/submissions/${sub["id"]}/approve", mapOf("force" to true)).first)
        assertEquals("9", ((a.get("/api/state").second["equipment"] as Map<*, *>)[k] as Map<*, *>)["floor"])
        assertTrue(a.node.run.proposals[prop] == "approved")
        // an admin change that clashes is held, then forced
        val held = a.post("/api/submit", mapOf("kind" to "equipment", "payload" to mapOf("kks" to k, "changes" to mapOf("notes" to "stale"), "base" to mapOf("notes" to "old"))))
        assertEquals("conflict", held.second["status"])
        assertEquals(409, a.post("/api/submissions/${held.second["id"]}/approve").first)
        assertEquals(200, a.post("/api/submissions/${held.second["id"]}/approve", mapOf("force" to true)).first)
        // History: stable row IDs; revert and restore
        val revs = a.get("/api/revisions").second["revisions"] as List<Map<String, Any?>>
        assertTrue(revs.size >= 4 && revs.all { (it["hid"] as String).isNotEmpty() })
        val first = revs.last()
        assertEquals(409, a.post("/api/revisions/${first["hid"]}/revert").first)          // changed again since
        assertEquals(200, a.post("/api/restore", mapOf("hid" to first["hid"])).first)
        assertEquals(mapOf("floor" to "6", "notes" to "n"), (a.get("/api/state").second["equipment"] as Map<*, *>)[k])
        assertEquals(200, a.post("/api/restore", mapOf("rev" to 0)).first)
        assertEquals(emptyMap<String, Any>(), a.get("/api/state").second["equipment"])
    }

    @Test fun photosVotesPickAndTags() {
        val pl = Plant("admin")
        val a = pl.phone
        val jpeg = "data:image/jpeg;base64," + java.util.Base64.getEncoder().encodeToString(byteArrayOf(-1, -40, -1, -32) + ByteArray(80) { 7 })
        val png = "data:image/png;base64," + java.util.Base64.getEncoder().encodeToString("<svg>".toByteArray())
        assertEquals(400, a.post("/api/submit", mapOf("kind" to "photo", "payload" to mapOf("kks" to "11LAB70AA501", "dataUrl" to png))).first)
        // two user photos for one item arrive by sync; the admin votes and picks one
        for (n in 1..2) {
            val bytes = byteArrayOf(-1, -40, -1, -32) + ByteArray(50) { n.toByte() }
            val sha = sha256(bytes).hex()
            pl.user.blobs[sha] = bytes
            pl.user.append("photo", mapOf("photo" to Payloads.newId(), "kks" to "11LAB70AA501", "blob" to sha, "caption" to "p$n"))
        }
        pl.exchange(pl.user, a.node)
        for (sha in a.node.blobWants()) assertTrue(a.node.blobPut(sha, pl.user.blobGet(sha)!!))
        val subs = a.get("/api/submissions").second["submissions"] as List<Map<String, Any?>>
        assertEquals(2, subs.size)
        assertEquals(200, a.post("/api/submissions/${subs[0]["id"]}/vote").first)
        assertEquals(1L, (a.get("/api/submissions").second["submissions"] as List<Map<String, Any?>>).first { it["id"] == subs[0]["id"] }["votes"])
        assertEquals(1L, a.post("/api/submissions/${subs[0]["id"]}/pick").second["rejected"])
        val photos = a.get("/api/state").second["photos"] as List<Map<String, Any?>>
        assertTrue((photos.single()["file"] as String).endsWith(".jpg"))
        // an admin's own photo applies directly
        assertEquals("approved", a.post("/api/submit", mapOf("kind" to "photo", "payload" to mapOf("kks" to "11LAB70AA502", "dataUrl" to jpeg))).second["status"])
        // a mark with a corrected code
        val t = pl.user.append("tag_add", mapOf("tag" to Payloads.newId(), "sheet" to "hp", "bbox" to listOf(1000L, 2000L, 1800L, 2300L),
                                                "kks" to "11LAB90CP502", "suffix" to "", "isa" to "PI", "note" to ""))
        pl.exchange(pl.user, a.node)
        val ts = (a.get("/api/submissions").second["submissions"] as List<Map<String, Any?>>).single { it["kind"] == "tag_add" }
        assertEquals(listOf(100.0, 200.0, 180.0, 230.0), (ts["payload"] as Map<*, *>)["bbox"])
        assertEquals(200, a.post("/api/submissions/${ts["id"]}/approve", mapOf("edit" to mapOf("kks" to "11LAB90CP501", "isa" to "PI"))).first)
        assertEquals("approved", a.node.run.proposals[t])
        assertEquals("11LAB90CP501", ((a.get("/api/state").second["added_tags"] as List<Map<String, Any?>>).single())["kks"])
    }

    @Test fun peopleAndDevices() {
        val pl = Plant("admin")
        val a = pl.phone
        val users = a.get("/api/users").second["users"] as List<Map<String, Any?>>
        val usr = users.first { it["username"] == "usr" }
        assertEquals(403, a.post("/api/persons/${pl.m}", mapOf("active" to false)).first)                  // not the manager
        assertEquals(200, a.post("/api/persons/${usr["person"]}", mapOf("full_name" to "Usr Renamed")).first)
        assertEquals("Usr Renamed", a.node.run.persons[usr["person"]]!!["full_name"])
        assertEquals(403, a.post("/api/persons/${usr["person"]}", mapOf("role" to "admin")).first)         // only the manager promotes
        val devs = a.get("/api/devices").second
        assertEquals(listOf(true), (devs["mine"] as List<Map<*, *>>).map { it["this_computer"] })
        assertEquals(400, a.post("/api/devices/revoke", mapOf("device" to a.node.device)).first)
        assertEquals(200, a.post("/api/devices/revoke", mapOf("device" to pl.userKey.peerId)).first)
        assertTrue(pl.userKey.peerId in a.node.run.cuts)
        assertEquals(200, a.post("/api/profile", mapOf("full_name" to "Me Again", "position" to "Engineer")).first)
        assertEquals("Engineer", (a.get("/api/me").second["user"] as Map<*, *>)["position"])
        assertEquals(403, Plant("user").phone.get("/api/users").first)
    }

    /** The real Python server (app.py, server mode) in another process: the phone joins it with an account. */
    @Test fun joinThroughRealServer() {
        val py = File(repo(), ".venv/bin/python")
        assumeTrue("needs the repo's .venv", py.canExecute())
        val tmp = kotlin.io.path.createTempDirectory("kks-server").toFile()
        val port = ServerSocket(0).use { it.localPort }
        val syncPort = ServerSocket(0).use { it.localPort }
        File(tmp, "data").mkdirs()
        File(tmp, "data/tags.json").writeText("[]"); File(tmp, "data/sheets.json").writeText("[]")
        File(tmp, "config.json").writeText(Json.write(mapOf("host" to "127.0.0.1", "port" to port.toLong(), "sync_port" to syncPort.toLong(),
            "discovery" to false, "data_dir" to "data", "db" to "plant.db", "photos_dir" to "photos", "backup_dir" to "backups")))
        val proc = ProcessBuilder(py.path, File(repo(), "app.py").path).redirectErrorStream(true)
            .also { it.environment()["KKS_CONFIG"] = File(tmp, "config.json").path; it.environment()["PYTHONUNBUFFERED"] = "1" }.start()
        try {
            val lines = proc.inputStream.bufferedReader()
            var token: String? = null
            while (true) {
                val l = lines.readLine() ?: error("server stopped")
                Regex("#setup=(\\S+)").find(l)?.let { token = it.groupValues[1] }
                if ("Ctrl+C" in l) break
            }
            thread(isDaemon = true) { lines.forEachLine { } }
            val web = Web("http://127.0.0.1:$port")
            assertEquals(200, web.post("/api/setup", mapOf("token" to token, "username" to "boss", "password" to "correct horse", "full_name" to "Boss Person")).first)
            val link = web.post("/api/users", mapOf("username" to "usr", "role" to "user", "full_name" to "Usr Person")).second["link"] as String
            assertEquals(200, Web("http://127.0.0.1:$port").post("/api/password-reset", mapOf("token" to link.substringAfter("#reset="), "password" to "usr password!")).first)
            web.post("/api/submit", mapOf("kind" to "link", "payload" to mapOf("proc" to "3.6.1", "step" to 1, "kks" to "11LAB70AA501")))
            val phone = Phone()
            assertEquals(400, phone.post("/api/node/join-server", mapOf("url" to "127.0.0.1:$port", "username" to "usr", "password" to "wrong password!")).first)
            val (s, r) = phone.post("/api/node/join-server", mapOf("url" to "http://127.0.0.1:$port", "username" to "usr", "password" to "usr password!"))
            assertEquals(r.toString(), 200, s)
            val me = phone.get("/api/me").second["user"] as Map<*, *>
            assertEquals("usr" to "user", me["username"] to me["role"])
            assertEquals(1, (phone.get("/api/state").second["links"] as List<*>).size)
            // the phone's proposal reaches the server's Approvals; the approval comes back
            phone.post("/api/submit", mapOf("kind" to "link", "payload" to mapOf("proc" to "3.6.1", "step" to 2, "kks" to "11LAB70AA501")))
            assertEquals(200, phone.post("/api/sync/now", mapOf("address" to "127.0.0.1:$syncPort")).first)
            val sub = (web.get("/api/submissions").second["submissions"] as List<Map<String, Any?>>).single()
            assertEquals("Usr Person", sub["by_name"])
            assertEquals(200, web.post("/api/submissions/${sub["id"]}/approve", emptyMap<String, Any?>()).first)
            phone.post("/api/sync/now", mapOf("address" to "127.0.0.1:$syncPort"))
            assertEquals(2, (phone.get("/api/state").second["links"] as List<*>).size)
            assertNotNull(phone.node.owner())

            // join by invite (PROTOCOL.md §16): the server's admin shows a QR code, a new phone asks, the admin accepts
            val inv = web.post("/api/invites", emptyMap<String, Any?>()).second["invite"] as Map<String, Any?>
            val code = Json.write(inv + ("addrs" to listOf("127.0.0.1:$syncPort")))    // (the test server listens on loopback only)
            val p2 = Phone("phone 2").also { it.api.invitePollMs = 100 }
            assertEquals(200, p2.post("/api/node/join-invite", mapOf("invite" to code, "username" to "newbie", "full_name" to "New Person")).first)
            val asked = waitFor { web.get("/api/invites/${inv["token"]}").second.takeIf { it["state"] == "asked" } }
            assertEquals(p2.node.device, (asked["request"] as Map<*, *>)["device"])
            assertEquals(200, web.post("/api/invites/${inv["token"]}", mapOf("action" to "accept")).first)
            waitFor { p2.get("/api/node/join-invite").second.takeIf { it["state"] == "joined" } }
            assertEquals("newbie", (p2.get("/api/me").second["user"] as Map<*, *>)["username"])
            assertEquals(2, (p2.get("/api/state").second["links"] as List<*>).size)
            // the Python server removes that phone; its next sync shows it the proof and the phone wipes itself
            var wiped = false
            p2.node.onWiped = { wiped = true }
            assertEquals(200, web.post("/api/devices/revoke", mapOf("device" to p2.node.device)).first)
            assertTrue(runCatching { Sync.syncWith(p2.node, "127.0.0.1", syncPort) }.exceptionOrNull()?.message?.contains("removed") == true)
            assertTrue(wiped)
            assertEquals(401, p2.get("/api/me").first)
        } finally {
            proc.destroy(); proc.waitFor()
            tmp.deleteRecursively()
        }
    }

    private fun <T> waitFor(fn: () -> T?): T {
        repeat(200) { fn()?.let { return it }; Thread.sleep(50) }
        error("timed out")
    }

    /** A phone that listens for sync connections (like PhoneSync), for invites. */
    class Listening : SyncControl {
        val node = LocalNode.open(MemStore())
        private val srv = ServerSocket(0)
        init { thread(isDaemon = true) { while (!srv.isClosed) { val s = runCatching { srv.accept() }.getOrNull() ?: break; thread(isDaemon = true) { runCatching { Sync.serveOne(node, s) } } } } }
        override val port: Int? = srv.localPort
        override fun addresses() = listOf("127.0.0.1:${srv.localPort}")
        override fun syncOne(host: String, port: Int, adoptRoot: String?) = Sync.syncWith(node, host, port, adoptRoot).second
        override fun syncAll() {}
        override fun snapshot() = mapOf<String, Any?>("discovery" to "off", "found" to emptyList<Any>(), "syncs" to emptyMap<String, Any>())
        override fun joined() {}
        fun close() = srv.close()
    }

    /** An admin phone shows an invite; a new phone joins through it; one use; refusing; an existing username. */
    @Test fun joinByInviteBetweenPhones() {
        val pl = Plant("admin")
        val lis = Listening()
        try {
            // the admin phone of the plant, now with a listener: move the plant into the listening node
            lis.node.adopt(pl.root.peerId); lis.node.ingest(pl.mgr.entriesFor(emptyMap<String, Any>()))
            pl.mgr.append("device_cert", mapOf("device" to lis.node.device, "person" to pl.person, "label" to "admin phone"))
            lis.node.ingest(pl.mgr.entriesFor(lis.node.vv()))
            val admin = LocalApi(lis.node, lis)
            fun get(p: String) = admin.handle("GET", p, emptyMap(), null).let { it.status to (it.json as Map<String, Any?>) }
            fun post(p: String, b: Map<String, Any?>) = admin.handle("POST", p, emptyMap(), b).let { it.status to (it.json as Map<String, Any?>) }
            assertEquals(403, Plant("user").phone.post("/api/invites").first)
            val (s, r) = post("/api/invites", emptyMap())
            assertEquals(200, s)
            val inv = r["invite"] as Map<String, Any?>
            val tok = inv["token"] as String
            assertEquals(lis.node.device, inv["peer"])
            assertEquals(400, Phone().post("/api/node/join-invite", mapOf("invite" to "{}", "username" to "x1", "full_name" to "X")).first)
            val p2 = Phone("phone 2").also { it.api.invitePollMs = 50 }
            assertEquals(200, p2.post("/api/node/join-invite", mapOf("invite" to r["code"], "username" to "newbie", "full_name" to "New Person")).first)
            waitFor { get("/api/invites/$tok").second.takeIf { it["state"] == "asked" } }
            waitFor { p2.get("/api/node/join-invite").second.takeIf { it["state"] == "waiting" } }
            val other = Phone("phone 3")
            val req3 = JoinRequests.make(other.node.identity(), other.node.device, "zed", "Zed", null, "x", 1)
            assertEquals("used", Sync.joinAsk(other.node.identity(), "127.0.0.1", lis.port!!, lis.node.device, tok, req3).first)
            assertEquals(200, post("/api/invites/$tok", mapOf("action" to "accept")).first)
            waitFor { p2.get("/api/node/join-invite").second.takeIf { it["state"] == "joined" } }
            assertEquals("newbie", (p2.get("/api/me").second["user"] as Map<*, *>)["username"])
            assertEquals(409, post("/api/invites/$tok", mapOf("action" to "accept")).first)
            // an existing username needs the admin's OK; refusing tells the phone
            val (_, r2) = post("/api/invites", emptyMap())
            val tok2 = (r2["invite"] as Map<*, *>)["token"] as String
            val p3 = Phone("phone 3b").also { it.api.invitePollMs = 50 }
            p3.post("/api/node/join-invite", mapOf("invite" to r2["code"], "username" to "usr", "full_name" to "Usr Person"))
            val st = waitFor { get("/api/invites/$tok2").second.takeIf { it["state"] == "asked" } }
            assertEquals("usr", (st["existing"] as Map<*, *>)["username"])
            assertEquals(409, post("/api/invites/$tok2", mapOf("action" to "accept")).first)
            assertEquals(200, post("/api/invites/$tok2", mapOf("action" to "refuse")).first)
            val f = waitFor { p3.get("/api/node/join-invite").second.takeIf { it["state"] == "failed" } }
            assertTrue((f["error"] as String).contains("refused"))
        } finally { lis.close() }
    }

    /** §16 without a token: a new phone asks an admin phone found on the Wi-Fi; the codes match; accept; confirm. */
    @Test fun joinNearbyWithoutInvite() {
        assertEquals("423442", joinCode("A".repeat(43), "b".repeat(43)))          // same as server/node.join_code
        assertEquals("865675", joinCode("x", "y"))
        val pl = Plant("admin")
        val lis = Listening()
        try {
            lis.node.adopt(pl.root.peerId); lis.node.ingest(pl.mgr.entriesFor(emptyMap<String, Any>()))
            pl.mgr.append("device_cert", mapOf("device" to lis.node.device, "person" to pl.person, "label" to "admin phone"))
            lis.node.ingest(pl.mgr.entriesFor(lis.node.vv()))
            val admin = LocalApi(lis.node, lis)
            fun get(p: String) = admin.handle("GET", p, emptyMap(), null).let { it.status to (it.json as Map<String, Any?>) }
            fun post(p: String, b: Map<String, Any?>) = admin.handle("POST", p, emptyMap(), b).let { it.status to (it.json as Map<String, Any?>) }
            val p2 = Phone("laptop-ish").also { it.api.invitePollMs = 50 }
            val near = mapOf("peer" to lis.node.device, "host" to "127.0.0.1", "port" to lis.port!!.toLong(), "plant" to "Test plant")
            assertEquals(200, p2.post("/api/node/join-invite", mapOf("nearby" to near, "username" to "lina", "full_name" to "Lina Person")).first)
            val reqs = waitFor { (get("/api/join-requests").second["requests"] as List<Map<String, Any?>>).takeIf { it.isNotEmpty() } }
            val code = p2.get("/api/node/join-invite").second["code"]
            assertEquals(code, reqs[0]["code"])
            assertEquals(200, post("/api/join-requests/${reqs[0]["device"]}", mapOf("action" to "accept")).first)
            waitFor { p2.get("/api/node/join-invite").second.takeIf { it["state"] == "confirm" } }
            assertEquals(null, p2.node.owner())                                     // nothing trusted before the OK
            assertEquals(200, p2.post("/api/node/join-invite", mapOf("confirm" to true)).first)
            waitFor { p2.get("/api/node/join-invite").second.takeIf { it["state"] == "joined" } }
            assertEquals("lina", (p2.get("/api/me").second["user"] as Map<*, *>)["username"])
        } finally { lis.close() }
    }

    /** An app.py process (server or peer mode) in a temp folder. */
    class Py(mode: String) : AutoCloseable {
        val tmp = kotlin.io.path.createTempDirectory("kks-py").toFile()
        val port = ServerSocket(0).use { it.localPort }
        val syncPort = ServerSocket(0).use { it.localPort }
        var setupToken: String? = null
        private val proc: Process
        init {
            File(tmp, "data").mkdirs()
            File(tmp, "data/tags.json").writeText("[]"); File(tmp, "data/sheets.json").writeText("[]")
            File(tmp, "config.json").writeText(Json.write(mapOf("mode" to mode, "host" to "127.0.0.1", "port" to port.toLong(),
                "sync_port" to syncPort.toLong(), "sync_host" to "127.0.0.1", "discovery" to false, "data_dir" to "data",
                "db" to "plant.db", "photos_dir" to "photos", "backup_dir" to "backups")))
            proc = ProcessBuilder(File(repo(), ".venv/bin/python").path, File(repo(), "app.py").path).redirectErrorStream(true)
                .also { it.environment()["KKS_CONFIG"] = File(tmp, "config.json").path; it.environment()["PYTHONUNBUFFERED"] = "1" }.start()
            val lines = proc.inputStream.bufferedReader()
            while (true) {
                val l = lines.readLine() ?: error("app.py stopped")
                Regex("#setup=(\\S+)").find(l)?.let { setupToken = it.groupValues[1] }
                if ("Ctrl+C" in l) break
            }
            thread(isDaemon = true) { lines.forEachLine { } }
        }
        fun web() = Web("http://127.0.0.1:$port")
        override fun close() { proc.destroy(); proc.waitFor(); tmp.deleteRecursively() }
    }

    /** M4 across implementations: a Python laptop and a Kotlin phone of the same person swap person secrets (§17)
     *  and read each other's course progress; the server between them relays it without being able to read it. */
    @Test fun courseProgressAcrossPythonAndKotlin() {
        assumeTrue("needs the repo's .venv", File(repo(), ".venv/bin/python").canExecute())
        Py("server").use { srv -> Py("peer").use { lap ->
            val boss = srv.web()
            assertEquals(200, boss.post("/api/setup", mapOf("token" to srv.setupToken, "username" to "boss", "password" to "correct horse", "full_name" to "Boss Person")).first)
            val link = boss.post("/api/users", mapOf("username" to "usr", "role" to "user", "full_name" to "Usr Person")).second["link"] as String
            assertEquals(200, srv.web().post("/api/password-reset", mapOf("token" to link.substringAfter("#reset="), "password" to "usr password!")).first)
            val join = mapOf("url" to "http://127.0.0.1:${srv.port}", "username" to "usr", "password" to "usr password!")
            val laptop = lap.web()
            assertEquals(200, laptop.post("/api/node/join-server", join).first)
            assertEquals(200, laptop.post("/api/progress", mapOf("course" to "ppt", "data" to mapOf("solved" to "{\"q1\":true}", "finalBest" to "7"))).first)
            val phone = Phone()
            assertEquals(200, phone.post("/api/node/join-server", join).first)
            assertEquals(emptyMap<String, Any>(), phone.get("/api/progress").second["courses"])       // nothing yet
            val (remote, _) = Sync.syncWith(phone.node, "127.0.0.1", lap.syncPort)                       // straight to the laptop
            assertEquals(1, Progress.swapAfterSync(phone.node, "127.0.0.1", lap.syncPort, remote))
            val got = phone.get("/api/progress?course=ppt").second["data"] as Map<*, *>
            assertEquals("{\"q1\":true}" to "7", got["solved"] to got["finalBest"])
            assertEquals(200, phone.post("/api/progress", mapOf("course" to "ppt", "data" to mapOf("solved" to "{\"q2\":true}", "finalBest" to "5.5"))).first)
            Sync.syncWith(phone.node, "127.0.0.1", srv.syncPort)                                         // via the server this time
            laptop.post("/api/sync/now", mapOf("address" to "127.0.0.1:${srv.syncPort}"))
            val onLaptop = laptop.get("/api/progress?course=ppt").second["data"] as Map<*, *>
            assertEquals(mapOf("q1" to true, "q2" to true), Json.parse(onLaptop["solved"] as String))
            assertEquals("7", onLaptop["finalBest"])
            assertEquals(404, boss.get("/api/progress").first)                                         // the server keeps none
        } }
    }

    /** Field report 2026-09-28: a user asks to delete an admin's photo, the admin rejects; both keep syncing and the
     *  user sees "rejected" (not "waiting") without restarting. Phones = real sync over TCP both ways. */
    @Test fun photoDeleteRequestRejectedBetweenPhones() {
        val pl = Plant("admin")
        val adm = Listening(); val usr = Listening()
        try {
            adm.node.adopt(pl.root.peerId); adm.node.ingest(pl.mgr.entriesFor(emptyMap<String, Any>()))
            pl.mgr.append("device_cert", mapOf("device" to adm.node.device, "person" to pl.person, "label" to "admin phone"))
            usr.node.adopt(pl.root.peerId)
            pl.mgr.append("device_cert", mapOf("device" to usr.node.device, "person" to pl.userPerson, "label" to "user phone"))
            adm.node.ingest(pl.mgr.entriesFor(adm.node.vv())); usr.node.ingest(pl.mgr.entriesFor(usr.node.vv()))
            val a = LocalApi(adm.node, adm); val u = LocalApi(usr.node, usr)
            fun call(api: LocalApi, m: String, p: String, b: Any? = null) = api.handle(m, p.substringBefore('?'),
                p.substringAfter('?', "").split("&").filter { "=" in it }.associate { it.substringBefore("=") to it.substringAfter("=") },
                b?.let { Json.parse(Json.write(it)) }).let { it.status to (it.json as Map<String, Any?>) }
            val png = "data:image/png;base64," + java.util.Base64.getEncoder().encodeToString(ByteArray(0).let {
                val img = java.awt.image.BufferedImage(4, 4, java.awt.image.BufferedImage.TYPE_INT_RGB)
                java.io.ByteArrayOutputStream().also { o -> javax.imageio.ImageIO.write(img, "png", o) }.toByteArray() })
            assertEquals(200, call(a, "POST", "/api/submit", mapOf("kind" to "photo", "payload" to mapOf("kks" to "11LAB70AA501", "dataUrl" to png))).first)
            fun sync(from: Listening, to: Listening) = Sync.syncWith(from.node, "127.0.0.1", to.port!!).second
            sync(usr, adm)
            val photo = (call(u, "GET", "/api/state").second["photos"] as List<Map<String, Any?>>).single()
            val (s1, r1) = call(u, "POST", "/api/submit", mapOf("kind" to "photo_delete", "payload" to mapOf("photo_id" to photo["id"])))
            assertEquals(r1.toString(), 200, s1)
            sync(usr, adm)
            val sub = (call(a, "GET", "/api/submissions?status=open").second["submissions"] as List<Map<String, Any?>>).single()
            assertEquals(200, call(a, "POST", "/api/submissions/${sub["id"]}/reject", mapOf("note" to "keep it")).first)
            sync(usr, adm); sync(adm, usr)                      // both directions keep working
            val mine = (call(u, "GET", "/api/submissions?status=all").second["submissions"] as List<Map<String, Any?>>).single { it["kind"] == "photo_delete" }
            assertEquals("rejected", mine["status"])
        } finally { adm.close(); usr.close() }
    }

    /** Two phones pressing "Sync now" at each other at the same moment both finish (no lock held across the network). */
    @Test fun simultaneousSyncNowDoesNotDeadlock() {
        val pl = Plant("admin")
        val x = Listening(); val y = Listening()
        try {
            for (n in listOf(x, y)) { n.node.adopt(pl.root.peerId); pl.mgr.append("device_cert", mapOf("device" to n.node.device, "person" to pl.person, "label" to "p")) }
            for (n in listOf(x, y)) n.node.ingest(pl.mgr.entriesFor(n.node.vv()))
            val ax = LocalApi(x.node, x); val ay = LocalApi(y.node, y)
            repeat(5) {
                val t0 = System.currentTimeMillis()
                val r = listOf(ax to y, ay to x).map { (api, other) -> java.util.concurrent.CompletableFuture.supplyAsync {
                    api.handle("POST", "/api/sync/now", emptyMap(), mapOf("address" to "127.0.0.1:${other.port}")).status } }.map { it.get() }
                assertEquals(listOf(200, 200), r)
                assertTrue("took ${System.currentTimeMillis() - t0} ms", System.currentTimeMillis() - t0 < 5000)
            }
        } finally { x.close(); y.close() }
    }

    /** A removed phone learns it at its next sync (the signed revoke entry as proof) and wipes itself; a revoke
     *  signed by a stranger is refused. */
    @Test fun removedPhoneWipesItself() {
        val pl = Plant("admin")
        val adm = Listening(); val usr = Listening()
        try {
            for (n in listOf(adm, usr)) n.node.adopt(pl.root.peerId)
            pl.mgr.append("device_cert", mapOf("device" to adm.node.device, "person" to pl.person, "label" to "admin phone"))
            pl.mgr.append("device_cert", mapOf("device" to usr.node.device, "person" to pl.userPerson, "label" to "user phone"))
            for (n in listOf(adm, usr)) n.node.ingest(pl.mgr.entriesFor(n.node.vv()))
            var wiped: Map<String, Any?>? = null
            usr.node.onWiped = { wiped = it }
            val stranger = SigningKey.generate()
            val fake = Proto.makeEntry(stranger, 1, null, listOf(1L, 0L), "revoke", mapOf("device" to usr.node.device, "last_seq" to 0L))
            assertEquals(false, usr.node.acceptRevocation(fake))
            val a = LocalApi(adm.node, adm)
            assertEquals(200, a.handle("POST", "/api/devices/revoke", emptyMap(), mapOf("device" to usr.node.device)).status)
            val err = runCatching { Sync.syncWith(usr.node, "127.0.0.1", adm.port!!) }.exceptionOrNull()
            assertTrue(err?.message ?: "no error", err?.message?.contains("removed") == true)
            assertEquals("Me Myself", wiped?.get("by"))
            assertEquals(null, usr.node.owner())
            assertEquals(0, usr.node.entries.size)
            val cfg = LocalApi(usr.node, usr).handle("GET", "/api/config", emptyMap(), null).json as Map<*, *>
            assertEquals("Me Myself", ((cfg["node"] as Map<*, *>)["removed"] as Map<*, *>)["by"])
        } finally { adm.close(); usr.close() }
    }

    /** A tiny HTTP client with a cookie, for the Python server. */
    class Web(private val base: String) {
        private var cookie: String? = null
        private fun call(method: String, path: String, body: Any?): Pair<Int, Map<String, Any?>> {
            val c = URI(base + path).toURL().openConnection() as HttpURLConnection
            c.requestMethod = method
            c.setRequestProperty("Content-Type", "application/json")
            cookie?.let { c.setRequestProperty("Cookie", it) }
            if (body != null) { c.doOutput = true; c.outputStream.use { it.write(Json.write(body).toByteArray()) } }
            val code = c.responseCode
            c.getHeaderField("Set-Cookie")?.let { sc -> Regex("(kks_session=[^;]*)").find(sc)?.let { cookie = it.groupValues[1] } }
            val text = (if (code < 400) c.inputStream else c.errorStream).readBytes().toString(Charsets.UTF_8)
            return code to (Json.parse(text) as Map<String, Any?>)
        }
        fun get(p: String) = call("GET", p, null)
        fun post(p: String, b: Any?) = call("POST", p, b)
    }
}

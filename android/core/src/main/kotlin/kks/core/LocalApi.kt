package kks.core

import java.net.HttpURLConnection
import java.net.URI

/** What the local API needs from the sync service (the app's discovery + listener; tests: a stub). */
interface SyncControl {
    val port: Int?
    fun syncOne(host: String, port: Int, adoptRoot: String? = null): SyncStats
    fun syncAll()
    fun snapshot(): Map<String, Any?>
    fun joined()
    /** "ip:port" addresses other devices on the network may reach this one at (for invites). */
    fun addresses(): List<String> = emptyList()
    /** For the status line: {reachable, nearby, last_sync} (devices of this plant seen or synced with lately). */
    fun reach(): Map<String, Any?> = emptyMap()
    /** Whether the phone has a working internet connection (null: can't tell). */
    fun internet(): Boolean? = null
    /** The plant's relay setting changed: reconnect to the new address (M5). */
    fun relayChanged() {}
}

class ApiResponse(val status: Int, val json: Any? = null, val bytes: ByteArray? = null,
                  val contentType: String = "application/json", val headers: Map<String, String> = emptyMap())

/**
 * The web UI's API on this device (peer mode: the device is one person's own; no passwords). Twin of the peer-mode
 * part of app.py + server/changes.py, same paths, same JSON. The app calls [handle] for every /api request.
 */
@Suppress("UNCHECKED_CAST")
class LocalApi(val node: LocalNode, private val sync: SyncControl, private val plantName: String = "KKS Explorer",
               private val maxUploadBytes: Int = 15 * 1024 * 1024) {
    private val OPEN = setOf("pending", "conflict")
    private val ENTITIES = setOf("equipment", "review", "link", "photo", "added_tag")
    private val USERNAME = Regex("[A-Za-z0-9_.@-]{2,40}")
    private val CLIENT_ID = Regex("[A-Za-z0-9_-]{8,64}")
    val invites = Invites().also { node.invites = it }      // join by invite: the QR codes this device shows
    @Volatile private var joining: InviteJoin? = null       // not joined yet: the join by invite that is running

    private fun ok(v: Any? = mapOf("ok" to true)) = ApiResponse(200, v)
    private fun err(status: Int, msg: String): Nothing = throw ApiError(status, msg)

    /** Routes that talk to other devices: they must not hold the node's lock while waiting on the network, or two
     *  phones syncing each other at the same moment each wait for the other's lock (until the socket times out). */
    private val UNLOCKED = setOf("/api/sync/now", "/api/node/join-server")

    /** Moves with every change (log entries by anyone, submission rows here): pages poll it (/api/sync/status). */
    private val rev = java.util.concurrent.atomic.AtomicLong(System.currentTimeMillis())
    init { node.listeners.add { rev.incrementAndGet() } }

    fun handle(method: String, path: String, query: Map<String, String>, body: Any?): ApiResponse = try {
        val d = (body as? Map<String, Any?>) ?: emptyMap()
        (if (method == "POST" && path in UNLOCKED) route(method, path, query, d, body)
         else synchronized(node) { route(method, path, query, d, body) }).also { if (method == "POST" && it.status < 400) rev.incrementAndGet() }
    } catch (e: ApiError) {
        ApiResponse(e.status, mapOf("error" to e.message) + e.extra)
    } catch (e: Conflict) {
        ApiResponse(409, mapOf("error" to "conflict", "conflicts" to e.detail))
    }

    private class Conflict(val detail: List<Map<String, Any?>>) : Exception("conflict")

    // ---------- the owner ("me") ----------
    private fun me(): Owner = node.owner() ?: err(401, "this device has not joined a plant yet")
    private fun publicUser(o: Owner) = mapOf("id" to 1L, "username" to o.username, "role" to o.role, "active" to true,
        "has_password" to true, "created" to null, "full_name" to o.fullName, "position" to (o.position ?: ""), "person" to o.person)

    private fun name(person: String?): Pair<String, String>? = node.run.persons[person]?.let { it["username"] as String to it["full_name"] as String }

    private fun route(method: String, path: String, q: Map<String, String>, d: Map<String, Any?>, raw: Any?): ApiResponse {
        if (method == "GET") when (path) {
            "/api/config" -> return ok(configOut())
            "/api/node/join-invite" -> return ok(joining?.state() ?: mapOf("state" to null))
            "/api/sync/status" -> return ok(mapOf("rev" to rev.get(), "mode" to "peer", "internet" to sync.internet()) + sync.reach())
            "/api/node/nearby" -> if (node.owner() == null) {      // admins' devices on this Wi-Fi a new device may ask (§16)
                val snap = sync.snapshot()
                val found = (snap["found"] as? List<Map<String, Any?>>).orEmpty().filter { it["adm"] == true && it["peer"] != null }
                return ok(mapOf("devices" to found.map { f -> listOf("peer", "host", "port", "plant", "label").associateWith { f[it] } },
                                "discovery" to snap["discovery"]))
            }
        }
        if (method == "POST" && path.startsWith("/api/node/") && node.owner() == null) return nodeAction(path.substringAfterLast('/'), d)
        if (method == "POST" && path == "/api/bundle/import") {
            if (node.owner() != null) me()
            val bytes = raw as? ByteArray ?: err(400, "send the bundle file")
            val r = try { node.importBundle(bytes) } catch (e: IllegalArgumentException) { err(400, e.message ?: "bad bundle") }
            if (node.owner() != null) sync.joined()
            return ok(mapOf("ok" to true) + r + ("joined" to (node.owner() != null)))
        }
        val me = me()
        if (method == "GET") return when (path) {
            "/api/me" -> ok(mapOf("user" to publicUser(me), "offline_days" to 3650L, "transfer_offer" to false, "transfer_pending" to null))
            "/api/state" -> ok(stateOut(me))
            "/api/submissions" -> {
                val status = q["status"] ?: "open"
                if (status !in setOf("open", "decided", "all")) err(400, "bad status")
                ok(mapOf("submissions" to listSubs(me, status, minOf(q["limit"]?.toIntOrNull() ?: 200, 1000))))
            }
            "/api/revisions" -> {
                need(me, "admin")
                val before = q["before"]?.toLongOrNull() ?: Long.MAX_VALUE
                val limit = minOf(q["limit"]?.toIntOrNull() ?: 100, 500)
                ok(mapOf("revisions" to historyOut(history().filter { it.first < before }.takeLast(limit).reversed())))
            }
            "/api/users" -> { need(me, "admin"); ok(mapOf("users" to usersOut(me))) }
            "/api/devices" -> ok(devicesOut(me))
            "/api/progress" -> {                               // course progress (M4): private to this person
                val got = Progress.load(node, me.person)
                ok(q["course"]?.let { mapOf("data" to (got[it] ?: emptyMap())) } ?: mapOf("courses" to got))
            }
            "/api/join-requests" -> {
                need(me, "admin")
                ok(mapOf("requests" to invites.lobbyList().map { r ->
                    r + mapOf("code" to joinCode(r["device"] as String, node.device),
                              "existing" to existingPerson((r["request"] as Map<String, Any?>)["username"] as? String))
                }))
            }
            else -> if (path.startsWith("/api/invites/")) inviteStatus(me, path.removePrefix("/api/invites/")) else null
        } ?: when (path) {
            "/api/sheets" -> {
                need(me, "admin")
                ok(mapOf("sheets" to emptyList<Any>(), "job" to null,
                         "importer" to mapOf("available" to false, "error" to "Adding drawings is done on a laptop or the server.")))
            }
            "/api/bundle" -> {
                need(me, "admin")
                val data = node.bundle(photos = q["photos"] == "1")
                val plant = ((node.run.settings["plant"] as? String) ?: "plant").replace(Regex("[^\\w.-]+"), "-").take(40)
                val stamp = java.text.SimpleDateFormat("yyyyMMdd-HHmm").format(java.util.Date())
                ApiResponse(200, bytes = data, contentType = "application/gzip",
                            headers = mapOf("Content-Disposition" to "attachment; filename=\"$plant-$stamp.kksbundle\""))
            }
            else -> err(404, "not found")
        }
        if (method != "POST") err(405, "method not allowed")
        Regex("/api/submissions/(\\d+)/(vote|withdraw|approve|reject|pick)").matchEntire(path)?.let {
            return ok(act(me, it.groupValues[1].toLong(), it.groupValues[2], d))
        }
        Regex("/api/revisions/([\\w-]+)/revert").matchEntire(path)?.let {
            need(me, "admin")
            val ref: Any = it.groupValues[1].toLongOrNull() ?: it.groupValues[1]
            return ok(mapOf("ok" to true, "changed" to revert(me, ref, Payloads.truthy(d["force"])).toLong()))
        }
        Regex("/api/persons/([0-9a-f]{32})").matchEntire(path)?.let { return updatePerson(me, it.groupValues[1], d) }
        Regex("/api/invites/([A-Za-z0-9_-]{16,40})").matchEntire(path)?.let { return inviteAction(me, it.groupValues[1], d) }
        Regex("/api/join-requests/([A-Za-z0-9_-]{43})").matchEntire(path)?.let { return lobbyAction(me, it.groupValues[1], d) }
        return when (path) {
            "/api/submit" -> ok(submit(me, d["kind"] as? String, d["payload"], d["client_id"], d["note"]))
            "/api/profile" -> {
                val (fn, pos) = person(d)
                if (fn != me.fullName || pos != me.position) node.write("person", personBody(me.person, fullName = fn, position = pos))
                ok()
            }
            "/api/restore" -> {
                need(me, "admin")
                val ref = d["hid"] ?: d["rev"]
                if (!(ref == 0L || ref is String || (ref is Long && ref > 0))) err(400, "hid (a History row) or rev 0 is required")
                ok(mapOf("ok" to true, "changed" to restoreTo(me, ref!!).toLong()))
            }
            "/api/devices/import-request" -> importRequest(me, d)
            "/api/settings/relay" -> {                           // M5: the plant's internet relay (manager)
                need(me, "manager")
                val url = ((d["url"] as? String) ?: "").trim().trimEnd('/')
                if (url.isNotEmpty() && !Regex("wss?://[A-Za-z0-9.-]+(:\\d+)?(/[A-Za-z0-9._~/-]*)?").matches(url))
                    err(400, "The relay address looks like wss://kks-relay.example.workers.dev")
                node.write("setting", mapOf("key" to "relay", "value" to url.ifEmpty { null }))
                sync.relayChanged()
                ok()
            }
            "/api/progress" -> {
                try { Progress.save(node, me, d["course"], d["data"]) } catch (e: IllegalArgumentException) { err(400, e.message ?: "bad progress") }
                ok()
            }
            "/api/invites" -> {
                need(me, "admin")
                if (sync.port == null) err(409, "Sync is off on this device, so devices cannot join through it.")
                val addrs = sync.addresses()
                if (addrs.isEmpty()) err(409, "This phone is not on a network other devices could reach (connect to the Wi-Fi, or turn on its hotspot).")
                val inv = invites.create(me.person, node.anchor, (node.run.settings["plant"] as? String) ?: plantName, node.device, addrs)
                ok(mapOf("ok" to true, "invite" to inv, "code" to Json.write(inv)))
            }
            "/api/devices/revoke" -> revokeDevice(me, d["device"])
            "/api/sync/now" -> {
                val addr = ((d["address"] as? String) ?: "").trim()
                if (addr.isNotEmpty()) {
                    val (host, port) = if (':' in addr) addr.substringBeforeLast(':') to (addr.substringAfterLast(':').toIntOrNull() ?: 8421) else addr to 8421
                    val st = try { sync.syncOne(host, port) } catch (e: Exception) { err(502, "sync with $addr failed: ${e.message}") }
                    ok(mapOf("ok" to true, "result" to statsOut(st)))
                } else { sync.syncAll(); ok(mapOf("ok" to true, "sync" to sync.snapshot())) }
            }
            else -> err(404, "not found")
        }
    }

    private fun need(me: Owner, role: String) {
        if (role == "admin" && !me.isAdmin() || role == "manager" && me.role != "manager") err(403, "$role only")
    }

    private fun configOut(): Map<String, Any?> {
        val plant = node.run.settings["plant"] as? String
        return mapOf("plant_name" to (plant ?: plantName), "offline_days" to 3650L, "mode" to "peer", "setup_needed" to false,
                     "app" to true,
                     // photos become JPEG XL here: the page sends lossless PNG (nothing crosses a network)
                     "photo_upload" to if (photoEncoder != null) mapOf("type" to "image/png", "ms_per_mp" to photoMsPerMp()) else mapOf("type" to "image/jpeg", "q" to 0.85),
                     "node" to mapOf("joined" to (node.owner() != null), "device" to node.device, "has_plant" to (node.anchor != null),
                                     "plant" to plant, "can_create" to false,
                                     "removed" to if (node.owner() == null) node.store.meta("removed")?.let { runCatching { Json.parse(it) }.getOrNull() } else null))
    }

    // ---------- /api/state ----------
    private fun stateOut(me: Owner): Map<String, Any?> {
        val run = node.run
        val created = HashMap<Any?, Long?>()
        for (h in run.history) if (h["entity"] == "photo" && h["before"] == null && h["after"] != null) created[h["key"]] = node.ts(h["at"] as String?)
        val opn = listSubs(me, "open", 1_000_000)
        val out = linkedMapOf<String, Any?>(
            "equipment" to run.equipment, "reviews" to run.reviews,
            "photos" to run.photos.map { (k, v) -> mapOf("id" to k, "kks" to v["kks"], "file" to node.store.blobName(v["blob"] as String),
                                                          "caption" to v["caption"], "created" to created[k]) }
                .sortedWith(compareBy({ (it["created"] as Long?) ?: 0L }, { it["id"] as String })),
            "links" to run.state()["links"].let { l -> (l as List<List<Any?>>).map { mapOf("proc" to it[0], "step" to it[1], "kks" to it[2]) } },
            "added_tags" to run.tags.map { (k, v) -> Payloads.tagOut(k, v) },
            "rev" to run.history.size.toLong(),
            "mine" to opn.filter { it["mine"] == true })
        if (me.isAdmin()) out["queue"] = opn.size.toLong()
        return out
    }

    // ---------- submissions (server/changes.py) ----------
    private fun conflictsOut(c: List<Map<String, Any?>>) = c.map { it.filterKeys { k -> k in setOf("field", "base", "live", "proposed") } }

    /** note: optional words for the approver, kept as a `comment` entry on the proposal (as changes.submit). */
    private fun submit(me: Owner, kind: String?, payload: Any?, clientId: Any?, noteIn: Any? = null): Map<String, Any?> {
        if (noteIn != null && (noteIn !is String || noteIn.length > 500)) err(400, "note: up to 500 characters")
        val requestNote = (noteIn as String?)?.trim().orEmpty()
        if (clientId != null && (clientId !is String || !CLIENT_ID.matches(clientId))) err(400, "bad client_id")
        if (clientId is String) node.store.subByClientId(clientId)?.let { old ->
            val (st, note) = subStatus(old)
            return mapOf("id" to old["id"], "status" to st, "note" to note, "duplicate" to true)
        }
        val p = Payloads.normalize(kind, payload, maxUploadBytes, photoEncoder) { sha, data -> node.store.blobName(sha) ?: "$sha.${blobExt(data)}".also { node.store.putBlob(sha, it, data) } }
        val body = Payloads.toBody(kind!!, p)
        try { Replay.checkData(kind, body) } catch (e: Replay.Ignore) { err(400, "invalid change") }
        val (_, conflicts) = node.plan(kind, body)
        val row = mapOf("id" to null, "client_id" to clientId, "person" to me.person, "kind" to kind, "created" to now())
        if (me.isAdmin() && conflicts.isNotEmpty()) {
            val sid = node.store.putSub(row + mapOf("held" to Json.write(mapOf("kind" to kind, "body" to body)), "status" to "conflict",
                                                    "note" to Json.write(conflictsOut(conflicts))))
            return mapOf("id" to sid, "status" to "conflict", "conflicts" to conflictsOut(conflicts))
        }
        val eid = node.write(kind, body)
        if (requestNote.isNotEmpty()) node.write("comment", mapOf("entry" to eid, "text" to requestNote))
        val sid = node.store.putSub(row + ("entry" to eid))
        return when {
            me.isAdmin() -> mapOf("id" to sid, "status" to "approved")
            conflicts.isNotEmpty() -> mapOf("id" to sid, "status" to "conflict", "conflicts" to conflictsOut(conflicts))
            else -> mapOf("id" to sid, "status" to "pending")
        }
    }

    private fun now() = System.currentTimeMillis() / 1000

    private fun kindBody(r: Map<String, Any?>): Pair<String, Map<String, Any?>> {
        val eid = r["entry"] as String?
        if (eid == null) {
            val h = Json.parse(r["held"] as String) as Map<String, Any?>
            return h["kind"] as String to h["body"] as Map<String, Any?>
        }
        val e = node.entries[eid]!!
        return e["type"] as String to e["body"] as Map<String, Any?>
    }

    /** -> (status, note, decided_at, decider person, conflicts) */
    private fun subStatus(r: Map<String, Any?>): SubStatus {
        val (kind, body) = kindBody(r)
        val eid = r["entry"] as String?
        if (eid == null) {
            val open = r["status"] in OPEN
            val c = if (open) node.plan(kind, body).second else emptyList()
            return SubStatus(if (open) (if (c.isNotEmpty()) "conflict" else "pending") else r["status"] as String,
                             (r["note"] as String?) ?: "", r["decided_at"] as Long?, null, c)
        }
        var (status, dec, note) = node.statusOf(eid)
        var c = emptyList<Map<String, Any?>>()
        if (status == "pending") {
            c = node.plan(kind, body).second
            if (c.isNotEmpty()) status = "conflict"
        }
        val decider = dec?.let { node.personOf(node.entries[it]!!["peer"] as String) }
        if (note.isEmpty() && dec != null) note = node.store.note(dec) ?: ""
        return SubStatus(status, note, if (dec != null) node.ts(dec) else if (status == "approved") node.ts(eid) else null, decider, c)
    }

    private data class SubStatus(val status: String, val note: String, val decidedAt: Long?, val decider: String?, val conflicts: List<Map<String, Any?>>)

    private fun subOut(r: Map<String, Any?>, me: Owner, live: Boolean): Map<String, Any?> {
        val (kind, body) = kindBody(r)
        val s = subStatus(r)
        val who = name(r["person"] as String?)
        val d = linkedMapOf<String, Any?>("id" to r["id"], "client_id" to r["client_id"], "kind" to kind, "target" to Payloads.target(kind, body),
            "status" to s.status, "created" to r["created"], "decided_at" to s.decidedAt, "note" to s.note,
            "payload" to Payloads.toPayload(node, kind, body), "by" to (who?.first ?: "?"), "mine" to (r["person"] == me.person))
        d["by_name"] = who?.second ?: d["by"]
        val author = (r["entry"] as String?)?.let { node.entries[it]?.get("peer") as String? }?.let { node.run.devices[it]?.get("person") }
        d["request_note"] = (r["entry"] as String?)?.let { e -> node.run.comments[e]?.firstOrNull { it["person"] == author }?.get("text") } ?: ""
        if (kind == "photo") {
            val voters = (r["entry"] as String?)?.let { node.run.votes[it] } ?: emptySet()
            d["votes"] = voters.size.toLong(); d["voted"] = me.person in voters
        }
        if (live && s.status in OPEN && me.isAdmin()) {
            d["conflicts"] = conflictsOut(s.conflicts)
            d["live"] = node.plan(kind, body).first.map { (entity, key) ->
                val k = if (key is Triple<*, *, *>) Json.write(listOf(key.first, key.second, key.third)) else key
                mapOf("entity" to entity, "key" to k, "value" to Payloads.valueOut(node, entity, key, node.run.get(entity, key)))
            }
        }
        return d
    }

    private fun listSubs(me: Owner, filter: String, limit: Int): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        for (r in node.store.subs()) {
            val st = subStatus(r).status
            if (filter == "open" && st !in OPEN) continue
            if (filter == "decided" && st in OPEN) continue
            if (!me.isAdmin() && r["person"] != me.person && !(r["kind"] == "photo" && st in OPEN)) continue
            out.add(subOut(r, me, live = true))
            if (out.size >= limit) break
        }
        return out
    }

    private fun rebase(kind: String, b: Map<String, Any?>): Map<String, Any?> = when (kind) {
        "equipment" -> {
            val cur = node.run.equipment[b["kks"]] ?: emptyMap()
            b + ("base" to (b["changes"] as Map<String, Any?>).keys.associateWith { cur[it] ?: LocalNode.default(it) })
        }
        "review" -> b + ("base" to node.run.reviews[b["tag_id"]])
        else -> b
    }

    private fun act(me: Owner, sid: Long, action: String, d: Map<String, Any?>): Map<String, Any?> {
        val r = node.store.sub(sid) ?: err(404, "no such submission")
        var (kind, body) = kindBody(r)
        val status = subStatus(r).status
        val open = status in OPEN
        val eid = r["entry"] as String?
        when (action) {
            "vote" -> {
                if (kind != "photo" || !open || eid == null) err(400, "only open photo proposals take votes")
                node.write("vote", mapOf("entry" to eid, "on" to (me.person !in (node.run.votes[eid] ?: emptySet()))))
                return mapOf("ok" to true)
            }
            "withdraw" -> {
                if (r["person"] != me.person || !open) err(403, "can only withdraw your own open submission")
                if (eid != null) node.write("withdraw", mapOf("entry" to eid))
                else node.store.putSub(r + mapOf("status" to "withdrawn", "decided_at" to now()))
                return mapOf("ok" to true)
            }
        }
        need(me, "admin")
        if (!open) err(409, "already $status")
        if (action == "reject") { rejectSub(r, ((d["note"] as? String) ?: "").take(500)); return mapOf("ok" to true) }
        var edit: Map<String, Any?>? = null
        if (kind == "tag_add" && d["edit"] is Map<*, *>) {   // the admin corrects the code while approving
            val e = d["edit"] as Map<String, Any?>
            val fixed = Payloads.tagPayload(Payloads.toPayload(node, kind, body) + mapOf("kks" to e["kks"], "isa" to e["isa"]), body["tag"] as String)
            edit = mapOf("kks" to fixed["kks"], "suffix" to fixed["suffix"], "isa" to fixed["isa"])
            body = body + edit
        }
        val conflicts = node.plan(kind, body).second
        if (me.role != "manager" && conflicts.any { it["manager"] == true })
            err(403, "The value there was set or approved by the manager; only the manager can overwrite it.")
        if (conflicts.isNotEmpty() && !Payloads.truthy(d["force"])) throw Conflict(conflictsOut(conflicts))
        var note = if (conflicts.isNotEmpty()) "forced over conflicting change" else ""
        val written: String
        if (eid != null) written = node.write("approve", mapOf("entry" to eid, "edit" to edit))
        else {
            written = node.write(kind, rebase(kind, body))
            node.store.putSub(r + mapOf("entry" to written, "held" to null, "status" to null))
            if (r["person"] != me.person) note = listOf(note, "proposed by ${name(r["person"] as String?)?.first ?: "?"}").filter { it.isNotEmpty() }.joinToString("; ")
        }
        if (note.isNotEmpty()) node.store.putNote(written, note)
        var rejected = 0L
        if (action == "pick") for (o in node.store.subs()) {   // choose this photo, discard the other open ones for the same item
            if (o["id"] == sid || o["kind"] != "photo") continue
            if (kindBody(o).second["kks"] == body["kks"] && subStatus(o).status in OPEN) { rejectSub(o, "another photo was chosen (#$sid)"); rejected++ }
        }
        return mapOf("ok" to true, "rejected" to rejected)
    }

    private fun rejectSub(r: Map<String, Any?>, note: String) {
        val eid = r["entry"] as String?
        if (eid != null) node.write("reject", mapOf("entry" to eid, "note" to note))
        else node.store.putSub(r + mapOf("status" to "rejected", "note" to note, "decided_at" to now()))
    }

    // ---------- History, revert, restore ----------
    private data class Item(val hid: String, val ts: Long, val person: String?, val entity: String, val key: Any?,
                            val before: Any?, val after: Any?, val sub: Long?, val note: String)

    private fun history(): List<Pair<Long, Item>> {
        val notes = node.store.notes()
        val subs = node.store.subs().filter { it["entry"] != null }.associate { it["entry"] as String to it["id"] as Long }
        val per = HashMap<String, Int>()
        val items = node.run.history.mapIndexed { i, h ->
            val at = h["at"] as String
            val k = per.merge(at, 0) { a, _ -> a + 1 }!!
            val e = node.entries[at]!!
            Triple(((e["hlc"] as List<*>)[0] as Long) / 1000, i, Item("${at.take(24)}-$k", ((e["hlc"] as List<*>)[0] as Long) / 1000,
                node.personOf(e["peer"] as String), h["entity"] as String, h["key"], h["before"], h["after"], subs[h["source"]],
                notes[at] ?: notes[h["source"]] ?: ""))
        }.sortedWith(compareBy({ it.first }, { it.second }))
        return items.mapIndexed { n, t -> (n + 1).toLong() to t.third }
    }

    private fun keyOf(it: Item): Any? = if (it.entity == "link") (it.key as List<*>).let { l -> Triple(l[0] as String, l[1] as Long, l[2] as String) } else it.key

    private fun historyOut(rows: List<Pair<Long, Item>>) = rows.map { (rev, it) ->
        val who = node.run.persons[it.person]
        mapOf("rev" to rev, "hid" to it.hid, "ts" to it.ts, "actor" to (if (it.person == node.owner()?.person) 1L else null),
              "username" to who?.get("username"), "full_name" to who?.get("full_name"), "entity" to it.entity,
              "key" to (if (it.entity == "link") Json.write(it.key) else it.key),
              "before" to Payloads.valueOut(node, it.entity, it.key, it.before)?.let { v -> Json.write(v) },
              "after" to Payloads.valueOut(node, it.entity, it.key, it.after)?.let { v -> Json.write(v) },
              "submission_id" to it.sub, "note" to it.note)
    }

    private fun find(rows: List<Pair<Long, Item>>, ref: Any): Int =
        rows.indexOfFirst { (rev, it) -> it.hid == ref || (ref is Long && rev == ref) }.takeIf { it >= 0 } ?: err(400, "no such revision")

    private fun putBack(me: Owner, targets: List<Triple<String, Any?, Any?>>, note: String): Int {
        val todo = targets.mapNotNull { (entity, key, value) ->
            val tb = node.restoreBody(entity, key, value) ?: return@mapNotNull null
            val (kind, body) = tb
            if (me.role != "manager" && (kind == "equipment" && (body["changes"] as Map<*, *>).keys.any { node.managerOwned("equipment", key as String, it as String) } ||
                                         kind == "review" && node.managerOwned("review", key as String)))
                err(403, "$key: set or approved by the manager; only the manager can change it back.")
            tb
        }
        for ((kind, body) in todo) node.store.putNote(node.write(kind, body), note)
        return todo.size
    }

    private fun revert(me: Owner, ref: Any, force: Boolean): Int {
        val rows = history()
        val (rev, it) = rows[find(rows, ref)]
        if (it.entity !in ENTITIES) err(400, "only data changes can be reverted")
        val key = keyOf(it)
        val live = node.run.get(it.entity, key)
        if (!pyEquals(live, it.after) && !force) throw Conflict(listOf(mapOf("field" to it.entity,
            "live" to Payloads.valueOut(node, it.entity, key, live), "proposed" to Payloads.valueOut(node, it.entity, key, it.before),
            "note" to "changed again after this revision")))
        return putBack(me, listOf(Triple(it.entity, key, it.before)), "revert of rev $rev")
    }

    private fun restoreTo(me: Owner, ref: Any): Int {
        val rows = history()
        val start = if (ref == 0L) 0 else find(rows, ref) + 1
        val rev = if (start > 0) rows[start - 1].first else 0L
        val first = LinkedHashMap<Pair<String, Any?>, Any?>()
        for ((_, it) in rows.drop(start)) if (it.entity in ENTITIES) {
            val k = it.entity to keyOf(it)
            if (!first.containsKey(k)) first[k] = it.before   // (not putIfAbsent: that overwrites a null "before")
        }
        return putBack(me, first.map { (k, v) -> Triple(k.first, k.second, v) }, "restore to rev $rev")
    }

    // ---------- people and devices ----------
    private fun person(d: Map<String, Any?>): Pair<String, String?> {
        val name = (d["full_name"] as? String ?: "").trim().split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")
        val pos = (d["position"] as? String ?: "").trim().split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")
        if (name.length < 2) err(400, "Enter the full name (so everyone knows whose account this is).")
        if (name.length > 80 || pos.length > 80) err(400, "Full name and position: up to 80 characters each.")
        return name to pos.ifEmpty { null }
    }

    private fun personBody(pid: String, fullName: String? = null, position: String? = null, role: String? = null, keepPosition: Boolean = fullName == null): Map<String, Any?> {
        val cur = node.run.persons[pid]!!
        return mapOf("person" to pid, "username" to cur["username"], "full_name" to (fullName ?: cur["full_name"]),
                      "position" to (if (keepPosition) cur["position"] else position), "role" to (role ?: cur["role"]))
    }

    private fun roleOf(pid: String) = if (node.run.manager == pid) "manager" else node.run.persons[pid]?.get("role") as String?

    private fun usersOut(me: Owner): List<Map<String, Any?>> {
        val rows = arrayListOf(publicUser(me))
        for ((pid, p) in node.run.persons.entries.sortedBy { (it.value["username"] as String).lowercase() }) {
            if (pid == me.person) continue
            val devs = node.run.devices.filter { it.value["person"] == pid }.keys
            rows.add(mapOf("id" to null, "person" to pid, "username" to p["username"], "full_name" to p["full_name"],
                           "position" to (p["position"] ?: ""), "no_account" to true, "has_password" to false, "role" to roleOf(pid),
                           "created" to null, "active" to devs.any { it !in node.run.cuts }, "devices" to devs.size.toLong()))
        }
        return rows
    }

    private fun updatePerson(me: Owner, pid: String, d: Map<String, Any?>): ApiResponse {
        need(me, "admin")
        val p = node.run.persons[pid] ?: err(404, "no such person")
        val target = roleOf(pid)
        if (target == "manager" || (target == "admin" && me.role != "manager")) err(403, "not allowed for this person")
        var role: String? = null
        if (d.containsKey("role") && d["role"] != p["role"]) {
            if (me.role != "manager" || d["role"] !in setOf("user", "admin")) err(403, "only the manager can promote or demote admins")
            role = d["role"] as String
        }
        var fn: String? = null; var pos: String? = null; var details = false
        if (d.containsKey("full_name") || d.containsKey("position")) {
            val r = person(mapOf("full_name" to (d["full_name"] ?: p["full_name"]), "position" to (d["position"] ?: p["position"])))
            fn = r.first; pos = r.second; details = true
        }
        if (role != null || details) node.write("person", personBody(pid, fn, pos, role, keepPosition = !details))
        if (d["active"] == false) for ((dev, v) in node.run.devices.toList()) {
            if (v["person"] == pid && dev !in node.run.cuts) node.write("revoke", mapOf("device" to dev, "last_seq" to lastSeq(dev)))
        } else if (d["active"] == true) err(400, "To come back they join again with a new join request.")
        return ok()
    }

    private fun lastSeq(dev: String): Long = node.vv()[dev]?.get(0) as Long? ?: 0L

    private fun devicesOut(me: Owner): Map<String, Any?> {
        val run = node.run
        fun dev(d: String, v: Map<String, Any?>) = mapOf("device" to d, "label" to v["label"], "person" to v["person"],
            "username" to run.persons[v["person"]]?.get("username"), "revoked" to (d in run.cuts), "this_computer" to (d == node.device))
        val names = run.devices.mapValues { (_, v) -> "${run.persons[v["person"]]?.get("username") ?: "?"} · ${(v["label"] as String).ifEmpty { "device" }}" }
        val snap = sync.snapshot().toMutableMap()
        snap["syncs"] = (snap["syncs"] as? Map<String, Map<String, Any?>> ?: emptyMap()).mapValues { (_, s) -> s + ("name" to names[s["peer"]]) }
        snap["found"] = (snap["found"] as? List<Map<String, Any?>> ?: emptyList()).map { it + ("name" to names[it["peer"]]) }
        return mapOf("mine" to run.devices.filter { it.value["person"] == me.person }.map { (d, v) -> dev(d, v) },
                     "all" to (if (me.isAdmin()) run.devices.map { (d, v) -> dev(d, v) } else null),
                     "node" to node.device, "mode" to "peer", "sync" to snap, "names" to names, "sync_port" to sync.port?.toLong())
    }

    private fun revokeDevice(me: Owner, dev: Any?): ApiResponse {
        val v = (dev as? String)?.let { node.run.devices[it] } ?: err(404, "no such device")
        val target = roleOf(v["person"] as String)
        if (!(me.role == "manager" || v["person"] == me.person || (me.role == "admin" && target == "user"))) err(403, "not allowed for that device")
        if (dev == node.device) err(400, "This is the device you are using; remove it from another one.")
        if (dev !in node.run.cuts) node.write("revoke", mapOf("device" to dev, "last_seq" to lastSeq(dev as String)))
        return ok()
    }

    fun checkJoinRequest(req: Any?): Map<String, Any?> =
        try { JoinRequests.check(req) } catch (e: IllegalArgumentException) { err(400, e.message ?: "bad join request") }

    private fun importRequest(me: Owner, d: Map<String, Any?>): ApiResponse {
        need(me, "admin")
        return ok(certify(me, checkJoinRequest(d["request"]), Payloads.truthy(d["existing_ok"])))
    }

    /** A checked join request -> device_cert (+ a new person). */
    private fun certify(me: Owner, req: Map<String, Any?>, existingOk: Boolean): Map<String, Any?> {
        val name = req["username"] as? String ?: ""
        if (!USERNAME.matches(name)) err(400, "the request has an invalid username")
        val (fn, pos) = person(req)
        val dev = req["device"] as String
        val have = node.run.devices[dev]
        var pid = node.run.persons.entries.firstOrNull { (it.value["username"] as String).lowercase() == name.lowercase() }?.key
        if (have != null && have["person"] != pid) err(409, "That laptop is already certified for someone else.")
        if (pid != null && !existingOk) {
            val p = node.run.persons[pid]!!
            throw ApiError(409, "existing person", mapOf("existing" to mapOf("username" to p["username"], "full_name" to p["full_name"], "role" to roleOf(pid))))
        }
        if (pid != null) {
            if (!(me.role == "manager" || pid == me.person || roleOf(pid) == "user")) err(403, "Only the manager can add devices for admins.")
        } else {
            pid = Payloads.newId()
            node.write("person", mapOf("person" to pid, "username" to name, "full_name" to fn, "position" to pos, "role" to "user"))
        }
        if (have == null) node.write("device_cert", mapOf("device" to dev, "person" to pid, "label" to ((req["label"] as? String) ?: "").take(80)))
        return mapOf("ok" to true, "username" to name, "person" to pid)
    }

    private fun inviteStatus(me: Owner, token: String): ApiResponse {
        need(me, "admin")
        val st = invites.status(token, me.person) ?: err(404, "no such invite")
        val req = st["request"] as Map<String, Any?>?
        return ok(st + ("existing" to req?.let { existingPerson(it["username"] as? String) }))
    }

    private fun existingPerson(username: String?): Map<String, Any?>? =
        node.run.persons.entries.firstOrNull { (it.value["username"] as String).lowercase() == username?.lowercase() }?.let {
            mapOf("username" to it.value["username"], "full_name" to it.value["full_name"], "role" to roleOf(it.key))
        }

    private fun lobbyAction(me: Owner, device: String, d: Map<String, Any?>): ApiResponse {
        need(me, "admin")
        if (d["action"] !in setOf("accept", "refuse")) err(400, "bad action")
        val req = invites.lobbyTake(device) ?: err(409, "That device is no longer waiting (it gave up, or was decided already).")
        if (d["action"] == "refuse") { invites.lobbyDone(device, false); return ok() }
        val r = certify(me, req, Payloads.truthy(d["existing_ok"]))
        invites.lobbyDone(device, true)
        return ok(r)
    }

    private fun inviteAction(me: Owner, token: String, d: Map<String, Any?>): ApiResponse {
        need(me, "admin")
        when (d["action"]) {
            "cancel" -> { invites.cancel(token, me.person); return ok() }
            "accept", "refuse" -> {}
            else -> err(400, "bad action")
        }
        val req = invites.take(token, me.person) ?: err(409, "No device is waiting on this invite (it expired, or was decided already).")
        if (d["action"] == "refuse") { invites.done(token, false); return ok() }
        val r = certify(me, req, Payloads.truthy(d["existing_ok"]))
        invites.done(token, true)
        return ok(r)
    }

    private fun statsOut(st: SyncStats) = mapOf("sent" to st.sent.toLong(), "received" to st.received.toLong(), "blobs_sent" to st.blobsSent.toLong(),
        "blobs_received" to st.blobsReceived.toLong(), "denied" to st.denied, "they_denied" to st.theyDenied)

    // ---------- before joining: join through a server, or make a join request ----------
    private fun nodeAction(action: String, d: Map<String, Any?>): ApiResponse = when (action) {
        "new-plant" -> err(400, "Start a new plant on a laptop: its root key should not live on a phone.")
        "join-request" -> {
            val name = ((d["username"] as? String) ?: "").trim()
            if (!USERNAME.matches(name)) err(400, "Username: 2-40 letters (a-z), digits, . _ - @")
            val (fn, pos) = person(d)
            ok(mapOf("ok" to true, "request" to JoinRequests.make(node.identity(), node.device, name, fn, pos, deviceLabel, now())))
        }
        "join-invite" -> {
            if (Payloads.truthy(d["cancel"]) || Payloads.truthy(d["confirm"])) {
                if (Payloads.truthy(d["cancel"])) joining?.cancel() else joining?.confirm()
                ok()
            } else {
                val name = ((d["username"] as? String) ?: "").trim()
                if (!USERNAME.matches(name)) err(400, "Username: 2-40 letters (a-z), digits, . _ - @")
                val (fn, pos) = person(d)
                val inv = try { if (d["nearby"] != null) parseNearby(d["nearby"]) else parseInvite(d["invite"]) }
                          catch (e: IllegalArgumentException) { err(400, e.message ?: "bad invite") }
                if (node.anchor != null && inv["root"] != null && node.anchor != inv["root"]) err(409, "This phone holds another plant's data; that invite is for a different plant.")
                joining?.cancel()
                val job = InviteJoin(node, sync, inv, JoinRequests.make(node.identity(), node.device, name, fn, pos, deviceLabel, now()), invitePollMs)
                joining = job; job.start()
                ok(mapOf("ok" to true) + job.state())
            }
        }
        "join-server" -> { joinServer(((d["url"] as? String) ?: "").trim(), d["username"] as? String, d["password"] as? String); ok() }
        else -> err(404, "not found")
    }

    var deviceLabel = "phone"
    /** Turns a photo (PNG/JPEG/WebP bytes) into JPEG XL; the app sets it (libjxl), tests leave it null. */
    var photoEncoder: ((ByteArray) -> ByteArray)? = null
    /** How long encoding took here lately per megapixel, for the pages' progress bar (the app measures it). */
    var photoMsPerMp: () -> Long = { 8000L }
    var invitePollMs = 2000L

    private fun joinServer(url: String, username: String?, password: String?) {
        val u = try { URI(if ("://" in url) url else "http://$url") } catch (e: Exception) { err(400, "enter the server address, e.g. http://192.168.1.20:8420") }
        if (u.host == null) err(400, "enter the server address, e.g. http://192.168.1.20:8420")
        val base = "${u.scheme}://${u.rawAuthority}"
        val answer: Map<String, Any?> = try {
            val c = URI("$base/api/devices/enroll").toURL().openConnection() as HttpURLConnection
            c.requestMethod = "POST"; c.doOutput = true; c.connectTimeout = 15000; c.readTimeout = 15000
            c.setRequestProperty("Content-Type", "application/json")
            c.outputStream.use { it.write(Json.write(mapOf("username" to username, "password" to password, "device" to node.device, "label" to deviceLabel)).toByteArray()) }
            val code = c.responseCode
            val text = (if (code < 400) c.inputStream else c.errorStream)?.readBytes()?.toString(Charsets.UTF_8) ?: ""
            val j = runCatching { Json.parse(text) as Map<String, Any?> }.getOrNull()
            if (code >= 400) err(400, (j?.get("error") as? String) ?: "the server answered $code")
            j ?: err(400, "the server's answer was not understood")
        } catch (e: ApiError) { throw e } catch (e: Exception) { err(400, "cannot reach $base: ${e.message}") }
        val port = (answer["sync_port"] as? Long)?.toInt()
        if (port == null || port == 0) err(400, "that server does not accept devices (its sync_port is 0)")
        try {
            sync.syncOne(u.host, port, if (node.anchor == null) answer["root"] as String else null)
        } catch (e: Exception) {
            err(400, "the server certified this device, but syncing failed: ${e.message}. Try \"Sync now\" later.")
        }
        if (node.owner() == null) err(400, "synced, but this device is not certified in what came back")
        sync.joined()
    }
}

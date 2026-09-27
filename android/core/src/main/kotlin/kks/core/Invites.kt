package kks.core

import java.security.SecureRandom

/** Join requests (the `.kksjoin` file, and what a device sends when it joins by invite): made and checked the same
 *  way as server/node.py. */
object JoinRequests {
    val DOMAIN = "kks-join-v1\n".toByteArray()

    fun make(identity: SigningKey, device: String, username: String, fullName: String, position: String?, label: String, created: Long): Map<String, Any?> {
        val req = linkedMapOf<String, Any?>("kks_join" to 1L, "device" to device, "username" to username, "full_name" to fullName,
            "position" to position, "label" to label, "created" to created)
        req["sig"] = B64u.encode(identity.sign(DOMAIN + Canonical.bytes(req)))
        return req
    }

    /** -> the request without its signature; IllegalArgumentException with the message for the person. */
    @Suppress("UNCHECKED_CAST")
    fun check(req: Any?): Map<String, Any?> {
        if (req !is Map<*, *> || req["kks_join"] != 1L) throw IllegalArgumentException("not a join request file")
        val body = (req as Map<String, Any?>).filterKeys { it != "sig" }
        val ok = try {
            ed25519Verify(B64u.decode(req["device"] as String), B64u.decode(req["sig"] as String), DOMAIN + Canonical.bytes(body))
        } catch (e: Exception) { false }
        if (!ok) throw IllegalArgumentException("the join request is damaged or was changed after it was made")
        return body
    }
}

/**
 * Join by invite (PROTOCOL.md §16), the inviting side; twin of server/invites.py. An admin shows a QR code naming this
 * device, its addresses, the plant's root and a one-time token; the new device sends its signed join request with
 * the token over the sync port; the admin accepts or refuses; the new device then syncs. In memory only.
 */
class Invites {
    companion object { const val TTL = 15 * 60L }

    private class Item(val by: String, val exp: Long) {
        var state = "open"
        var request: Map<String, Any?>? = null     // what the admin sees
        var full: Map<String, Any?>? = null        // the checked request, to certify
        var device: String? = null
        var seen = 0L
    }

    private val items = HashMap<String, Item>()
    private val lobby = HashMap<String, Item>()          // device → a request made without a token (by = "")
    private val rng = SecureRandom()
    private fun now() = System.currentTimeMillis() / 1000

    @Synchronized fun create(by: String, root: String?, plant: String?, peer: String, addrs: List<String>): Map<String, Any?> {
        items.entries.removeIf { it.value.exp < now() - 3600 }
        val token = B64u.encode(ByteArray(16).also { rng.nextBytes(it) })
        val exp = now() + TTL
        items[token] = Item(by, exp)
        return linkedMapOf("kks_invite" to 1L, "plant" to plant, "root" to root, "peer" to peer, "addrs" to addrs, "token" to token, "exp" to exp)
    }

    @Synchronized fun status(token: String, by: String): Map<String, Any?>? {
        val v = items[token]?.takeIf { it.by == by } ?: return null
        val state = if (v.exp < now() && v.state in setOf("open", "asked")) "expired" else v.state
        return mapOf("state" to state, "exp" to v.exp, "request" to v.request, "seen" to v.seen)
    }

    @Synchronized fun cancel(token: String, by: String) {
        items[token]?.takeIf { it.by == by && it.state in setOf("open", "asked") }?.state = "cancelled"
    }

    /** The pending (checked) request to decide on, or null. */
    @Synchronized fun take(token: String, by: String): Map<String, Any?>? =
        items[token]?.takeIf { it.by == by && it.exp >= now() && it.state == "asked" }?.full

    @Synchronized fun done(token: String, accepted: Boolean) {
        items[token]?.takeIf { it.state == "asked" }?.state = if (accepted) "accepted" else "refused"
    }

    // ---------- the lobby: asked on the Wi-Fi without a token; any admin here decides ----------
    @Synchronized fun lobbyList(): List<Map<String, Any?>> = lobby.filter { it.value.state == "asked" && it.value.exp >= now() }
        .map { (d, v) -> mapOf("device" to d, "request" to v.request, "seen" to v.seen, "exp" to v.exp) }

    @Synchronized fun lobbyTake(device: String): Map<String, Any?>? = lobby[device]?.takeIf { it.state == "asked" && it.exp >= now() }?.full

    @Synchronized fun lobbyDone(device: String, accepted: Boolean) {
        val v = lobby[device]?.takeIf { it.state == "asked" } ?: return
        lobby[device] = Item("", now() + TTL).also { it.state = if (accepted) "accepted" else "refused"; it.request = v.request; it.full = v.full; it.device = device }
    }

    private fun lobbyOffer(remote: String, msg: Map<String, Any?>, ack: (String, String?) -> Map<String, Any?>): Map<String, Any?> {
        synchronized(this) {
            lobby.entries.removeIf { it.value.exp < now() }
            val v = lobby[remote]
            if (v != null && (v.state == "accepted" || v.state == "refused")) return ack(v.state, null)
            if (v != null) { v.seen = now(); return ack("waiting", null) }
            if (lobby.size >= 50) return ack("used", "too many devices are waiting here; try again later")
        }
        val req = try { JoinRequests.check(msg["request"]) } catch (e: IllegalArgumentException) { return ack("bad", e.message) }
        if (req["device"] != remote) return ack("bad", "the join request is not from the device that sent it")
        synchronized(this) {
            lobby.getOrPut(remote) { Item("", now() + TTL).also {
                it.state = "asked"; it.device = remote; it.seen = now(); it.full = req
                it.request = listOf("device", "username", "full_name", "position", "label").associateWith { k -> req[k] }
            } }
        }
        return ack("waiting", null)
    }

    /** From the sync listener: a device asks with a token (or none: the lobby). -> the join_ack message. */
    fun offer(remote: String, msg: Map<String, Any?>): Map<String, Any?> {
        fun ack(state: String, why: String? = null) = mapOf("t" to "join_ack", "state" to state) + (if (why != null) mapOf("why" to why) else emptyMap())
        if (msg["token"] == null) return lobbyOffer(remote, msg, ::ack)
        val token = msg["token"] as? String
        synchronized(this) {
            val v = token?.let { items[it] }
            if (v == null || v.state == "cancelled") return ack("unknown", "this invite was cancelled or never existed here")
            if (v.device != null && v.device != remote) return ack("used", "another device is already using this invite")
            if (v.state == "accepted" || v.state == "refused") return ack(v.state)
            if (v.exp < now()) return ack("unknown", "this invite has expired; ask for a new one")
            if (v.state == "asked") { v.seen = now(); return ack("waiting") }
        }
        val req = try { JoinRequests.check(msg["request"]) } catch (e: IllegalArgumentException) { return ack("bad", e.message) }
        if (req["device"] != remote) return ack("bad", "the join request is not from the device that sent it")
        synchronized(this) {
            val v = items[token!!] ?: return ack("unknown")
            if (v.device != null && v.device != remote) return ack("used", "another device is already using this invite")
            v.state = "asked"; v.device = remote; v.seen = now(); v.full = req
            v.request = listOf("device", "username", "full_name", "position", "label").associateWith { req[it] }
        }
        return ack("waiting")
    }
}

/** The QR code's text -> the invite; IllegalArgumentException if it isn't one. */
@Suppress("UNCHECKED_CAST")
fun parseInvite(text: Any?): Map<String, Any?> {
    val inv = when (text) {
        is String -> runCatching { Json.parse(text) }.getOrNull()
        else -> text
    } as? Map<String, Any?>
    val addrs = inv?.get("addrs") as? List<*>
    val ok = inv != null && inv["kks_invite"] == 1L && listOf("root", "peer", "token").all { inv[it] is String } &&
             !addrs.isNullOrEmpty() && addrs.all { it is String && ':' in it }
    if (!ok) throw IllegalArgumentException("that is not a KKS Explorer invite")
    val exp = inv!!["exp"] as? Long
    if (exp != null && exp < System.currentTimeMillis() / 1000 - 120) throw IllegalArgumentException("this invite has expired; ask the admin for a new one")
    return listOf("kks_invite", "plant", "root", "peer", "addrs", "token", "exp").associateWith { inv[it] }
}

/** The 6 digits both screens show when a device asks an admin's device without an invite (§16); = node.join_code. */
fun joinCode(joiner: String, admin: String): String {
    val h = java.security.MessageDigest.getInstance("SHA-256").digest("kks-join-code-v1\n$joiner\n$admin".toByteArray())
    val n = ((h[0].toLong() and 0xff) shl 24) or ((h[1].toLong() and 0xff) shl 16) or ((h[2].toLong() and 0xff) shl 8) or (h[3].toLong() and 0xff)
    return "%06d".format(n % 1_000_000)
}

/** A device picked from /api/node/nearby -> an invite without a token (§16: ask the lobby). */
fun parseNearby(dev: Any?): Map<String, Any?> {
    val d = dev as? Map<*, *>
    val port = (d?.get("port") as? Long)
    if (d == null || d["peer"] !is String || d["host"] !is String || port == null) throw IllegalArgumentException("pick a device from the list")
    return mapOf("kks_invite" to 1L, "plant" to d["plant"], "root" to null, "peer" to d["peer"], "addrs" to listOf("${d["host"]}:$port"),
                 "token" to null, "exp" to null)
}

/** Join by invite, the joining side: ask until the admin decides, then sync. [state] for the UI (polled):
 *  connecting | waiting | confirm | syncing | joined | failed | cancelled. Without a token (a device picked on the
 *  Wi-Fi) the person must also confirm that the admin's screen shows the same code ([confirm]) before this device
 *  trusts that plant. */
class InviteJoin(private val node: LocalNode, private val sync: SyncControl, private val inv: Map<String, Any?>,
                 private val request: Map<String, Any?>, private val poll: Long = 2000, private val limitMs: Long = 20 * 60_000L) {
    private val nearby = inv["token"] == null
    @Volatile private var confirmed = !nearby
    @Volatile private var st: Map<String, Any?> = mapOf("state" to "connecting", "error" to null, "plant" to inv["plant"], "address" to null,
        "code" to if (nearby) joinCode(node.device, inv["peer"] as String) else null)
    @Volatile private var stop = false

    fun state() = st
    fun cancel() { stop = true }
    fun confirm() { confirmed = true }
    private fun set(vararg kv: Pair<String, Any?>) { st = st + kv }

    fun start() = Thread({ run() }, "kks-join").apply { isDaemon = true; start() }

    private fun run() {
        val deadline = System.currentTimeMillis() + limitMs
        var lastErr: String? = null
        try {
            while (!stop && System.currentTimeMillis() < deadline) {
                var answer: Triple<Triple<String, String, Map<String, Any?>>, String, Int>? = null
                for (a in inv["addrs"] as List<*>) {
                    val host = (a as String).substringBeforeLast(':')
                    val port = a.substringAfterLast(':').toIntOrNull() ?: continue
                    try {
                        answer = Triple(Sync.joinAsk(node.identity(), host, port, inv["peer"] as String, inv["token"] as String?, request, 8000), host, port)
                        break
                    } catch (e: Exception) { lastErr = "$a: ${e.message}" }
                }
                if (answer == null) { set("state" to "connecting", "error" to "cannot reach the admin's device yet ($lastErr)"); Thread.sleep(poll); continue }
                val (res, host, port) = answer
                set("address" to "$host:$port")
                when (res.first) {
                    "waiting" -> { set("state" to "waiting", "error" to null); Thread.sleep(poll); continue }
                    "accepted" -> {}
                    else -> { set("state" to "failed", "error" to (if (res.first == "refused") "the admin refused this device" else res.second.ifEmpty { res.first })); return }
                }
                val root = (inv["root"] ?: res.third["root"]) as? String ?: throw IllegalStateException("the admin's device did not say which plant")
                set("plant" to (res.third["plant"] ?: inv["plant"]))
                while (!confirmed && !stop && System.currentTimeMillis() < deadline) { set("state" to "confirm", "error" to null); Thread.sleep(300) }
                if (!confirmed) break
                set("state" to "syncing", "error" to null)
                sync.syncOne(host, port, if (node.anchor == null) root else null)
                if (node.owner() == null) throw IllegalStateException("synced, but this device is not certified in what came back")
                sync.joined()
                set("state" to "joined")
                return
            }
            set("state" to if (stop) "cancelled" else "failed", "error" to if (stop) null else "the invite ran out of time")
        } catch (e: Exception) {
            set("state" to "failed", "error" to (e.message ?: e.toString()))
        }
    }
}

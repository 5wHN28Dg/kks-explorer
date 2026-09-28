package kks.explorer

import android.content.Context
import android.net.ConnectivityManager
import android.os.Build
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.util.Log
import kks.core.Json
import kks.core.LocalNode
import kks.core.Sync
import kks.core.SyncControl
import kks.core.SyncStats
import java.net.Inet4Address
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.ServerSocket
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.Semaphore

/**
 * Sync on the phone (docs/PROTOCOL.md §15), the twin of server/syncsvc.py:
 * - a listener other devices connect to (port 8421, or any free one);
 * - finding devices on the same Wi-Fi with Android's NSD: the same mDNS service as the laptops' zeroconf
 *   (`_kks._tcp`, TXT peer = device ID, root = start of the plant's root key; other plants are skipped);
 * - automatic syncs while the app is open: every [INTERVAL_MS], [AFTER_CHANGE_MS] after a local change, and as soon
 *   as a new device appears; in the background [SyncWorker] does a short round every 15 minutes;
 * - the addresses of devices it synced with are remembered, for when discovery finds nothing (e.g. Wi-Fi that blocks
 *   multicast) — "Sync now" tries them too;
 * - automatic syncs skip metered networks (mobile data, hotspots, Wi-Fi marked as metered) unless the person allowed
 *   them ([METERED_META]); "Sync now" always syncs.
 */
class PhoneSync(context: Context, private val node: LocalNode) : SyncControl {
    companion object {
        const val SERVICE = "_kks._tcp"
        const val INTERVAL_MS = 120_000L
        const val AFTER_CHANGE_MS = 5_000L
        const val METERED_META = "sync_metered"             // "1": automatic syncs also on metered networks
        private const val TAG = "KKSSync"
    }

    data class Found(val name: String, val host: String, val port: Int, val peer: String?, val root: String,
                     val plant: String, val label: String, val adm: Boolean)

    private val nsd = context.getSystemService(Context.NSD_SERVICE) as NsdManager
    private val cm = context.getSystemService(ConnectivityManager::class.java)
    private val status = LinkedHashMap<String, Map<String, Any?>>()
    private val found = ConcurrentHashMap<String, Found>()
    private val pool = Executors.newCachedThreadPool()
    /** M5: the plant's internet relay (manager setting `relay`), while this phone is active and allowed to use the
     *  network it is on (metered setting). */
    val net = kks.core.Internet(node, relay = { (runCatching { synchronized(node) { node.run.settings["relay"] } }.getOrNull() as? String)?.ifEmpty { null } },
        record = { r, a, ok, res, d -> record(r, a, ok, res, d) }, allowed = { autoAllowed() }, onChange = { onJoinAsked?.invoke() })
    private val resolveQueue = LinkedBlockingQueue<NsdServiceInfo>()
    private val wake = Object()
    private var srv: ServerSocket? = null
    override val port: Int? get() = srv?.localPort

    @Volatile var discovery = "off"; private set
    @Volatile var onJoinAsked: (() -> Unit)? = null           // a device asked to join (the admin's badge)
    @Volatile private var selfSeen = false
    @Volatile private var active = false                     // discovery + auto sync running (app on screen, or a worker)
    private var discoveryListener: NsdManager.DiscoveryListener? = null
    private var registration: NsdManager.RegistrationListener? = null
    private var announced: Map<String, String>? = null      // the TXT attributes currently announced
    @Volatile private var due = 0L
    @Volatile private var roundRunning = false

    init {
        node.listeners.add { why ->
            if (why == "local") poke(AFTER_CHANGE_MS)
            pool.execute { announce() }                         // e.g. just joined a plant: announce it
        }
        pool.execute { resolver() }
        pool.execute { autoLoop() }
    }

    // ---------- listener ----------
    fun listen(preferred: Int = 8421) {
        val s = ServerSocket()
        s.reuseAddress = true
        try { s.bind(InetSocketAddress(preferred)) } catch (e: Exception) { s.bind(InetSocketAddress(0)) }
        srv = s
        val slots = Semaphore(4)
        pool.execute {
            while (!s.isClosed) {
                val sock = try { s.accept() } catch (e: Exception) { break }
                if (!slots.tryAcquire()) { sock.close(); continue }
                pool.execute {
                    val addr = sock.inetAddress.hostAddress ?: "?"
                    try {
                        val (remote, st) = Sync.serveOne(node, sock)
                        if (st.join == null) record(remote, addr, true, st, "in")      // (a join-by-invite question is not a sync)
                        else { Log.i(TAG, "join by invite from $addr: ${st.join}"); onJoinAsked?.invoke() }
                    } catch (e: Exception) {
                        record(null, addr, false, e.message, "in")
                    } finally { slots.release() }
                }
            }
        }
    }

    // ---------- discovery (NSD) ----------
    /** Start finding and announcing (the app came on screen, or a background round began). Idempotent. */
    override fun relayChanged() { if (active) pool.execute { net.stop(); Thread.sleep(300); net.start() } }

    fun start() {
        synchronized(this) { if (active) return; active = true }
        net.start()
        announce()                                  // (outside the lock: it reads the node)
        synchronized(this) { startDiscovery() }
    }

    private fun startDiscovery() {
        if (!active || discoveryListener != null) return
        val l = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(t: String) { discovery = "on" }
            override fun onDiscoveryStopped(t: String) { if (!active) discovery = "off" }
            override fun onStartDiscoveryFailed(t: String, code: Int) { discovery = "could not start (error $code)" }
            override fun onStopDiscoveryFailed(t: String, code: Int) {}
            override fun onServiceFound(info: NsdServiceInfo) { if (info.serviceName.startsWith("kks-")) resolveQueue.offer(info) }
            override fun onServiceLost(info: NsdServiceInfo) { found.remove(info.serviceName) }
        }
        discoveryListener = l
        runCatching { nsd.discoverServices(SERVICE, NsdManager.PROTOCOL_DNS_SD, l) }.onFailure { discovery = "unavailable: ${it.message}" }
        poke(2_000)
    }

    /** Stop finding (the app left the screen). The listener keeps answering while the process lives. */
    @Synchronized fun stop() {
        if (!active) return
        active = false
        net.stop()
        discoveryListener?.let { runCatching { nsd.stopServiceDiscovery(it) } }
        discoveryListener = null
        registration?.let { runCatching { nsd.unregisterService(it) } }
        registration = null; announced = null
        found.clear()
        discovery = "off (the app is in the background)"
    }

    /** Resolve found services one at a time (NsdManager allows only one resolve in flight). */
    private fun resolver() {
        while (true) {
            val info = resolveQueue.take()
            val done = Object()
            var result: NsdServiceInfo? = null
            @Suppress("DEPRECATION")
            runCatching {
                nsd.resolveService(info, object : NsdManager.ResolveListener {
                    override fun onServiceResolved(i: NsdServiceInfo) { result = i; synchronized(done) { done.notifyAll() } }
                    override fun onResolveFailed(i: NsdServiceInfo, code: Int) { synchronized(done) { done.notifyAll() } }
                })
                synchronized(done) { done.wait(5_000) }
            }
            val r = result ?: continue
            val attrs = r.attributes.mapValues { (_, v) -> v?.toString(Charsets.UTF_8) ?: "" }
            @Suppress("DEPRECATION") val host = r.host?.hostAddress ?: continue
            if (attrs["peer"] == node.device) { selfSeen = true; continue }   // our own announcement
            val f = Found(r.serviceName, host, r.port, attrs["peer"], attrs["root"] ?: "", attrs["plant"] ?: "", attrs["label"] ?: "", attrs["adm"] == "1")
            val isNew = found.put(r.serviceName, f) == null
            Log.i(TAG, "found ${f.peer?.take(12)} at ${f.host}:${f.port} root ${f.root}")
            if (isNew && f.root.isNotEmpty() && f.root == myRoot()) poke(1_000)
        }
    }

    private fun myRoot() = (node.anchor ?: "").take(16)

    /** (Re)announce this phone: device ID + start of its plant's root, so others skip other plants. */
    private fun announce() {
        // plant name, who this is and whether an admin can accept a joining device here (§16). Read from the node
        // BEFORE taking this object's lock: the API thread holds the node's lock while it asks for snapshot()
        val o = node.owner()
        val plant = if (node.anchor != null) ((synchronized(node) { node.run.settings["plant"] } as? String) ?: "") else ""
        val want = mapOf("peer" to node.device, "root" to myRoot(), "v" to "1", "plant" to plant.take(80),
            "label" to (listOfNotNull(o?.fullName, "${Build.MANUFACTURER} ${Build.MODEL}".trim()).joinToString(" · ")).take(120),
            "adm" to if (o?.isAdmin() == true) "1" else "")
        synchronized(this) { register(want) }
    }

    private fun register(want: Map<String, String>) {
        if (!active) return
        val p = port ?: return
        if (want == announced) return
        registration?.let { runCatching { nsd.unregisterService(it) } }
        val info = NsdServiceInfo().apply {
            serviceName = "kks-${node.device.take(12)}"; serviceType = SERVICE; this.port = p
            want.forEach { (k, v) -> setAttribute(k, v) }
        }
        val l = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(i: NsdServiceInfo) { Log.i(TAG, "announced as ${i.serviceName}") }
            override fun onRegistrationFailed(i: NsdServiceInfo, code: Int) { Log.w(TAG, "announce failed $code") }
            override fun onServiceUnregistered(i: NsdServiceInfo) {}
            override fun onUnregistrationFailed(i: NsdServiceInfo, code: Int) {}
        }
        registration = l; announced = want
        runCatching { nsd.registerService(info, NsdManager.PROTOCOL_DNS_SD, l) }
    }

    // ---------- automatic sync ----------
    private fun poke(inMs: Long) {
        val t = System.currentTimeMillis() + inMs
        if (due == 0L || t < due) due = t
        synchronized(wake) { wake.notifyAll() }
    }

    private fun autoLoop() {
        while (true) {
            val wait = if (due == 0L) INTERVAL_MS else due - System.currentTimeMillis()
            if (wait > 0) { synchronized(wake) { wake.wait(minOf(wait, INTERVAL_MS)) }; continue }
            due = System.currentTimeMillis() + INTERVAL_MS
            if (active && node.anchor != null && autoAllowed()) runCatching { syncAll() }
        }
    }

    var meteredAllowed: Boolean
        get() = node.store.meta(METERED_META) == "1"
        set(v) { node.store.setMeta(METERED_META, if (v) "1" else null); if (v) poke(1_000) }

    /** Automatic syncs run on unmetered networks, and on metered ones only if allowed. */
    fun autoAllowed() = meteredAllowed || !cm.isActiveNetworkMetered

    // ---------- syncing ----------
    override fun syncOne(host: String, port: Int, adoptRoot: String?): SyncStats {
        val (remote, st) = try {
            Sync.syncWith(node, host, port, adoptRoot, timeoutMs = 20_000)
        } catch (e: Exception) {
            record(null, "$host:$port", false, e.message, "out"); throw e
        }
        record(remote, "$host:$port", true, st, "out")
        remember("$host:$port")
        kks.core.Progress.swapAfterSync(node, host, port, remote)     // another device of this person: share the progress key
        return st
    }

    @Suppress("UNCHECKED_CAST")
    private fun known(): List<String> = runCatching { Json.parse(node.store.meta("sync_peers") ?: "[]") as List<String> }.getOrDefault(emptyList())

    private fun remember(address: String) {
        node.store.setMeta("sync_peers", Json.write((listOf(address) + known().filter { it != address }).take(10)))
    }

    /** One round: every device found on this Wi-Fi for this plant, then remembered addresses not seen that way. */
    override fun syncAll() {
        if (roundRunning) return
        roundRunning = true
        val start = System.currentTimeMillis() / 1000
        try {
            val root = myRoot()
            val targets = LinkedHashSet<String>()
            found.values.filter { it.root.isNotEmpty() && it.root == root }.forEach { targets.add("${it.host}:${it.port}") }
            targets.addAll(known())
            for (a in targets) runCatching { syncOne(a.substringBeforeLast(':'), a.substringAfterLast(':').toInt()) }
            syncInternet(start)
        } finally { roundRunning = false }
    }

    /** Devices of the plant online on the relay that weren't reached on this network in this round (§18). */
    private fun syncInternet(start: Long) {
        val fresh = synchronized(this) { status.filter { it.value["ok"] == true && ((it.value["last_ok"] as Long?) ?: 0) >= start }.keys }
        for (peer in net.online.toList() - fresh) runCatching {
            net.sync(peer)
            kks.core.Progress.swapAfterSync(node, "", 0, peer) { net.connect(peer).first }
        }
    }

    @Synchronized private fun record(remote: String?, address: String, ok: Boolean, result: Any?, direction: String) {
        val key = remote ?: address
        val st = result as? SyncStats
        if (!ok && remote == null) for ((k, v) in status.entries.toList())   // it didn't answer: whoever was there isn't reachable now
            if (v["address"] == address && v["ok"] == true) status[k] = v + mapOf("ok" to false, "at" to System.currentTimeMillis() / 1000, "error" to result?.toString())
        Log.i(TAG, "sync $direction $address: " + if (ok && st != null) "received ${st.received}, sent ${st.sent}" else "failed: $result")
        status[key] = (status[key] ?: emptyMap()) + mapOf("peer" to remote, "address" to address, "at" to System.currentTimeMillis() / 1000,
            "ok" to ok, "direction" to direction, "last_ok" to if (ok) System.currentTimeMillis() / 1000 else status[key]?.get("last_ok")) + if (ok && st != null) mapOf("error" to null, "result" to mapOf(
                "sent" to st.sent.toLong(), "received" to st.received.toLong(), "denied" to st.denied, "they_denied" to st.theyDenied))
            else mapOf("error" to result?.toString())
    }

    @Synchronized override fun snapshot(): Map<String, Any?> = mapOf(
        "discovery" to discovery + (if (discovery == "on" && selfSeen) " (this phone is visible to others)" else ""),
        "port" to port?.toLong(),
        "found" to found.values.map { mapOf("host" to it.host, "port" to it.port.toLong(), "peer" to it.peer, "root" to it.root,
                                            "plant" to it.plant, "label" to it.label, "adm" to it.adm) },
        "syncs" to LinkedHashMap(status), "self_seen" to selfSeen,
        "metered_allowed" to meteredAllowed, "paused" to !autoAllowed(), "internet" to net.snapshot())

    /** This phone's addresses on local networks (Wi-Fi, its own hotspot, Ethernet), for invites. Mobile data and VPN
     *  interfaces are left out: other phones can't reach those. */
    override fun addresses(): List<String> {
        val p = port ?: return emptyList()
        val out = ArrayList<Pair<String, String>>()
        runCatching {
            for (ni in NetworkInterface.getNetworkInterfaces()) {
                if (!ni.isUp || ni.isLoopback || ni.isVirtual) continue
                if (ni.name.startsWith("rmnet") || ni.name.startsWith("ccmni") || ni.name.startsWith("tun") || ni.name.startsWith("dummy") || ni.name.startsWith("v4-")) continue
                for (a in ni.inetAddresses) if (a is Inet4Address && !a.isLoopbackAddress && !a.isLinkLocalAddress) out.add(ni.name to a.hostAddress!!)
            }
        }
        return out.sortedBy { if (it.first.startsWith("wlan")) 0 else 1 }.map { "${it.second}:$p" }
    }

    override fun reach(): Map<String, Any?> {
        val root = myRoot(); val now = System.currentTimeMillis() / 1000
        val nearby = found.values.filter { root.isNotEmpty() && it.root == root }.mapNotNull { it.peer }.toSet() + net.online
        val recent = synchronized(this) { status.values.filter { it["ok"] == true && now - ((it["at"] as Long?) ?: 0) < 180 }.mapNotNull { it["peer"] as String? }.toSet() }
        val last = synchronized(this) { status.values.mapNotNull { it["last_ok"] as Long? }.maxOrNull() }
        return mapOf("reachable" to (nearby + recent).size.toLong(), "nearby" to nearby.size.toLong(), "last_sync" to last)
    }

    /** Android's own check: the active network reaches the internet (it probes that itself). */
    override fun internet(): Boolean? = runCatching {
        cm.getNetworkCapabilities(cm.activeNetwork)?.hasCapability(android.net.NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true
    }.getOrNull()

    override fun joined() { pool.execute { announce() }; poke(1_000) }
}

package kks.explorer

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.util.Log
import kks.core.Json
import kks.core.LocalNode
import kks.core.Sync
import kks.core.SyncControl
import kks.core.SyncStats
import java.net.InetSocketAddress
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
 *   multicast) — "Sync now" tries them too.
 */
class PhoneSync(context: Context, private val node: LocalNode) : SyncControl {
    companion object {
        const val SERVICE = "_kks._tcp"
        const val INTERVAL_MS = 120_000L
        const val AFTER_CHANGE_MS = 5_000L
        private const val TAG = "KKSSync"
    }

    data class Found(val name: String, val host: String, val port: Int, val peer: String?, val root: String)

    private val nsd = context.getSystemService(Context.NSD_SERVICE) as NsdManager
    private val status = LinkedHashMap<String, Map<String, Any?>>()
    private val found = ConcurrentHashMap<String, Found>()
    private val pool = Executors.newCachedThreadPool()
    private val resolveQueue = LinkedBlockingQueue<NsdServiceInfo>()
    private val wake = Object()
    private var srv: ServerSocket? = null
    override val port: Int? get() = srv?.localPort

    @Volatile var discovery = "off"; private set
    @Volatile private var selfSeen = false
    @Volatile private var active = false                     // discovery + auto sync running (app on screen, or a worker)
    private var discoveryListener: NsdManager.DiscoveryListener? = null
    private var registration: NsdManager.RegistrationListener? = null
    private var announced: Pair<String, String>? = null      // (peer, root) currently announced
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
                        record(remote, addr, true, st, "in")
                    } catch (e: Exception) {
                        record(null, addr, false, e.message, "in")
                    } finally { slots.release() }
                }
            }
        }
    }

    // ---------- discovery (NSD) ----------
    /** Start finding and announcing (the app came on screen, or a background round began). Idempotent. */
    @Synchronized fun start() {
        if (active) return
        active = true
        announce()
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
            val f = Found(r.serviceName, host, r.port, attrs["peer"], attrs["root"] ?: "")
            val isNew = found.put(r.serviceName, f) == null
            Log.i(TAG, "found ${f.peer?.take(12)} at ${f.host}:${f.port} root ${f.root}")
            if (isNew && f.root.isNotEmpty() && f.root == myRoot()) poke(1_000)
        }
    }

    private fun myRoot() = (node.anchor ?: "").take(16)

    /** (Re)announce this phone: device ID + start of its plant's root, so others skip other plants. */
    @Synchronized private fun announce() {
        if (!active) return
        val p = port ?: return
        val want = node.device to myRoot()
        if (want == announced) return
        registration?.let { runCatching { nsd.unregisterService(it) } }
        val info = NsdServiceInfo().apply {
            serviceName = "kks-${node.device.take(12)}"; serviceType = SERVICE; this.port = p
            setAttribute("peer", node.device); setAttribute("root", myRoot()); setAttribute("v", "1")
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
            if (active && node.anchor != null) runCatching { syncAll() }
        }
    }

    // ---------- syncing ----------
    override fun syncOne(host: String, port: Int, adoptRoot: String?): SyncStats {
        val (remote, st) = try {
            Sync.syncWith(node, host, port, adoptRoot, timeoutMs = 20_000)
        } catch (e: Exception) {
            record(null, "$host:$port", false, e.message, "out"); throw e
        }
        record(remote, "$host:$port", true, st, "out")
        remember("$host:$port")
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
        try {
            val root = myRoot()
            val targets = LinkedHashSet<String>()
            found.values.filter { it.root.isNotEmpty() && it.root == root }.forEach { targets.add("${it.host}:${it.port}") }
            targets.addAll(known())
            for (a in targets) runCatching { syncOne(a.substringBeforeLast(':'), a.substringAfterLast(':').toInt()) }
        } finally { roundRunning = false }
    }

    @Synchronized private fun record(remote: String?, address: String, ok: Boolean, result: Any?, direction: String) {
        val key = remote ?: address
        val st = result as? SyncStats
        Log.i(TAG, "sync $direction $address: " + if (ok && st != null) "received ${st.received}, sent ${st.sent}" else "failed: $result")
        status[key] = (status[key] ?: emptyMap()) + mapOf("peer" to remote, "address" to address, "at" to System.currentTimeMillis() / 1000,
            "ok" to ok, "direction" to direction) + if (ok && st != null) mapOf("error" to null, "result" to mapOf(
                "sent" to st.sent.toLong(), "received" to st.received.toLong(), "denied" to st.denied, "they_denied" to st.theyDenied))
            else mapOf("error" to result?.toString())
    }

    @Synchronized override fun snapshot(): Map<String, Any?> = mapOf(
        "discovery" to discovery + (if (discovery == "on" && selfSeen) " (this phone is visible to others)" else ""),
        "port" to port?.toLong(),
        "found" to found.values.map { mapOf("host" to it.host, "port" to it.port.toLong(), "peer" to it.peer, "root" to it.root) },
        "syncs" to LinkedHashMap(status), "self_seen" to selfSeen)

    override fun joined() { pool.execute { announce() }; poke(1_000) }
}

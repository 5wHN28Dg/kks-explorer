package kks.explorer.sync

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.util.Log
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

/**
 * mDNS through Android's NSD (decision 0002): announce _kks._tcp with the TXT of PROTOCOL-v2 §16, find the others.
 * Resolves run one at a time: before Android 14, NSD refuses a second resolve while one is running (v1 PhoneSync).
 */
object Discovery {
    data class Found(val name: String, val host: String, val port: Int, val peer: String, val root: String, val plant: String,
                     val label: String, val admin: Boolean)
    private val found = ConcurrentHashMap<String, Found>()
    fun found(): List<Found> = found.values.toList()
    @Volatile var onFound: ((Found) -> Unit)? = null

    private var nsd: NsdManager? = null
    private var browsing: NsdManager.DiscoveryListener? = null
    private var registered: NsdManager.RegistrationListener? = null
    private var announced = ""
    private val queue = LinkedBlockingQueue<NsdServiceInfo>()
    private val resolver = Executors.newSingleThreadExecutor { Thread(it, "kks-nsd-resolve") }

    @Synchronized fun start(ctx: Context) {
        if (browsing != null) return
        val m = nsd ?: (ctx.getSystemService(Context.NSD_SERVICE) as NsdManager).also { nsd = it }
        val l = object : NsdManager.DiscoveryListener {
            override fun onStartDiscoveryFailed(t: String?, e: Int) { Log.w("KKSSync", "discovery failed $e") }
            override fun onStopDiscoveryFailed(t: String?, e: Int) {}
            override fun onDiscoveryStarted(t: String?) {}
            override fun onDiscoveryStopped(t: String?) {}
            override fun onServiceLost(s: NsdServiceInfo) { found.remove(s.serviceName) }
            override fun onServiceFound(s: NsdServiceInfo) { queue.offer(s); resolver.execute { resolveNext(m) } }
        }
        browsing = l
        m.discoverServices("_kks._tcp", NsdManager.PROTOCOL_DNS_SD, l)
    }

    @Synchronized fun stop() {
        val m = nsd ?: return
        browsing?.let { runCatching { m.stopServiceDiscovery(it) } }
        browsing = null
        found.clear()
    }

    /** one resolve at a time; waits for its answer (at most 10 s) */
    private fun resolveNext(m: NsdManager) {
        val s = queue.poll() ?: return
        val done = LinkedBlockingQueue<Unit>()
        @Suppress("DEPRECATION")
        m.resolveService(s, object : NsdManager.ResolveListener {
            override fun onResolveFailed(si: NsdServiceInfo?, e: Int) { done.offer(Unit) }
            override fun onServiceResolved(r: NsdServiceInfo) {
                fun txt(k: String) = r.attributes[k]?.toString(Charsets.UTF_8) ?: ""
                @Suppress("DEPRECATION") val host = r.host?.hostAddress
                if (host != null) {
                    val f = Found(r.serviceName, host, r.port, txt("peer"), txt("root"), txt("plant"), txt("label"), txt("adm") == "1")
                    found[r.serviceName] = f
                    Log.i("KKSSync", "found ${f.name} ${f.host}:${f.port} plant=${f.plant}")
                    onFound?.invoke(f)
                }
                done.offer(Unit)
            }
        })
        done.poll(10, TimeUnit.SECONDS)
    }

    /** announce (again when the TXT changed: a new plant, a new role) */
    @Synchronized fun announce(ctx: Context, name: String, port: Int, txt: Map<String, String>) {
        val m = nsd ?: (ctx.getSystemService(Context.NSD_SERVICE) as NsdManager).also { nsd = it }
        val key = "$name:$port:$txt"
        if (key == announced) return
        registered?.let { runCatching { m.unregisterService(it) } }
        val info = NsdServiceInfo().apply { serviceName = name; serviceType = "_kks._tcp"; setPort(port); txt.forEach { (k, v) -> setAttribute(k, v) } }
        val l = object : NsdManager.RegistrationListener {
            override fun onRegistrationFailed(s: NsdServiceInfo?, e: Int) { Log.w("KKSSync", "announce failed $e") }
            override fun onUnregistrationFailed(s: NsdServiceInfo?, e: Int) {}
            override fun onServiceRegistered(s: NsdServiceInfo?) { Log.i("KKSSync", "announced as ${s?.serviceName}") }
            override fun onServiceUnregistered(s: NsdServiceInfo?) {}
        }
        registered = l
        announced = key
        m.registerService(info, NsdManager.PROTOCOL_DNS_SD, l)
    }

    @Synchronized fun unannounce() {
        val m = nsd ?: return
        registered?.let { runCatching { m.unregisterService(it) } }
        registered = null
        announced = ""
    }
}

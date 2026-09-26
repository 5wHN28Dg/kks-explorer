package kks.explorer

import kks.core.Json
import kks.core.LocalNode
import kks.core.Sync
import kks.core.SyncControl
import kks.core.SyncStats
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.util.concurrent.Executors
import java.util.concurrent.Semaphore

/**
 * Sync on the phone (docs/PROTOCOL.md §15): a listener other devices connect to, sync by address, and the addresses of
 * devices it synced with (tried again by "Sync now"). Finding devices on the Wi-Fi by itself (NSD) comes in M3d.
 */
class PhoneSync(private val node: LocalNode) : SyncControl {
    private val status = LinkedHashMap<String, Map<String, Any?>>()
    private val pool = Executors.newCachedThreadPool()
    private var srv: ServerSocket? = null
    override val port: Int? get() = srv?.localPort

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

    override fun syncAll() {
        for (a in known()) runCatching { syncOne(a.substringBeforeLast(':'), a.substringAfterLast(':').toInt()) }
    }

    @Synchronized private fun record(remote: String?, address: String, ok: Boolean, result: Any?, direction: String) {
        val key = remote ?: address
        val st = result as? SyncStats
        status[key] = (status[key] ?: emptyMap()) + mapOf("peer" to remote, "address" to address, "at" to System.currentTimeMillis() / 1000,
            "ok" to ok, "direction" to direction) + if (ok && st != null) mapOf("error" to null, "result" to mapOf(
                "sent" to st.sent.toLong(), "received" to st.received.toLong(), "denied" to st.denied, "they_denied" to st.theyDenied))
            else mapOf("error" to result?.toString())
    }

    @Synchronized override fun snapshot(): Map<String, Any?> = mapOf(
        "discovery" to "not on phones yet (next update); \"Sync with it\" by address works",
        "port" to port?.toLong(), "found" to emptyList<Any>(), "syncs" to LinkedHashMap(status))

    override fun joined() {}
}

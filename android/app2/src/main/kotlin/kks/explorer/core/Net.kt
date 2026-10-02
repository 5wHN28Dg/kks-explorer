package kks.explorer.core

import android.util.Base64
import org.json.JSONObject
import java.io.DataInputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.Socket
import java.net.URL
import java.security.KeyStore
import java.security.MessageDigest
import java.security.Principal
import java.security.PrivateKey
import java.security.cert.X509Certificate
import java.security.interfaces.ECPublicKey
import javax.net.ssl.KeyManager
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLServerSocket
import javax.net.ssl.SSLSocket
import javax.net.ssl.X509ExtendedKeyManager
import javax.net.ssl.X509TrustManager
import javax.net.ssl.SSLEngine

/**
 * Sync over TLS (PROTOCOL-v2 §15, decisions 0017 and 0032). TLS is Android's: client and server authenticate with the
 * device's AndroidKeyStore key and its self-signed certificate, and each side pins the other's peer ID (24 bytes of
 * SHA-256 over the uncompressed point, base64url). The core's session sees only the plaintext.
 */
object Net {
    const val ALPN = "kks-sync/2"
    private const val TIMEOUT = 15_000
    private val SUITES = arrayOf("TLS_AES_128_GCM_SHA256", "TLS_AES_256_GCM_SHA384",
        "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256", "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384")

    fun b64u(b: ByteArray): String = Base64.encodeToString(b, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)

    fun peerIdOf(cert: X509Certificate): String {
        val w = (cert.publicKey as ECPublicKey).w
        fun be32(x: java.math.BigInteger) = x.toByteArray().let { if (it.size > 32) it.copyOfRange(it.size - 32, it.size) else ByteArray(32 - it.size) + it }
        val pub = byteArrayOf(4) + be32(w.affineX) + be32(w.affineY)
        return b64u(MessageDigest.getInstance("SHA-256").digest(pub).copyOfRange(0, 24))
    }

    private class DeviceKeys : X509ExtendedKeyManager() {
        private val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        override fun getClientAliases(t: String?, issuers: Array<out Principal>?) = arrayOf(Keys.DEVICE)
        override fun chooseClientAlias(t: Array<out String>?, issuers: Array<out Principal>?, s: Socket?) = Keys.DEVICE
        override fun chooseEngineClientAlias(t: Array<out String>?, issuers: Array<out Principal>?, e: SSLEngine?) = Keys.DEVICE
        override fun getServerAliases(t: String?, issuers: Array<out Principal>?) = arrayOf(Keys.DEVICE)
        override fun chooseServerAlias(t: String?, issuers: Array<out Principal>?, s: Socket?) = Keys.DEVICE
        override fun chooseEngineServerAlias(t: String?, issuers: Array<out Principal>?, e: SSLEngine?) = Keys.DEVICE
        override fun getCertificateChain(alias: String?) = arrayOf(ks.getCertificate(Keys.DEVICE) as X509Certificate)
        override fun getPrivateKey(alias: String?) = ks.getKey(Keys.DEVICE, null) as PrivateKey
    }

    /** accepts any self-signed peer certificate; the peer ID is checked after the handshake (expected or recorded) */
    private object AnyPeer : X509TrustManager {
        override fun checkClientTrusted(chain: Array<out X509Certificate>, authType: String?) { require(chain.isNotEmpty()) }
        override fun checkServerTrusted(chain: Array<out X509Certificate>, authType: String?) { require(chain.isNotEmpty()) }
        override fun getAcceptedIssuers() = arrayOf<X509Certificate>()
    }

    private val ctx: SSLContext by lazy {
        SSLContext.getInstance("TLS").apply { init(arrayOf<KeyManager>(DeviceKeys()), arrayOf(AnyPeer), null) }
    }

    private fun profile(s: SSLSocket) {
        s.enabledProtocols = s.supportedProtocols.filter { it == "TLSv1.3" || it == "TLSv1.2" }.toTypedArray()
        s.enabledCipherSuites = s.supportedCipherSuites.filter { it in SUITES }.toTypedArray()
        s.sslParameters = s.sslParameters.apply { applicationProtocols = arrayOf(ALPN) }
    }

    /** an authenticated sync connection: TLS over TCP (an SSLSocket) or over a relay pipe (EngineTls) */
    class Peer(val input: InputStream, val output: OutputStream, val remote: String, private val closer: java.io.Closeable) {
        constructor(s: SSLSocket, remote: String) : this(s.inputStream, s.outputStream, remote, s)
        fun close() { runCatching { closer.close() } }
    }

    /** TLS with the sync's profile over a relay pipe (§18); the client pins expectPeer, the server requires a client certificate */
    fun overPipe(ws: WsClient, client: Boolean, expectPeer: String): Peer {
        val e = ctx.createSSLEngine()
        e.useClientMode = client
        e.enabledProtocols = e.supportedProtocols.filter { it == "TLSv1.3" || it == "TLSv1.2" }.toTypedArray()
        e.enabledCipherSuites = e.supportedCipherSuites.filter { it in SUITES }.toTypedArray()
        e.sslParameters = e.sslParameters.apply { applicationProtocols = arrayOf(ALPN) }
        if (!client) e.needClientAuth = true
        ws.setTimeout(TIMEOUT * 2)
        val t = EngineTls(e, rawIn = {
            var got: ByteArray? = null
            while (got == null) {
                val (op, data) = try { ws.recv() } catch (x: IOException) { break }
                if (op == WsClient.BINARY) got = data
            }
            got
        }, rawOut = { ws.sendBinary(it) }, onClose = { ws.close() })
        try {
            t.handshake()
            if (e.applicationProtocol != ALPN) throw IllegalStateException("the other side does not speak $ALPN")
            val remote = peerIdOf(e.session.peerCertificates[0] as X509Certificate)
            if (expectPeer.isNotEmpty() && remote != expectPeer) throw IllegalStateException("another device answered")
            return Peer(t.input, t.output, remote, t)
        } catch (x: Exception) { t.close(); throw x }
    }

    fun connect(host: String, port: Int, expectPeer: String): Peer {
        val raw = Socket()
        raw.connect(InetSocketAddress(host, port), TIMEOUT)
        raw.soTimeout = TIMEOUT * 2
        val s = ctx.socketFactory.createSocket(raw, host, port, true) as SSLSocket
        profile(s)
        s.useClientMode = true
        s.startHandshake()
        if (s.applicationProtocol != ALPN) { s.close(); throw IllegalStateException("the other side does not speak $ALPN") }
        val remote = peerIdOf(s.session.peerCertificates[0] as X509Certificate)
        if (expectPeer.isNotEmpty() && remote != expectPeer) { s.close(); throw IllegalStateException("that address is another device") }
        return Peer(s, remote)
    }

    /** one §15 exchange to the end; returns the session's summary */
    fun drive(p: Peer, initiator: Boolean, adoptRoot: String = ""): JSONObject {
        val sid = Core.syncStart(initiator, p.remote, adoptRoot)
        try {
            var out = Core.syncFeed(sid, ByteArray(0))
            val buf = ByteArray(64 * 1024)
            while (true) {
                if (out.isNotEmpty()) { p.output.write(out); p.output.flush() }
                val info = Core.syncInfo(sid)
                if (info.optBoolean("done")) return info
                if (info.optString("error").isNotEmpty()) throw IllegalStateException(info.optString("error"))
                val n = p.input.read(buf)
                if (n < 0) throw IllegalStateException("the other side closed the connection")
                out = Core.syncFeed(sid, buf.copyOf(n))
            }
        } finally {
            Core.syncEnd(sid)
        }
    }

    fun syncWith(host: String, port: Int, expectPeer: String, adoptRoot: String = ""): JSONObject {
        val p = connect(host, port, expectPeer)
        try { return drive(p, true, adoptRoot) } finally { p.close() }
    }

    private fun frame(j: JSONObject): ByteArray {
        val b = j.toString().toByteArray(Charsets.UTF_8)
        return byteArrayOf((b.size ushr 24).toByte(), (b.size ushr 16).toByte(), (b.size ushr 8).toByte(), b.size.toByte()) + b
    }

    /** one question instead of a sync (§16 join): send msg, return the single answer */
    fun ask(host: String, port: Int, expectPeer: String, msg: JSONObject): JSONObject {
        val p = connect(host, port, expectPeer)
        try {
            p.output.write(frame(msg)); p.output.flush()
            val din = DataInputStream(p.input)
            val n = din.readInt()
            require(n in 0..(64 shl 20))
            val b = ByteArray(n); din.readFully(b)
            return JSONObject(b.toString(Charsets.UTF_8))
        } finally { p.close() }
    }

    /** incoming syncs (other devices on the Wi-Fi); returns the port it listens on */
    fun listen(firstPort: Int, onDone: (String, JSONObject) -> Unit): SSLServerSocket {
        var port = firstPort
        var server: SSLServerSocket? = null
        while (server == null) {
            try { server = ctx.serverSocketFactory.createServerSocket(port) as SSLServerSocket } catch (e: java.net.BindException) { port++; if (port > firstPort + 20) throw e }
        }
        server.needClientAuth = true
        Thread({
            while (!server.isClosed) {
                val s = try { server.accept() as SSLSocket } catch (e: Exception) { break }
                Thread({
                    try {
                        profile(s)
                        s.soTimeout = TIMEOUT * 2
                        s.startHandshake()
                        val remote = peerIdOf(s.session.peerCertificates[0] as X509Certificate)
                        onDone(remote, drive(Peer(s, remote), false))
                    } catch (e: Exception) {
                        android.util.Log.w("KKSSync", "incoming sync: ${e.message}")
                    } finally { s.close() }
                }, "kks-sync-in").start()
            }
        }, "kks-listen").start()
        return server
    }

    /** "join through a server": the server certifies this device for the person (server/node.py join_via_server) */
    fun enroll(base: String, username: String, password: String, device: String, label: String): JSONObject {
        val c = URL(base.trimEnd('/') + "/api/devices/enroll").openConnection() as HttpURLConnection
        c.requestMethod = "POST"; c.doOutput = true; c.connectTimeout = TIMEOUT; c.readTimeout = TIMEOUT
        c.setRequestProperty("Content-Type", "application/json")
        c.outputStream.use { it.write(JSONObject().put("username", username).put("password", password).put("device", device).put("label", label).toString().toByteArray()) }
        val code = c.responseCode
        val body = (if (code in 200..299) c.inputStream else c.errorStream)?.readBytes()?.toString(Charsets.UTF_8) ?: ""
        val j = try { JSONObject(body) } catch (e: Exception) { JSONObject().put("error", "the server answered $code") }
        if (code !in 200..299) throw IllegalStateException(j.optString("error", "the server answered $code"))
        return j
    }
}

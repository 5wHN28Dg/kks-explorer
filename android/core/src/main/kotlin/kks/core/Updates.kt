package kks.core

import java.net.HttpURLConnection
import java.net.URI

/**
 * Self-updates from GitHub Releases (M5b); the twin of server/updates.py, the same signed manifest. A release counts
 * only if `release.json.sig` is an Ed25519 signature by the pinned release key over "kks-release-v1\n" + release.json,
 * and a download counts only if it matches its hash in that manifest. (On Android the system installer also checks
 * that the APK is signed with the app's own key.)
 */
object Updates {
    const val REPO = "5wHN28Dg/kks-explorer"
    const val RELEASE_PUB = "YBHkaex01_tOIIUiI8kZMAHCwUF-aHIGYJtR0jnENtM"
    const val APK = "kks-explorer.apk"
    val DOMAIN = "kks-release-v1\n".toByteArray()
    private val VERSION = Regex("\\d{1,4}\\.\\d{1,4}\\.\\d{1,4}")
    private val SHA = Regex("[0-9a-f]{64}")

    data class Release(val version: String, val notes: String, val files: Map<String, Pair<String, Long>>, val urls: Map<String, String>)

    fun vtuple(v: String?): List<Int> = if (v != null && VERSION.matches(v)) v.split('.').map { it.toInt() } else listOf(0, 0, 0)

    /** Is version [a] newer than [b]? */
    fun newer(a: String?, b: String?): Boolean {
        val x = vtuple(a); val y = vtuple(b)
        for (i in 0..2) if (x[i] != y[i]) return x[i] > y[i]
        return false
    }

    /** -> the manifest if the release key signed it; throws IllegalArgumentException otherwise. */
    fun verify(manifest: ByteArray, sig: String, pub: String = RELEASE_PUB): Pair<String, Map<String, Any?>> {
        val ok = runCatching { ed25519Verify(B64u.decode(pub), B64u.decode(sig.trim()), DOMAIN + manifest) }.getOrDefault(false)
        if (!ok) throw IllegalArgumentException("the release is not signed by the KKS Explorer release key")
        @Suppress("UNCHECKED_CAST")
        val m = runCatching { Json.parse(String(manifest, Charsets.UTF_8)) as Map<String, Any?> }.getOrNull()
            ?: throw IllegalArgumentException("not a KKS Explorer release manifest")
        val version = m["version"] as? String
        if (m["app"] != "kks-explorer" || version == null || !VERSION.matches(version) || m["files"] !is Map<*, *>)
            throw IllegalArgumentException("not a KKS Explorer release manifest")
        return version to m
    }

    private fun get(url: String, timeoutMs: Int = 30_000): ByteArray {
        var u = url
        repeat(6) {                                        // GitHub's asset links redirect (to another host)
            val c = URI(u).toURL().openConnection() as HttpURLConnection
            c.instanceFollowRedirects = false
            c.connectTimeout = timeoutMs; c.readTimeout = timeoutMs
            c.setRequestProperty("User-Agent", "kks-explorer-updater")
            c.setRequestProperty("Accept", "application/octet-stream, application/json")
            when (val code = c.responseCode) {
                in 200..299 -> return c.inputStream.use { it.readBytes() }
                301, 302, 303, 307, 308 -> u = URI(u).resolve(c.getHeaderField("Location")).toString()
                else -> throw java.io.IOException("HTTP $code from ${URI(u).host}")
            }
        }
        throw java.io.IOException("too many redirects")
    }

    /** The newest release on GitHub, verified. Throws on anything wrong (offline, unsigned, ...). */
    fun fetchLatest(api: String = "https://api.github.com/repos/$REPO/releases/latest", pub: String = RELEASE_PUB): Release {
        val rel = Json.parse(String(get(api), Charsets.UTF_8)) as Map<*, *>
        val urls = (rel["assets"] as? List<*>).orEmpty().mapNotNull { a ->
            val m = a as? Map<*, *> ?: return@mapNotNull null
            val n = m["name"] as? String ?: return@mapNotNull null
            n to (m["browser_download_url"] as? String ?: return@mapNotNull null)
        }.toMap()
        val mu = urls["release.json"]; val su = urls["release.json.sig"]
        if (mu == null || su == null) throw IllegalArgumentException("the latest release has no signed manifest")
        val (version, m) = verify(get(mu), String(get(su), Charsets.UTF_8), pub)
        val files = (m["files"] as Map<*, *>).mapNotNull { (k, v) ->
            val f = v as? Map<*, *> ?: return@mapNotNull null
            val sha = f["sha256"] as? String ?: return@mapNotNull null
            val size = f["size"] as? Long ?: return@mapNotNull null
            if (!SHA.matches(sha)) null else (k as String) to (sha to size)
        }.toMap()
        return Release(version, (m["notes"] as? String ?: "").take(4000), files, urls)
    }

    /** Download [name] of [r] and check it against the signed manifest. */
    fun download(r: Release, name: String): ByteArray {
        val (sha, size) = r.files[name] ?: throw IllegalArgumentException("the release has no $name")
        val data = get(r.urls[name] ?: throw IllegalArgumentException("the release has no $name"), 300_000)
        if (data.size.toLong() != size || sha256(data).hex() != sha)
            throw IllegalArgumentException("the download does not match the signed release (corrupted or tampered): not installed")
        return data
    }
}

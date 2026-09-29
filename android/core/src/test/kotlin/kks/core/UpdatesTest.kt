package kks.core

import com.sun.net.httpserver.HttpServer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File
import java.net.InetSocketAddress

/** M5b self-updates: the manifest signed by the Python release tool (tools/release.py) verifies here, downloads are
 *  checked against it, and both implementations pin the same release key. */
class UpdatesTest {

    /** release.json + its signature made by tools/release.py with a throwaway key -> (manifest, sig, public key) */
    private fun pythonRelease(files: Map<String, ByteArray>, version: String = "9.1.2"): Triple<ByteArray, String, String> {
        val tmp = kotlin.io.path.createTempDirectory("kks-rel").toFile()
        files.forEach { (n, b) -> File(tmp, n).writeBytes(b) }
        val script = """
import sys, os; sys.path.insert(0, sys.argv[1])
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from tools import release as R
k = Ed25519PrivateKey.generate(); d = sys.argv[2]
files = {n: os.path.join(d, n) for n in sorted(os.listdir(d))}
m = R.manifest(sys.argv[3], files, 'notes')
open(os.path.join(d, 'release.json'), 'wb').write(m); open(os.path.join(d, 'sig'), 'w').write(R.sign(m, k))
print(R.public_b64u(k))
"""
        val p = ProcessBuilder(File(repo(), ".venv/bin/python").path, "-c", script, repo().path, tmp.path, version).redirectErrorStream(true).start()
        val pub = p.inputStream.bufferedReader().readText().trim()
        assertEquals(pub, 0, p.waitFor())
        return Triple(File(tmp, "release.json").readBytes(), File(tmp, "sig").readText(), pub).also { tmp.deleteRecursively() }
    }

    @Test fun sameKeyPinnedInBothImplementations() {
        val py = File(repo(), "server/updates.py").readText()
        assertTrue(py.contains("RELEASE_PUB = '${Updates.RELEASE_PUB}'"))
        assertTrue(py.contains("REPO = '${Updates.REPO}'"))
    }

    @Test fun versions() {
        assertTrue(Updates.newer("0.10.0", "0.9.9")); assertFalse(Updates.newer("1.0.0", "1.0.0"))
        assertFalse(Updates.newer("garbage", "0.0.1")); assertTrue(Updates.newer("1.0.0", null))
    }

    @Test fun pythonSignedReleaseVerifiesDownloadsAreChecked() {
        assumeTrue("needs the repo's .venv", File(repo(), ".venv/bin/python").canExecute())
        val apk = "apk bytes".repeat(1000).toByteArray()
        val (manifest, sig, pub) = pythonRelease(mapOf(Updates.APK to apk))
        assertEquals("9.1.2", Updates.verify(manifest, sig, pub).first)
        assertTrue(runCatching { Updates.verify(manifest, sig) }.isFailure)                         // not the pinned key
        assertTrue(runCatching { Updates.verify(String(manifest).replace("9.1.2", "9.9.9").toByteArray(), sig, pub) }.isFailure)

        // a fake GitHub: the API, and asset links that redirect like the real ones
        val served = HashMap<String, ByteArray>(mapOf("release.json" to manifest, "release.json.sig" to sig.toByteArray(), Updates.APK to apk))
        val srv = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        val base = "http://127.0.0.1:${srv.address.port}"
        srv.createContext("/") { ex ->
            val p = ex.requestURI.path
            val (code, body) = when {
                p == "/repos/x/releases/latest" -> 200 to Json.write(mapOf("assets" to served.keys.map { mapOf("name" to it, "browser_download_url" to "$base/dl/$it") })).toByteArray()
                p.startsWith("/dl/") -> { ex.responseHeaders.add("Location", "/blob/" + p.removePrefix("/dl/")); 302 to ByteArray(0) }
                p.startsWith("/blob/") && p.removePrefix("/blob/") in served -> 200 to served[p.removePrefix("/blob/")]!!
                else -> 404 to ByteArray(0)
            }
            ex.sendResponseHeaders(code, if (body.isEmpty()) -1 else body.size.toLong()); ex.responseBody.use { it.write(body) }
        }
        srv.start()
        try {
            val r = Updates.fetchLatest("$base/repos/x/releases/latest", pub)
            assertEquals("9.1.2", r.version)
            assertTrue(Updates.download(r, Updates.APK).contentEquals(apk))
            served[Updates.APK] = "evil".toByteArray()                                                // swapped after signing
            assertTrue(runCatching { Updates.download(r, Updates.APK) }.exceptionOrNull()!!.message!!.contains("does not match"))
            assertTrue(runCatching { Updates.fetchLatest("$base/repos/x/releases/latest") }.isFailure)  // pinned key: refused
        } finally { srv.stop(0) }
    }
}

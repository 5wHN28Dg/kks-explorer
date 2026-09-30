package kks.core

/**
 * Noise_XX_25519_ChaChaPoly_SHA256 (Noise Protocol Framework rev. 34), the pattern used to connect two peers (§15).
 * Twin of peer/noise.py; checked against the published vector (peer/vectors/noise-xx.json).
 */
class NoiseError(msg: String) : Exception(msg)

class CipherState(private val k: ByteArray? = null) {
    var n = 0L
        private set

    private fun nonce(): ByteArray {
        if (n == -1L) throw NoiseError("nonce exhausted")
        return ByteArray(12).also { for (i in 0 until 8) it[4 + i] = (n ushr (8 * i)).toByte() }
    }

    fun encrypt(ad: ByteArray, pt: ByteArray): ByteArray {
        if (k == null) return pt
        return ChaChaPoly.encrypt(k, nonce(), pt, ad).also { n++ }
    }

    fun decrypt(ad: ByteArray, ct: ByteArray): ByteArray {
        if (k == null) return ct
        val pt = try { ChaChaPoly.decrypt(k, nonce(), ct, ad) } catch (e: AeadError) { throw NoiseError("decryption failed") }
        n++
        return pt
    }
}

class Handshake(private val initiator: Boolean, private val s: X25519Key, prologue: ByteArray = ByteArray(0),
                private var e: X25519Key? = null) {
    companion object {
        val NAME = "Noise_XX_25519_ChaChaPoly_SHA256".toByteArray()
        const val DHLEN = 32
        const val MAX_MSG = 65535

        fun hkdf(ck: ByteArray, ikm: ByteArray): Pair<ByteArray, ByteArray> {
            val t = hmacSha256(ck, ikm)
            val o1 = hmacSha256(t, byteArrayOf(1))
            return o1 to hmacSha256(t, o1 + byteArrayOf(2))
        }
    }

    var h: ByteArray = if (NAME.size <= 32) NAME + ByteArray(32 - NAME.size) else sha256(NAME)
        private set
    private var ck = h.copyOf()
    private var c = CipherState()
    var re: ByteArray? = null
        private set
    var rs: ByteArray? = null
        private set
    private var step = 0

    init { mixHash(prologue) }

    private fun mixHash(d: ByteArray) { h = sha256(h + d) }
    private fun mixKey(ikm: ByteArray) { val (a, b) = hkdf(ck, ikm); ck = a; c = CipherState(b) }
    private fun encHash(pt: ByteArray) = c.encrypt(h, pt).also { mixHash(it) }
    private fun decHash(ct: ByteArray) = c.decrypt(h, ct).also { mixHash(ct) }
    private fun myTurn() = (step % 2 == 0) == initiator

    fun write(payload: ByteArray = ByteArray(0)): ByteArray {
        if (!myTurn() || step > 2) throw NoiseError("not our turn")
        var out = ByteArray(0)
        when (step) {
            0 -> { val ep = (e ?: X25519Key.generate()).also { e = it }.publicKey; out += ep; mixHash(ep) }
            1 -> {
                val ep = (e ?: X25519Key.generate()).also { e = it }.publicKey
                out += ep; mixHash(ep)
                mixKey(e!!.agree(re!!))
                out += encHash(s.publicKey)
                mixKey(s.agree(re!!))
            }
            else -> { out += encHash(s.publicKey); mixKey(s.agree(re!!)) }
        }
        out += encHash(payload)
        step++
        if (out.size > MAX_MSG) throw NoiseError("handshake message too long")
        return out
    }

    fun read(msg: ByteArray): ByteArray {
        if (myTurn() || step > 2) throw NoiseError("not their turn")
        try {
            val rest: ByteArray
            when (step) {
                0 -> { re = msg.copyOfRange(0, DHLEN); rest = msg.copyOfRange(DHLEN, msg.size); mixHash(re!!) }
                1 -> {
                    re = msg.copyOfRange(0, DHLEN); mixHash(re!!)
                    mixKey(e!!.agree(re!!))
                    rs = decHash(msg.copyOfRange(DHLEN, DHLEN + DHLEN + 16))
                    mixKey(e!!.agree(rs!!))
                    rest = msg.copyOfRange(DHLEN + DHLEN + 16, msg.size)
                }
                else -> {
                    rs = decHash(msg.copyOfRange(0, DHLEN + 16))
                    mixKey(e!!.agree(rs!!))
                    rest = msg.copyOfRange(DHLEN + 16, msg.size)
                }
            }
            val p = decHash(rest)
            step++
            return p
        } catch (x: IndexOutOfBoundsException) {
            throw NoiseError("short handshake message")
        } catch (x: IllegalArgumentException) {
            throw NoiseError("bad handshake message")
        }
    }

    /** -> (cipher for sending, cipher for receiving) */
    fun split(): Pair<CipherState, CipherState> {
        val (k1, k2) = hkdf(ck, ByteArray(0))
        return if (initiator) CipherState(k1) to CipherState(k2) else CipherState(k2) to CipherState(k1)
    }
}

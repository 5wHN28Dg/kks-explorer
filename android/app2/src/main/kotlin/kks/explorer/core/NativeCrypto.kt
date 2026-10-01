package kks.explorer.core

import java.math.BigInteger
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.SecureRandom
import java.security.Signature
import java.security.interfaces.ECPrivateKey
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import java.security.spec.ECParameterSpec
import java.security.spec.ECPoint
import java.security.spec.ECPrivateKeySpec
import java.security.spec.ECPublicKeySpec
import javax.crypto.Cipher
import javax.crypto.KeyAgreement
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * The core's crypto provider on Android (decisions 0029, 0032): JCA, called from C (jni_shim.c) with one method.
 * Errors return null; the core raises. Keys: a scalar (32 bytes) or an AndroidKeyStore alias ("ks:<alias>").
 */
object NativeCrypto {
    private val rng = SecureRandom()
    private val params: ECParameterSpec by lazy {
        val g = KeyPairGenerator.getInstance("EC")
        g.initialize(ECGenParameterSpec("secp256r1"))
        (g.generateKeyPair().public as ECPublicKey).params
    }
    private val P = BigInteger("ffffffff00000001000000000000000000000000ffffffffffffffffffffffff", 16)
    private val B = BigInteger("5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b", 16)

    private fun u(b: ByteArray, off: Int, n: Int) = BigInteger(1, b.copyOfRange(off, off + n))
    private fun be32(x: BigInteger): ByteArray {
        val r = x.toByteArray()
        return when {
            r.size == 32 -> r
            r.size > 32 -> r.copyOfRange(r.size - 32, r.size)
            else -> ByteArray(32 - r.size) + r
        }
    }

    fun onCurve(pub: ByteArray?): Boolean {
        if (pub == null || pub.size != 65 || pub[0] != 4.toByte()) return false
        val x = u(pub, 1, 32); val y = u(pub, 33, 32)
        if (x >= P || y >= P) return false
        val lhs = y.multiply(y).mod(P)
        val rhs = x.pow(3).subtract(x.multiply(BigInteger.valueOf(3))).add(B).mod(P)
        return lhs == rhs
    }

    private fun publicKey(pub: ByteArray) =
        KeyFactory.getInstance("EC").generatePublic(ECPublicKeySpec(ECPoint(u(pub, 1, 32), u(pub, 33, 32)), params))

    private fun privateKey(scalar: ByteArray?, handle: ByteArray?): PrivateKey {
        val h = handle?.toString(Charsets.UTF_8) ?: ""
        if (h.startsWith("ks:")) {
            val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            return ks.getKey(h.substring(3), null) as PrivateKey
        }
        return KeyFactory.getInstance("EC").generatePrivate(ECPrivateKeySpec(BigInteger(1, scalar!!), params))
    }

    /** DER ECDSA signature ↔ r ‖ s */
    private fun derToRaw(der: ByteArray): ByteArray {
        var i = 2
        if (der[1].toInt() and 0x80 != 0) i += der[1].toInt() and 0x7f
        fun int(): BigInteger {
            require(der[i] == 2.toByte()); val n = der[i + 1].toInt() and 0xff
            val v = BigInteger(1, der.copyOfRange(i + 2, i + 2 + n)); i += 2 + n; return v
        }
        val r = int(); val s = int()
        return be32(r) + be32(s)
    }
    private fun rawToDer(raw: ByteArray): ByteArray {
        fun enc(x: ByteArray): ByteArray {
            var v = x.dropWhile { it == 0.toByte() }.toByteArray()
            if (v.isEmpty() || v[0].toInt() and 0x80 != 0) v = byteArrayOf(0) + v
            return byteArrayOf(2, v.size.toByte()) + v
        }
        val body = enc(raw.copyOfRange(0, 32)) + enc(raw.copyOfRange(32, 64))
        return byteArrayOf(0x30, body.size.toByte()) + body
    }

    private fun pbkdf2(password: ByteArray, salt: ByteArray, iterations: Int, length: Int): ByteArray {
        // byte-exact (no char[] conversion, unlike PBEKeySpec)
        // HMAC pads its key with zeros to the block size, so an empty key equals 64 zero bytes (JCA refuses empty keys)
        val mac = Mac.getInstance("HmacSHA256").apply { init(SecretKeySpec(if (password.isEmpty()) ByteArray(64) else password, "HmacSHA256")) }
        val out = ByteArray(length)
        var block = 1; var off = 0
        while (off < length) {
            mac.update(salt); mac.update(byteArrayOf((block ushr 24).toByte(), (block ushr 16).toByte(), (block ushr 8).toByte(), block.toByte()))
            var u = mac.doFinal(); val t = u.copyOf()
            for (k in 1 until iterations) { u = mac.doFinal(u); for (j in t.indices) t[j] = (t[j].toInt() xor u[j].toInt()).toByte() }
            val n = minOf(32, length - off); System.arraycopy(t, 0, out, off, n); off += n; block++
        }
        return out
    }

    @JvmStatic
    fun call(op: Int, a: ByteArray?, b: ByteArray?, c: ByteArray?, d: ByteArray?, n1: Int, n2: Int): ByteArray? = try {
        val e = ByteArray(0)
        when (op) {
            1 -> MessageDigest.getInstance("SHA-256").digest(a ?: e)
            2 -> Mac.getInstance("HmacSHA256").run {
                init(SecretKeySpec(if (a == null || a.isEmpty()) ByteArray(64) else a, "HmacSHA256")); doFinal(b ?: e)
            }
            3 -> pbkdf2(a ?: e, b ?: e, n1, n2)
            4 -> byteArrayOf(if (onCurve(a)) 1 else 0)
            5 -> KeyPairGenerator.getInstance("EC").run {
                initialize(ECGenParameterSpec("secp256r1"), rng)
                val kp = generateKeyPair()
                val w = (kp.public as ECPublicKey).w
                be32((kp.private as ECPrivateKey).s) + byteArrayOf(4) + be32(w.affineX) + be32(w.affineY)
            }
            6 -> Signature.getInstance("SHA256withECDSA").run {
                initSign(privateKey(a, b)); update(c ?: e); derToRaw(sign())
            }
            7 -> byteArrayOf(if (onCurve(a) && Signature.getInstance("SHA256withECDSA").run {
                initVerify(publicKey(a!!)); update(b ?: e); verify(rawToDer(c!!))
            }) 1 else 0)
            8 -> KeyAgreement.getInstance("ECDH").run {
                init(privateKey(a, b)); doPhase(publicKey(c!!), true); generateSecret()
            }
            9 -> Cipher.getInstance("AES/GCM/NoPadding").run {
                init(Cipher.ENCRYPT_MODE, SecretKeySpec(a, "AES"), GCMParameterSpec(128, b)); if (d != null) updateAAD(d); doFinal(c ?: e)
            }
            10 -> Cipher.getInstance("AES/GCM/NoPadding").run {
                init(Cipher.DECRYPT_MODE, SecretKeySpec(a, "AES"), GCMParameterSpec(128, b)); if (d != null) updateAAD(d); doFinal(c ?: e)
            }
            11 -> ByteArray(n1).also { rng.nextBytes(it) }
            else -> null
        }
    } catch (t: Throwable) {
        null
    }
}

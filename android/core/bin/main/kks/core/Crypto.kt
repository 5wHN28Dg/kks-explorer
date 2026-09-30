package kks.core

import org.bouncycastle.crypto.agreement.X25519Agreement
import org.bouncycastle.crypto.modes.ChaCha20Poly1305
import org.bouncycastle.crypto.params.AEADParameters
import org.bouncycastle.crypto.params.Ed25519PrivateKeyParameters
import org.bouncycastle.crypto.params.Ed25519PublicKeyParameters
import org.bouncycastle.crypto.params.KeyParameter
import org.bouncycastle.crypto.params.X25519PrivateKeyParameters
import org.bouncycastle.crypto.params.X25519PublicKeyParameters
import org.bouncycastle.crypto.signers.Ed25519Signer
import java.security.MessageDigest
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/** base64url without padding (§2). */
object B64u {
    fun encode(b: ByteArray): String = java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(b)
    fun decode(s: String): ByteArray = java.util.Base64.getUrlDecoder().decode(s + "=".repeat((4 - s.length % 4) % 4))
}

fun ByteArray.hex(): String = joinToString("") { "%02x".format(it) }
fun String.unhex(): ByteArray = chunked(2).map { it.toInt(16).toByte() }.toByteArray()

fun sha256(b: ByteArray): ByteArray = MessageDigest.getInstance("SHA-256").digest(b)

fun hmacSha256(key: ByteArray, data: ByteArray): ByteArray =
    Mac.getInstance("HmacSHA256").apply { init(SecretKeySpec(key, "HmacSHA256")) }.doFinal(data)

/** An Ed25519 device (or root) key from its 32-byte seed (RFC 8032; deterministic signatures). */
class SigningKey(val seed: ByteArray) {
    private val priv = Ed25519PrivateKeyParameters(seed, 0)
    val publicKey: ByteArray = priv.generatePublicKey().encoded
    val peerId: String = B64u.encode(publicKey)

    fun sign(msg: ByteArray): ByteArray = Ed25519Signer().run { init(true, priv); update(msg, 0, msg.size); generateSignature() }

    companion object {
        fun generate(): SigningKey = SigningKey(ByteArray(32).also { java.security.SecureRandom().nextBytes(it) })
    }
}

fun ed25519Verify(publicKey: ByteArray, sig: ByteArray, msg: ByteArray): Boolean = try {
    if (publicKey.size != 32 || sig.size != 64) false
    else Ed25519Signer().run { init(false, Ed25519PublicKeyParameters(publicKey, 0)); update(msg, 0, msg.size); verifySignature(sig) }
} catch (e: Exception) {
    false
}

/** X25519 (Noise, §15). The private key is clamped inside, as in every X25519 implementation. */
class X25519Key(val privateBytes: ByteArray) {
    private val priv = X25519PrivateKeyParameters(privateBytes, 0)
    val publicKey: ByteArray = priv.generatePublicKey().encoded

    fun agree(peerPublic: ByteArray): ByteArray = ByteArray(32).also {
        X25519Agreement().run { init(priv); calculateAgreement(X25519PublicKeyParameters(peerPublic, 0), it, 0) }
    }

    companion object {
        fun generate(): X25519Key = X25519Key(ByteArray(32).also { java.security.SecureRandom().nextBytes(it) })
    }
}

class AeadError : Exception("decryption failed")

object ChaChaPoly {
    fun encrypt(key: ByteArray, nonce: ByteArray, pt: ByteArray, aad: ByteArray): ByteArray = run(true, key, nonce, pt, aad)

    fun decrypt(key: ByteArray, nonce: ByteArray, ct: ByteArray, aad: ByteArray): ByteArray = try {
        run(false, key, nonce, ct, aad)
    } catch (e: Exception) {
        throw AeadError()
    }

    private fun run(enc: Boolean, key: ByteArray, nonce: ByteArray, input: ByteArray, aad: ByteArray): ByteArray {
        val c = ChaCha20Poly1305()
        c.init(enc, AEADParameters(KeyParameter(key), 128, nonce, aad))
        val out = ByteArray(c.getOutputSize(input.size))
        val n = c.processBytes(input, 0, input.size, out, 0)
        val m = c.doFinal(out, n)
        return out.copyOf(n + m)
    }
}

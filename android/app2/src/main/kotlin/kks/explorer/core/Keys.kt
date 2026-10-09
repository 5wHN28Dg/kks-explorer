package kks.explorer.core

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.File
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.SecureRandom
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Keys in the Android Keystore (decisions 0020, 0032): the device's signing key (non-exportable P-256, also the TLS
 * client key with its generated self-signed certificate) and the key that wraps the store's 32-byte storage key.
 */
object Keys {
    const val DEVICE = "kks-device"
    private const val WRAP = "kks-storage-wrap"
    private const val QUEUE = "kks-local-seal"
    private fun ks() = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    /** the device key's 65-byte uncompressed public point (made on first use) */
    fun devicePublic(): ByteArray {
        val ks = ks()
        if (!ks.containsAlias(DEVICE)) {
            KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore").apply {
                initialize(KeyGenParameterSpec.Builder(DEVICE, KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY)
                    .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                    .setDigests(KeyProperties.DIGEST_SHA256, KeyProperties.DIGEST_NONE)   // NONE: TLS signs a ready digest
                    .build())
            }.generateKeyPair()
        }
        val w = (ks.getCertificate(DEVICE).publicKey as ECPublicKey).w
        fun be32(x: java.math.BigInteger) = x.toByteArray().let { if (it.size > 32) it.copyOfRange(it.size - 32, it.size) else ByteArray(32 - it.size) + it }
        return byteArrayOf(4) + be32(w.affineX) + be32(w.affineY)
    }

    /** a non-exportable AES-256-GCM key in the Keystore, made on first use */
    private fun aesKey(alias: String): SecretKey {
        val ks = ks()
        if (!ks.containsAlias(alias)) {
            KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
                init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256).build())
            }.generateKey()
        }
        return ks.getKey(alias, null) as SecretKey
    }

    private fun wrapKey(): SecretKey = aesKey(WRAP)

    private val MAGIC = byteArrayOf('K'.code.toByte(), 'S'.code.toByte(), 'L'.code.toByte(), '1'.code.toByte())

    /**
     * Plant data kept outside the store for a while (the photo queue, decision 0049), sealed at rest: a fresh random
     * AES-256 key per file encrypts the bytes (AES-GCM, `aad` bound in: a file can't be passed off as another), and
     * that key is wrapped by a non-exportable Keystore key. "KSL1" ‖ n ‖ wrapped key (IV ‖ sealed, n bytes) ‖ IV ‖ sealed.
     * The per-file key keeps a large photo off the Keystore's slow path (only 32 bytes go through it).
     */
    fun seal(plain: ByteArray, aad: ByteArray): ByteArray {
        val dek = ByteArray(32).also { SecureRandom().nextBytes(it) }
        try {
            val w = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, aesKey(QUEUE)) }
            val wrapped = w.iv + w.doFinal(dek)
            val c = Cipher.getInstance("AES/GCM/NoPadding")
            c.init(Cipher.ENCRYPT_MODE, SecretKeySpec(dek, "AES"))
            c.updateAAD(aad)
            val body = c.doFinal(plain)
            return MAGIC + byteArrayOf(wrapped.size.toByte()) + wrapped + c.iv + body
        } finally { dek.fill(0) }
    }

    /** the bytes [seal] sealed with the same `aad`; throws if they were changed, swapped or the key is gone */
    fun open(sealed: ByteArray, aad: ByteArray): ByteArray {
        require(sealed.size > 5 && sealed.copyOfRange(0, 4).contentEquals(MAGIC)) { "not a sealed file" }
        val n = sealed[4].toInt() and 0xff
        val wrapped = sealed.copyOfRange(5, 5 + n)
        val w = Cipher.getInstance("AES/GCM/NoPadding")
        w.init(Cipher.DECRYPT_MODE, aesKey(QUEUE), GCMParameterSpec(128, wrapped.copyOfRange(0, 12)))
        val dek = w.doFinal(wrapped.copyOfRange(12, wrapped.size))
        try {
            val c = Cipher.getInstance("AES/GCM/NoPadding")
            c.init(Cipher.DECRYPT_MODE, SecretKeySpec(dek, "AES"), GCMParameterSpec(128, sealed.copyOfRange(5 + n, 5 + n + 12)))
            c.updateAAD(aad)
            return c.doFinal(sealed, 5 + n + 12, sealed.size - (5 + n + 12))
        } finally { dek.fill(0) }
    }

    /** the store's storage key: random on first use, kept wrapped (IV ‖ sealed) next to the database */
    fun storageKey(ctx: Context): ByteArray {
        val f = File(ctx.filesDir, "storage.key.wrapped")
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        if (f.isFile) {
            val all = f.readBytes()
            c.init(Cipher.DECRYPT_MODE, wrapKey(), GCMParameterSpec(128, all.copyOfRange(0, 12)))
            return c.doFinal(all.copyOfRange(12, all.size))
        }
        val key = ByteArray(32).also { SecureRandom().nextBytes(it) }
        c.init(Cipher.ENCRYPT_MODE, wrapKey())
        f.writeBytes(c.iv + c.doFinal(key))
        return key
    }

    /** forget everything (a removed device): the next start makes new keys */
    fun wipe(ctx: Context) {
        val ks = ks()
        for (a in listOf(DEVICE, WRAP, QUEUE)) if (ks.containsAlias(a)) ks.deleteEntry(a)
        File(ctx.filesDir, "storage.key.wrapped").delete()
    }
}

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

/**
 * Keys in the Android Keystore (decisions 0020, 0032): the device's signing key (non-exportable P-256, also the TLS
 * client key with its generated self-signed certificate) and the key that wraps the store's 32-byte storage key.
 */
object Keys {
    const val DEVICE = "kks-device"
    private const val WRAP = "kks-storage-wrap"
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

    private fun wrapKey(): SecretKey {
        val ks = ks()
        if (!ks.containsAlias(WRAP)) {
            KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
                init(KeyGenParameterSpec.Builder(WRAP, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256).build())
            }.generateKey()
        }
        return ks.getKey(WRAP, null) as SecretKey
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
        for (a in listOf(DEVICE, WRAP)) if (ks.containsAlias(a)) ks.deleteEntry(a)
        File(ctx.filesDir, "storage.key.wrapped").delete()
    }
}

package kks.explorer

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import kks.core.Json
import kks.core.NodeStore
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * The phone's [NodeStore]: SQLite for the log, submissions and notes; photos as files; the device's Ed25519 seed
 * encrypted with an AES key that lives in the Android Keystore (it never leaves the Keystore; on phones with secure
 * hardware it is kept there). Copying the app's files off the phone therefore doesn't copy a usable device key.
 */
class SqliteStore(context: Context) : NodeStore {
    private val db: SQLiteDatabase = object : SQLiteOpenHelper(context, "kks.db", null, 1) {
        override fun onCreate(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE meta(k TEXT PRIMARY KEY, v TEXT)")
            db.execSQL("CREATE TABLE entries(id TEXT PRIMARY KEY, data TEXT NOT NULL, evidence INTEGER NOT NULL)")
            db.execSQL("CREATE TABLE blobs(sha TEXT PRIMARY KEY, name TEXT NOT NULL)")
            db.execSQL("CREATE TABLE subs(id INTEGER PRIMARY KEY AUTOINCREMENT, client_id TEXT UNIQUE, entry TEXT, data TEXT NOT NULL)")
            db.execSQL("CREATE TABLE notes(entry TEXT PRIMARY KEY, note TEXT)")
        }
        override fun onUpgrade(db: SQLiteDatabase, old: Int, new: Int) {}
    }.writableDatabase
    private val photos = File(context.filesDir, "photos").also { it.mkdirs() }

    // ---------- device key ----------
    private val alias = "kks-device-seed"

    private fun aesKey(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(alias, null) as SecretKey?)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256).build())
            generateKey()
        }
    }

    override fun deviceSeed(): ByteArray? {
        val v = meta("device_seed") ?: return null
        val raw = android.util.Base64.decode(v, android.util.Base64.NO_WRAP)
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.DECRYPT_MODE, aesKey(), GCMParameterSpec(128, raw.copyOfRange(0, 12)))
        return c.doFinal(raw.copyOfRange(12, raw.size))
    }

    override fun setDeviceSeed(seed: ByteArray) {
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, aesKey())
        setMeta("device_seed", android.util.Base64.encodeToString(c.iv + c.doFinal(seed), android.util.Base64.NO_WRAP))
    }

    // ---------- tables ----------
    override fun meta(k: String): String? = db.rawQuery("SELECT v FROM meta WHERE k=?", arrayOf(k)).use { if (it.moveToFirst()) it.getString(0) else null }

    override fun setMeta(k: String, v: String?) {
        if (v == null) db.delete("meta", "k=?", arrayOf(k))
        else db.insertWithOnConflict("meta", null, ContentValues().apply { put("k", k); put("v", v) }, SQLiteDatabase.CONFLICT_REPLACE)
    }

    @Suppress("UNCHECKED_CAST")
    private fun load(evidence: Int): Map<String, Map<String, Any?>> {
        val out = LinkedHashMap<String, Map<String, Any?>>()
        db.rawQuery("SELECT id, data FROM entries WHERE evidence=? ORDER BY rowid", arrayOf(evidence.toString())).use {
            while (it.moveToNext()) out[it.getString(0)] = Json.parse(it.getString(1)) as Map<String, Any?>
        }
        return out
    }

    override fun entries() = load(0)
    override fun evidence() = load(1)

    override fun putEntry(eid: String, e: Map<String, Any?>, isEvidence: Boolean) {
        db.insertWithOnConflict("entries", null, ContentValues().apply {
            put("id", eid); put("data", Json.write(e)); put("evidence", if (isEvidence) 1 else 0)
        }, SQLiteDatabase.CONFLICT_IGNORE)
    }

    override fun blobName(sha: String): String? = db.rawQuery("SELECT name FROM blobs WHERE sha=?", arrayOf(sha)).use { if (it.moveToFirst()) it.getString(0) else null }

    override fun blob(sha: String): ByteArray? = blobName(sha)?.let { File(photos, it).takeIf { f -> f.exists() }?.readBytes() }

    override fun putBlob(sha: String, name: String, data: ByteArray) {
        val f = File(photos, name)
        val tmp = File(photos, "$name.part")
        tmp.writeBytes(data)
        tmp.renameTo(f)
        db.insertWithOnConflict("blobs", null, ContentValues().apply { put("sha", sha); put("name", name) }, SQLiteDatabase.CONFLICT_REPLACE)
    }

    fun photoFile(name: String): File? = File(photos, name).takeIf { it.exists() && it.parentFile == photos }

    @Suppress("UNCHECKED_CAST")
    private fun row(id: Long, data: String) = (Json.parse(data) as Map<String, Any?>) + ("id" to id)

    override fun subs(): List<Map<String, Any?>> = db.rawQuery("SELECT id, data FROM subs ORDER BY id DESC", null).use {
        val out = ArrayList<Map<String, Any?>>()
        while (it.moveToNext()) out.add(row(it.getLong(0), it.getString(1)))
        out
    }

    override fun sub(id: Long): Map<String, Any?>? = db.rawQuery("SELECT id, data FROM subs WHERE id=?", arrayOf(id.toString())).use {
        if (it.moveToFirst()) row(it.getLong(0), it.getString(1)) else null
    }

    override fun subByClientId(clientId: String): Map<String, Any?>? = db.rawQuery("SELECT id, data FROM subs WHERE client_id=?", arrayOf(clientId)).use {
        if (it.moveToFirst()) row(it.getLong(0), it.getString(1)) else null
    }

    override fun putSub(row: Map<String, Any?>): Long {
        val v = ContentValues().apply {
            put("client_id", row["client_id"] as String?); put("entry", row["entry"] as String?); put("data", Json.write(row - "id"))
        }
        val id = row["id"] as Long?
        return if (id == null) db.insertOrThrow("subs", null, v)
        else { v.put("id", id); db.insertWithOnConflict("subs", null, v, SQLiteDatabase.CONFLICT_REPLACE); id }
    }

    override fun note(eid: String): String? = db.rawQuery("SELECT note FROM notes WHERE entry=?", arrayOf(eid)).use { if (it.moveToFirst()) it.getString(0) else null }

    override fun notes(): Map<String, String> = db.rawQuery("SELECT entry, note FROM notes", null).use {
        val out = HashMap<String, String>()
        while (it.moveToNext()) out[it.getString(0)] = it.getString(1)
        out
    }

    override fun putNote(eid: String, note: String) {
        db.insertWithOnConflict("notes", null, ContentValues().apply { put("entry", eid); put("note", note) }, SQLiteDatabase.CONFLICT_REPLACE)
    }

    override fun <T> tx(block: () -> T): T {
        db.beginTransaction()
        try {
            val r = block()
            db.setTransactionSuccessful()
            return r
        } finally {
            db.endTransaction()
        }
    }
}

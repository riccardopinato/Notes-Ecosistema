package it.notes.ecosystem.sync

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import org.json.JSONObject
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import java.util.Base64

internal fun AtomicFile.replace(bytes: ByteArray) {
    val stream = startWrite()
    try { stream.write(bytes); finishWrite(stream) }
    catch (e: Exception) { failWrite(stream); throw e }
}

/** Credentials are encrypted with an Android Keystore key, excluded from backup. */
class SyncStorage(context: Context) {
    private val dir = File(context.noBackupFilesDir, "github-sync").apply { mkdirs() }
    private val configFile = AtomicFile(File(dir, "connection"))
    private val alias = "notes-github-v1"
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    fun config(): GitHubConfig? {
        val raw = try { configFile.openRead().use { it.readBytesLimited(16384) } } catch (_: java.io.FileNotFoundException) { return null }
        val objectValue = JSONObject(strictUtf8(raw))
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, Base64.getDecoder().decode(objectValue.getString("iv"))))
        val o = JSONObject(strictUtf8(cipher.doFinal(Base64.getDecoder().decode(objectValue.getString("data")))))
        return GitHubConfig(o.getString("owner"), o.getString("repo"), o.getString("branch"), o.getString("folder"), o.getString("token"), o.optBoolean("allowPublic", false))
    }
    fun connect(c: GitHubConfig) {
        val text = JSONObject().put("owner", c.owner).put("repo", c.repo).put("branch", c.branch)
            .put("folder", c.folder).put("token", c.token).put("allowPublic", c.allowPublic).toString()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.ENCRYPT_MODE, key())
        val encrypted = cipher.doFinal(text.toByteArray(Charsets.UTF_8))
        configFile.replace(JSONObject().put("iv", Base64.getEncoder().encodeToString(cipher.iv))
            .put("data", Base64.getEncoder().encodeToString(encrypted)).toString().toByteArray(Charsets.UTF_8))
    }
    fun disconnect() { configFile.delete() }
    fun retryAt(key: String): Long = try { File(dir, SyncCodec.hash(key) + ".retry").readText().toLong() } catch (_: Exception) { 0L }
    fun setRetryAt(key: String, time: Long) { AtomicFile(File(dir, SyncCodec.hash(key) + ".retry")).replace(time.toString().toByteArray()) }
    private fun stateFile(key: String) = AtomicFile(File(dir, SyncCodec.hash(key) + ".json"))
    fun load(key: String): MutableMap<String, SyncRecord> {
        val raw = try { stateFile(key).openRead().use { it.readBytesLimited(64 * 1024 * 1024) } }
            catch (_: java.io.FileNotFoundException) { return mutableMapOf() }
        val o = JSONObject(strictUtf8(raw))
        require(o.getInt("version") == 1)
        val rows = o.getJSONArray("records")
        return (0 until rows.length()).associate { i ->
            val row = rows.getJSONObject(i)
            fun doc(name: String) = if (row.isNull(name)) null else SyncCodec.decode(row.getString(name))
            row.getString("id") to SyncRecord(doc("base"), if (row.isNull("sha")) null else row.getString("sha"),
                row.getBoolean("conflict"), doc("local"), doc("remote"))
        }.toMutableMap()
    }
    fun save(key: String, records: Map<String, SyncRecord>) {
        val rows = org.json.JSONArray()
        records.toSortedMap().forEach { (id, r) ->
            fun encoded(d: SyncDocument?): Any = d?.let(SyncCodec::encode) ?: JSONObject.NULL
            rows.put(JSONObject().put("id", id).put("base", encoded(r.base)).put("sha", r.sha ?: JSONObject.NULL)
                .put("conflict", r.conflict).put("local", encoded(r.local)).put("remote", encoded(r.remote)))
        }
        stateFile(key).replace(JSONObject().put("version", 1).put("records", rows).toString().toByteArray(Charsets.UTF_8))
    }
}

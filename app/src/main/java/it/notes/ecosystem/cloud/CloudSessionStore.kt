package it.notes.ecosystem.cloud

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class CloudSessionStore(context: Context) {
    private val prefs = context.getSharedPreferences("notes_cloud_session_v1", Context.MODE_PRIVATE)
    private val _session = MutableStateFlow(loadPublicSession())
    val session = _session.asStateFlow()
    private val _syncEnabled = MutableStateFlow(prefs.getBoolean(KEY_SYNC, false))
    val personalSyncEnabled = _syncEnabled.asStateFlow()

    fun refreshToken(): String? = prefs.getString(KEY_REFRESH, null)?.let { runCatching { decrypt(it) }.getOrNull() }

    fun save(session: CloudSession, refreshToken: String) {
        prefs.edit()
            .putString(KEY_ACCOUNT, session.accountId)
            .putString(KEY_EMAIL, session.email)
            .putString(KEY_NAME, session.displayName)
            .putString(KEY_REFRESH, encrypt(refreshToken))
            .apply()
        _session.value = session
    }

    fun updateAccess(session: CloudSession, refreshToken: String) = save(session, refreshToken)

    fun setPersonalSyncEnabled(enabled: Boolean) {
        prefs.edit().putBoolean(KEY_SYNC, enabled).apply()
        _syncEnabled.value = enabled
    }

    fun writeContext(): CloudWriteContext? {
        if (!_syncEnabled.value) return null
        val id = prefs.getString(KEY_ACCOUNT, null)?.takeIf { it.isNotBlank() } ?: return null
        return CloudWriteContext(id)
    }

    fun clearSession() {
        prefs.edit().remove(KEY_ACCOUNT).remove(KEY_EMAIL).remove(KEY_NAME).remove(KEY_REFRESH).putBoolean(KEY_SYNC, false).apply()
        _syncEnabled.value = false
        _session.value = null
    }

    private fun loadPublicSession(): CloudSession? {
        val id = prefs.getString(KEY_ACCOUNT, null)?.takeIf { it.isNotBlank() } ?: return null
        return CloudSession(
            accountId = id,
            email = prefs.getString(KEY_EMAIL, "").orEmpty(),
            displayName = prefs.getString(KEY_NAME, "").orEmpty(),
            accessToken = "",
            expiresAtEpochSeconds = 0L,
        )
    }

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(
                KeyGenParameterSpec.Builder(
                    KEY_ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                ).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256)
                    .build()
            )
        }.generateKey()
    }

    private fun encrypt(value: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val bytes = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(cipher.iv + bytes, Base64.NO_WRAP)
    }

    private fun decrypt(value: String): String {
        val packed = Base64.decode(value, Base64.NO_WRAP)
        require(packed.size > 12)
        val iv = packed.copyOfRange(0, 12)
        val encrypted = packed.copyOfRange(12, packed.size)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, iv))
        return cipher.doFinal(encrypted).toString(Charsets.UTF_8)
    }

    companion object {
        private const val KEY_ALIAS = "notes_cloud_refresh_v1"
        private const val KEY_ACCOUNT = "account_id"
        private const val KEY_EMAIL = "email"
        private const val KEY_NAME = "display_name"
        private const val KEY_REFRESH = "refresh_token"
        private const val KEY_SYNC = "personal_sync"
    }
}

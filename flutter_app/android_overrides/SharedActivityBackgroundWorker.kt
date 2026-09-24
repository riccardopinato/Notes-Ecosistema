package it.notes.ecosystem.notes_ecosistema

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.work.Constraints
import androidx.work.Worker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.net.HttpURLConnection
import java.net.URLEncoder
import java.net.URL
import java.security.KeyStore
import java.util.concurrent.TimeUnit
import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import org.json.JSONArray
import org.json.JSONObject

object SharedBackgroundContract {
    const val CHANNEL = "notes.ecosystem/shared_background"
    const val ACTION_OPEN_SHARED_SPACE =
        "it.notes.ecosystem.OPEN_SHARED_SPACE"
    const val EXTRA_SPACE_ID = "spaceId"
    const val NOTIFICATION_CHANNEL = "shared_space_updates"

    private const val WORK_NAME = "notes-shared-activity-background"
    private const val NATIVE_PREFS = "shared_background_sync"
    private const val ENABLED_AT = "enabled_at"

    fun setEnabled(context: Context, enabled: Boolean) {
        val prefs = context.getSharedPreferences(
            NATIVE_PREFS,
            Context.MODE_PRIVATE,
        )
        if (enabled && prefs.getLong(ENABLED_AT, 0L) == 0L) {
            prefs.edit()
                .putLong(ENABLED_AT, System.currentTimeMillis())
                .apply()
        }
        if (!enabled) {
            prefs.edit().remove(ENABLED_AT).apply()
            WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
            return
        }
        schedule(context)
    }

    fun syncWithFlutterPreference(context: Context) {
        val enabled = flutterPreferences(context)
            .getBoolean("flutter.shared_live_sync_enabled_v1", false)
        if (enabled) {
            setEnabled(context, true)
        } else {
            WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
        }
    }

    fun status(context: Context): Map<String, Any?> {
        val prefs = context.getSharedPreferences(
            NATIVE_PREFS,
            Context.MODE_PRIVATE,
        )
        return mapOf(
            "enabledAt" to prefs.getLong(ENABLED_AT, 0L),
            "lastCheckAt" to prefs.getLong("last_check_at", 0L),
            "lastSuccessAt" to prefs.getLong("last_success_at", 0L),
            "lastError" to prefs.getString("last_error", null),
            "intervalMinutes" to 15,
        )
    }

    private fun schedule(context: Context) {
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()
        val request = PeriodicWorkRequestBuilder<SharedActivityBackgroundWorker>(
            15,
            TimeUnit.MINUTES,
        )
            .setConstraints(constraints)
            .build()
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            WORK_NAME,
            ExistingPeriodicWorkPolicy.UPDATE,
            request,
        )
    }

    internal fun nativePreferences(context: Context) =
        context.getSharedPreferences(NATIVE_PREFS, Context.MODE_PRIVATE)

    internal fun flutterPreferences(context: Context) =
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
}

class SharedActivityBackgroundWorker(
    context: Context,
    params: WorkerParameters,
) : Worker(context, params) {
    companion object {
        private const val GITHUB_KEY_ALIAS = "notes-github-v1"
        private const val MAX_STATE_BYTES = 1024 * 1024
    }

    override fun doWork(): Result {
        val flutter = SharedBackgroundContract.flutterPreferences(
            applicationContext,
        )
        if (!flutter.getBoolean("flutter.shared_live_sync_enabled_v1", false)) {
            return Result.success()
        }

        val native = SharedBackgroundContract.nativePreferences(
            applicationContext,
        )
        native.edit()
            .putLong("last_check_at", System.currentTimeMillis())
            .apply()

        return try {
            val owner = flutter.getString("flutter.github_owner", null)
                ?.takeIf { it.matches(Regex("^[A-Za-z0-9-]{1,100}$")) }
                ?: return Result.success()
            val repo = flutter.getString("flutter.github_repo", null)
                ?.takeIf { it.matches(Regex("^[A-Za-z0-9_.-]{1,100}$")) }
                ?: return Result.success()
            val branch = flutter.getString("flutter.github_branch", null)
                ?.takeIf { it.isNotBlank() && it.length <= 200 }
                ?: return Result.success()
            val folder = flutter.getString("flutter.github_folder", null)
                ?.takeIf { it.isNotBlank() && it.length <= 160 }
                ?: return Result.success()
            val sharedRaw = flutter.getString("flutter.shared_spaces_v1", null)
                ?: return Result.success()
            val token = readGitHubToken() ?: return Result.success()

            val localSnapshot = JSONObject(sharedRaw)
            val localIdentity = localSnapshot.optJSONObject("identity")
                ?: return Result.success()
            val identityId = localIdentity.optString("id")
                .takeIf { it.isNotBlank() && it.length <= 200 }
                ?: return Result.success()
            val githubUserId = localIdentity.optString("githubUserId")
                .takeIf { it.matches(Regex("^[1-9][0-9]{0,19}$")) }
                ?: return Result.success()

            val authenticated = requestJson(
                token = token,
                url = "https://api.github.com/user",
            ) as? JSONObject ?: return Result.retry()
            if (authenticated.optString("id") != githubUserId) {
                native.edit()
                    .putString(
                        "last_error",
                        "Account GitHub diverso dal profilo Shared Spaces.",
                    )
                    .apply()
                return Result.failure()
            }

            val repository = requestJson(
                token = token,
                url = "https://api.github.com/repos/$owner/$repo",
            ) as? JSONObject ?: return Result.retry()
            val permissions = repository.optJSONObject("permissions")
            if (!repository.optBoolean("private", false) ||
                permissions?.optBoolean("push", false) != true
            ) {
                throw PermanentBackgroundFailure(
                    "Shared Spaces richiede un repository GitHub privato e scrivibile.",
                )
            }

            val ref = URLEncoder.encode(branch, Charsets.UTF_8.name())
            val base = "https://api.github.com/repos/$owner/$repo/contents"
            val sharedPath = folder
                .split("/")
                .joinToString("/") { Uri.encode(it) } + "/shared"

            val index = requestJson(
                token = token,
                url = "$base/$sharedPath?ref=$ref",
                allowNotFound = true,
            )
            if (index == null) {
                markSuccess(native)
                return Result.success()
            }
            if (index !is JSONArray || index.length() > 200) {
                error("Indice Shared Spaces remoto non valido.")
            }

            val enabledAt = native.getLong(
                "enabled_at",
                System.currentTimeMillis(),
            )
            for (i in 0 until index.length()) {
                val item = index.optJSONObject(i) ?: continue
                if (item.optString("type") != "dir") continue
                val directory = item.optString("name")
                if (!directory.matches(Regex("^[a-f0-9]{32}$"))) continue

                val stateEnvelope = requestJson(
                    token = token,
                    url = "$base/$sharedPath/$directory/space.json?ref=$ref",
                    allowNotFound = true,
                ) as? JSONObject ?: continue
                if (stateEnvelope.optString("encoding") != "base64") continue

                val encoded = stateEnvelope.optString("content")
                    .replace(Regex("\\s"), "")
                val bytes = Base64.decode(encoded, Base64.DEFAULT)
                if (bytes.isEmpty() || bytes.size > MAX_STATE_BYTES) continue

                val state = JSONObject(bytes.toString(Charsets.UTF_8))
                if (state.optString("format") != "notes-ecosystem-shared-live") {
                    continue
                }
                val version = state.optInt("version", -1)
                if (version != 2) continue

                val space = state.optJSONObject("space") ?: continue
                val spaceId = space.optString("id")
                    .takeIf { it.isNotBlank() && it.length <= 200 }
                    ?: continue
                if (!hasAccess(space, identityId)) continue

                val activity = state.optJSONArray("activity") ?: continue
                if (activity.length() > 200) continue

                val seenKey = "seen_$spaceId"
                val seenAt = maxOf(
                    native.getLong(seenKey, enabledAt),
                    enabledAt,
                )
                val events = newRemoteEvents(
                    activity = activity,
                    identityId = identityId,
                    after = seenAt,
                    expectedSpaceId = spaceId,
                )
                if (events.isEmpty()) continue

                val latestAt = events.maxOf { it.at }
                if (notificationsAllowed()) {
                    notifySpace(
                        spaceId = spaceId,
                        spaceName = space.optString("name")
                            .take(100)
                            .ifBlank { "Shared Space" },
                        events = events,
                    )
                }
                native.edit().putLong(seenKey, latestAt).apply()
            }

            markSuccess(native)
            Result.success()
        } catch (error: PermanentBackgroundFailure) {
            native.edit()
                .putString(
                    "last_error",
                    error.message?.take(500) ?: "Configurazione background non valida.",
                )
                .apply()
            Result.success()
        } catch (error: Exception) {
            native.edit()
                .putString(
                    "last_error",
                    error.message?.take(500) ?: "Errore background sync.",
                )
                .apply()
            Result.retry()
        }
    }

    private data class RemoteEvent(
        val actor: String,
        val kind: String,
        val at: Long,
    )

    private fun newRemoteEvents(
        activity: JSONArray,
        identityId: String,
        after: Long,
        expectedSpaceId: String,
    ): List<RemoteEvent> {
        val result = mutableListOf<RemoteEvent>()
        for (i in 0 until activity.length()) {
            val event = activity.optJSONObject(i) ?: continue
            if (event.optString("spaceId") != expectedSpaceId) continue
            val actorId = event.optString("actorId")
            if (actorId.isBlank() || actorId == identityId) continue
            val at = event.optLong("at", -1L)
            if (at <= after || at > 4102444800000L) continue
            val actor = event.optString("actorName")
                .take(80)
                .ifBlank { "Un collaboratore" }
            result += RemoteEvent(
                actor = actor,
                kind = event.optString("kind"),
                at = at,
            )
        }
        return result.sortedBy { it.at }
    }

    private fun hasAccess(space: JSONObject, identityId: String): Boolean {
        val members = space.optJSONArray("members") ?: return false
        for (i in 0 until members.length()) {
            val member = members.optJSONObject(i) ?: continue
            if (member.optString("id") != identityId) continue
            val updatedAt = member.optLong("updatedAt", -1L)
            if (updatedAt < 0L) continue
            if (member.isNull("removedAt")) return true
            val removedAt = member.optLong("removedAt", Long.MAX_VALUE)
            if (updatedAt > removedAt) return true
        }
        return false
    }

    private fun notificationsAllowed(): Boolean {
        if (
            Build.VERSION.SDK_INT >= 33 &&
            applicationContext.checkSelfPermission(
                Manifest.permission.POST_NOTIFICATIONS,
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        val manager = applicationContext.getSystemService(
            NotificationManager::class.java,
        )
        if (!manager.areNotificationsEnabled()) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            ensureChannel(manager)
            return manager.getNotificationChannel(
                SharedBackgroundContract.NOTIFICATION_CHANNEL,
            )?.importance != NotificationManager.IMPORTANCE_NONE
        }
        return true
    }

    private fun notifySpace(
        spaceId: String,
        spaceName: String,
        events: List<RemoteEvent>,
    ) {
        val manager = applicationContext.getSystemService(
            NotificationManager::class.java,
        )
        ensureChannel(manager)

        val latest = events.last()
        val text = if (events.size == 1) {
            "${latest.actor} ${eventLabel(latest.kind)}"
        } else {
            "${events.size} nuove attività · ultima: " +
                "${latest.actor} ${eventLabel(latest.kind)}"
        }

        val open = PendingIntent.getActivity(
            applicationContext,
            spaceId.hashCode(),
            Intent(applicationContext, MainActivity::class.java)
                .setAction(SharedBackgroundContract.ACTION_OPEN_SHARED_SPACE)
                .setData(
                    Uri.parse(
                        "notes-shared://space/${Uri.encode(spaceId)}",
                    ),
                )
                .putExtra(
                    SharedBackgroundContract.EXTRA_SPACE_ID,
                    spaceId,
                )
                .addFlags(
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP,
                ),
            PendingIntent.FLAG_UPDATE_CURRENT or
                PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(
                applicationContext,
                SharedBackgroundContract.NOTIFICATION_CHANNEL,
            )
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(applicationContext)
        }
        val notification = builder
            .setSmallIcon(applicationContext.applicationInfo.icon)
            .setContentTitle(spaceName)
            .setContentText(text)
            .setAutoCancel(true)
            .setContentIntent(open)
            .setCategory(Notification.CATEGORY_SOCIAL)
            .build()

        manager.notify("shared-space", spaceId.hashCode(), notification)
    }

    private fun eventLabel(kind: String): String = when (kind) {
        "spaceCreated" -> "ha creato lo spazio"
        "spaceUpdated" -> "ha aggiornato lo spazio"
        "contentAdded" -> "ha condiviso un contenuto"
        "contentRemoved" -> "ha rimosso un contenuto"
        "memberChanged" -> "ha aggiornato i membri"
        "documentUpdated" -> "ha modificato un contenuto"
        "conflictPreserved" -> "ha generato un conflitto"
        else -> "ha aggiornato lo spazio"
    }

    private fun ensureChannel(manager: NotificationManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    SharedBackgroundContract.NOTIFICATION_CHANNEL,
                    "Aggiornamenti Shared Spaces",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ).apply {
                    description =
                        "Nuove attività negli spazi condivisi di Notes."
                },
            )
        }
    }

    private fun markSuccess(
        preferences: android.content.SharedPreferences,
    ) {
        preferences.edit()
            .putLong("last_success_at", System.currentTimeMillis())
            .remove("last_error")
            .apply()
    }

    private fun requestJson(
        token: String,
        url: String,
        allowNotFound: Boolean = false,
    ): Any? {
        val connection = URL(url).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "GET"
            connection.connectTimeout = 15_000
            connection.readTimeout = 20_000
            connection.instanceFollowRedirects = false
            connection.setRequestProperty(
                "Authorization",
                "Bearer $token",
            )
            connection.setRequestProperty(
                "Accept",
                "application/vnd.github+json",
            )
            connection.setRequestProperty(
                "X-GitHub-Api-Version",
                "2026-03-10",
            )
            connection.setRequestProperty(
                "User-Agent",
                "Notes-Ecosistema-Background",
            )

            val status = connection.responseCode
            if (allowNotFound && status == 404) return null
            if (status !in 200..299) {
                if (status in 400..499 &&
                    status != 408 &&
                    status != 429
                ) {
                    throw PermanentBackgroundFailure(
                        if (status == 401 || status == 403) {
                            "Accesso GitHub non valido o non autorizzato."
                        } else {
                            "GitHub background sync HTTP $status."
                        },
                    )
                }
                error("GitHub background sync HTTP $status.")
            }
            val bytes = connection.inputStream.use { stream ->
                val output = java.io.ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                var total = 0
                while (true) {
                    val count = stream.read(buffer)
                    if (count < 0) break
                    total += count
                    if (total > MAX_STATE_BYTES * 2) {
                        error("Risposta GitHub background troppo grande.")
                    }
                    output.write(buffer, 0, count)
                }
                output.toByteArray()
            }
            val text = bytes.toString(Charsets.UTF_8)
            return if (text.trimStart().startsWith("[")) {
                JSONArray(text)
            } else {
                JSONObject(text)
            }
        } finally {
            connection.disconnect()
        }
    }

    private fun readGitHubToken(): String? {
        val preferences = applicationContext.getSharedPreferences(
            "github_secure",
            Context.MODE_PRIVATE,
        )
        val iv = preferences.getString("iv", null) ?: return null
        val data = preferences.getString("data", null) ?: return null
        val store = KeyStore.getInstance("AndroidKeyStore").apply {
            load(null)
        }
        val key = store.getKey(GITHUB_KEY_ALIAS, null) as? SecretKey
            ?: return null
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            key,
            GCMParameterSpec(
                128,
                Base64.decode(iv, Base64.NO_WRAP),
            ),
        )
        return cipher.doFinal(
            Base64.decode(data, Base64.NO_WRAP),
        ).toString(Charsets.UTF_8)
    }
}


private class PermanentBackgroundFailure(
    message: String,
) : Exception(message)

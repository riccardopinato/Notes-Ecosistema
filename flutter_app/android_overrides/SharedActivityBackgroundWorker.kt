package it.notes.ecosystem.notes_ecosistema

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.work.BackoffPolicy
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
            "notificationsAllowed" to notificationsAllowed(context),
            "backgroundRestricted" to backgroundRestricted(context),
        )
    }

    fun ensureNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        context.getSystemService(NotificationManager::class.java)
            .createNotificationChannel(
                NotificationChannel(
                    NOTIFICATION_CHANNEL,
                    "Aggiornamenti Shared Spaces",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ).apply {
                    description =
                        "Nuove attività negli spazi condivisi di Notes."
                },
            )
    }

    fun notificationsAllowed(context: Context): Boolean {
        if (
            Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        val manager = context.getSystemService(NotificationManager::class.java)
        if (!manager.areNotificationsEnabled()) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            ensureNotificationChannel(context)
            return manager.getNotificationChannel(NOTIFICATION_CHANNEL)?.importance !=
                NotificationManager.IMPORTANCE_NONE
        }
        return true
    }

    fun backgroundRestricted(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return false
        return context.getSystemService(ActivityManager::class.java)
            .isBackgroundRestricted
    }

    fun postTestNotification(context: Context): Boolean {
        ensureNotificationChannel(context)
        if (!notificationsAllowed(context)) return false

        val open = PendingIntent.getActivity(
            context,
            7321,
            Intent(context, MainActivity::class.java)
                .addFlags(
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP,
                ),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, NOTIFICATION_CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
            .setSmallIcon(context.applicationInfo.icon)
            .setContentTitle("Test Shared Spaces")
            .setContentText("Le notifiche background sono configurate.")
            .setAutoCancel(true)
            .setContentIntent(open)
            .build()
        context.getSystemService(NotificationManager::class.java)
            .notify("shared-test", 7321, notification)
        return true
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
            .setBackoffCriteria(
                BackoffPolicy.EXPONENTIAL,
                30,
                TimeUnit.SECONDS,
            )
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
                ?: return unavailable(native, "GitHub Sync non configurato.")
            val repo = flutter.getString("flutter.github_repo", null)
                ?.takeIf { it.matches(Regex("^[A-Za-z0-9_.-]{1,100}$")) }
                ?: return unavailable(native, "Repository GitHub non configurato.")
            val branch = flutter.getString("flutter.github_branch", null)
                ?.takeIf { it.isNotBlank() && it.length <= 200 }
                ?: return unavailable(native, "Ramo GitHub non configurato.")
            val folder = flutter.getString("flutter.github_folder", null)
                ?.takeIf { it.isNotBlank() && it.length <= 160 }
                ?: return unavailable(native, "Cartella GitHub non configurata.")
            val sharedRaw = flutter.getString("flutter.shared_spaces_v1", null)
                ?: return unavailable(native, "Profilo Shared Spaces non disponibile.")
            val token = readGitHubToken()
                ?: return unavailable(native, "Token GitHub non disponibile.")

            val localSnapshot = JSONObject(sharedRaw)
            val localIdentity = localSnapshot.optJSONObject("identity")
                ?: return unavailable(native, "Identità Shared Spaces non disponibile.")
            val identityId = localIdentity.optString("id")
                .takeIf { it.isNotBlank() && it.length <= 200 }
                ?: return unavailable(native, "Identità Shared Spaces non valida.")
            val githubUserId = localIdentity.optString("githubUserId")
                .takeIf { it.matches(Regex("^[1-9][0-9]{0,19}$")) }
                ?: return unavailable(native, "Collega il profilo Shared Spaces a GitHub.")

            val authenticated = requestJson(
                token = token,
                url = "https://api.github.com/user",
            ) as? JSONObject ?: throw PermanentBackgroundFailure(
                "Risposta account GitHub non valida.",
            )
            if (authenticated.optString("id") != githubUserId) {
                throw PermanentBackgroundFailure(
                    "Account GitHub diverso dal profilo Shared Spaces.",
                )
            }

            val repository = requestJson(
                token = token,
                url = "https://api.github.com/repos/$owner/$repo",
            ) as? JSONObject ?: throw PermanentBackgroundFailure(
                "Risposta repository GitHub non valida.",
            )
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
                if (version != 1 && version != 2) continue

                val space = state.optJSONObject("space") ?: continue
                val spaceId = space.optString("id")
                    .takeIf { it.isNotBlank() && it.length <= 200 }
                    ?: continue
                if (!hasAccess(space, identityId)) continue

                val activity = state.optJSONArray("activity") ?: continue
                if (activity.length() > 200) continue

                val seenKey = "seen_$spaceId"
                val idsKey = "seen_ids_$spaceId"
                val generationKey = "seen_generation_$spaceId"
                val previousIds = native.getStringSet(
                    idsKey,
                    emptySet(),
                ).orEmpty().filterTo(linkedSetOf()) {
                    it.matches(Regex("^[a-f0-9]{64}$"))
                }
                val generation = native.getLong(generationKey, 0L)
                val allRemote = remoteEvents(
                    activity = activity,
                    identityId = identityId,
                    expectedSpaceId = spaceId,
                )
                val baselineAt = maxOf(
                    native.getLong(seenKey, enabledAt),
                    enabledAt,
                )
                val events = if (generation == enabledAt) {
                    allRemote.filter { !previousIds.contains(it.id) }
                } else {
                    allRemote.filter { it.at > baselineAt }
                }

                if (events.isNotEmpty() &&
                    SharedBackgroundContract.notificationsAllowed(
                        applicationContext,
                    )
                ) {
                    notifySpace(
                        spaceId = spaceId,
                        spaceName = space.optString("name")
                            .take(100)
                            .ifBlank { "Shared Space" },
                        events = events,
                    )
                }

                val currentIds = allRemote.mapTo(linkedSetOf()) { it.id }
                val nextIds = linkedSetOf<String>().apply {
                    addAll(currentIds)
                    for (id in previousIds) {
                        if (size >= 400) break
                        add(id)
                    }
                }
                val latestAt = allRemote.maxOfOrNull { it.at } ?: baselineAt
                native.edit()
                    .putLong(seenKey, maxOf(baselineAt, latestAt))
                    .putLong(generationKey, enabledAt)
                    .putStringSet(idsKey, nextIds)
                    .apply()
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
        val id: String,
        val actor: String,
        val kind: String,
        val at: Long,
    )

    private fun remoteEvents(
        activity: JSONArray,
        identityId: String,
        expectedSpaceId: String,
    ): List<RemoteEvent> {
        val result = mutableListOf<RemoteEvent>()
        for (i in 0 until activity.length()) {
            val event = activity.optJSONObject(i) ?: continue
            if (event.optString("spaceId") != expectedSpaceId) continue
            val actorId = event.optString("actorId")
            if (actorId.isBlank() || actorId == identityId) continue
            val id = event.optString("id")
            if (!id.matches(Regex("^[a-f0-9]{64}$"))) continue
            val at = event.optLong("at", -1L)
            if (at < 0L || at > 4102444800000L) continue
            val actor = event.optString("actorName")
                .take(80)
                .ifBlank { "Un collaboratore" }
            result += RemoteEvent(
                id = id,
                actor = actor,
                kind = event.optString("kind"),
                at = at,
            )
        }
        return result
            .distinctBy { it.id }
            .sortedWith(compareBy<RemoteEvent> { it.at }.thenBy { it.id })
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

    private fun notifySpace(
        spaceId: String,
        spaceName: String,
        events: List<RemoteEvent>,
    ) {
        val manager = applicationContext.getSystemService(
            NotificationManager::class.java,
        )
        SharedBackgroundContract.ensureNotificationChannel(
            applicationContext,
        )

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

    private fun unavailable(
        preferences: android.content.SharedPreferences,
        message: String,
    ): Result {
        preferences.edit()
            .putString("last_error", message.take(500))
            .apply()
        return Result.success()
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
                val rateLimited =
                    status == 403 &&
                        connection.getHeaderField("X-RateLimit-Remaining") == "0"
                if (status in 400..499 &&
                    status != 408 &&
                    status != 429 &&
                    !rateLimited
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

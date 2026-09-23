package it.notes.ecosystem.notes_ecosistema

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ClipData
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import androidx.core.content.FileProvider
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.Worker
import androidx.work.WorkerParameters
import androidx.work.WorkManager
import androidx.work.workDataOf
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.KeyStore
import java.util.UUID
import java.util.concurrent.TimeUnit
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "notes.ecosystem/capture"
        private const val REMINDER_CHANNEL = "notes.ecosystem/reminders"
        private const val REMINDER_ACTION_CHANNEL = "notes.ecosystem/reminder_actions"
        private const val SECURE_CHANNEL = "notes.ecosystem/secure"
        private const val ATTACHMENT_CHANNEL = "notes.ecosystem/attachments"
        private const val VISUAL_SHARE_CHANNEL = "notes.ecosystem/visual_share"
        private const val QUICK_SYNC_CHANNEL = "notes.ecosystem/quick_sync"
        private const val GITHUB_KEY_ALIAS = "notes-github-v1"
        const val NOTIFICATION_CHANNEL = "task_reminders"
        private const val PERMISSION_REQUEST = 4102
        private const val NEW_NOTE = "it.notes.ecosystem.NEW_NOTE"
        private const val NEW_CHECKLIST = "it.notes.ecosystem.NEW_CHECKLIST"
        const val QUICK_SYNC = "it.notes.ecosystem.QUICK_SYNC"
        const val OPEN_REMINDER = "it.notes.ecosystem.OPEN_REMINDER"
        const val SNOOZE_REMINDER = "it.notes.ecosystem.SNOOZE_REMINDER"
        private const val FILE_LIMIT = 8 * 1024 * 1024
        private const val MAX_FILES = 20
    }

    private var channel: MethodChannel? = null
    private var quickSyncChannel: MethodChannel? = null
    private var reminderActionChannel: MethodChannel? = null
    private var reminderPermissionResult: MethodChannel.Result? = null
    private var pendingCapture: Map<String, Any?>? = null
    private var pendingQuickSync = false
    private var pendingReminderAction: Map<String, Any?>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        pendingCapture = parseCapture(intent)
        pendingQuickSync = intent?.action == QUICK_SYNC
        pendingReminderAction = parseReminderAction(intent)
        super.onCreate(savedInstanceState)
        installShortcuts()
        ensureReminderChannel()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).also { methodChannel ->
            methodChannel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialCapture" -> {
                        result.success(pendingCapture)
                        pendingCapture = null
                    }
                    "pinNoteShortcut" -> result.success(requestPinnedNoteShortcut())
                    "pinCaptureWidget" -> result.success(requestPinnedCaptureWidget())
                    else -> result.notImplemented()
                }
            }
        }

        quickSyncChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            QUICK_SYNC_CHANNEL,
        ).also { methodChannel ->
            methodChannel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialRequest" -> {
                        result.success(pendingQuickSync)
                        pendingQuickSync = false
                    }
                    else -> result.notImplemented()
                }
            }
        }

        reminderActionChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            REMINDER_ACTION_CHANNEL,
        ).also { methodChannel ->
            methodChannel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialAction" -> {
                        result.success(pendingReminderAction)
                        pendingReminderAction = null
                    }
                    else -> result.notImplemented()
                }
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            REMINDER_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "sync" -> {
                    runCatching { syncReminders(call.arguments) }
                        .onSuccess { result.success(null) }
                        .onFailure { result.error("REMINDER_SYNC", it.message, null) }
                }
                "allowed" -> result.success(notificationsAllowed())
                "requestPermission" -> requestNotificationPermission(result)
                "openSettings" -> {
                    startActivity(
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    )
                    result.success(null)
                }
                "zoneId" -> result.success(java.time.ZoneId.systemDefault().id)
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ATTACHMENT_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "open", "share" -> {
                    runCatching {
                        val args = call.arguments as? Map<*, *>
                            ?: error("Parametri allegato mancanti.")
                        val key = args["key"]?.toString().orEmpty()
                        val name = args["name"]?.toString().orEmpty()
                        val mime = args["mime"]?.toString().orEmpty()
                        launchAttachment(
                            key = key,
                            name = name,
                            mime = mime,
                            share = call.method == "share",
                        )
                    }
                        .onSuccess { result.success(null) }
                        .onFailure {
                            result.error(
                                "ATTACHMENT",
                                it.message ?: "Allegato non disponibile.",
                                null,
                            )
                        }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            VISUAL_SHARE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "sharePng" -> {
                    runCatching { shareVisualPng(call.arguments) }
                        .onSuccess { result.success(null) }
                        .onFailure {
                            result.error(
                                "VISUAL_SHARE",
                                it.message ?: "Impossibile condividere il PNG.",
                                null,
                            )
                        }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SECURE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveGitHubToken" -> {
                    val token = call.arguments as? String
                    if (token.isNullOrBlank() || token.any { it.isWhitespace() }) {
                        result.error("TOKEN", "Token GitHub non valido.", null)
                    } else {
                        runCatching { saveGitHubToken(token) }
                            .onSuccess { result.success(null) }
                            .onFailure { result.error("KEYSTORE", it.message, null) }
                    }
                }
                "readGitHubToken" -> {
                    runCatching { readGitHubToken() }
                        .onSuccess { result.success(it) }
                        .onFailure { result.success(null) }
                }
                "deleteGitHubToken" -> {
                    deleteGitHubToken()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)

        val reminderAction = parseReminderAction(intent)
        if (reminderAction != null) {
            getSystemService(NotificationManager::class.java)
                .cancel(reminderAction["id"].toString(), 1)
            val currentReminder = reminderActionChannel
            if (currentReminder == null) {
                pendingReminderAction = reminderAction
            } else {
                currentReminder.invokeMethod("action", reminderAction)
            }
            return
        }

        if (intent.action == QUICK_SYNC) {
            val currentSync = quickSyncChannel
            if (currentSync == null) {
                pendingQuickSync = true
            } else {
                currentSync.invokeMethod("sync", null)
            }
            return
        }

        val capture = parseCapture(intent) ?: return
        val current = channel
        if (current == null) {
            pendingCapture = capture
        } else {
            current.invokeMethod("capture", capture)
        }
    }

    private fun parseReminderAction(intent: Intent?): Map<String, Any?>? {
        intent ?: return null
        val action = intent.action ?: return null
        if (action != OPEN_REMINDER && action != SNOOZE_REMINDER) return null
        val id = intent.getStringExtra("id")
            ?.takeIf { it.isNotBlank() && it.length <= 200 }
            ?: return null
        if (action == OPEN_REMINDER) {
            return mapOf(
                "action" to "open",
                "id" to id,
            )
        }
        val expectedAt = intent.getLongExtra("expectedAt", -1L)
        val nextAt = intent.getLongExtra("nextAt", -1L)
        if (expectedAt < 0L || nextAt <= expectedAt) return null
        return mapOf(
            "action" to "snooze",
            "id" to id,
            "expectedAt" to expectedAt,
            "nextAt" to nextAt,
        )
    }

    private fun parseCapture(intent: Intent?): Map<String, Any?>? {
        intent ?: return null
        return try {
            when (intent.action) {
                NEW_NOTE -> capture(checklist = false)
                NEW_CHECKLIST -> capture(checklist = true)
                Intent.ACTION_SEND -> parseSend(intent)
                Intent.ACTION_SEND_MULTIPLE -> parseSendMultiple(intent)
                else -> null
            }
        } catch (error: Exception) {
            mapOf(
                "title" to "",
                "body" to "",
                "checklist" to false,
                "files" to emptyList<Map<String, String>>(),
                "error" to (
                    error.message
                        ?.takeIf { it.isNotBlank() }
                        ?: "Contenuto condiviso non leggibile."
                    ),
            )
        }
    }

    private fun capture(
        title: String = "",
        body: String = "",
        checklist: Boolean = false,
        files: List<Map<String, String>> = emptyList(),
    ): Map<String, Any?> = mapOf(
        "title" to title,
        "body" to body,
        "checklist" to checklist,
        "files" to files,
    )

    private fun parseSend(intent: Intent): Map<String, Any?> {
        val mime = intent.type.orEmpty().lowercase()
        val subject = intent
            .getCharSequenceExtra(Intent.EXTRA_SUBJECT)
            ?.toString()
            .orEmpty()
            .trim()

        val uri = stream(intent)
        if (mime == "text/plain" && uri == null) {
            val text = intent
                .getCharSequenceExtra(Intent.EXTRA_TEXT)
                ?.toString()
                .orEmpty()
            require(subject.isNotBlank() || text.isNotBlank()) {
                "Nessun testo da acquisire."
            }
            return capture(title = subject, body = text)
        }

        require(uri != null) {
            "Il contenuto condiviso non contiene un file leggibile."
        }
        require(mime.startsWith("image/") || mime == "application/pdf") {
            "Formato condiviso non supportato."
        }
        return capture(
            title = subject,
            files = listOf(copyShared(uri, mime)),
        )
    }

    private fun parseSendMultiple(intent: Intent): Map<String, Any?> {
        val mime = intent.type.orEmpty().lowercase()
        require(
            mime.startsWith("image/") ||
                mime == "application/pdf" ||
                mime == "*/*"
        ) {
            "Puoi condividere più immagini o documenti PDF."
        }

        val uris = streams(intent).distinct()
        require(uris.isNotEmpty()) {
            "Nessun file condiviso."
        }
        require(uris.size <= MAX_FILES) {
            "Puoi acquisire fino a 20 file per volta."
        }

        val subject = intent
            .getCharSequenceExtra(Intent.EXTRA_SUBJECT)
            ?.toString()
            .orEmpty()
            .trim()

        return capture(
            title = subject,
            files = uris.map { uri ->
                copyShared(
                    uri,
                    contentResolver.getType(uri).orEmpty().lowercase(),
                )
            },
        )
    }

    private fun copyShared(
        uri: Uri,
        declaredMime: String,
    ): Map<String, String> {
        require(uri.scheme == "content" || uri.scheme == "file") {
            "File condiviso non leggibile."
        }

        val name = displayName(uri)
            .take(120)
            .ifBlank { "Allegato" }
        val mime = declaredMime
            .ifBlank { contentResolver.getType(uri).orEmpty().lowercase() }

        require(mime.startsWith("image/") || mime == "application/pdf") {
            "Formato condiviso non supportato: $name"
        }

        val extension = when {
            name.substringAfterLast('.', "").isNotBlank() ->
                "." + name.substringAfterLast('.').lowercase().take(8)
            mime == "application/pdf" -> ".pdf"
            mime == "image/png" -> ".png"
            mime == "image/webp" -> ".webp"
            else -> ".jpg"
        }

        val dir = File(cacheDir, "shared_capture").apply { mkdirs() }
        val target = File(
            dir,
            "share-${UUID.randomUUID()}$extension",
        )

        val input = if (uri.scheme == "file") {
            File(uri.path ?: error("Percorso file mancante.")).inputStream()
        } else {
            contentResolver.openInputStream(uri)
                ?: error("Impossibile leggere $name.")
        }

        input.use { source ->
            target.outputStream().use { output ->
                val buffer = ByteArray(8192)
                var total = 0
                while (true) {
                    val count = source.read(buffer)
                    if (count < 0) break
                    total += count
                    require(total <= FILE_LIMIT) {
                        "Allegato oltre 8 MiB: $name"
                    }
                    output.write(buffer, 0, count)
                }
                output.flush()
            }
        }

        return mapOf(
            "path" to target.absolutePath,
            "name" to name,
            "mime" to mime,
        )
    }

    private fun displayName(uri: Uri): String {
        if (uri.scheme == "file") {
            return File(uri.path.orEmpty()).name
        }

        return runCatching {
            contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        }.getOrNull().orEmpty()
    }

    @Suppress("DEPRECATION")
    private fun stream(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }

    @Suppress("DEPRECATION")
    private fun streams(intent: Intent): List<Uri> =
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableArrayListExtra(
                Intent.EXTRA_STREAM,
                Uri::class.java,
            ).orEmpty()
        } else {
            intent.getParcelableArrayListExtra<Uri>(
                Intent.EXTRA_STREAM,
            ).orEmpty()
        }

    private fun shareVisualPng(raw: Any?) {
        val args = raw as? Map<*, *> ?: error("Parametri export mancanti.")
        val bytes = args["bytes"] as? ByteArray ?: error("PNG mancante.")
        require(bytes.size in 8..(16 * 1024 * 1024)) { "PNG vuoto o troppo grande." }
        require(
            (bytes[0].toInt() and 0xFF) == 0x89 &&
                bytes[1].toInt() == 0x50 &&
                bytes[2].toInt() == 0x4E &&
                bytes[3].toInt() == 0x47
        ) { "File PNG non valido." }

        val title = args["title"]?.toString()?.trim()
            ?.take(200)
            ?.ifBlank { "Notes" }
            ?: "Notes"
        val folder = File(cacheDir, "visual_exports")
        check(folder.isDirectory || folder.mkdirs()) { "Cartella export non disponibile." }
        val now = System.currentTimeMillis()
        folder.listFiles()?.filter {
            it.isFile && now - it.lastModified() > TimeUnit.DAYS.toMillis(1)
        }?.forEach { it.delete() }

        val file = File(folder, UUID.randomUUID().toString() + ".png")
        file.writeBytes(bytes)
        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.attachments",
            file,
        )
        val send = Intent(Intent.ACTION_SEND)
            .setType("image/png")
            .putExtra(Intent.EXTRA_STREAM, uri)
            .putExtra(Intent.EXTRA_SUBJECT, title)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            .apply {
                clipData = ClipData.newUri(contentResolver, title, uri)
            }
        startActivity(Intent.createChooser(send, "Condividi immagine"))
    }

    private fun launchAttachment(
        key: String,
        name: String,
        mime: String,
        share: Boolean,
    ) {
        require(
            Regex(
                "^[a-f0-9]{64}\\.(jpg|png|webp|m4a|mp3|wav|ogg|pdf|txt|docx|xlsx|pptx)$"
            ).matches(key)
        ) {
            "Allegato non valido."
        }
        require(mime.isNotBlank() && mime.length <= 200) {
            "Tipo allegato non valido."
        }

        val root = File(filesDir, "attachments").canonicalFile
        val file = File(root, key).canonicalFile
        require(file.parentFile == root && file.isFile && file.length() in 1..FILE_LIMIT.toLong()) {
            "Allegato non disponibile."
        }

        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.attachments",
            file,
        )
        val safeName = name.take(120).ifBlank { "Allegato" }
        val intent = if (share) {
            Intent(Intent.ACTION_SEND)
                .setType(mime)
                .putExtra(Intent.EXTRA_STREAM, uri)
                .putExtra(Intent.EXTRA_TITLE, safeName)
        } else {
            Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, mime)
        }
        intent
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            .also {
                it.clipData = ClipData.newRawUri(safeName, uri)
            }

        startActivity(
            if (share) Intent.createChooser(intent, "Condividi allegato")
            else Intent.createChooser(intent, "Apri allegato")
        )
    }

    private fun githubSecretKey(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(GITHUB_KEY_ALIAS, null) as? SecretKey)?.let { return it }

        return KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            "AndroidKeyStore",
        ).apply {
            init(
                KeyGenParameterSpec.Builder(
                    GITHUB_KEY_ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT or
                        KeyProperties.PURPOSE_DECRYPT,
                )
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(
                        KeyProperties.ENCRYPTION_PADDING_NONE
                    )
                    .build()
            )
        }.generateKey()
    }

    private fun saveGitHubToken(token: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, githubSecretKey())
        val encrypted = cipher.doFinal(token.toByteArray(Charsets.UTF_8))
        getSharedPreferences("github_secure", Context.MODE_PRIVATE)
            .edit()
            .putString(
                "iv",
                Base64.encodeToString(cipher.iv, Base64.NO_WRAP),
            )
            .putString(
                "data",
                Base64.encodeToString(encrypted, Base64.NO_WRAP),
            )
            .commit()
    }

    private fun readGitHubToken(): String? {
        val preferences =
            getSharedPreferences("github_secure", Context.MODE_PRIVATE)
        val iv = preferences.getString("iv", null) ?: return null
        val data = preferences.getString("data", null) ?: return null
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            githubSecretKey(),
            GCMParameterSpec(
                128,
                Base64.decode(iv, Base64.NO_WRAP),
            ),
        )
        return cipher.doFinal(
            Base64.decode(data, Base64.NO_WRAP)
        ).toString(Charsets.UTF_8)
    }

    private fun deleteGitHubToken() {
        getSharedPreferences("github_secure", Context.MODE_PRIVATE)
            .edit()
            .clear()
            .commit()
    }

    private fun ensureReminderChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(
                    NOTIFICATION_CHANNEL,
                    "Promemoria attività",
                    NotificationManager.IMPORTANCE_DEFAULT,
                )
            )
        }
    }

    private fun notificationsAllowed(): Boolean {
        if (
            Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        val manager = getSystemService(NotificationManager::class.java)
        if (!manager.areNotificationsEnabled()) return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.getNotificationChannel(NOTIFICATION_CHANNEL)?.importance !=
                NotificationManager.IMPORTANCE_NONE
        } else {
            true
        }
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33 || notificationsAllowed()) {
            result.success(true)
            return
        }
        if (reminderPermissionResult != null) {
            result.error("BUSY", "Richiesta notifiche già in corso.", null)
            return
        }
        reminderPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            PERMISSION_REQUEST,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST) {
            reminderPermissionResult?.success(notificationsAllowed())
            reminderPermissionResult = null
        }
    }

    private fun syncReminders(raw: Any?) {
        ensureReminderChannel()
        val values = raw as? List<*> ?: emptyList<Any?>()
        val manager = WorkManager.getInstance(this)
        val preferences =
            getSharedPreferences("flutter_task_reminders", Context.MODE_PRIVATE)
        val previous = preferences
            .getStringSet("scheduled", emptySet())
            .orEmpty()
            .toSet()
        val current = mutableSetOf<String>()

        values.forEach { value ->
            val row = value as? Map<*, *> ?: return@forEach
            val id = row["id"]?.toString()
                ?.takeIf { it.isNotBlank() && it.length <= 200 }
                ?: return@forEach
            val title = row["title"]?.toString()
                ?.take(8000)
                ?.ifBlank { "Attività" }
                ?: "Attività"
            val at = (row["at"] as? Number)?.toLong()
                ?.takeIf { it >= 0L }
                ?: return@forEach

            current += id
            val request = OneTimeWorkRequestBuilder<ReminderWorker>()
                .setInitialDelay(
                    (at - System.currentTimeMillis()).coerceAtLeast(0L),
                    TimeUnit.MILLISECONDS,
                )
                .setInputData(
                    workDataOf(
                        "id" to id,
                        "title" to title,
                        "at" to at,
                    )
                )
                .build()
            manager.enqueueUniqueWork(
                "task-reminder-$id",
                ExistingWorkPolicy.REPLACE,
                request,
            )
        }

        (previous - current).forEach { id ->
            manager.cancelUniqueWork("task-reminder-$id")
            getSystemService(NotificationManager::class.java).cancel(id, 1)
        }
        preferences.edit().putStringSet("scheduled", current).apply()
    }

    private fun requestPinnedNoteShortcut(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val manager = getSystemService(ShortcutManager::class.java) ?: return false
        if (!manager.isRequestPinShortcutSupported) return false
        val shortcut = ShortcutInfo.Builder(this, "capture-note-pinned")
            .setShortLabel("Nuova nota")
            .setLongLabel("Scrivi una nuova nota")
            .setIcon(Icon.createWithResource(this, applicationInfo.icon))
            .setIntent(
                Intent(this, MainActivity::class.java)
                    .setAction(NEW_NOTE)
            )
            .build()
        return manager.requestPinShortcut(shortcut, null)
    }

    private fun requestPinnedCaptureWidget(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val manager = getSystemService(AppWidgetManager::class.java) ?: return false
        if (!manager.isRequestPinAppWidgetSupported) return false
        return manager.requestPinAppWidget(
            ComponentName(this, QuickCaptureWidget::class.java),
            null,
            null,
        )
    }

    private fun installShortcuts() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N_MR1) return
        val manager = getSystemService(ShortcutManager::class.java) ?: return

        fun shortcut(
            id: String,
            label: String,
            action: String,
        ): ShortcutInfo =
            ShortcutInfo.Builder(this, id)
                .setShortLabel(label)
                .setLongLabel(label)
                .setIcon(
                    Icon.createWithResource(
                        this,
                        applicationInfo.icon,
                    )
                )
                .setIntent(
                    Intent(this, MainActivity::class.java)
                        .setAction(action)
                )
                .build()

        runCatching {
            manager.dynamicShortcuts = listOf(
                shortcut(
                    "capture-note",
                    "Nuova nota",
                    NEW_NOTE,
                ),
                shortcut(
                    "capture-checklist",
                    "Nuova checklist",
                    NEW_CHECKLIST,
                ),
            )
        }
    }
}


class ReminderWorker(
    context: Context,
    params: WorkerParameters,
) : Worker(context, params) {
    override fun doWork(): Result {
        val id = inputData.getString("id") ?: return Result.failure()
        val title = inputData.getString("title")
            ?.take(8000)
            ?.ifBlank { "Attività" }
            ?: "Attività"
        val at = inputData.getLong("at", -1L)
        if (at < 0L) return Result.failure()

        if (
            Build.VERSION.SDK_INT >= 33 &&
            applicationContext.checkSelfPermission(
                Manifest.permission.POST_NOTIFICATIONS
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            return Result.success()
        }

        val manager =
            applicationContext.getSystemService(NotificationManager::class.java)
        if (!manager.areNotificationsEnabled()) return Result.success()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    MainActivity.NOTIFICATION_CHANNEL,
                    "Promemoria attività",
                    NotificationManager.IMPORTANCE_DEFAULT,
                )
            )
        }

        val open = PendingIntent.getActivity(
            applicationContext,
            id.hashCode(),
            Intent(applicationContext, MainActivity::class.java)
                .setAction(MainActivity.OPEN_REMINDER)
                .setData(Uri.parse("notes-reminder://open/${Uri.encode(id)}/$at"))
                .putExtra("id", id)
                .addFlags(
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                ),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val nextAt = System.currentTimeMillis() + 10 * 60 * 1000L
        val snooze = PendingIntent.getActivity(
            applicationContext,
            id.hashCode() xor at.hashCode(),
            Intent(applicationContext, MainActivity::class.java)
                .setAction(MainActivity.SNOOZE_REMINDER)
                .setData(Uri.parse("notes-reminder://snooze/${Uri.encode(id)}/$at"))
                .putExtra("id", id)
                .putExtra("expectedAt", at)
                .putExtra("nextAt", nextAt)
                .addFlags(
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                ),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(
                    applicationContext,
                    MainActivity.NOTIFICATION_CHANNEL,
                )
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(applicationContext)
            }
                .setSmallIcon(applicationContext.applicationInfo.icon)
                .setContentTitle(title)
                .setContentText("È il momento della tua attività.")
                .setAutoCancel(true)
                .setContentIntent(open)
                .addAction(
                    applicationContext.applicationInfo.icon,
                    "Rinvia 10 min",
                    snooze,
                )
                .build()

        manager.notify(id, 1, notification)
        return Result.success()
    }
}

package it.notes.ecosystem.notes_ecosistema

import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "notes.ecosystem/capture"
        private const val NEW_NOTE = "it.notes.ecosystem.NEW_NOTE"
        private const val NEW_CHECKLIST = "it.notes.ecosystem.NEW_CHECKLIST"
        private const val FILE_LIMIT = 8 * 1024 * 1024
        private const val MAX_FILES = 20
    }

    private var channel: MethodChannel? = null
    private var pendingCapture: Map<String, Any?>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        pendingCapture = parseCapture(intent)
        super.onCreate(savedInstanceState)
        installShortcuts()
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
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val capture = parseCapture(intent) ?: return
        val current = channel
        if (current == null) {
            pendingCapture = capture
        } else {
            current.invokeMethod("capture", capture)
        }
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

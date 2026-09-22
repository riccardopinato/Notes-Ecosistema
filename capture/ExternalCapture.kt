package it.notes.ecosystem.capture

import android.content.Intent
import android.net.Uri
import it.notes.ecosystem.domain.CaptureSeed
import it.notes.ecosystem.domain.QuickCapture
import it.notes.ecosystem.domain.SmartCaptureRules

data class ExternalCapture(
    val seed: CaptureSeed,
    val uris: List<Uri> = emptyList(),
    val shouldSuggestWebCapture: Boolean = false,
    val shouldSuggestOcr: Boolean = false,
) {
    val empty: Boolean get() = !seed.hasContent && uris.isEmpty()
}

object ExternalCaptureIntents {

    fun read(intent: Intent): ExternalCapture {
        return when (intent.action) {
            CaptureIntents.NEW_NOTE -> ExternalCapture(CaptureSeed())
            CaptureIntents.NEW_CHECKLIST -> ExternalCapture(CaptureSeed(checklist = true))
            Intent.ACTION_SEND -> readSingle(intent)
            Intent.ACTION_SEND_MULTIPLE -> readMultiple(intent)
            else -> error("Azione non supportata.")
        }.also {
            require(!it.empty || intent.action in setOf(CaptureIntents.NEW_NOTE, CaptureIntents.NEW_CHECKLIST)) {
                "Nessun contenuto da acquisire."
            }
        }
    }

    private fun readSingle(intent: Intent): ExternalCapture {
        val type = intent.type.orEmpty().lowercase()

        if (type == "text/plain" && !intent.hasExtra(Intent.EXTRA_STREAM)) {
            val seed = QuickCapture.shared(
                intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString(),
                intent.getCharSequenceExtra(Intent.EXTRA_SUBJECT)?.toString(),
            )
            return ExternalCapture(
                seed = seed,
                shouldSuggestWebCapture =
                    SmartCaptureRules.extractSingleHttpUrl(seed.body) != null,
            )
        }

        val uri = stream(intent)
            ?: throw IllegalArgumentException("Il contenuto condiviso non contiene un file leggibile.")

        require(isSupportedType(type)) {
            "Formato condiviso non supportato. Usa immagini JPEG/PNG/WebP o PDF."
        }

        val subject = intent.getCharSequenceExtra(Intent.EXTRA_SUBJECT)?.toString().orEmpty().trim()

        return ExternalCapture(
            seed = CaptureSeed(title = subject),
            uris = listOf(uri),
            shouldSuggestOcr = type.startsWith("image/"),
        )
    }

    private fun readMultiple(intent: Intent): ExternalCapture {
        val type = intent.type.orEmpty().lowercase()
        require(isSupportedType(type) || type == "*/*") {
            "Puoi condividere più immagini o documenti PDF."
        }

        val uris = multipleStreams(intent)
        require(uris.isNotEmpty()) { "Nessun file condiviso." }
        require(uris.size <= SmartCaptureRules.MAX_SHARED_URIS) {
            "Puoi acquisire fino a ${SmartCaptureRules.MAX_SHARED_URIS} file per volta."
        }

        val subject = intent.getCharSequenceExtra(Intent.EXTRA_SUBJECT)?.toString().orEmpty().trim()

        return ExternalCapture(
            seed = CaptureSeed(title = subject),
            uris = uris,
            shouldSuggestOcr = type.startsWith("image/"),
        )
    }

    @Suppress("DEPRECATION")
    private fun stream(intent: Intent): Uri? {
        return if (android.os.Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }
    }

    @Suppress("DEPRECATION")
    private fun multipleStreams(intent: Intent): List<Uri> {
        return if (android.os.Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java).orEmpty()
        } else {
            intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM).orEmpty()
        }.distinct()
    }

    private fun isSupportedType(type: String): Boolean =
        type.startsWith("image/") || type == "application/pdf"
}

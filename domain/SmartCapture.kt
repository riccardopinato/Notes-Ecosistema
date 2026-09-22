package it.notes.ecosystem.domain

import java.net.URI
import java.util.Locale

enum class SmartCaptureKind {
    TEXT,
    LINK,
    IMAGE,
    DOCUMENT,
    SCAN,
}

data class OcrText(
    val text: String,
    val blockCount: Int,
) {
    val hasText: Boolean get() = text.isNotBlank()
}

data class WebSnapshot(
    val requestedUrl: String,
    val finalUrl: String,
    val title: String,
    val description: String,
    val text: String,
) {
    fun toMarkdown(): String {
        val safeTitle = title.trim().ifBlank { finalUrl }
        val cleanDescription = description.trim()
        val cleanText = text.trim()

        return buildString {
            append("## ")
            append(safeTitle)
            append('\n')
            append('\n')
            append("[Apri fonte](")
            append(finalUrl)
            append(")")
            append('\n')

            if (cleanDescription.isNotBlank()) {
                append('\n')
                append("> ")
                append(cleanDescription.replace("\n", "\n> "))
                append('\n')
            }

            if (cleanText.isNotBlank()) {
                append('\n')
                append(cleanText)
                append('\n')
            }
        }.trim()
    }
}

object SmartCaptureRules {
    const val MAX_SHARED_URIS = 20
    const val MAX_WEB_HTML_BYTES = 1_500_000
    const val MAX_WEB_TEXT_CHARS = 24_000
    const val MAX_OCR_TEXT_CHARS = 60_000
    const val MAX_URL_LENGTH = 4_096

    private val exactUrl = Regex("""^https?://[^\s]+$""", RegexOption.IGNORE_CASE)

    fun extractSingleHttpUrl(text: String): String? {
        val candidate = text.trim()
        if (candidate.length !in 8..MAX_URL_LENGTH) return null
        if (!exactUrl.matches(candidate)) return null
        return runCatching { normalizeHttpUrl(candidate) }.getOrNull()
    }

    fun normalizeHttpUrl(raw: String): String {
        require(raw.length <= MAX_URL_LENGTH) { "URL troppo lungo." }
        val uri = URI(raw.trim())
        require(uri.scheme?.lowercase(Locale.ROOT) in setOf("http", "https")) {
            "Sono supportati solo link http e https."
        }
        require(!uri.host.isNullOrBlank()) { "Indirizzo web non valido." }
        require(uri.userInfo.isNullOrBlank()) { "URL con credenziali non supportato." }
        require(uri.fragment?.length.orZero() <= 2_000) { "URL non valido." }

        val scheme = uri.scheme.lowercase(Locale.ROOT)
        val host = uri.host.lowercase(Locale.ROOT)
        val portPart = if (uri.port == -1) "" else ":${uri.port}"
        val rawPath = uri.rawPath?.ifBlank { "/" } ?: "/"
        val query = uri.rawQuery?.let { "?$it" }.orEmpty()
        val fragment = uri.rawFragment?.let { "#$it" }.orEmpty()
        return "$scheme://$host$portPart$rawPath$query$fragment"
    }

    private fun Int?.orZero(): Int = this ?: 0

    fun appendSection(
        body: String,
        title: String,
        content: String,
        maxTotalChars: Int = 200_000,
    ): String {
        val clean = content.trim()
        if (clean.isBlank()) return body
        val heading = title.trim().ifBlank { "Contenuto acquisito" }

        val addition = buildString {
            if (body.isNotBlank()) append("\n\n")
            append("## ")
            append(heading)
            append("\n\n")
            append(clean)
            append('\n')
        }

        require(body.length + addition.length <= maxTotalChars) {
            "La nota diventerebbe troppo lunga. Riduci il contenuto e riprova."
        }
        return body + addition
    }

    fun containsSection(
        body: String,
        title: String,
        content: String,
    ): Boolean {
        val clean = content.trim()
        if (clean.isBlank()) return true
        val marker = "## ${title.trim()}\n\n$clean"
        return body.contains(marker)
    }

    fun clipOcr(text: String): String =
        text.replace('\u0000', ' ')
            .trim()
            .take(MAX_OCR_TEXT_CHARS)

    fun clipWebText(text: String): String =
        text.replace('\u0000', ' ')
            .replace(Regex("""[ \t]+\n"""), "\n")
            .replace(Regex("""\n{3,}"""), "\n\n")
            .trim()
            .take(MAX_WEB_TEXT_CHARS)
}

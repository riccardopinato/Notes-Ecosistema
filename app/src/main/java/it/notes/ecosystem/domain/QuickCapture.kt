package it.notes.ecosystem.domain

/** Plain text only: URLs remain text and are never fetched. */
data class CaptureSeed(val title: String = "", val body: String = "", val checklist: Boolean = false) {
    val hasContent: Boolean get() = title.isNotBlank() || body.isNotBlank()
}
object QuickCapture {
    const val MAX_BYTES = 200 * 1024
    fun shared(text: String?, subject: String?): CaptureSeed {
        val body = text.orEmpty()
        val title = subject.orEmpty().trim()
        require(title.length <= 8000) { "Il titolo condiviso è troppo lungo." }
        require(body.length <= MAX_BYTES && title.length + body.length <= MAX_BYTES) { "Testo condiviso oltre 200 KB." }
        require(title.toByteArray(Charsets.UTF_8).size + body.toByteArray(Charsets.UTF_8).size <= MAX_BYTES) { "Testo condiviso oltre 200 KB." }
        require('\u0000' !in body && '\u0000' !in title) { "Il contenuto non è testo valido." }
        return CaptureSeed(title, body).also { require(it.hasContent) { "Nessun testo da aggiungere. Condividi un testo o un link." } }
    }
}

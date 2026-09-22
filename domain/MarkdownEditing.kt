package it.notes.ecosystem.domain

import java.net.URI

data class MarkdownEdit(val text: String, val start: Int, val end: Int)
enum class MarkdownAction { BOLD, ITALIC, HEADING, BULLET, NUMBERED, QUOTE, CODE, CODE_BLOCK }
object MarkdownEditing {
    fun apply(text: String, start: Int, end: Int, action: MarkdownAction): MarkdownEdit {
        val a = minOf(start, end).coerceIn(0, text.length)
        val b = maxOf(start, end).coerceIn(a, text.length)
        val chosen = text.substring(a, b)
        fun wrap(left: String, right: String = left): MarkdownEdit {
            val inner = chosen.ifEmpty { "testo" }
            return MarkdownEdit(text.replaceRange(a, b, left + inner + right), a + left.length, a + left.length + inner.length)
        }
        return when (action) {
            MarkdownAction.BOLD -> wrap("**")
            MarkdownAction.ITALIC -> wrap("*")
            MarkdownAction.CODE -> {
                require('\n' !in chosen && '\r' !in chosen) { "Per più righe usa Blocco codice." }
                val fence = "`".repeat((Regex("`+").findAll(chosen).maxOfOrNull { it.value.length } ?: 0) + 1)
                val padding = if (chosen.startsWith('`') || chosen.endsWith('`') || (chosen.startsWith(' ') && chosen.endsWith(' '))) " " else ""
                wrap(fence + padding, padding + fence)
            }
            MarkdownAction.CODE_BLOCK -> {
                val nl = if ("\r\n" in text) "\r\n" else "\n"
                val fence = "`".repeat(maxOf(3, (Regex("`+").findAll(chosen).maxOfOrNull { it.value.length } ?: 0) + 1))
                wrap((if (a > 0 && text[a - 1] != '\n') nl else "") + fence + nl,
                    nl + fence + (if (b < text.length && text[b] != '\n' && text[b] != '\r') nl else ""))
            }
            else -> {
                val lineStart = text.lastIndexOf('\n', a - 1).let { if (a == 0) 0 else it + 1 }
                val last = if (b > a && text.getOrNull(b - 1) == '\n') b - 1 else b
                val lineEnd = text.indexOf('\n', last).let { if (it < 0) text.length else it }
                val lines = text.substring(lineStart, lineEnd).split('\n')
                val replacement = lines.mapIndexed { index, line ->
                    val prefix = when (action) {
                        MarkdownAction.HEADING -> "## "
                        MarkdownAction.BULLET -> "- "
                        MarkdownAction.NUMBERED -> "${index + 1}. "
                        else -> "> "
                    }
                    prefix + line
                }.joinToString("\n")
                MarkdownEdit(text.replaceRange(lineStart, lineEnd, replacement), lineStart, lineStart + replacement.length)
            }
        }
    }
    fun link(text: String, start: Int, end: Int, label: String, url: String): MarkdownEdit {
        val uri = runCatching { URI(url.trim()) }.getOrNull()
        require(uri != null && uri.scheme?.lowercase() in listOf("http", "https") && !uri.host.isNullOrBlank() && uri.userInfo == null) { "Inserisci un link http o https valido." }
        require('\n' !in label && '\r' !in label && label.isNotBlank()) { "Inserisci un testo del link su una sola riga." }
        val a = minOf(start, end).coerceIn(0, text.length); val b = maxOf(start, end).coerceIn(a, text.length)
        val safeLabel = label.replace("\\", "\\\\").replace("[", "\\[").replace("]", "\\]")
        val result = "[$safeLabel](<${uri.toASCIIString()}>)"
        return MarkdownEdit(text.replaceRange(a, b, result), a + result.length, a + result.length)
    }
}

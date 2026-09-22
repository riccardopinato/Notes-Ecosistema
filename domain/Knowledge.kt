package it.notes.ecosystem.domain

import java.time.LocalDate
import java.util.UUID

data class NoteLink(val id: String, val label: String, val start: Int, val end: Int)
data class NoteHeading(val title: String, val level: Int, val offset: Int)

/** Local links are plain Markdown, with stable IDs, never title-based identities. */
object Knowledge {
    private val uuid = "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
    private val target = Regex("^notes://note/($uuid)$")
    private val link = Regex("(?<!!)\\[((?:\\\\.|[^\\]\\r\\n])*)]\\(notes://note/($uuid)\\)")
    fun targetId(uri: String): String? = target.matchEntire(uri)?.groupValues?.get(1)?.lowercase()
    fun url(id: String): String {
        require(Regex("^$uuid$").matches(id)) { "Identificatore della nota non valido." }
        return "notes://note/${id.lowercase()}"
    }
    fun insert(text: String, start: Int, end: Int, id: String, label: String): MarkdownEdit {
        val a = minOf(start, end).coerceIn(0, text.length)
        val b = maxOf(start, end).coerceIn(a, text.length)
        val safe = label.take(300).replace("\\", "\\\\").replace("[", "\\[").replace("]", "\\]")
            .replace('\n', ' ').replace('\r', ' ').ifBlank { "Nota" }
        val value = "[$safe](${url(id)})"
        return MarkdownEdit(text.replaceRange(a, b, value), a + value.length, a + value.length)
    }
    // Preserve offsets while excluding fenced/indented code and inline code spans.
    internal fun visible(text: String): BooleanArray {
        val result = BooleanArray(text.length) { true }
        var fence: Char? = null; var fenceSize = 0; var pos = 0
        for (line in text.split('\n')) {
            val raw = line.removeSuffix("\r")
            val match = Regex("^ {0,3}(`{3,}|~{3,})(.*)$").matchEntire(raw)
            var hidden = fence != null || raw.startsWith("    ") || raw.startsWith("\t")
            if (match != null) {
                val token = match.groupValues[1]; val tail = match.groupValues[2]
                if (fence == null && !(token[0] == '`' && '`' in tail)) {
                    fence = token[0]; fenceSize = token.length; hidden = true
                } else if (fence == token[0] && token.length >= fenceSize && tail.isBlank()) {
                    fence = null; hidden = true
                }
            }
            if (hidden) for (i in pos until minOf(text.length, pos + line.length)) result[i] = false
            pos += line.length + 1
        }
        val ticks = Regex("`+").findAll(text).filter { result[it.range.first] }.toList()
        val next = IntArray(ticks.size) { -1 }
        val latest = mutableMapOf<Int,Int>()
        for (n in ticks.indices.reversed()) {
            next[n] = latest[ticks[n].value.length] ?: -1
            latest[ticks[n].value.length] = n
        }
        val hiddenPrefix = IntArray(text.length + 1)
        for (n in text.indices) hiddenPrefix[n+1] = hiddenPrefix[n] + if(result[n]) 0 else 1
        var i = 0
        while(i < ticks.size) {
            val j = next[i]
            if(j >= 0 && hiddenPrefix[ticks[j].range.last+1] == hiddenPrefix[ticks[i].range.first]) {
                for(n in ticks[i].range.first..ticks[j].range.last) result[n] = false
                i = j + 1
            } else i++
        }
        return result
    }
    internal fun escaped(text: String, offset: Int): Boolean {
        var p = offset - 1; var count = 0
        while (p >= 0 && text[p--] == '\\') count++
        return count % 2 == 1
    }
    fun links(text: String): List<NoteLink> {
        val mask = visible(text)
        return link.findAll(text).filter { !escaped(text, it.range.first) && it.range.all { p -> mask[p] } }.map {
            NoteLink(it.groupValues[2].lowercase(), it.groupValues[1].replace(Regex("\\\\(.)"), "$1"), it.range.first, it.range.last + 1)
        }.toList()
    }
    fun remap(text: String, ids: Map<String, String>): String {
        var result = text
        links(text).asReversed().forEach { ref ->
            ids[ref.id]?.let { replacement ->
                val old = result.substring(ref.start, ref.end)
                val start = old.lastIndexOf("notes://note/")
                result = result.replaceRange(ref.start + start, ref.end - 1, url(replacement))
            }
        }
        return result
    }
    fun headings(text: String): List<NoteHeading> {
        val mask = visible(text); var offset = 0
        return text.split('\n').mapNotNull { line ->
            val start = offset; offset += line.length + 1
            val match = Regex("^ {0,3}(#{1,6})(?:[ \\t]+|$)(.*)$").matchEntire(line.removeSuffix("\r"))
            if (match == null || start >= mask.size || !mask[start]) null else
                NoteHeading(match.groupValues[2].replace(Regex("[ \\t]+#+[ \\t]*$"), "").trim(), match.groupValues[1].length, start)
        }
    }
}

object LiteralSearch {
    fun ranges(text: String, query: String, ignoreCase: Boolean = true): List<IntRange> {
        if (query.isEmpty()) return emptyList()
        val result = mutableListOf<IntRange>(); var from = 0
        while (from <= text.length - query.length) {
            val index = text.indexOf(query, from, ignoreCase)
            if (index < 0) break
            result += index until index + query.length; from = index + query.length
        }
        return result
    }
    fun replaceAll(text: String, query: String, replacement: String, ignoreCase: Boolean = true): MarkdownEdit {
        val matches = ranges(text, query, ignoreCase)
        val length = text.length.toLong() + matches.size.toLong() * (replacement.length.toLong() - query.length)
        require(length <= 200_000) { "Il risultato supera 200.000 caratteri. Riduci la sostituzione." }
        val result = buildString {
            var last = 0
            for (range in matches) { append(text, last, range.first); append(replacement); last = range.last + 1 }
            append(text, last, text.length)
        }
        return MarkdownEdit(result, 0, 0)
    }
}

data class PageTemplate(val key: String, val name: String, val title: String, val body: String)
object PageTemplates {
    val all = listOf(
        PageTemplate("meeting", "Riunione", "Riunione", "# Obiettivo\n\n## Appunti\n\n## Decisioni\n\n## Prossime azioni\n- [ ] "),
        PageTemplate("project", "Progetto", "Nuovo progetto", "# Risultato desiderato\n\n## Materiali e collegamenti\n\n## Prossimi passi\n- [ ] \n\n## Decisioni\n"),
        PageTemplate("study", "Studio", "Sessione di studio", "# Argomento\n\n## Concetti chiave\n\n## Domande\n\n## Riepilogo\n"),
        PageTemplate("review", "Revisione settimanale", "Revisione settimanale", "# Cosa ho completato\n\n## Cosa ho imparato\n\n## Da riprendere\n- [ ] \n\n## Priorità della prossima settimana\n")
    )
    fun dailyId(date: LocalDate): String = UUID.nameUUIDFromBytes("notes-ecosystem:daily:$date".toByteArray(Charsets.UTF_8)).toString()
    fun daily(date: LocalDate) = PageTemplate("daily", "Diario di oggi", "Diario · $date", "# $date\n\n## Oggi conta\n- [ ] \n\n## Appunti della giornata\n\n## Una cosa da ricordare\n")
}

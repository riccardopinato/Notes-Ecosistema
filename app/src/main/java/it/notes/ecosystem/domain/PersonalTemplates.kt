package it.notes.ecosystem.domain

import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

data class TemplateContent(val title: String, val body: String, val tags: List<String>)

/** Models remain ordinary notes, so existing backup, history and sync preserve them. */
object PersonalTemplates {
    const val TAG = "modello"
    private val variable = Regex("\\{\\{(data|ora|giorno)\\}\\}")
    fun eligible(note: Note) = note.deletedAt == null && note.task == null && note.sketch == null && TAG in note.tags
    fun catalog(notes: List<Note>, query: String = "") = notes.filter {
        eligible(it) && (query.isBlank() || it.title.contains(query.trim(), true))
    }.sortedWith(compareBy<Note> { it.title.lowercase(Locale.ROOT) }.thenBy { it.id })
    fun expand(text: String, now: ZonedDateTime): String = variable.replace(text) {
        when (it.groupValues[1]) {
            "data" -> now.format(DateTimeFormatter.ofPattern("dd/MM/yyyy"))
            "ora" -> now.format(DateTimeFormatter.ofPattern("HH:mm"))
            else -> now.format(DateTimeFormatter.ofPattern("EEEE", Locale.ITALIAN))
        }
    }
    fun instantiate(title: String, body: String, tags: List<String>, now: ZonedDateTime, reset: Boolean): TemplateContent {
        val expanded = expand(body, now)
        val result = if (reset) {
            val chars = expanded.toCharArray()
            Checklist.parse(expanded).filter { it.completed }.forEach { chars[it.markerOffset] = ' ' }
            String(chars)
        } else expanded
        val heading = expand(title, now)
        require(heading.length <= 8000 && result.length <= 200000) { "Il modello supera i limiti di una nota." }
        return TemplateContent(heading, result, Tags.normalize(Diary.userTags(tags).filterNot { it == TAG }))
    }
    fun from(note: Note, now: ZonedDateTime, reset: Boolean): TemplateContent {
        require(eligible(note)) { "Il modello non è più disponibile. Riapri la galleria." }
        return instantiate(note.title, note.body, note.tags, now, reset)
    }
    fun capture(title: String, body: String, tags: List<String>): TemplateContent {
        require(title.isNotBlank() || body.isNotBlank()) { "Scrivi qualcosa prima di creare un modello." }
        require(title.length <= 8000 && body.length <= 200000) { "La nota supera i limiti del modello." }
        return TemplateContent(title.trim().ifBlank { "Modello personale" }, body, Tags.add(tags, TAG))
    }
}

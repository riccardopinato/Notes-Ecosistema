package it.notes.ecosystem.domain

data class ChecklistItem(val lineIndex: Int, val markerOffset: Int, val label: String, val completed: Boolean, val depth: Int = 0, val parentLine: Int? = null)
data class NoteTask(val noteId: String, val noteTitle: String, val sourceBody: String, val item: ChecklistItem)

object Checklist {
    fun hasMarker(
        body: String,
        maxChars: Int = 12_000,
    ): Boolean {
        if (body.isEmpty()) return false

        return body
            .take(maxChars)
            .lineSequence()
            .any { line ->
                val value = line.trimStart()

                value.startsWith("- [ ] ") ||
                    value.startsWith("- [x] ", ignoreCase = true) ||
                    value.startsWith("* [ ] ") ||
                    value.startsWith("* [x] ", ignoreCase = true)
            }
    }

    private val lines = Regex("""[^\r\n]*(?:\r\n|\r|\n|$)""")
    private val task = Regex("""^( {0,3}[-*+][ \t]+\[)([ xX])][ \t]+(.*)$""")

    private fun scan(body: String): Pair<List<ChecklistItem>, Boolean> {
        val result = mutableListOf<ChecklistItem>()
        var fenceChar: Char? = null
        var fenceLength = 0
        var lineIndex = 0
        for (line in lines.findAll(body)) {
            if (line.value.isEmpty()) continue
            val text = line.value.trimEnd('\r', '\n')
            val indent = text.takeWhile { it == ' ' }.length
            val trimmed = text.drop(indent)
            val char = trimmed.firstOrNull()
            val length = if (char == 96.toChar() || char == '~') trimmed.takeWhile { it == char }.length else 0
            if (indent <= 3 && length >= 3) {
                if (fenceChar == null) {
                    fenceChar = char
                    fenceLength = length
                } else if (fenceChar == char && length >= fenceLength && trimmed.drop(length).isBlank()) {
                    fenceChar = null
                    fenceLength = 0
                }
                lineIndex++
                continue
            }
            if (fenceChar == null) {
                val match = task.matchEntire(text)
                if (match != null && match.groupValues[3].isNotBlank()) {
                    val previous = result.lastOrNull()?.takeIf { it.lineIndex == lineIndex - 1 }
                    val parent = if (indent >= 2 && previous != null) previous.parentLine ?: previous.lineIndex else null
                    result += ChecklistItem(lineIndex, line.range.first + match.groups[2]!!.range.first,
                        match.groupValues[3].trim(), match.groupValues[2] != " ", if (parent == null) 0 else 1, parent)
                }
            }
            lineIndex++
        }
        return result to (fenceChar != null)
    }

    fun parse(body: String): List<ChecklistItem> = scan(body).first

    fun setCompleted(body: String, lineIndex: Int, completed: Boolean): String {
        val item = parse(body).firstOrNull { it.lineIndex == lineIndex }
            ?: error("L'attività è cambiata. Riapri la nota.")
        val marker = if (completed) "x" else " "
        return body.replaceRange(item.markerOffset, item.markerOffset + 1, marker)
    }

    fun append(body: String, label: String): String {
        require(label.isNotBlank() && '\n' !in label && '\r' !in label) { "Scrivi un'attività su una sola riga." }
        require(!scan(body).second) { "Chiudi il blocco di codice in modalità Testo prima di aggiungere attività." }
        val newline = if ("\r\n" in body) "\r\n" else "\n"
        val separator = if (body.isEmpty() || body.endsWith('\n') || body.endsWith('\r')) "" else newline
        return body + separator + "- [ ] " + label.trim()
    }
}

fun collectTasks(notes: List<Note>): List<NoteTask> = notes.filter { it.deletedAt == null && !it.archived }.flatMap { note ->
    Checklist.parse(note.body).map { NoteTask(note.id, note.title, note.body, it) }
}

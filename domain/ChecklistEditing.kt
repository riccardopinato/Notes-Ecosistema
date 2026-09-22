package it.notes.ecosystem.domain

/** Edits are applied to an exact body snapshot. Prose/fenced blocks are never moved. */
object ChecklistEditing {
    private data class Line(val text: String, val end: String)
    private fun lines(body: String) = Regex("""[^\r\n]*(?:\r\n|\r|\n|$)""").findAll(body)
        .filter { it.value.isNotEmpty() }.map { val text = it.value.trimEnd('\r', '\n'); Line(text, it.value.drop(text.length)) }.toList()
    private fun rebuild(original: List<Line>, content: List<String>) = content.mapIndexed { i, text -> text + original[i].end }.joinToString("")
    private fun selected(body: String, line: Int) = Checklist.parse(body).firstOrNull { it.lineIndex == line }
        ?: error("L'attività è cambiata. Riprova.")
    fun rename(body: String, line: Int, label: String): String {
        require(label.isNotBlank() && '\n' !in label && '\r' !in label) { "Scrivi una voce su una sola riga." }
        selected(body, line)
        val rows = lines(body); val text = rows[line].text
        val endMarker = text.indexOf(']')
        val contents = rows.map { it.text }.toMutableList()
        contents[line] = text.substring(0, endMarker + 1) + " " + label.trim()
        return rebuild(rows, contents)
    }
    fun addChild(body: String, line: Int, label: String): String {
        require(label.isNotBlank() && '\n' !in label && '\r' !in label) { "Scrivi una voce su una sola riga." }
        val item = selected(body, line); val root = item.parentLine ?: item.lineIndex
        val end = Checklist.parse(body).lastOrNull { it.parentLine == root }?.lineIndex ?: root
        val rows = lines(body).toMutableList()
        val newline = rows[end].end.ifEmpty { if ("\r\n" in body) "\r\n" else "\n" }
        val last = rows[end].end
        rows[end] = rows[end].copy(end = newline)
        rows.add(end + 1, Line("  - [ ] " + label.trim(), last.ifEmpty { "" }))
        return rows.joinToString("") { it.text + it.end }
    }
    fun move(body: String, from: Int, to: Int): String {
        if (from == to) return body
        val items = Checklist.parse(body); val source = selected(body, from); val target = selected(body, to)
        require(source.parentLine == target.parentLine) { "Sposta tra voci dello stesso livello e della stessa sezione." }
        fun last(item: ChecklistItem) = if (item.depth == 0) items.lastOrNull { it.parentLine == item.lineIndex }?.lineIndex ?: item.lineIndex else item.lineIndex
        val sourceEnd = last(source); val targetEnd = last(target)
        val range = minOf(from, to)..maxOf(sourceEnd, targetEnd)
        require(range.all { n -> items.any { it.lineIndex == n } }) { "Non puoi trascinare attraverso testo o blocchi di codice." }
        val rows = lines(body); val order = rows.indices.toMutableList(); val moving = (from..sourceEnd).toList()
        order.removeAll(moving.toSet())
        val insert = if (from < to) order.indexOf(targetEnd) + 1 else order.indexOf(to)
        order.addAll(insert, moving)
        return rebuild(rows, order.map { n -> if (items.any { it.lineIndex == n && it.depth == 0 }) rows[n].text.trimStart(' ') else rows[n].text })
    }
    fun completedLast(body: String): String {
        val rows = lines(body); val items = Checklist.parse(body); val contents = rows.map { it.text }.toMutableList()
        val runs = mutableListOf<MutableList<ChecklistItem>>()
        items.forEach { item ->
            if (runs.lastOrNull()?.lastOrNull()?.lineIndex != item.lineIndex - 1) runs.add(mutableListOf())
            runs.last().add(item)
        }
        runs.forEach { run ->
            val roots = run.filter { it.depth == 0 }.sortedBy { it.completed }
            val ordered = roots.flatMap { root -> listOf(root) + run.filter { it.parentLine == root.lineIndex }.sortedBy { it.completed } }
            check(ordered.size == run.size)
            run.map { it.lineIndex }.zip(ordered).forEach { (position, item) -> contents[position] = if (item.depth == 0) rows[item.lineIndex].text.trimStart(' ') else rows[item.lineIndex].text }
        }
        return rebuild(rows, contents)
    }
}

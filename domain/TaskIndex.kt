package it.notes.ecosystem.domain

/** Single-collector cache: removed/trashed bodies are released on each update. */
class TaskIndex(private val parse: (String) -> List<ChecklistItem> = Checklist::parse) {
    private data class Entry(val body: String, val items: List<ChecklistItem>)
    private var entries = emptyMap<String, Entry>()

    fun update(notes: List<Note>): List<NoteTask> {
        val next = HashMap<String, Entry>()
        val result = ArrayList<NoteTask>()
        for (note in notes) {
            if (note.deletedAt != null || note.archived || note.task != null || note.sketch != null) continue
            val cached = entries[note.id]
            val entry = if (cached != null && cached.body == note.body) cached
                else Entry(note.body, parse(note.body))
            next[note.id] = entry
            entry.items.forEach { result.add(NoteTask(note.id, note.title, note.body, it)) }
        }
        entries = next
        return result
    }
}

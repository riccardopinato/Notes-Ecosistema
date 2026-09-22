package it.notes.ecosystem.domain

enum class TaskPresence { ANY, HAS_TASKS, OPEN_TASKS, NO_TASKS }
data class SearchOptions(
    val tags: List<String> = emptyList(),
    val allTags: Boolean = true,
    val favoritesOnly: Boolean = false,
    val pinnedOnly: Boolean = false,
    val tasks: TaskPresence = TaskPresence.ANY,
)
fun searchNotes(notes: List<Note>, filter: NoteFilter, query: String = "", collectionId: String? = null,
    options: SearchOptions = SearchOptions()): List<Note> {
    val tags = Tags.normalize(options.tags)
    return filterNotes(notes, filter, query, collectionId).filter { n ->
        (!options.favoritesOnly || n.favorite) && (!options.pinnedOnly || n.pinned) &&
            (tags.isEmpty() || if (options.allTags) tags.all { it in n.tags } else tags.any { it in n.tags }) &&
            when (options.tasks) {
                TaskPresence.ANY -> true
                TaskPresence.HAS_TASKS -> Checklist.parse(n.body).isNotEmpty()
                TaskPresence.OPEN_TASKS -> Checklist.parse(n.body).any { !it.completed }
                TaskPresence.NO_TASKS -> Checklist.parse(n.body).isEmpty()
            }
    }
}

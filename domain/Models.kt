package it.notes.ecosystem.domain

import kotlinx.coroutines.flow.Flow

data class Note(
    val id: String,
    val title: String,
    val body: String,
    val collectionId: String? = null,
    val favorite: Boolean = false,
    val createdAt: Long,
    val updatedAt: Long,
    val deletedAt: Long? = null,
    val pinned: Boolean = false,
    val archived: Boolean = false,
    val tags: List<String> = emptyList(),
    val task: TaskDetails? = null,
    val sketch: SketchInfo? = null,
)
data class Collection(val id: String, val name: String)

data class Draft(val id: String, val title: String, val body: String, val collectionId: String?, val updatedAt: Long, val tags: List<String> = emptyList())
data class BackupSnapshot(val notes: List<Note>, val collections: List<Collection>, val drafts: List<Draft>)

data class NoteRevision(val revisionId: String, val noteId: String, val title: String, val body: String,
    val collectionId: String?, val savedAt: Long, val tags: List<String> = emptyList())

interface NotesRepository {
    suspend fun createTemplate(content: TemplateContent): String { error("Modelli non disponibili") }
    suspend fun cleanupAttachments(cleanup: (Set<String>)->Int): Int { error("Pulizia allegati non disponibile") }

    fun beginSketchEditing(id: String): Boolean = false
    fun queueSketch(id: String, expectedBody: String?, title: String, body: String, info: SketchInfo): kotlinx.coroutines.Deferred<Note> { error("Sketchbook non disponibile") }
    fun beginWhiteboardEditing(id: String): Boolean = beginSketchEditing(id)
    fun queueWhiteboard(id: String, expectedBody: String?, title: String, body: String, info: SketchInfo): kotlinx.coroutines.Deferred<Note> { error("Whiteboard non disponibile") }
    suspend fun savePlannedTask(expected: Note?, id: String, title: String, body: String, details: TaskDetails) { error("Attività non supportate") }
    suspend fun updatePlannedTask(expected: Note, details: TaskDetails, deleted: Boolean = false) { error("Attività non supportate") }
    suspend fun addFocusSession(id:String,session:FocusSession) { addFocus(id,session.id,session.seconds) }
    suspend fun snoozeReminder(id:String,expectedAt:Long,nextAt:Long):Boolean = false
    suspend fun addFocus(id: String, sessionId: String, seconds: Long) { error("Focus non supportato") }
    suspend fun history(id: String): List<NoteRevision> = emptyList()
    fun beginEditing(id: String) {}
    fun endEditing(id: String) {}
    val drafts: Flow<List<Draft>>
    suspend fun getDraft(id: String): Draft?
    fun queueDraft(draft: Draft): kotlinx.coroutines.Deferred<Unit>
    suspend fun discardDraft(id: String)
    suspend fun snapshot(): BackupSnapshot
    suspend fun importCopies(data: BackupSnapshot)
    val notes: Flow<List<Note>>
    val collections: Flow<List<Collection>>
    suspend fun get(id: String): Note?
    suspend fun save(id: String, title: String, body: String, collectionId: String?)
    suspend fun saveTagged(id: String, title: String, body: String, collectionId: String?, tags: List<String>) {
        require(tags.isEmpty()) { "Tag non supportati dal repository." }; save(id, title, body, collectionId)
    }
    suspend fun bulkEdit(expected: List<Note>, change: BulkChange): Int { error("Operazioni multiple non supportate.") }
    suspend fun setTaskCompleted(id: String, expectedBody: String, lineIndex: Int, completed: Boolean)
    suspend fun setPinned(id: String, pinned: Boolean) { error("Operazione non disponibile") }
    suspend fun setArchived(id: String, archived: Boolean) { error("Operazione non disponibile") }
    suspend fun toggleFavorite(id: String)
    suspend fun trash(id: String)
    suspend fun restore(id: String)
    suspend fun renameCollection(expected: Collection, name: String) { error("Rinomina non disponibile") }
    suspend fun deleteEmptyCollection(expected: Collection) { error("Eliminazione non disponibile") }
    suspend fun createCollection(name: String)
}

enum class NoteFilter { ALL, INBOX, FAVORITES, TRASH, ARCHIVE }

fun filterNotes(notes: List<Note>, filter: NoteFilter, query: String = "", collectionId: String? = null): List<Note> {
    val needle = query.trim()
    return notes.filter { note ->
        val visible = when (filter) {
            NoteFilter.TRASH -> note.deletedAt != null
            NoteFilter.ARCHIVE -> note.deletedAt == null && note.archived
            else -> note.deletedAt == null && !note.archived
        }
        note.task == null && visible && when (filter) {
            NoteFilter.INBOX -> note.collectionId == null
            NoteFilter.FAVORITES -> note.favorite
            else -> true
        } && (collectionId == null || note.collectionId == collectionId) &&
            (needle.isEmpty() || note.title.contains(needle, ignoreCase = true) || (note.sketch == null && note.body.contains(needle, ignoreCase = true)) || note.tags.any { it.contains(needle.removePrefix("#"), ignoreCase = true) })
    }.sortedWith(compareByDescending<Note> { it.pinned }.thenByDescending { it.favorite }.thenByDescending { it.updatedAt }.thenBy { it.id })
}

class SaveNote(private val repository: NotesRepository) {
    suspend operator fun invoke(id: String, title: String, body: String, collectionId: String?, tags: List<String>? = null) {
        require(title.isNotBlank() || body.isNotBlank()) { "Scrivi un titolo o un appunto prima di salvare." }
        if (tags == null) repository.save(id, title.trim(), body, collectionId)
        else repository.saveTagged(id, title.trim(), body, collectionId, Tags.normalize(tags))
    }
}

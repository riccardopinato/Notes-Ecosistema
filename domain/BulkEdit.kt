package it.notes.ecosystem.domain

enum class BulkAction { ARCHIVE, UNARCHIVE, PIN, UNPIN, FAVORITE, UNFAVORITE, MOVE, ADD_TAG, REMOVE_TAG, TRASH, RESTORE }
data class BulkChange(val action: BulkAction, val collectionId: String? = null, val tag: String? = null)

/** Pure preflight: the repository persists the complete plan in one transaction or nothing. */
fun planBulkEdit(notes: List<Note>, change: BulkChange, now: Long): List<Note> {
    require(notes.isNotEmpty() && notes.size <= 500) { "Seleziona da 1 a 500 note." }
    require(notes.map { it.id }.distinct().size == notes.size) { "Selezione duplicata." }
    require(now >= 0)
    val tag = if (change.action in listOf(BulkAction.ADD_TAG, BulkAction.REMOVE_TAG)) Tags.name(change.tag.orEmpty()) else null
    return notes.map { n ->
        check(if (change.action == BulkAction.RESTORE) n.deletedAt != null else n.deletedAt == null) {
            "La selezione contiene note con uno stato non compatibile. Aggiorna la selezione."
        }
        val result = when (change.action) {
            BulkAction.ARCHIVE -> n.copy(archived = true)
            BulkAction.UNARCHIVE -> n.copy(archived = false)
            BulkAction.PIN -> n.copy(pinned = true)
            BulkAction.UNPIN -> n.copy(pinned = false)
            BulkAction.FAVORITE -> n.copy(favorite = true)
            BulkAction.UNFAVORITE -> n.copy(favorite = false)
            BulkAction.MOVE -> n.copy(collectionId = change.collectionId)
            BulkAction.ADD_TAG -> n.copy(tags = Tags.add(n.tags, tag!!))
            BulkAction.REMOVE_TAG -> n.copy(tags = n.tags.filterNot { it == tag })
            BulkAction.TRASH -> n.copy(deletedAt = now)
            BulkAction.RESTORE -> n.copy(deletedAt = null)
        }
        if (result == n) n else result.copy(updatedAt = now)
    }
}

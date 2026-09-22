package it.notes.ecosystem.domain

import java.util.Locale

enum class NoteOrder(val label: String) {
    RECENT("Ultima modifica"), CREATED("Più recenti"), OLDEST("Meno recenti"), TITLE("Titolo A–Z")
}

/** Pinned notes always lead. Favorite precedence is retained for the default order only. */
fun orderNotes(notes: List<Note>, order: NoteOrder): List<Note> {
    val pinned = compareByDescending<Note> { it.pinned }
    val comparator = when (order) {
        NoteOrder.RECENT -> pinned.thenByDescending { it.favorite }.thenByDescending { it.updatedAt }
        NoteOrder.CREATED -> pinned.thenByDescending { it.createdAt }
        NoteOrder.OLDEST -> pinned.thenBy { it.createdAt }
        NoteOrder.TITLE -> pinned.thenBy { it.title.trim().ifBlank { "Senza titolo" }.lowercase(Locale.ROOT) }
    }
    return notes.sortedWith(comparator.thenBy { it.id })
}

data class SavedSearch(
    val id: String, val name: String, val query: String = "",
    val filter: NoteFilter = NoteFilter.ALL, val collectionId: String? = null,
    val options: SearchOptions = SearchOptions(), val kind: String = "Tutte",
    val order: NoteOrder = NoteOrder.RECENT,
)

fun validateSavedSearch(search: SavedSearch): SavedSearch {
    require(search.id.isNotBlank() && search.id.length <= 200) { "Identificatore ricerca non valido." }
    val name = search.name.trim()
    require(name.isNotEmpty() && name.length <= 80 && name.none { it.isISOControl() }) { "Usa un nome di 1–80 caratteri." }
    require(search.query.length <= 8000 && '\u0000' !in search.query) { "Ricerca troppo lunga o non valida." }
    require(search.collectionId == null || search.collectionId.isNotBlank() && search.collectionId.length <= 200)
    require(search.kind in listOf("Tutte", "Testo", "Checklist", "Disegni"))
    return search.copy(name = name, options = search.options.copy(tags = Tags.normalize(search.options.tags)))
}

fun upsertSavedSearch(current: List<SavedSearch>, incoming: SavedSearch): List<SavedSearch> {
    val value = validateSavedSearch(incoming)
    require(current.none { it.id != value.id && it.name.equals(value.name, ignoreCase = true) }) { "Esiste già una ricerca con questo nome." }
    require(current.size < 30 || current.any { it.id == value.id }) { "Puoi salvare fino a 30 ricerche." }
    return if (current.any { it.id == value.id }) current.map { if (it.id == value.id) value else it }
    else current + value
}

fun collectionName(raw: String, existing: List<Collection>, exceptId: String? = null): String {
    val value = raw.trim()
    require(value.isNotEmpty() && value.length <= 120 && value.none { it.isISOControl() }) { "Usa un nome di 1–120 caratteri." }
    require(existing.none { it.id != exceptId && it.name.equals(value, ignoreCase = true) }) { "Esiste già una raccolta con questo nome." }
    return value
}

data class CollectionOverview(val active: Int, val archived: Int, val trash: Int, val drafts: Int) {
    val empty: Boolean get() = active + archived + trash + drafts == 0
}
fun collectionOverview(id: String, notes: List<Note>, drafts: List<Draft>): CollectionOverview {
    val rows = notes.filter { it.collectionId == id }
    return CollectionOverview(rows.count { it.deletedAt == null && !it.archived },
        rows.count { it.deletedAt == null && it.archived }, rows.count { it.deletedAt != null }, drafts.count { it.collectionId == id })
}

/** One pass per source, regardless of the number of collections. */
fun collectionOverviews(notes: List<Note>, drafts: List<Draft>): Map<String,CollectionOverview> {
    val counts = mutableMapOf<String,IntArray>()
    notes.forEach { n -> n.collectionId?.let { id ->
        val row=counts.getOrPut(id){IntArray(4)}
        row[if(n.deletedAt!=null) 2 else if(n.archived) 1 else 0]++
    } }
    drafts.forEach { d -> d.collectionId?.let { counts.getOrPut(it){IntArray(4)}[3]++ } }
    return counts.mapValues { (_,v) -> CollectionOverview(v[0],v[1],v[2],v[3]) }
}

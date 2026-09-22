package it.notes.ecosystem.domain

import org.junit.Assert.*
import org.junit.Test

class FilterNotesTest {
    private fun note(id: String, body: String = "", favorite: Boolean = false, collection: String? = null, deleted: Long? = null, updated: Long = 10) =
        Note(id, "Appunto", body, collection, favorite, 1, updated, deleted)

    @Test fun trashNeverLeaksIntoLibrarySearchOrFavorites() {
        val notes = listOf(note("live", "segreto"), note("trash", "segreto", favorite = true, deleted = 20))
        assertEquals(listOf("live"), filterNotes(notes, NoteFilter.ALL, "segreto").map { it.id })
        assertTrue(filterNotes(notes, NoteFilter.FAVORITES).isEmpty())
        assertEquals(listOf("trash"), filterNotes(notes, NoteFilter.TRASH).map { it.id })
    }
    @Test fun inboxContainsOnlyUnassignedLiveNotes() {
        val notes = listOf(note("inbox"), note("filed", collection = "work"), note("trash", deleted = 20))
        assertEquals(listOf("inbox"), filterNotes(notes, NoteFilter.INBOX).map { it.id })
    }
    @Test fun searchTreatsWildcardsLiterallyAndIgnoresCase() {
        val notes = listOf(note("literal", "Budget 20%_CAFÈ"), note("other", "Budget 200"))
        assertEquals(listOf("literal"), filterNotes(notes, NoteFilter.ALL, "  %_cafè ").map { it.id })
    }
    @Test fun collectionAndFavoritesFiltersCombine() {
        val notes = listOf(note("one", favorite = true, collection = "a"),
            note("two", favorite = true, collection = "b"), note("three", collection = "a"))
        assertEquals(listOf("one"), filterNotes(notes, NoteFilter.FAVORITES, collectionId = "a").map { it.id })
    }
    @Test fun favoritesPrecedeMoreRecentNotes() {
        val notes = listOf(note("recent", updated = 100), note("star", favorite = true, updated = 5))
        assertEquals(listOf("star", "recent"), filterNotes(notes, NoteFilter.ALL).map { it.id })
    }
}

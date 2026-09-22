package it.notes.ecosystem.domain
import org.junit.Assert.*
import org.junit.Test
class OrganizationTest {
    private fun note(id: String, pinned: Boolean = false, archived: Boolean = false, favorite: Boolean = false) = Note(id,id,"- [ ] Task",favorite=favorite,createdAt=1,updatedAt=2,pinned=pinned,archived=archived)
    @Test fun pinnedPrecedesFavorite() { assertEquals(listOf("p","f","n"),filterNotes(listOf(note("f",favorite=true),note("n"),note("p",pinned=true)),NoteFilter.ALL).map{it.id}) }
    @Test fun archiveExcludedFromOrdinaryFilters() { for (filter in listOf(NoteFilter.ALL,NoteFilter.INBOX,NoteFilter.FAVORITES)) assertTrue(filterNotes(listOf(note("a",archived=true,favorite=true)),filter).isEmpty()) }
    @Test fun archiveSearchAndTrashAreDistinct() {
        val a=note("archived",archived=true);val t=a.copy(id="trashed",deletedAt=3)
        assertEquals(listOf(a),filterNotes(listOf(a,t),NoteFilter.ARCHIVE,"arch"))
        assertEquals(listOf(t),filterNotes(listOf(a,t),NoteFilter.TRASH))
    }
    @Test fun archivedTasksDisappearAndReturn() {
        val index=TaskIndex();val n=note("n")
        assertEquals(1,index.update(listOf(n)).size)
        assertTrue(index.update(listOf(n.copy(archived=true))).isEmpty())
        assertEquals(1,index.update(listOf(n)).size)
        assertTrue(collectTasks(listOf(n.copy(archived=true))).isEmpty())
    }
    @Test fun pinOrderIsDeterministic() { assertEquals(listOf("a","b"),filterNotes(listOf(note("b",pinned=true),note("a",pinned=true)),NoteFilter.ALL).map{it.id}) }
}

package it.notes.ecosystem.domain
import org.junit.Assert.*
import org.junit.Test
class AdvancedSearchTest {
    private fun n(id: String, tags: List<String> = emptyList(), body: String = "Report") = Note(id,id,body,"work",true,1,2,pinned=true,tags=tags)
    @Test fun allFiltersCombineWithAnd() {
        val a=n("a",listOf("lavoro","urgente"),"Report\n- [ ] Invia")
        val b=a.copy(id="b",pinned=false);val c=a.copy(id="c",collectionId="other")
        assertEquals(listOf(a),searchNotes(listOf(a,b,c),NoteFilter.ALL,"report","work",SearchOptions(listOf("lavoro","urgente"),true,true,true,TaskPresence.OPEN_TASKS)))
    }
    @Test fun tagAndOrAreDifferent() {
        val notes=listOf(n("a",listOf("a")),n("ab",listOf("a","b")))
        assertEquals(1,searchNotes(notes,NoteFilter.ALL,options=SearchOptions(listOf("a","b"))).size)
        assertEquals(2,searchNotes(notes,NoteFilter.ALL,options=SearchOptions(listOf("a","b"),allTags=false)).size)
    }
    @Test fun textSearchIncludesTags() { assertEquals(1,searchNotes(listOf(n("a",listOf("lavoro"))),NoteFilter.ALL,"#lavo").size) }
    @Test fun codeFenceIsNotAnActivity() {
        val note=n("a",body="```\n- [ ] code\n```")
        assertTrue(searchNotes(listOf(note),NoteFilter.ALL,options=SearchOptions(tasks=TaskPresence.HAS_TASKS)).isEmpty())
        assertEquals(1,searchNotes(listOf(note),NoteFilter.ALL,options=SearchOptions(tasks=TaskPresence.NO_TASKS)).size)
    }
    @Test fun completedTasksAreNotPending() { assertTrue(searchNotes(listOf(n("a",body="- [x] done")),NoteFilter.ALL,options=SearchOptions(tasks=TaskPresence.OPEN_TASKS)).isEmpty()) }
    @Test fun archivedAndTrashScopesRemainSeparate() {
        val a=n("a",listOf("x")).copy(archived=true);val t=a.copy(id="t",deletedAt=9)
        assertEquals(listOf(a),searchNotes(listOf(a,t),NoteFilter.ARCHIVE,options=SearchOptions(listOf("x"))))
        assertEquals(listOf(t),searchNotes(listOf(a,t),NoteFilter.TRASH,options=SearchOptions(listOf("x"))))
    }
    @Test fun literalSpecialCharactersStayLiteral() { assertEquals(1,searchNotes(listOf(n("a",body="100%_ok")),NoteFilter.ALL,"%_").size) }
    @Test fun typingNarrowsPhraseAndDeletingRestoresMatches() {
        val notes=listOf(n("a",body="Casa di Anna"),n("b",body="Casa di Luca"),n("c",body="Casa al mare"),n("d",body="Ufficio"))
        fun ids(query:String)=searchNotes(notes,NoteFilter.ALL,query).map {it.id}.toSet()
        assertEquals(setOf("a","b","c"),ids("Casa"))
        assertEquals(setOf("a","b"),ids("Casa di"))
        assertEquals(setOf("a"),ids("Casa di Anna"))
        assertEquals(setOf("a"),ids("casa DI anna"))
        assertTrue(ids("Casa di Anna inesistente").isEmpty())
        assertEquals(setOf("a","b","c"),ids("Casa"))
        assertEquals(setOf("a","b","c","d"),ids(""))
    }
}

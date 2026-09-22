package it.notes.ecosystem.domain

import it.notes.ecosystem.data.SavedSearchCodec
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class LibraryOrganizationTest {
    private fun n(id:String,title:String=id,created:Long=1,updated:Long=1,pinned:Boolean=false,favorite:Boolean=false) =
        Note(id,title,"Casa di Anna",createdAt=created,updatedAt=updated,pinned=pinned,favorite=favorite)
    private fun saved(id:String="a",name:String="Casa")=SavedSearch(id,name,"Casa di Anna",NoteFilter.ARCHIVE,"c",
        SearchOptions(listOf("lavoro"),false,true,true,TaskPresence.OPEN_TASKS),"Checklist",NoteOrder.TITLE)
    @Test fun defaultOrderPreservesPinnedFavoriteAndUpdatedPrecedence() {
        val rows=listOf(n("recent",updated=99),n("fav",favorite=true),n("pin",pinned=true))
        assertEquals(listOf("pin","fav","recent"),orderNotes(rows,NoteOrder.RECENT).map{it.id})
    }
    @Test fun titleOrderIgnoresFavoritePrecedence() {
        assertEquals(listOf("a","z"),orderNotes(listOf(n("z",favorite=true),n("a")),NoteOrder.TITLE).map{it.id})
    }
    @Test fun pinnedAlwaysFirstInEveryOrder() {
        NoteOrder.entries.forEach { order -> assertEquals("z",orderNotes(listOf(n("a",created=9),n("z",pinned=true)),order).first().id) }
    }
    @Test fun chronologicalOrdersUseCreationInsteadOfModification() {
        val rows=listOf(n("old",created=1,updated=9),n("new",created=2,updated=1))
        assertEquals("new",orderNotes(rows,NoteOrder.CREATED).first().id);assertEquals("old",orderNotes(rows,NoteOrder.OLDEST).first().id)
    }
    @Test fun equalSortKeysUseStableIds() { assertEquals(listOf("a","b"),orderNotes(listOf(n("b","same"),n("a","same")),NoteOrder.TITLE).map{it.id}) }
    @Test fun titleSortingIgnoresCaseAndWhitespace() { assertEquals(listOf("a","b"),orderNotes(listOf(n("b","beta"),n("a"," ALFA ")),NoteOrder.TITLE).map{it.id}) }
    @Test fun orderingDoesNotDropArchivedOrTrashRows() { val rows=listOf(n("a").copy(archived=true),n("b").copy(deletedAt=2));assertEquals(rows.toSet(),orderNotes(rows,NoteOrder.CREATED).toSet()) }
    @Test fun savedSearchRoundTripPreservesEveryFilter() { val s=saved();assertEquals(listOf(s),SavedSearchCodec.decode(SavedSearchCodec.encode(listOf(s)))) }
    @Test fun emptyAndUnsetPreferencesAreValid() { assertTrue(SavedSearchCodec.decode(null).isEmpty());assertTrue(SavedSearchCodec.decode(SavedSearchCodec.encode(emptyList())).isEmpty()) }
    @Test fun savedNameIsTrimmed() { assertEquals("Casa",validateSavedSearch(saved(name=" Casa ")).name) }
    @Test(expected=IllegalArgumentException::class) fun duplicateNamesIgnoreCase() {upsertSavedSearch(listOf(saved()),saved("b","CASA"))}
    @Test fun renamingKeepsSearchPositionAndQuery() {val a=saved();val b=saved("b","Studio");val result=upsertSavedSearch(listOf(a,b),a.copy(name="Casa nuova"));assertEquals(listOf("a","b"),result.map{it.id});assertEquals(a.query,result.first().query)}
    @Test(expected=IllegalArgumentException::class) fun thirtySearchLimitEnforced() {upsertSavedSearch((0..29).map{saved("$it","Ricerca $it")},saved("extra","Extra"))}
    @Test fun renameAtCapacityIsAllowed() {val values=(0..29).map{saved("$it","Ricerca $it")};assertEquals(30,upsertSavedSearch(values,values.first().copy(name="Nuovo nome")).size)}
    @Test(expected=IllegalArgumentException::class) fun unknownStorageVersionRejected() {SavedSearchCodec.decode("{\"version\":2,\"searches\":[]}")}
    @Test(expected=IllegalArgumentException::class) fun duplicateStoredIdsRejected() {
        val obj=JSONObject(SavedSearchCodec.encode(listOf(saved())));val array=obj.getJSONArray("searches");array.put(array.getJSONObject(0));SavedSearchCodec.decode(obj.toString())
    }
    @Test(expected=IllegalArgumentException::class) fun invalidContentKindRejected() {validateSavedSearch(saved().copy(kind="Unknown"))}
    @Test(expected=IllegalArgumentException::class) fun overlongQueryRejected() {validateSavedSearch(saved().copy(query="x".repeat(8001)))}
    @Test(expected=IllegalArgumentException::class) fun nullByteQueryRejected() {validateSavedSearch(saved().copy(query="Casa\u0000"))}
    @Test(expected=IllegalArgumentException::class) fun blankSearchNameRejected() {validateSavedSearch(saved(name=" "))}
    @Test fun collectionNameIsTrimmed() {assertEquals("Casa",collectionName(" Casa ",emptyList()))}
    @Test(expected=IllegalArgumentException::class) fun collectionCaseDuplicateRejected() {collectionName("CASA",listOf(Collection("c","Casa")))}
    @Test fun collectionCanChangeOwnCapitalization() {assertEquals("CASA",collectionName("CASA",listOf(Collection("c","Casa")),"c"))}
    @Test(expected=IllegalArgumentException::class) fun collectionControlCharactersRejected() {collectionName("Casa\nAnna",emptyList())}
    @Test(expected=IllegalArgumentException::class) fun collectionNameTooLongRejected() {collectionName("a".repeat(121),emptyList())}
    @Test fun collectionCountsDoNotTreatTrashAsEmpty() {
        val summary=collectionOverview("c",listOf(n("a").copy(collectionId="c",deletedAt=2)),emptyList());assertFalse(summary.empty);assertEquals(1,summary.trash)
    }
    @Test fun collectionCountsSeparateArchiveAndDrafts() {
        val rows=listOf(n("a").copy(collectionId="c"),n("b").copy(collectionId="c",archived=true),n("other"))
        val summary=collectionOverview("c",rows,listOf(Draft("d","","","c",1)))
        assertEquals(CollectionOverview(1,1,0,1),summary)
    }
    @Test fun aggregateCountsMatchSingleCollectionCounts() {
        val rows=listOf(n("a").copy(collectionId="c"),n("b").copy(collectionId="d",deletedAt=2))
        val drafts=listOf(Draft("draft","","","c",1));val all=collectionOverviews(rows,drafts)
        listOf("c","d").forEach {assertEquals(collectionOverview(it,rows,drafts),all[it])}
    }
    @Test fun savedQueryRemainsLiteralOnRestore() {
        val original=saved().copy(filter=NoteFilter.ALL,collectionId=null,options=SearchOptions(),kind="Tutte")
        val restored=SavedSearchCodec.decode(SavedSearchCodec.encode(listOf(original))).single()
        assertEquals(listOf("match"),searchNotes(listOf(n("match"),n("other").copy(body="Casa bella")),restored.filter,restored.query,restored.collectionId,restored.options).map{it.id})
    }
    @Test fun unicodeAndQuotesRoundTrip() {val s=saved(name="Caffè «casa»").copy(query="Casa \"Anna\"\nCaffè");assertEquals(s,SavedSearchCodec.decode(SavedSearchCodec.encode(listOf(s))).single())}
}

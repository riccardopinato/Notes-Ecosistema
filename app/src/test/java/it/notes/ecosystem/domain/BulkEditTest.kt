package it.notes.ecosystem.domain
import org.junit.Assert.*
import org.junit.Test
class BulkEditTest {
    private fun n(id: String="a")=Note(id,"Title","Body",createdAt=1,updatedAt=2,tags=listOf("work"))
    @Test fun archiveRetainsTextAndTags() { val result=planBulkEdit(listOf(n()),BulkChange(BulkAction.ARCHIVE),3).single();assertTrue(result.archived);assertEquals("Body",result.body);assertEquals(listOf("work"),result.tags) }
    @Test fun allFlagsHaveExplicitSetAndClearActions() {
        for ((set,clear) in listOf(BulkAction.PIN to BulkAction.UNPIN,BulkAction.ARCHIVE to BulkAction.UNARCHIVE,BulkAction.FAVORITE to BulkAction.UNFAVORITE)) {
            val changed=planBulkEdit(listOf(n()),BulkChange(set),3)
            assertEquals(n().copy(updatedAt=4),planBulkEdit(changed,BulkChange(clear),4).single())
        }
    }
    @Test fun moveToInboxPreservesOtherMetadata() { val result=planBulkEdit(listOf(n().copy(collectionId="c")),BulkChange(BulkAction.MOVE),4).single();assertNull(result.collectionId);assertEquals(n().tags,result.tags) }
    @Test fun addAndRemoveCanonicalTag() {
        val added=planBulkEdit(listOf(n()),BulkChange(BulkAction.ADD_TAG,tag="#Urgente"),3)
        assertEquals(listOf("urgente","work"),added.single().tags)
        assertEquals(listOf("work"),planBulkEdit(added,BulkChange(BulkAction.REMOVE_TAG,tag="URGENTE"),4).single().tags)
    }
    @Test fun noOpDoesNotChangeTimestamp() { assertEquals(n(),planBulkEdit(listOf(n()),BulkChange(BulkAction.ADD_TAG,tag="work"),99).single()) }
    @Test fun trashAndRestorePreserveMetadata() { val deleted=planBulkEdit(listOf(n()),BulkChange(BulkAction.TRASH),3);assertEquals(3L,deleted.single().deletedAt);assertEquals(n().copy(updatedAt=4),planBulkEdit(deleted,BulkChange(BulkAction.RESTORE),4).single()) }
    @Test fun mixedTrashSelectionIsRejected() { rejected { planBulkEdit(listOf(n(),n("b").copy(deletedAt=3)),BulkChange(BulkAction.PIN),5) } }
    @Test fun duplicateAndEmptySelectionRejected() { rejected { planBulkEdit(emptyList(),BulkChange(BulkAction.PIN),3) };rejected { planBulkEdit(listOf(n(),n()),BulkChange(BulkAction.PIN),3) } }
    @Test fun tagOverflowOnOneNoteRejectsWholePlan() { rejected { planBulkEdit(listOf(n(),n("b").copy(tags=(1..20).map { "t$it" })),BulkChange(BulkAction.ADD_TAG,tag="extra"),3) } }
    @Test fun selectionLimitIsEnforced() { rejected { planBulkEdit((1..501).map { n(it.toString()) },BulkChange(BulkAction.PIN),3) } }
    private fun rejected(block: () -> Unit) { try { block();fail() } catch (_:IllegalArgumentException) {} catch (_:IllegalStateException) {} }
}

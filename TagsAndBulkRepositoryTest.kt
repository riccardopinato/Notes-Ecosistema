package it.notes.ecosystem.data

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import it.notes.ecosystem.domain.*
import kotlinx.coroutines.test.runTest
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class TagsAndBulkRepositoryTest {
    private lateinit var db: NotesDatabase
    private lateinit var repo: LocalNotesRepository
    @Before fun setup() {
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(), NotesDatabase::class.java).build()
        repo = LocalNotesRepository(db)
    }
    @After fun cleanup() = db.close()
    private suspend fun seed() {
        repo.saveTagged("a", "A", "Corpo", null, listOf("lavoro"))
        repo.save("b", "B", "Altro", null)
    }
    private suspend fun selection() = listOf(repo.get("a")!!, repo.get("b")!!)
    private suspend fun mustFail(block: suspend () -> Unit) {
        try { block() } catch (e: IllegalArgumentException) { return }
        catch (e: IllegalStateException) { return }
        fail("L'operazione doveva essere rifiutata")
    }
    @Test fun legacySavePreservesTagsAndTaggedSavePreservesHistory() = runTest {
        seed(); repo.save("a", "A", "Modificato", null)
        assertEquals(listOf("lavoro"), repo.get("a")!!.tags)
        repo.saveTagged("a", "A", "Modificato", null, listOf("casa"))
        assertEquals(listOf("lavoro"), repo.history("a").first().tags)
    }
    @Test fun draftAndImportKeepTags() = runTest {
        seed(); repo.queueDraft(Draft("a", "Bozza", "Corpo", null, 1, listOf("bozza"))).await()
        assertEquals(listOf("bozza"), repo.getDraft("a")!!.tags)
        repo.importCopies(repo.snapshot())
        val copies = repo.snapshot()
        assertEquals(2, copies.notes.count { it.tags == listOf("lavoro") })
        assertEquals(2, copies.drafts.count { it.tags == listOf("bozza") })
    }
    @Test fun staleSecondNotePreventsFirstNoteWrite() = runTest {
        seed(); val expected = selection(); repo.save("b", "B", "Nuovo", null)
        mustFail { repo.bulkEdit(expected, BulkChange(BulkAction.ARCHIVE)) }
        assertFalse(repo.get("a")!!.archived); assertFalse(repo.get("b")!!.archived)
    }
    @Test fun draftProtectsWholeBatch() = runTest {
        seed(); val expected = selection()
        repo.queueDraft(Draft("b", "Bozza", "Testo", null, 1)).await()
        mustFail { repo.bulkEdit(expected, BulkChange(BulkAction.TRASH)) }
        assertNull(repo.get("a")!!.deletedAt); assertNotNull(repo.getDraft("b"))
    }
    @Test fun editorProtectsWholeBatchThenReleaseAllowsIt() = runTest {
        seed(); val expected = selection(); repo.beginEditing("b")
        mustFail { repo.bulkEdit(expected, BulkChange(BulkAction.PIN)) }
        assertFalse(repo.get("a")!!.pinned); repo.endEditing("b")
        assertEquals(2, repo.bulkEdit(expected, BulkChange(BulkAction.PIN)))
    }
    @Test fun missingCollectionPreventsEveryWrite() = runTest {
        seed(); mustFail { repo.bulkEdit(selection(), BulkChange(BulkAction.MOVE, collectionId = "missing")) }
        assertNull(repo.get("a")!!.collectionId); assertNull(repo.get("b")!!.collectionId)
    }
    @Test fun tagOverflowPreventsEveryWrite() = runTest {
        seed(); repo.saveTagged("b", "B", "Altro", null, (1..20).map { "tag$it" })
        mustFail { repo.bulkEdit(selection(), BulkChange(BulkAction.ADD_TAG, tag = "nuovo")) }
        assertEquals(listOf("lavoro"), repo.get("a")!!.tags)
    }
    @Test fun tagsTrashAndRestorePreserveContents() = runTest {
        seed(); assertEquals(2, repo.bulkEdit(selection(), BulkChange(BulkAction.ADD_TAG, tag = "Oggi")))
        assertEquals(listOf("lavoro", "oggi"), repo.get("a")!!.tags)
        repo.bulkEdit(selection(), BulkChange(BulkAction.TRASH))
        repo.bulkEdit(selection(), BulkChange(BulkAction.RESTORE))
        assertNull(repo.get("a")!!.deletedAt); assertEquals("Corpo", repo.get("a")!!.body)
        assertEquals(listOf("lavoro", "oggi"), repo.get("a")!!.tags)
    }
}

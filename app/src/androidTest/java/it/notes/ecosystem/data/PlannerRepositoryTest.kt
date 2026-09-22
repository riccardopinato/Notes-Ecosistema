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
class PlannerRepositoryTest {
    private lateinit var db: NotesDatabase
    private lateinit var repo: LocalNotesRepository
    @Before fun setup() { db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),NotesDatabase::class.java).build();repo=LocalNotesRepository(db) }
    @After fun cleanup() = db.close()
    private suspend fun seed() { repo.save("note","Nota","Testo",null);repo.savePlannedTask(null,"task","Attività","Descrizione",TaskDetails(due="2026-09-15",linkedNoteId="note")) }
    private suspend fun rejected(block:suspend ()->Unit) { try { block();fail("Expected rejection") } catch(_:IllegalStateException) {} catch(_:IllegalArgumentException) {} }
    @Test fun taskRoundTripAndImportRemapLink() = runTest {
        seed();repo.importCopies(repo.snapshot());val data=repo.snapshot()
        val task=data.notes.single { it.task!=null && it.id!="task" }
        val copiedNote=data.notes.single { it.task==null && it.id!="note" }
        assertEquals(copiedNote.id,task.task!!.linkedNoteId)
        assertEquals("note",repo.get("task")!!.task!!.linkedNoteId)
    }
    @Test fun missingLinkPreventsCreate() = runTest {
        rejected { repo.savePlannedTask(null,"task","A","B",TaskDetails(linkedNoteId="missing")) };assertNull(repo.get("task"))
    }
    @Test fun staleSaveCannotOverwriteNewerTask() = runTest {
        seed();val expected=repo.get("task")!!
        repo.updatePlannedTask(expected,expected.task!!.copy(priority=3))
        rejected { repo.savePlannedTask(expected,"task","Old","Old",expected.task!!) }
        assertEquals(3,repo.get("task")!!.task!!.priority)
    }
    @Test fun recurringCompletionUpdatesSameId() = runTest {
        seed();val original=repo.get("task")!!;repo.updatePlannedTask(original,original.task!!.copy(repeat=RepeatRule.DAILY))
        val current=repo.get("task")!!;repo.updatePlannedTask(current,completePlannedTask(current.task!!,true,10,java.time.LocalDate.of(2026,9,15)))
        assertEquals("2026-09-16",repo.get("task")!!.task!!.due);assertEquals(2,repo.snapshot().notes.size)
    }
    @Test fun focusRetryPersistsOnce() = runTest { seed();repo.addFocus("task","session",1500);repo.addFocus("task","session",1500);assertEquals(1500L,repo.get("task")!!.task!!.focusSeconds) }
    @Test fun trashRestorePreservesTaskAndLinkedNote() = runTest {
        seed();val n=repo.get("task")!!;repo.updatePlannedTask(n,n.task!!,true)
        val trashed=repo.get("task")!!;repo.updatePlannedTask(trashed,trashed.task!!)
        assertEquals(n.task,repo.get("task")!!.task);assertNull(repo.get("note")!!.deletedAt)
    }
    @Test fun genericEditorCannotEraseTaskMetadata() = runTest { seed();rejected { repo.save("task","Bad","Bad",null) };assertNotNull(repo.get("task")!!.task) }
    @Test fun remoteTaskRoundTripPreservesFocus() = runTest {
        seed();repo.addFocus("task","session",60);val d=repo.syncDocument("task")!!
        assertTrue(repo.applySync("task",d,d.copy(task=d.task!!.copy(priority=2))))
        assertEquals(60L,repo.get("task")!!.task!!.focusSeconds)
    }
    @Test fun concurrentCompletionRejectsSecondTapSnapshot() = runTest {
        seed();val n=repo.get("task")!!;val done=completePlannedTask(n.task!!,true,10,java.time.LocalDate.of(2026,9,15))
        repo.updatePlannedTask(n,done);rejected { repo.updatePlannedTask(n,done) };assertEquals(10L,repo.get("task")!!.task!!.completedAt)
    }

    @Test fun importedLinkToMissingNoteDoesNotPointToDraft() = runTest {
        val task=Note("task","Attività","",createdAt=1,updatedAt=2,task=TaskDetails(linkedNoteId="draft"))
        repo.importCopies(BackupSnapshot(listOf(task),emptyList(),listOf(Draft("draft","Bozza","Testo",null,2))))
        assertNull(repo.snapshot().notes.single().task!!.linkedNoteId)
    }
}

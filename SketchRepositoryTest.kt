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
class SketchRepositoryTest {
    private lateinit var db:NotesDatabase
    private lateinit var repo:LocalNotesRepository
    private val empty=SketchCodec.encode(SketchPage())
    private val ink=SketchCodec.encode(SketchPage(listOf(InkStroke(-1,4,false,listOf(InkPoint(3,4))))))
    @Before fun setup(){db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),NotesDatabase::class.java).build();repo=LocalNotesRepository(db)}
    @After fun cleanup(){db.close()}
    private suspend fun rejected(block:suspend ()->Unit){try{block();fail("Expected rejection")}catch(_:IllegalStateException){}catch(_:IllegalArgumentException){}}
    @Test fun autosavesRemainInSubmissionOrder()=runTest {
        val first=repo.queueSketch("s",null,"Uno",empty,SketchInfo())
        val second=repo.queueSketch("s",empty,"Due",ink,SketchInfo())
        first.await();second.await();assertEquals(ink,repo.get("s")!!.body);assertEquals("Due",repo.get("s")!!.title)
    }
    @Test fun exclusiveEditorRejectsSecondInstance()=runTest {assertTrue(repo.beginSketchEditing("s"));assertFalse(repo.beginSketchEditing("s"));repo.endEditing("s");assertTrue(repo.beginSketchEditing("s"));repo.endEditing("s")}
    @Test fun remoteChangesWaitForSketchEditor()=runTest {
        repo.queueSketch("s",null,"Uno",empty,SketchInfo()).await();val old=repo.syncDocument("s")!!
        repo.beginSketchEditing("s");assertFalse(repo.applySync("s",old,old.copy(body=ink)));repo.endEditing("s")
        assertTrue(repo.applySync("s",old,old.copy(body=ink)))
    }
    @Test fun staleAutosaveCannotOverwrite()=runTest {repo.queueSketch("s",null,"Uno",empty,SketchInfo()).await();rejected {repo.queueSketch("s",null,"Due",ink,SketchInfo()).await()};assertEquals(empty,repo.get("s")!!.body)}
    @Test fun ordinaryEditorCannotEraseSketchType()=runTest {repo.queueSketch("s",null,"Uno",empty,SketchInfo()).await();rejected {repo.save("s","Bad","Bad",null)};assertNotNull(repo.get("s")!!.sketch)}
    @Test fun importRemapsLinkedNote()=runTest {
        repo.save("n","Nota","Testo",null);repo.queueSketch("s",null,"Disegno",ink,SketchInfo("n")).await();repo.importCopies(repo.snapshot())
        val all=repo.snapshot().notes;val copy=all.single {it.sketch!=null && it.id!="s"};val text=all.single {it.sketch==null && it.id!="n"}
        assertEquals(text.id,copy.sketch!!.linkedNoteId);assertEquals(ink,copy.body)
    }
    @Test fun missingLinkRejectsFirstSave()=runTest {rejected {repo.queueSketch("s",null,"Uno",empty,SketchInfo("missing")).await()};assertNull(repo.get("s"))}
    @Test fun invalidVectorDoesNotReplaceSavedBody()=runTest {repo.queueSketch("s",null,"Uno",empty,SketchInfo()).await();rejected {repo.queueSketch("s",empty,"Uno","{}",SketchInfo()).await()};assertEquals(empty,repo.get("s")!!.body)}
    @Test fun trashRestorePreservesVectorAndMetadata()=runTest {repo.queueSketch("s",null,"Uno",ink,SketchInfo()).await();repo.trash("s");repo.restore("s");assertEquals(ink,repo.get("s")!!.body);assertNotNull(repo.get("s")!!.sketch)}
    @Test fun sketchIsolationAndQueue() = runTest {
        val page = SketchPage(listOf(InkStroke(0xFF17212B.toInt(), 4, false, listOf(InkPoint(0, 0), InkPoint(100, 100)))))
        val encoded = SketchCodec.encode(page)
        assertTrue(repo.beginSketchEditing("sketch-1"))
        assertFalse(repo.beginSketchEditing("sketch-1"))
        val note = repo.queueSketch("sketch-1", null, "Schizzo", encoded, SketchInfo()).await()
        assertEquals("Schizzo", note.title); assertNotNull(note.sketch); assertNull(note.task)
        assertEquals(0, repo.history("sketch-1").size)
        repo.endEditing("sketch-1")
    }
}

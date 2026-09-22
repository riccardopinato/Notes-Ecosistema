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
class OrganizationRepositoryTest {
    private lateinit var db: NotesDatabase
    private lateinit var repo: LocalNotesRepository
    @Before fun setup() { db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),NotesDatabase::class.java).build();repo=LocalNotesRepository(db) }
    @After fun cleanup()=db.close()
    @Test fun flagsSurviveEditingTrashAndRestore()=runTest {
        repo.save("a","Title","Body",null);repo.setPinned("a",true);repo.setArchived("a",true)
        repo.save("a","Edited","Changed",null);repo.trash("a");repo.restore("a")
        val n=repo.get("a")!!;assertTrue(n.pinned);assertTrue(n.archived);assertEquals("Changed",n.body)
    }
    @Test fun importedCopiesKeepFlagsAndDoNotOverwriteExisting()=runTest {
        repo.save("a","Existing","Original",null)
        val data=BackupSnapshot(listOf(Note("a","Imported","Body",createdAt=1,updatedAt=2,pinned=true,archived=true)),emptyList(),emptyList())
        repo.importCopies(data)
        val all=repo.snapshot().notes;assertEquals("Original",all.single{it.id=="a"}.body)
        val copy=all.single{it.id!="a"};assertTrue(copy.pinned);assertTrue(copy.archived)
    }
    @Test fun archiveKeepsDraftAndGlobalTaskWritesAreBlocked()=runTest {
        repo.save("a","Title","- [ ] Task",null)
        repo.queueDraft(Draft("a","Draft","Changed",null,2)).await();repo.setArchived("a",true)
        assertEquals("Changed",repo.getDraft("a")?.body);repo.discardDraft("a")
        try { repo.setTaskCompleted("a","- [ ] Task",0,true);fail() } catch (_:IllegalStateException) {}
        assertEquals("- [ ] Task",repo.get("a")?.body)
    }
    @Test fun remoteFlagsAndDraftProtectionWorkTogether()=runTest {
        repo.save("a","Title","Body",null);val base=repo.syncDocument("a")!!
        val remote=base.copy(pinned=true,archived=true)
        repo.beginEditing("a");assertFalse(repo.applySync("a",base,remote));repo.endEditing("a")
        assertTrue(repo.applySync("a",base,remote));assertEquals(remote,repo.syncDocument("a"))
    }
}

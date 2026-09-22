package it.notes.ecosystem.data

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import it.notes.ecosystem.domain.*
import it.notes.ecosystem.domain.Collection
import kotlinx.coroutines.test.runTest
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class CollectionManagementTest {
    private lateinit var db: NotesDatabase
    private lateinit var repo: LocalNotesRepository
    @Before fun setup() { db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),NotesDatabase::class.java).build();repo=LocalNotesRepository(db) }
    @After fun close() { db.close() }
    private suspend fun collection(): Collection {repo.createCollection("Casa");return repo.snapshot().collections.single()}
    private suspend fun mustFail(block:suspend ()->Unit) { try {block();fail("Expected rejection")} catch(_:IllegalStateException) {} }
    @Test fun renamePreservesNoteDraftAndStableIds()=runTest {
        val c=collection();repo.save("n","Titolo","Testo",c.id);repo.queueDraft(Draft("n","Bozza","Testo nuovo",c.id,2)).await()
        val old=repo.get("n");val draft=repo.getDraft("n")
        repo.renameCollection(c,"Studio");assertEquals(old,repo.get("n"));assertEquals(draft,repo.getDraft("n"));assertEquals(c.copy(name="Studio"),repo.snapshot().collections.single())
    }
    @Test fun renamedCollectionAppearsInSyncAndBackup()=runTest {
        val c=collection();repo.save("n","Titolo","Testo",c.id);repo.renameCollection(c,"Studio")
        assertEquals("Studio",repo.syncDocument("n")!!.collection)
        assertEquals("Studio",BackupReader.parse(BackupWriter.json(repo.snapshot())).collections.single().name)
    }
    @Test fun staleRenameCannotOverwriteNewName()=runTest {val c=collection();repo.renameCollection(c,"Studio");mustFail{repo.renameCollection(c,"Vecchio")};assertEquals("Studio",repo.snapshot().collections.single().name)}
    @Test fun duplicateRenameRollsBack()=runTest {
        val c=collection();repo.createCollection("Studio")
        try {repo.renameCollection(c,"STUDIO");fail("Expected duplicate")}catch(_:IllegalArgumentException){}
        assertTrue(repo.snapshot().collections.contains(c))
    }
    @Test fun emptyCollectionCanBeDeleted()=runTest {val c=collection();repo.deleteEmptyCollection(c);assertTrue(repo.snapshot().collections.isEmpty())}
    @Test fun archivedAndTrashedNotesPreventDeletion()=runTest {
        val c=collection();repo.save("n","Titolo","Testo",c.id);repo.setArchived("n",true);mustFail{repo.deleteEmptyCollection(c)}
        repo.trash("n");mustFail{repo.deleteEmptyCollection(c)};assertEquals(c.id,repo.get("n")!!.collectionId)
    }
    @Test fun draftOnlyCollectionCannotBeDeleted()=runTest {
        val c=collection();repo.queueDraft(Draft("d","Bozza","Testo",c.id,2)).await();mustFail{repo.deleteEmptyCollection(c)};assertNotNull(repo.getDraft("d"))
    }
    @Test fun editorLeasePreventsEmptyDeletion()=runTest {
        val c=collection();repo.beginEditing("new");mustFail{repo.deleteEmptyCollection(c)};repo.endEditing("new");repo.deleteEmptyCollection(c)
    }
    @Test fun oldRevisionKeepsCollectionAvailableForRestore()=runTest {
        val c=collection();repo.save("n","Titolo","Testo",c.id);repo.save("n","Titolo","Testo nuovo",null)
        mustFail{repo.deleteEmptyCollection(c)};assertEquals(c.id,repo.history("n").first().collectionId)
    }
    @Test fun queuedDraftCannotReferenceDeletedCollection()=runTest {
        val c=collection();repo.deleteEmptyCollection(c)
        mustFail{repo.queueDraft(Draft("d","Bozza","Testo",c.id,2)).await()};assertNull(repo.getDraft("d"))
    }
    @Test fun staleSyncCannotUndoRename()=runTest {
        val c=collection();repo.save("n","Titolo","Testo",c.id);val old=repo.syncDocument("n")!!;repo.renameCollection(c,"Studio")
        assertFalse(repo.applySync("n",old,old.copy(body="Remoto")));assertEquals("Studio",repo.syncDocument("n")!!.collection)
    }
}

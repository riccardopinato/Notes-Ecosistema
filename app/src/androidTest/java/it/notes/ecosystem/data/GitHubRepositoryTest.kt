package it.notes.ecosystem.data

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import it.notes.ecosystem.domain.Draft
import it.notes.ecosystem.sync.SyncDocument
import kotlinx.coroutines.test.runTest
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class GitHubRepositoryTest {
    private lateinit var db: NotesDatabase
    private lateinit var repo: LocalNotesRepository
    private val remote = SyncDocument("a", "Remoto", "Testo", "Lavoro", false, 1, 2, null)
    @Before fun setup() {
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(), NotesDatabase::class.java).build()
        repo = LocalNotesRepository(db)
    }
    @After fun cleanup() = db.close()
    @Test fun importsNoteAndCollectionWithoutChangingId() = runTest {
        assertTrue(repo.applySync("a", null, remote))
        assertEquals(remote, repo.syncDocument("a"))
        assertEquals(1, repo.snapshot().collections.size)
    }
    @Test fun staleSnapshotIsRejected() = runTest {
        repo.save("a", "Prima", "Prima", null)
        val expected = repo.syncDocument("a")
        repo.save("a", "Dopo", "Dopo", null)
        assertFalse(repo.applySync("a", expected, remote))
        assertEquals("Dopo", repo.get("a")!!.body)
    }
    @Test fun openedEditorAndDraftEachBlockIncomingWrite() = runTest {
        repo.save("a", "Locale", "Locale", null)
        val expected = repo.syncDocument("a")
        repo.beginEditing("a")
        assertFalse(repo.applySync("a", expected, remote))
        repo.endEditing("a")
        repo.queueDraft(Draft("a", "Bozza", "Bozza", null, 4)).await()
        assertFalse(repo.applySync("a", expected, remote))
        assertEquals("Bozza", repo.getDraft("a")!!.body)
        repo.discardDraft("a")
        assertTrue(repo.applySync("a", expected, remote))
    }
    @Test fun keepingBothPreservesLocalContentInNewNote() = runTest {
        repo.save("a", "Locale", "Testo locale", null)
        val expected = repo.syncDocument("a")
        assertTrue(repo.resolveSync("a", expected, remote, "both"))
        val all = repo.snapshot().notes
        assertEquals(2, all.size)
        assertEquals(remote, repo.syncDocument("a"))
        assertEquals("Testo locale", all.single { it.id != "a" }.body)
    }
    @Test fun remoteTrashAndRestoreAreAppliedWithoutLosingBody() = runTest {
        assertTrue(repo.applySync("a", null, remote.tombstone()))
        assertNotNull(repo.get("a")!!.deletedAt)
        assertTrue(repo.applySync("a", remote.tombstone(), remote))
        assertNull(repo.get("a")!!.deletedAt)
        assertEquals(remote.body, repo.get("a")!!.body)
    }
    @Test fun onlyLastEditorClosureReleasesSync() = runTest {
        repo.beginEditing("a"); repo.beginEditing("a")
        repo.endEditing("a")
        assertEquals(0L, repo.editorClosures.value)
        assertFalse(repo.applySync("a", null, remote))
        repo.endEditing("a")
        assertEquals(1L, repo.editorClosures.value)
        assertTrue(repo.applySync("a", null, remote))
        repo.endEditing("a")
        assertEquals(1L, repo.editorClosures.value)
    }
}

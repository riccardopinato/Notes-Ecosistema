package it.notes.ecosystem.data

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import it.notes.ecosystem.domain.Draft
import kotlinx.coroutines.test.runTest
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class TaskRepositoryTest {
    private lateinit var db: NotesDatabase
    private lateinit var repo: LocalNotesRepository
    private val original = "Testo\n- [ ] Uno\n- [ ] Due"
    @Before fun setup() {
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(), NotesDatabase::class.java).build()
        repo = LocalNotesRepository(db)
    }
    @After fun cleanup() = db.close()

    @Test fun completesOnlyRequestedTaskAndPreservesMetadata() = runTest {
        repo.save("a", "Titolo", original, null)
        repo.toggleFavorite("a")
        val before = repo.get("a")!!
        repo.setTaskCompleted("a", original, 2, true)
        val after = repo.get("a")!!
        assertEquals("Testo\n- [ ] Uno\n- [x] Due", after.body)
        assertEquals(before.title, after.title)
        assertEquals(before.createdAt, after.createdAt)
        assertTrue(after.favorite)
    }

    @Test fun staleSnapshotDoesNotOverwriteNewerContent() = runTest {
        repo.save("a", "Titolo", original, null)
        repo.save("a", "Titolo", "Nuova riga\n" + original, null)
        val before = repo.get("a")
        try { repo.setTaskCompleted("a", original, 1, true); fail("Stale snapshot accepted") }
        catch (_: IllegalStateException) { }
        assertEquals(before, repo.get("a"))
    }

    @Test fun draftBlocksGlobalToggleWithoutLosingEitherVersion() = runTest {
        repo.save("a", "Titolo", original, null)
        repo.queueDraft(Draft("a", "Bozza", "Diversa", null, 1)).await()
        val before = repo.snapshot()
        try { repo.setTaskCompleted("a", original, 1, true); fail("Draft overwritten") }
        catch (_: IllegalStateException) { }
        assertEquals(before, repo.snapshot())
    }

    @Test fun trashedNoteCannotBeChangedFromTasks() = runTest {
        repo.save("a", "Titolo", original, null)
        repo.trash("a")
        val before = repo.get("a")
        try { repo.setTaskCompleted("a", original, 1, true); fail("Trash edited") }
        catch (_: IllegalStateException) { }
        assertEquals(before, repo.get("a"))
    }
}

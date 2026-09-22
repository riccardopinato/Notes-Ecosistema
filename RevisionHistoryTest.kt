package it.notes.ecosystem.data

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.test.runTest
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class RevisionHistoryTest {
    private lateinit var db: NotesDatabase
    private lateinit var repo: LocalNotesRepository
    @Before fun setup() {
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(), NotesDatabase::class.java).build()
        repo = LocalNotesRepository(db)
    }
    @After fun cleanup() = db.close()
    @Test fun savesPreviousTextAndCurrentNoteTogether() = runTest {
        repo.save("n", "Prima", "Originale", null)
        repo.save("n", "Dopo", "Nuovo", null)
        assertEquals("Originale", repo.history("n").single().body)
        assertEquals("Nuovo", repo.get("n")!!.body)
    }
    @Test fun remoteReplacementPreservesLocalVersion() = runTest {
        repo.save("n", "Nota", "Locale", null)
        val old = repo.syncDocument("n")!!
        assertTrue(repo.applySync("n", old, old.copy(body = "Remoto")))
        assertEquals("Locale", repo.history("n").single().body)
    }
    @Test fun failedSyncDoesNotWriteHistory() = runTest {
        repo.save("n", "Nota", "Locale", null)
        val old = repo.syncDocument("n")!!
        repo.beginEditing("n")
        assertFalse(repo.applySync("n", old, old.copy(body = "Remoto")))
        assertTrue(repo.history("n").isEmpty())
    }
    @Test fun boundsHistoryToLatestFiftyVersions() = runTest {
        repeat(60) { repo.save("n", "Nota", "Versione $it", null) }
        val all = repo.history("n")
        assertEquals(50, all.size)
        assertEquals("Versione 58", all.first().body)
        assertEquals("Versione 9", all.last().body)
    }
    @Test fun checklistToggleIsRecoverable() = runTest {
        repo.save("n", "Lista", "- [ ] Uno", null)
        repo.setTaskCompleted("n", "- [ ] Uno", 0, true)
        assertEquals("- [ ] Uno", repo.history("n").single().body)
    }
}

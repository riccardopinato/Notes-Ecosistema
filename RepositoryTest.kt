package it.notes.ecosystem.data

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import android.content.Context
import it.notes.ecosystem.domain.SaveNote
import kotlinx.coroutines.test.runTest
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class RepositoryTest {
    private lateinit var database: NotesDatabase
    private lateinit var repository: LocalNotesRepository
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val databaseName = "test-${UUID.randomUUID()}.db"
    private fun open() {
        database = Room.databaseBuilder(context, NotesDatabase::class.java, databaseName).build()
        repository = LocalNotesRepository(database)
    }
    @Before fun setup() = open()
    @After fun cleanup() { database.close(); context.deleteDatabase(databaseName) }

    @Test fun saveSurvivesClosingAndReopeningDatabase() = runTest {
        SaveNote(repository)("a", "  Titolo  ", "Corpo\ncon righe", null)
        repository.toggleFavorite("a")
        val original = repository.get("a")!!
        database.close()
        open()
        assertEquals(original, repository.get("a"))
        SaveNote(repository)("a", "Aggiornato", "Nuovo testo", null)
        assertTrue(repository.get("a")!!.favorite)
        assertEquals(original.createdAt, repository.get("a")!!.createdAt)
    }
    @Test fun trashCannotBeOverwrittenAndRestorePreservesContent() = runTest {
        repository.save("a", "Titolo", "Contenuto", null)
        repository.trash("a")
        assertNotNull(repository.get("a")!!.deletedAt)
        try {
            repository.save("a", "Sovrascritto", "", null)
            fail("Saving a trashed note must fail")
        } catch (_: IllegalStateException) { }
        repository.restore("a")
        assertNull(repository.get("a")!!.deletedAt)
        assertEquals("Contenuto", repository.get("a")!!.body)
    }
    @Test fun blankNoteIsRejected() = runTest {
        try {
            SaveNote(repository)("a", " ", "\n", null)
            fail("Blank note must fail validation")
        } catch (_: IllegalArgumentException) { }
        assertNull(repository.get("a"))
    }
    @Test fun missingCollectionIsRejectedWithoutLosingOriginal() = runTest {
        repository.save("a", "Originale", "Testo", null)
        try {
            repository.save("a", "Modificato", "Testo", "nonexistent")
            fail("Invalid collection must fail")
        } catch (_: android.database.sqlite.SQLiteConstraintException) { }
        assertEquals("Originale", repository.get("a")!!.title)
    }
}

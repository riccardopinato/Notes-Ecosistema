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
class ImportCopiesTest {
    private lateinit var db: NotesDatabase
    private lateinit var repo: LocalNotesRepository
    @Before fun setup() {
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(), NotesDatabase::class.java).build()
        repo = LocalNotesRepository(db)
    }
    @After fun cleanup() = db.close()
    private val backup = BackupSnapshot(
        listOf(Note("old", "Importata", "Testo", "c", true, 1, 2),
            Note("trash", "Eliminata", "Conservata", "c", false, 1, 3, 3)),
        listOf(it.notes.ecosystem.domain.Collection("c", "Lavoro")),
        listOf(Draft("old", "Bozza collegata", "Modifiche", null, 4),
            Draft("new", "", "Solo bozza", "c", 5))
    )
    @Test fun importsCopiesPreservingLinksAndExistingDataEvenWhenRepeated() = runTest {
        repo.save("old", "Originale", "Intatta", null)
        repo.createCollection("Lavoro")
        repeat(2) { repo.importCopies(backup) }
        val result = repo.snapshot()
        assertEquals("Originale", repo.get("old")!!.title)
        assertEquals(5, result.notes.size)
        assertEquals(3, result.collections.size)
        assertEquals(4, result.drafts.size)
        assertEquals(3, result.collections.map { it.name }.toSet().size)
        val imported = result.notes.filter { it.title == "Importata" }
        assertEquals(2, imported.size)
        imported.forEach { n ->
            assertTrue(n.favorite)
            assertNotEquals("old", n.id)
            assertTrue(result.collections.any { it.id == n.collectionId })
            assertEquals("Bozza collegata", result.drafts.first { it.id == n.id }.title)
            assertNull(result.drafts.first { it.id == n.id }.collectionId)
        }
        assertEquals(2, result.notes.count { it.deletedAt == 3L })
    }
    @Test fun invalidBackupDoesNotMutateDatabase() = runTest {
        repo.save("old", "Originale", "Intatta", null)
        val before = repo.snapshot()
        try {
            repo.importCopies(backup.copy(collections = emptyList()))
            fail("Missing collection accepted")
        } catch (_: IllegalArgumentException) { }
        assertEquals(before, repo.snapshot())
    }
    @Test fun writeFailureRollsBackCollectionsNotesAndDrafts() = runTest {
        repo.save("old", "Originale", "Intatta", null)
        val before = repo.snapshot()
        db.openHelper.writableDatabase.execSQL("CREATE TRIGGER reject_import BEFORE INSERT ON notes WHEN NEW.title = 'Eliminata' BEGIN SELECT RAISE(ABORT, 'simulated failure'); END")
        try {
            repo.importCopies(backup)
            fail("Injected failure expected")
        } catch (_: android.database.sqlite.SQLiteConstraintException) { }
        assertEquals(before, repo.snapshot())
    }
}

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
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class DraftsTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val name = "draft-test-${UUID.randomUUID()}.db"
    private lateinit var db: NotesDatabase
    private lateinit var repo: LocalNotesRepository
    private fun open() {
        db = Room.databaseBuilder(context, NotesDatabase::class.java, name)
            .addMigrations(NotesDatabase.MIGRATION_1_2, NotesDatabase.MIGRATION_2_3, NotesDatabase.MIGRATION_3_4, NotesDatabase.MIGRATION_4_5, NotesDatabase.MIGRATION_5_6, NotesDatabase.MIGRATION_6_7).build()
        repo = LocalNotesRepository(db)
    }
    @Before fun setup() = open()
    @After fun cleanup() { db.close(); context.deleteDatabase(name) }

    @Test fun draftsSurviveReopenAndCommitClearsDraftAtomically() = runTest {
        repo.queueDraft(Draft("new", "Idea", "Caffè", null, 1)).await()
        db.close(); open()
        assertEquals("Caffè", repo.getDraft("new")!!.body)
        assertNull(repo.get("new"))
        repo.save("new", "Idea", "Salvata", null)
        assertNull(repo.getDraft("new"))
        assertEquals("Salvata", repo.get("new")!!.body)
    }
    @Test fun latestQueuedEditWinsAndDiscardDoesNotChangeSavedNote() = runTest {
        repo.save("a", "Originale", "Testo", null)
        repeat(30) { repo.queueDraft(Draft("a", "Bozza", "Edizione $it", null, it.toLong())) }
        assertEquals("Edizione 29", repo.getDraft("a")!!.body)
        repo.discardDraft("a")
        assertNull(repo.getDraft("a"))
        assertEquals("Originale", repo.get("a")!!.title)
    }
    @Test fun failedCommitKeepsDraftAndOriginal() = runTest {
        repo.save("a", "Originale", "Testo", null)
        repo.queueDraft(Draft("a", "Bozza", "Recuperabile", "missing", 1)).await()
        try {
            repo.save("a", "Bozza", "Recuperabile", "missing")
            fail("Foreign key violation expected")
        } catch (_: android.database.sqlite.SQLiteConstraintException) { }
        assertEquals("Recuperabile", repo.getDraft("a")!!.body)
        assertEquals("Originale", repo.get("a")!!.title)
    }
    @Test fun migrationPreservesV1DataAndAddsDrafts() = runTest {
        db.close()
        context.openOrCreateDatabase(name, Context.MODE_PRIVATE, null).use { old ->
            old.execSQL("CREATE TABLE collections (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL)")
            old.execSQL("CREATE UNIQUE INDEX index_collections_name ON collections(name)")
            old.execSQL("CREATE TABLE notes (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, body TEXT NOT NULL, collectionId TEXT, favorite INTEGER NOT NULL, createdAt INTEGER NOT NULL, updatedAt INTEGER NOT NULL, deletedAt INTEGER, FOREIGN KEY(collectionId) REFERENCES collections(id) ON UPDATE NO ACTION ON DELETE SET NULL)")
            old.execSQL("CREATE INDEX index_notes_collectionId ON notes(collectionId)")
            old.execSQL("CREATE INDEX index_notes_deletedAt ON notes(deletedAt)")
            old.execSQL("CREATE INDEX index_notes_updatedAt ON notes(updatedAt)")
            old.execSQL("INSERT INTO notes VALUES ('old', 'Esistente', 'Non perdere', NULL, 1, 1, 2, NULL)")
            old.version = 1
        }
        open()
        assertEquals("Non perdere", repo.get("old")!!.body)
        assertTrue(repo.get("old")!!.favorite)
        repo.queueDraft(Draft("new", "", "Nuova", null, 3)).await()
        assertEquals("Nuova", repo.getDraft("new")!!.body)
    }
}

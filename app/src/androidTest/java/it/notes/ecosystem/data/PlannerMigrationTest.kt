package it.notes.ecosystem.data

import android.content.Context
import androidx.room.Room
import androidx.sqlite.db.SupportSQLiteDatabase
import androidx.sqlite.db.SupportSQLiteOpenHelper
import androidx.sqlite.db.framework.FrameworkSQLiteOpenHelperFactory
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import it.notes.ecosystem.domain.RepeatRule
import it.notes.ecosystem.domain.TaskDetails
import kotlinx.coroutines.test.runTest
import org.json.JSONObject
import org.junit.Test
import org.junit.Assert.*
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class PlannerMigrationTest {
    @Test fun versionFiveNotesDraftsAndHistorySurviveMigrationToSix() = runTest {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val name = "planner-migration-" + java.util.UUID.randomUUID() + ".db"
        val json = InstrumentationRegistry.getInstrumentation().context.assets.open("it.notes.ecosystem.data.NotesDatabase/4.json").bufferedReader().use { JSONObject(it.readText()) }
        val helper = FrameworkSQLiteOpenHelperFactory().create(SupportSQLiteOpenHelper.Configuration.builder(context).name(name)
            .callback(object : SupportSQLiteOpenHelper.Callback(5) {
                override fun onCreate(db: SupportSQLiteDatabase) {
                    val entities = json.getJSONObject("database").getJSONArray("entities")
                    for (i in 0 until entities.length()) {
                        val entity = entities.getJSONObject(i)
                        val table = entity.getString("tableName")
                        db.execSQL(entity.getString("createSql").replace("${'$'}{TABLE_NAME}", table))
                        val indices = entity.optJSONArray("indices") ?: org.json.JSONArray()
                        for (j in 0 until indices.length()) db.execSQL(indices.getJSONObject(j).getString("createSql").replace("${'$'}{TABLE_NAME}", table))
                    }
                    // Build a real v5 fixture from the available v4 schema and production migration.
                    NotesDatabase.MIGRATION_4_5.migrate(db)
                    db.execSQL("INSERT INTO notes (id,title,body,collectionId,favorite,createdAt,updatedAt,deletedAt,pinned,archived,tagsJson) VALUES ('n','Nota','Testo',NULL,1,10,20,NULL,1,0,'[\"focus\"]')")
                    db.execSQL("INSERT INTO note_revisions (revisionId,noteId,title,body,collectionId,savedAt,tagsJson) VALUES ('r','n','Nota antica','Testo antico',NULL,5,'[\"focus\"]')")
                    db.execSQL("INSERT INTO drafts (id,title,body,collectionId,updatedAt,tagsJson) VALUES ('d','Bozza','Testo bozza',NULL,30,'[\"focus\"]')")
                }
                override fun onUpgrade(db: SupportSQLiteDatabase, old: Int, new: Int) = error("Unexpected upgrade")
            }).build())
        try {
            helper.writableDatabase; helper.close()
            val database = Room.databaseBuilder(context, NotesDatabase::class.java, name).addMigrations(NotesDatabase.MIGRATION_5_6, NotesDatabase.MIGRATION_6_7).build()
            try {
                val repo = LocalNotesRepository(database)
                val note = repo.get("n")!!
                assertEquals("Nota", note.title); assertEquals("Testo", note.body)
                assertTrue(note.favorite); assertTrue(note.pinned); assertEquals(listOf("focus"), note.tags)
                assertNull(note.task)
                assertEquals("Testo antico", repo.history("n").single().body)
                assertEquals("Testo bozza", repo.getDraft("d")!!.body)
                repo.savePlannedTask(null, "task-1", "Spesa", "Pane", TaskDetails(due = "2026-05-01", priority = 2, repeat = RepeatRule.DAILY, linkedNoteId = "n"))
                val taskNote = repo.get("task-1")!!
                assertEquals("Spesa", taskNote.title)
                assertEquals(RepeatRule.DAILY, taskNote.task!!.repeat)
                assertEquals("n", taskNote.task!!.linkedNoteId)
            } finally { database.close() }
        } finally { helper.close(); context.deleteDatabase(name) }
    }
}

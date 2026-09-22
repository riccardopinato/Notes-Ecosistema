package it.notes.ecosystem.data

import android.content.Context
import androidx.room.Room
import androidx.sqlite.db.SupportSQLiteDatabase
import androidx.sqlite.db.SupportSQLiteOpenHelper
import androidx.sqlite.db.framework.FrameworkSQLiteOpenHelperFactory
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.test.runTest
import org.json.JSONObject
import org.junit.Test
import org.junit.Assert.*
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class TagsMigrationTest {
    @Test fun versionFourDataNotesDraftsAndHistorySurviveMigrationToFive() = runTest {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val name = "tags-migration-" + java.util.UUID.randomUUID() + ".db"
        val json = InstrumentationRegistry.getInstrumentation().context.assets.open("it.notes.ecosystem.data.NotesDatabase/4.json").bufferedReader().use { JSONObject(it.readText()) }
        val helper = FrameworkSQLiteOpenHelperFactory().create(SupportSQLiteOpenHelper.Configuration.builder(context).name(name)
            .callback(object : SupportSQLiteOpenHelper.Callback(4) {
                override fun onCreate(db: SupportSQLiteDatabase) {
                    val entities = json.getJSONObject("database").getJSONArray("entities")
                    for (i in 0 until entities.length()) {
                        val entity = entities.getJSONObject(i)
                        val table = entity.getString("tableName")
                        db.execSQL(entity.getString("createSql").replace("${'$'}{TABLE_NAME}", table))
                        val indices = entity.optJSONArray("indices") ?: org.json.JSONArray()
                        for (j in 0 until indices.length()) db.execSQL(indices.getJSONObject(j).getString("createSql").replace("${'$'}{TABLE_NAME}", table))
                    }
                    db.execSQL("INSERT INTO notes (id,title,body,collectionId,favorite,createdAt,updatedAt,deletedAt,pinned,archived) VALUES ('n','Nota','Testo',NULL,1,10,20,NULL,1,0)")
                    db.execSQL("INSERT INTO note_revisions (revisionId,noteId,title,body,collectionId,savedAt) VALUES ('r','n','Nota antica','Testo antico',NULL,5)")
                    db.execSQL("INSERT INTO drafts (id,title,body,collectionId,updatedAt) VALUES ('d','Bozza','Testo bozza',NULL,30)")
                }
                override fun onUpgrade(db: SupportSQLiteDatabase, old: Int, new: Int) = error("Unexpected upgrade")
            }).build())
        try {
            helper.writableDatabase; helper.close()
            val database = Room.databaseBuilder(context, NotesDatabase::class.java, name).addMigrations(NotesDatabase.MIGRATION_4_5, NotesDatabase.MIGRATION_5_6, NotesDatabase.MIGRATION_6_7).build()
            try {
                val repo = LocalNotesRepository(database)
                val note = repo.get("n")!!
                assertEquals("Nota", note.title); assertEquals("Testo", note.body)
                assertTrue(note.favorite); assertTrue(note.pinned); assertEquals(emptyList<String>(), note.tags)
                assertEquals(emptyList<String>(), repo.history("n").single().tags)
                assertEquals(emptyList<String>(), repo.getDraft("d")!!.tags)
                repo.saveTagged("n", "Nota", "Testo con tag", null, listOf("progetto", "idea"))
                assertEquals(listOf("progetto", "idea"), repo.get("n")!!.tags)
                assertEquals(emptyList<String>(), repo.history("n").first().tags)
            } finally { database.close() }
        } finally { helper.close(); context.deleteDatabase(name) }
    }
}

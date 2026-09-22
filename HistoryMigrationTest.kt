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
class HistoryMigrationTest {
    @Test fun existingVersionTwoNotesAndDraftsSurviveMigration() = runTest {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val name = "history-migration-" + java.util.UUID.randomUUID() + ".db"
        val json = InstrumentationRegistry.getInstrumentation().context.assets.open("it.notes.ecosystem.data.NotesDatabase/2.json").bufferedReader().use { JSONObject(it.readText()) }
        val helper = FrameworkSQLiteOpenHelperFactory().create(SupportSQLiteOpenHelper.Configuration.builder(context).name(name)
            .callback(object : SupportSQLiteOpenHelper.Callback(2) {
                override fun onCreate(db: SupportSQLiteDatabase) {
                    val entities = json.getJSONObject("database").getJSONArray("entities")
                    for (i in 0 until entities.length()) {
                        val entity = entities.getJSONObject(i)
                        val table = entity.getString("tableName")
                        db.execSQL(entity.getString("createSql").replace("${'$'}{TABLE_NAME}", table))
                        val indices = entity.optJSONArray("indices") ?: org.json.JSONArray()
                        for (j in 0 until indices.length()) db.execSQL(indices.getJSONObject(j).getString("createSql").replace("${'$'}{TABLE_NAME}", table))
                    }
                    db.execSQL("INSERT INTO notes (id,title,body,collectionId,favorite,createdAt,updatedAt,deletedAt) VALUES ('n','Prima','Originale',NULL,0,1,1,NULL)")
                    db.execSQL("INSERT INTO drafts (id,title,body,collectionId,updatedAt) VALUES ('draft','Bozza','Da conservare',NULL,1)")
                }
                override fun onUpgrade(db: SupportSQLiteDatabase, old: Int, new: Int) = error("Unexpected upgrade")
            }).build())
        try {
            helper.writableDatabase; helper.close()
            val database = Room.databaseBuilder(context, NotesDatabase::class.java, name).addMigrations(NotesDatabase.MIGRATION_2_3, NotesDatabase.MIGRATION_3_4, NotesDatabase.MIGRATION_4_5, NotesDatabase.MIGRATION_5_6, NotesDatabase.MIGRATION_6_7).build()
            try {
                val repo = LocalNotesRepository(database)
                assertEquals("Originale", repo.get("n")!!.body)
                assertEquals("Da conservare", repo.getDraft("draft")!!.body)
                repo.save("n", "Nuova", "Aggiornata", null)
                assertEquals("Originale", repo.history("n").single().body)
            } finally { database.close() }
        } finally { helper.close(); context.deleteDatabase(name) }
    }
}

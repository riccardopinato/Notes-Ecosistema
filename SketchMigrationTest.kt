package it.notes.ecosystem.data

import android.content.Context
import androidx.room.Room
import androidx.sqlite.db.SupportSQLiteDatabase
import androidx.sqlite.db.SupportSQLiteOpenHelper
import androidx.sqlite.db.framework.FrameworkSQLiteOpenHelperFactory
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import it.notes.ecosystem.domain.*
import kotlinx.coroutines.test.runTest
import org.json.JSONObject
import org.junit.Test
import org.junit.Assert.*
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SketchMigrationTest {
    @Test fun versionSixNotesAndPlannerSurviveMigrationToSeven() = runTest {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val name = "sketch-migration-" + java.util.UUID.randomUUID() + ".db"
        val json = InstrumentationRegistry.getInstrumentation().context.assets.open("it.notes.ecosystem.data.NotesDatabase/6.json").bufferedReader().use { JSONObject(it.readText()) }
        val helper = FrameworkSQLiteOpenHelperFactory().create(SupportSQLiteOpenHelper.Configuration.builder(context).name(name)
            .callback(object : SupportSQLiteOpenHelper.Callback(6) {
                override fun onCreate(db: SupportSQLiteDatabase) {
                    val entities = json.getJSONObject("database").getJSONArray("entities")
                    for (i in 0 until entities.length()) {
                        val entity = entities.getJSONObject(i)
                        val table = entity.getString("tableName")
                        db.execSQL(entity.getString("createSql").replace("${'$'}{TABLE_NAME}", table))
                        val indices = entity.optJSONArray("indices") ?: org.json.JSONArray()
                        for (j in 0 until indices.length()) db.execSQL(indices.getJSONObject(j).getString("createSql").replace("${'$'}{TABLE_NAME}", table))
                    }
                    db.execSQL("INSERT INTO notes (id,title,body,collectionId,favorite,createdAt,updatedAt,deletedAt,pinned,archived,tagsJson,taskJson) VALUES ('n','Nota','Testo',NULL,1,10,20,NULL,1,0,'[\"focus\"]',NULL)")
                    db.execSQL("INSERT INTO notes (id,title,body,collectionId,favorite,createdAt,updatedAt,deletedAt,pinned,archived,tagsJson,taskJson) VALUES ('t','Attività','Descrizione',NULL,0,10,20,NULL,0,0,'[]','{\"format\":\"notes-task\",\"version\":1,\"completedAt\":null,\"due\":\"2026-05-01\",\"priority\":2,\"repeat\":\"NONE\",\"completedCycles\":0,\"linkedNoteId\":\"n\",\"focusSeconds\":0,\"focusReceipts\":[]}')")
                }
                override fun onUpgrade(db: SupportSQLiteDatabase, old: Int, new: Int) = error("Unexpected upgrade")
            }).build())
        try {
            helper.writableDatabase; helper.close()
            val database = Room.databaseBuilder(context, NotesDatabase::class.java, name).addMigrations(NotesDatabase.MIGRATION_6_7).build()
            try {
                val repo = LocalNotesRepository(database)
                val note = repo.get("n")!!
                assertEquals("Nota", note.title); assertNull(note.sketch)
                val task = repo.get("t")!!
                assertEquals("Attività", task.title); assertNotNull(task.task); assertNull(task.sketch)
                val page = SketchPage(listOf(InkStroke(0xFF17212B.toInt(), 4, false, listOf(InkPoint(10, 20), InkPoint(30, 40)))))
                repo.queueSketch("s", null, "Disegno", SketchCodec.encode(page), SketchInfo("n")).await()
                val sketch = repo.get("s")!!
                assertEquals("Disegno", sketch.title); assertEquals("n", sketch.sketch!!.linkedNoteId)
            } finally { database.close() }
        } finally { helper.close(); context.deleteDatabase(name) }
    }
}

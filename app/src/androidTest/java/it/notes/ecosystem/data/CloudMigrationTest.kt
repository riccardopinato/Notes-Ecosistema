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
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class CloudMigrationTest {
    @Test fun versionEightMigratesToNinePrivateByDefault() = runTest {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val name = "cloud-migration-" + java.util.UUID.randomUUID() + ".db"
        val json = InstrumentationRegistry.getInstrumentation().context.assets
            .open("it.notes.ecosystem.data.NotesDatabase/8.json").bufferedReader().use { JSONObject(it.readText()) }
        val helper = FrameworkSQLiteOpenHelperFactory().create(
            SupportSQLiteOpenHelper.Configuration.builder(context).name(name)
                .callback(object : SupportSQLiteOpenHelper.Callback(8) {
                    override fun onCreate(db: SupportSQLiteDatabase) {
                        val entities = json.getJSONObject("database").getJSONArray("entities")
                        for (i in 0 until entities.length()) {
                            val entity = entities.getJSONObject(i)
                            val table = entity.getString("tableName")
                            db.execSQL(entity.getString("createSql").replace("${TABLE_NAME}", table))
                            val indices = entity.optJSONArray("indices") ?: org.json.JSONArray()
                            for (j in 0 until indices.length()) {
                                db.execSQL(indices.getJSONObject(j).getString("createSql").replace("${TABLE_NAME}", table))
                            }
                        }
                        db.execSQL("INSERT INTO notes (id,title,body,collectionId,favorite,createdAt,updatedAt,deletedAt,pinned,archived,tagsJson,taskJson,sketchJson) VALUES ('n','Nota','Testo',NULL,0,10,20,NULL,0,0,'[]',NULL,NULL)")
                    }
                    override fun onUpgrade(db: SupportSQLiteDatabase, oldVersion: Int, newVersion: Int) = error("Unexpected upgrade")
                }).build()
        )
        try {
            helper.writableDatabase
            helper.close()
            val database = Room.databaseBuilder(context, NotesDatabase::class.java, name)
                .addMigrations(NotesDatabase.MIGRATION_8_9).build()
            try {
                val note = LocalNotesRepository(database).get("n")!!
                assertEquals(it.notes.ecosystem.domain.NoteVisibility.PRIVATE, note.visibility)
                assertEquals(it.notes.ecosystem.domain.CloudState.LOCAL, note.cloudState)
                assertEquals(0L, note.remoteRevision)
                assertNull(note.spaceId)
                assertNull(note.cloudAccountId)
                assertEquals(emptyList<SyncOutboxEntity>(), database.cloudDao().outbox("x"))
            } finally { database.close() }
        } finally {
            helper.close()
            context.deleteDatabase(name)
        }
    }
}

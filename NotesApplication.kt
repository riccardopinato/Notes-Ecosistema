package it.notes.ecosystem

import android.app.Application
import androidx.room.Room
import it.notes.ecosystem.data.*
import kotlinx.coroutines.*

class NotesApplication : Application() {
    private val database by lazy {
        Room.databaseBuilder(this, NotesDatabase::class.java, "notes.db")
            .addMigrations(
                NotesDatabase.MIGRATION_1_2,
                NotesDatabase.MIGRATION_2_3,
                NotesDatabase.MIGRATION_3_4,
                NotesDatabase.MIGRATION_4_5,
                NotesDatabase.MIGRATION_5_6,
                NotesDatabase.MIGRATION_6_7,
                NotesDatabase.MIGRATION_7_8,
            )
            .build()
    }

    val attachments by lazy {
        it.notes.ecosystem.media.AttachmentFiles(java.io.File(filesDir, "attachments"))
    }
    val repository by lazy { LocalNotesRepository(database) }

    /**
     * Fondazione v8 per il futuro Universal Block Editor.
     * In 0.19 non viene usata automaticamente dalla UI.
     */
    val contentBlocks by lazy { ContentBlockStore(database) }

    val githubSync by lazy { it.notes.ecosystem.sync.GitHubSync(this, repository) }
    val reminders by lazy { it.notes.ecosystem.reminders.TaskReminders(this, repository) }

    override fun onCreate() {
        super.onCreate()
        githubSync.start()
        reminders.start()
        CoroutineScope(Dispatchers.IO).launch {
            runCatching { it.notes.ecosystem.media.cleanupMediaTemporaryFiles(cacheDir) }
        }
    }

    val preferences by lazy { Preferences(this) }
}

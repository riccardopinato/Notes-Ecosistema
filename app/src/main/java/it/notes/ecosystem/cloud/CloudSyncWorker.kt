package it.notes.ecosystem.cloud

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import it.notes.ecosystem.NotesApplication

class CloudSyncWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val app = applicationContext as? NotesApplication ?: return Result.failure()
        return if (app.cloudSync.syncNow()) Result.success() else Result.retry()
    }
}

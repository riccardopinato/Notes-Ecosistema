package it.notes.ecosystem.reminders

import android.app.*
import android.content.*
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.work.*
import it.notes.ecosystem.MainActivity
import it.notes.ecosystem.NotesApplication
import it.notes.ecosystem.R
import it.notes.ecosystem.domain.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import java.util.concurrent.TimeUnit

class TaskReminders(private val context:Context,private val repository:NotesRepository) {
    private val scope=CoroutineScope(SupervisorJob()+Dispatchers.IO)
    private val refresh=MutableStateFlow(0)
    val error=MutableStateFlow<String?>(null)
    private val preferences=context.getSharedPreferences("task_reminders",Context.MODE_PRIVATE)
    companion object {const val CHANNEL="task_reminders";const val TASK_EXTRA="notes.reminder.task"}
    init {context.getSystemService(NotificationManager::class.java).createNotificationChannel(
        NotificationChannel(CHANNEL,"Promemoria attività",NotificationManager.IMPORTANCE_DEFAULT))}
    fun refresh(){refresh.value++}
    fun allowed():Boolean = NotificationManagerCompat.from(context).areNotificationsEnabled() &&
        context.getSystemService(NotificationManager::class.java).getNotificationChannel(CHANNEL)?.importance!=NotificationManager.IMPORTANCE_NONE
    fun delivered(id:String,at:Long)=preferences.getLong("delivered-$id",-1)==at
    fun markDelivered(id:String,at:Long){check(preferences.edit().putLong("delivered-$id",at).commit())}
    fun cancel(id:String){NotificationManagerCompat.from(context).cancel(id,1)}
    fun start(){scope.launch {
        var previous=preferences.getStringSet("scheduled",emptySet()).orEmpty().associateWith {preferences.getLong("scheduled-at-$it",-1)}
        combine(repository.notes.map {notes->notes.filter(Reminders::active).associate {it.id to it.task!!.reminderAt!!}}.distinctUntilChanged(),refresh) {map,_->map}
            .collect {current ->
                try {
                val manager=WorkManager.getInstance(context)
                val remembered=preferences.getStringSet("scheduled",emptySet()).orEmpty().toSet()
                (remembered-current.keys).forEach {id->manager.cancelUniqueWork("task-reminder-$id-${preferences.getLong("scheduled-at-$id",-1)}");cancel(id);preferences.edit().remove("delivered-$id").remove("scheduled-at-$id").apply()}
                current.forEach {(id,at)->
                    if(previous[id]!=null && previous[id]!=at) {manager.cancelUniqueWork("task-reminder-$id-${previous[id]}");cancel(id)}
                    if(!delivered(id,at)) {
                        val request=OneTimeWorkRequestBuilder<ReminderWorker>()
                            .setInitialDelay((at-System.currentTimeMillis()).coerceAtLeast(0),TimeUnit.MILLISECONDS)
                            .setInputData(workDataOf("id" to id,"at" to at)).build()
                        manager.enqueueUniqueWork("task-reminder-$id-$at",ExistingWorkPolicy.KEEP,request)
                    }
                }
                preferences.edit().also {edit->edit.putStringSet("scheduled",current.keys.toSet());current.forEach {(id,at)->edit.putLong("scheduled-at-$id",at)}}.apply();previous=current;error.value=null
                } catch(e:CancellationException){throw e} catch(_:Exception){error.value="Impossibile programmare i promemoria. Riapri Attività per riprovare."}
            }
    }}
}

class ReminderWorker(context:Context,parameters:WorkerParameters):CoroutineWorker(context,parameters) {
    override suspend fun doWork():Result = try {deliver()} catch(e:CancellationException){throw e} catch(_:Exception){Result.retry()}
    private suspend fun deliver():Result {
        val app=applicationContext as NotesApplication
        val id=inputData.getString("id") ?: return Result.failure()
        val at=inputData.getLong("at",-1)
        val note=app.repository.get(id) ?: return Result.success()
        if(!Reminders.active(note) || note.task!!.reminderAt!=at || app.reminders.delivered(id,at)) return Result.success()
        if(System.currentTimeMillis()<at) return Result.retry()
        if(!app.reminders.allowed()) return Result.failure()
        val open=PendingIntent.getActivity(applicationContext,0,Intent(applicationContext,MainActivity::class.java)
            .setData(Uri.parse("notes-reminder://open/${Uri.encode(id)}"))
            .putExtra(TaskReminders.TASK_EXTRA,id),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val snooze=PendingIntent.getBroadcast(applicationContext,0,Intent(applicationContext,SnoozeReceiver::class.java)
            .setData(Uri.parse("notes-reminder://snooze/${Uri.encode(id)}/$at"))
            .putExtra("id",id).putExtra("at",at),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification=NotificationCompat.Builder(applicationContext,TaskReminders.CHANNEL)
            .setSmallIcon(R.drawable.ic_capture_checklist).setContentTitle(note.title)
            .setContentText("È il momento della tua attività.").setContentIntent(open).setAutoCancel(true)
            .setOnlyAlertOnce(true).setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .addAction(R.drawable.ic_capture_checklist,"Rinvia 10 min",snooze).build()
        val latest=app.repository.get(id)
        if(latest==null || !Reminders.active(latest) || latest.task!!.reminderAt!=at) return Result.success()
        return try {
            NotificationManagerCompat.from(applicationContext).notify(id,1,notification)
            app.reminders.markDelivered(id,at);Result.success()
        } catch(_:SecurityException){Result.failure()} catch(_:IllegalStateException){Result.retry()}
    }
}
class SnoozeReceiver:BroadcastReceiver() {
    override fun onReceive(context:Context,intent:Intent) {
        val id=intent.getStringExtra("id")?.takeIf {it.isNotBlank() && it.length<=200} ?: return
        val at=intent.getLongExtra("at",-1);if(at<0)return
        val request=OneTimeWorkRequestBuilder<SnoozeWorker>().setInputData(workDataOf("id" to id,"at" to at,
            "next" to (System.currentTimeMillis()+600000))).build()
        val pending=goAsync()
        try {WorkManager.getInstance(context).enqueueUniqueWork("snooze-$id-$at",ExistingWorkPolicy.KEEP,request).result
            .addListener({pending.finish()},java.util.concurrent.Executor {it.run()})}
        catch(_:Exception){pending.finish()}
    }
}
class SnoozeWorker(context:Context,parameters:WorkerParameters):CoroutineWorker(context,parameters) {
    override suspend fun doWork():Result {
        val id=inputData.getString("id") ?: return Result.failure()
        val at=inputData.getLong("at",-1);val next=inputData.getLong("next",-1)
        val app=applicationContext as NotesApplication
        return try {if(app.repository.snoozeReminder(id,at,next)) {app.reminders.cancel(id);app.reminders.refresh()};Result.success()}
        catch(e:CancellationException){throw e} catch(_:Exception){Result.retry()}
    }
}

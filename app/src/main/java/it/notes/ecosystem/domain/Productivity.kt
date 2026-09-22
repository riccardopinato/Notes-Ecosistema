package it.notes.ecosystem.domain

import java.time.*
import java.time.format.DateTimeFormatter
import java.time.format.ResolverStyle

enum class TaskStage { TODO, DOING, WAITING }
enum class TaskStatus { TODO, DOING, WAITING, DONE }
fun TaskDetails.status() = if(completedAt!=null) TaskStatus.DONE else TaskStatus.valueOf(stage.name)
fun statusLabel(value:TaskStatus) = when(value) {
    TaskStatus.TODO -> "Da fare"; TaskStatus.DOING -> "In corso"; TaskStatus.WAITING -> "In attesa"; TaskStatus.DONE -> "Completata"
}
fun changeTaskStatus(task:TaskDetails,status:TaskStatus,now:Long,today:LocalDate):TaskDetails =
    if(status==TaskStatus.DONE) completePlannedTask(task,true,now,today)
    else validateTask(task.copy(completedAt=null,stage=TaskStage.valueOf(status.name)))

data class FocusSession(val id:String,val seconds:Long,val endedAt:Long)
fun recordFocusSession(task:TaskDetails,session:FocusSession):TaskDetails {
    validateTask(task)
    if(session.id in task.focusReceipts) return task
    val next=recordFocus(task,session.id,session.seconds)
    return validateTask(next.copy(focusHistory=next.focusHistory+session))
}

data class FocusHistoryRow(val taskId:String,val title:String,val session:FocusSession)
fun focusHistory(notes:List<Note>):List<FocusHistoryRow> = notes.asSequence()
    .filter {it.deletedAt==null && it.task!=null}.sortedByDescending {it.updatedAt}
    .flatMap {note->note.task!!.focusHistory.asSequence().map {FocusHistoryRow(note.id,note.title,it)}}
    .distinctBy {it.session.id}.sortedByDescending {it.session.endedAt}.toList()
fun weeklyFocus(notes:List<Note>,today:LocalDate,zone:ZoneId):List<Pair<LocalDate,Long>> {
    val history=focusHistory(notes).groupBy {Instant.ofEpochMilli(it.session.endedAt).atZone(zone).toLocalDate()}
    return (6 downTo 0).map {back->val day=today.minusDays(back.toLong());day to history[day].orEmpty().sumOf {it.session.seconds}}
}
object Reminders {
    private val format=DateTimeFormatter.ofPattern("uuuu-MM-dd HH:mm").withResolverStyle(ResolverStyle.STRICT)
    fun parse(text:String,zone:String):Long {
        val local=LocalDateTime.parse(text.trim(),format);val id=ZoneId.of(zone)
        require(id.rules.getValidOffsets(local).isNotEmpty()) {"Quest’ora non esiste per il cambio dell’ora legale."}
        return local.atZone(id).toInstant().toEpochMilli().also {require(it in 946684800000L..7258118399999L)}
    }
    fun display(at:Long,zone:String):String = format.format(Instant.ofEpochMilli(at).atZone(ZoneId.of(zone)))
    fun active(note:Note):Boolean = note.deletedAt==null && !note.archived && note.task?.let {it.completedAt==null && it.reminderAt!=null}==true
}

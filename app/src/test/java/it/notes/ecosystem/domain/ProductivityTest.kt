package it.notes.ecosystem.domain
import it.notes.ecosystem.data.*
import it.notes.ecosystem.sync.*
import org.json.JSONObject
import org.junit.Test
import org.junit.Assert.*
import java.time.*

class ProductivityTest {
    private val at=Instant.parse("2026-09-16T09:00:00Z").toEpochMilli()
    private val today=LocalDate.of(2026,9,16)
    private fun note(id:String="a",task:TaskDetails=TaskDetails())=Note(id,id,"Descrizione",createdAt=1,updatedAt=2,task=task)
    private fun rich()=recordFocusSession(TaskDetails(due=today.toString(),stage=TaskStage.DOING,reminderAt=at,reminderZone="Europe/Rome"),FocusSession("session",60,at))
    @Test fun stateChangesKeepContentAndHistory() {val t=rich();val next=changeTaskStatus(t,TaskStatus.WAITING,at,today);assertEquals(TaskStage.WAITING,next.stage);assertEquals(t.focusHistory,next.focusHistory);assertEquals(at,next.reminderAt)}
    @Test fun completionClearsReminder() {val next=changeTaskStatus(rich(),TaskStatus.DONE,at,today);assertEquals(TaskStatus.DONE,next.status());assertNull(next.reminderAt);assertNull(next.reminderZone)}
    @Test fun reopeningAllowsChoosingColumn() {val done=completePlannedTask(rich(),true,at,today);val next=changeTaskStatus(done,TaskStatus.DOING,at,today);assertNull(next.completedAt);assertEquals(TaskStatus.DOING,next.status())}
    @Test fun recurringDoneReturnsToTodo() {val t=rich().copy(repeat=RepeatRule.DAILY);val next=changeTaskStatus(t,TaskStatus.DONE,at,today);assertEquals("2026-09-17",next.due);assertEquals(TaskStatus.TODO,next.status());assertEquals("2026-09-17 11:00",Reminders.display(next.reminderAt!!,next.reminderZone!!))}
    @Test fun pauseFreezesRemainingTime() {val c=FocusClock.start("s","t",1,1000).pause(31000);assertEquals(30,c.remaining(999999));assertFalse(c.finished(999999))}
    @Test fun resumeExcludesPausedTime() {val c=FocusClock.start("s","t",1,1000).pause(31000).resume(100000);assertEquals(20,c.remaining(110000));assertTrue(c.finished(130000))}
    @Test(expected=IllegalStateException::class) fun completedClockCannotPause() {FocusClock.start("s","t",1,0).pause(60000)}
    @Test fun nextWorkAndBreakPreserveSettings() {val c=FocusClock.start("a","t",50,0,10,20);val rest=c.next(3000000,"b");assertEquals(FocusPhase.BREAK,rest.phase);assertEquals(600,rest.durationSeconds);val next=rest.next(rest.deadline,"c");assertEquals(3000,next.durationSeconds);assertEquals(FocusPhase.WORK,next.phase)}
    @Test fun fourthBlockUsesLongBreak() {val c=FocusClock.start("a","t",25,0).copy(completedBlocks=3);val rest=c.next(c.deadline,"b");assertEquals(900,rest.durationSeconds);assertEquals(4,rest.completedBlocks)}
    @Test fun pausedClockRoundTrips() {val c=FocusClock.start("s","t",25,0).pause(30000);assertEquals(c,FocusClockCodec.decode(FocusClockCodec.encode(c)))}
    @Test fun oldClockLoadsAsWork() {val c=FocusClockCodec.decode("""{"sessionId":"s","taskId":"t","seconds":600,"deadline":1000000}""");assertEquals(FocusPhase.WORK,c.phase);assertEquals(10,c.workMinutes);assertNull(c.pausedMillis)}
    @Test fun sessionRetryDoesNotDoubleCount() {val t=rich();assertEquals(t,recordFocusSession(t,FocusSession("session",60,at+999)))}
    @Test fun newSessionsHaveDateAndReceipt() {val t=rich();assertEquals(60,t.focusSeconds);assertEquals(listOf("session"),t.focusReceipts);assertEquals(at,t.focusHistory.single().endedAt)}
    @Test(expected=IllegalArgumentException::class) fun unknownReceiptInHistoryRejected() {validateTask(TaskDetails(focusHistory=listOf(FocusSession("bad",60,at))))}
    @Test(expected=IllegalArgumentException::class) fun negativeSessionRejected() {recordFocusSession(TaskDetails(),FocusSession("bad",60,-1))}
    @Test fun historyDeduplicatesImportedCopies() {val t=rich();assertEquals(1,focusHistory(listOf(note("a",t),note("b",t))).size)}
    @Test fun weekIncludesOnlySevenLocalDays() {val t=rich();val old=recordFocusSession(t,FocusSession("old",60,at-8*86400000));val days=weeklyFocus(listOf(note(task=old)),today,ZoneId.of("Europe/Rome"));assertEquals(7,days.size);assertEquals(60,days.sumOf {it.second});assertEquals(today,days.last().first)}
    @Test fun archivedHistoryRemainsButTrashIsExcluded() {val n=note(task=rich());assertEquals(1,focusHistory(listOf(n.copy(archived=true))).size);assertTrue(focusHistory(listOf(n.copy(deletedAt=at))).isEmpty())}
    @Test fun reminderZoneRoundTrip() {assertEquals(at,Reminders.parse(Reminders.display(at,"Europe/Rome"),"Europe/Rome"))}
    @Test(expected=IllegalArgumentException::class) fun daylightSavingGapRejected() {Reminders.parse("2026-03-29 02:30","Europe/Rome")}
    @Test fun activeReminderRejectsTrashAndCompleted() {val n=note(task=rich());assertTrue(Reminders.active(n));assertFalse(Reminders.active(n.copy(deletedAt=at)));assertFalse(Reminders.active(n.copy(archived=true)));assertFalse(Reminders.active(n.copy(task=n.task!!.copy(completedAt=at))))}
    @Test fun taskCodecPreservesAllNewProperties() {val t=rich();assertEquals(t,TaskCodec.decode(TaskCodec.encode(t)))}
    @Test fun oldTaskDefaultsAreSafe() {val obj=JSONObject(TaskCodec.encode(rich())!!);listOf("stage","reminderAt","reminderZone","focusHistory").forEach {obj.remove(it)};val t=TaskCodec.read(obj)!!;assertEquals(TaskStage.TODO,t.stage);assertNull(t.reminderAt);assertTrue(t.focusHistory.isEmpty());assertEquals(60,t.focusSeconds)}
    @Test fun backupV6RoundTripsAllFields() {val data=BackupSnapshot(listOf(note(task=rich())),emptyList(),emptyList());val text=BackupWriter.json(data);assertEquals(6,JSONObject(text).getInt("formatVersion"));assertEquals(data,BackupReader.parse(text))}
    @Test fun syncV6RoundTripsAllFields() {val d=SyncDocument.from(note(task=rich()),null);assertEquals(d,SyncCodec.decode(SyncCodec.encode(d)))}
    @Test fun workflowChangesCauseConflict() {val d=SyncDocument.from(note(task=rich()),null);assertEquals(SyncDecision.CONFLICT,decideSync(d,d.copy(task=d.task!!.copy(stage=TaskStage.WAITING)),d.copy(task=d.task!!.copy(reminderAt=at+600000))))}
    @Test(expected=IllegalArgumentException::class) fun reminderWithoutZoneRejected() {validateTask(TaskDetails(reminderAt=at))}
    @Test(expected=IllegalArgumentException::class) fun excessiveHistoryTotalsRejected() {validateTask(TaskDetails(focusSeconds=1,focusReceipts=listOf("s"),focusHistory=listOf(FocusSession("s",60,at))))}
    @Test fun snoozeDoesNotShiftFutureRecurrenceTime() {
        val task=rich().copy(repeat=RepeatRule.DAILY,reminderAt=at+600000,reminderTime="11:00")
        val next=completePlannedTask(task,true,at+600000,today)
        assertEquals("2026-09-17 11:00",Reminders.display(next.reminderAt!!,next.reminderZone!!))
        assertEquals(task,TaskCodec.decode(TaskCodec.encode(task)))
    }
}

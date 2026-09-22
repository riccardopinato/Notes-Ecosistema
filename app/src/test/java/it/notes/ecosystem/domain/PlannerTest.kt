package it.notes.ecosystem.domain
import java.time.LocalDate
import org.junit.Test
import org.junit.Assert.*
class PlannerTest {
    private val today = LocalDate.of(2026, 9, 15)
    private fun n(id: String, task: TaskDetails? = TaskDetails(), deleted: Long? = null) = Note(id, "Titolo", "Descrizione", createdAt=1, updatedAt=2, deletedAt=deleted, task=task)
    @Test fun todayIncludesOverdueAndTodayOnly() { val rows=listOf(n("a",TaskDetails(due="2026-09-14")),n("b",TaskDetails(due="2026-09-15")),n("c",TaskDetails(due="2026-09-16")),n("d"));assertEquals(listOf("a","b"),plannerNotes(rows,PlannerScope.TODAY,today).map{it.id}) }
    @Test fun upcomingExcludesCompletedAndTrash() { assertEquals(listOf("a"),plannerNotes(listOf(n("a",TaskDetails(due="2026-09-16")),n("b",TaskDetails(due="2026-09-16",completedAt=3)),n("c",TaskDetails(due="2026-09-16"),4)),PlannerScope.UPCOMING,today).map{it.id}) }
    @Test fun standaloneTasksAreExcludedFromNoteLibrary() { assertEquals(listOf("note"),filterNotes(listOf(n("task"),n("note",null)),NoteFilter.ALL).map{it.id}) }
    @Test fun taskDescriptionDoesNotCreateChecklistDuplicates() { assertTrue(TaskIndex().update(listOf(n("task").copy(body="- [ ] Uno"))).isEmpty()) }
    @Test fun undatedTasksRemainInAll() { assertEquals(1,plannerNotes(listOf(n("a")),PlannerScope.ALL,today).size) }
    @Test fun prioritySortsSameDate() { assertEquals(listOf("b","a"),plannerNotes(listOf(n("a",TaskDetails(priority=1)),n("b",TaskDetails(priority=3))),PlannerScope.ALL,today).map{it.id}) }
    @Test fun completionAndReopeningKeepStableIdentityAndMetadata() { val t=TaskDetails(priority=3,linkedNoteId="note");val done=completePlannedTask(t,true,10,today);assertEquals(10L,done.completedAt);assertEquals(t,completePlannedTask(done,false,11,today)) }
    @Test fun dailySkipsMissedOccurrences() { val t=completePlannedTask(TaskDetails(due="2026-09-10",repeat=RepeatRule.DAILY),true,1,today);assertEquals("2026-09-16",t.due);assertEquals(1,t.completedCycles);assertNull(t.completedAt) }
    @Test fun weeklyPreservesWeekday() { assertEquals("2026-09-21",completePlannedTask(TaskDetails(due="2026-09-07",repeat=RepeatRule.WEEKLY),true,1,today).due) }
    @Test fun monthlyClampsToEndOfMonth() { assertEquals("2026-02-28",completePlannedTask(TaskDetails(due="2026-01-31",repeat=RepeatRule.MONTHLY),true,1,LocalDate.of(2026,1,31)).due) }
    @Test fun repeatRequiresDate() { rejected { validateTask(TaskDetails(repeat=RepeatRule.DAILY)) } }
    @Test fun invalidDateAndPriorityRejected() { rejected { validateTask(TaskDetails(due="2026-02-30")) };rejected { validateTask(TaskDetails(priority=4)) } }
    @Test fun trashIsIsolated() { assertEquals(1,plannerNotes(listOf(n("a",deleted=4),n("b")),PlannerScope.TRASH,today).size) }
    @Test fun focusRetryIsIdempotent() { val t=recordFocus(TaskDetails(),"s",1500);assertEquals(t,recordFocus(t,"s",1500));assertEquals(1500L,t.focusSeconds) }
    @Test fun distinctFocusSessionsAccumulate() { assertEquals(1800L,recordFocus(recordFocus(TaskDetails(),"a",1500),"b",300).focusSeconds) }
    @Test fun focusReceiptLimitRejectsWithoutMutation() { val t=TaskDetails(focusReceipts=(1..200).map{it.toString()});rejected { recordFocus(t,"new",60) };assertEquals(t,recordFocus(t,"1",60)) }
    @Test fun focusClockSurvivesLeavingScreen() { val c=FocusClock.start("s","t",25,1000);assertEquals(0L,c.remaining(1501000));assertTrue(c.finished(1501000));assertEquals(1500L,c.remaining(0)) }
    @Test fun focusClockRejectsInvalidDuration() { rejected { FocusClock.start("s","t",0,1000) };rejected { FocusClock.start("s","t",121,1000) } }
    private fun rejected(block:()->Unit) { try { block();fail("Expected rejection") } catch(_:Exception) {} }
}

package it.notes.ecosystem.data
import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import it.notes.ecosystem.domain.*
import kotlinx.coroutines.test.runTest
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import java.time.LocalDate

@RunWith(AndroidJUnit4::class)
class ProductivityRepositoryTest {
    private lateinit var db:NotesDatabase
    private lateinit var repo:LocalNotesRepository
    private val at=1789556400000L
    private val details=TaskDetails(stage=TaskStage.DOING,reminderAt=at,reminderZone="Europe/Rome")
    @Before fun setup(){db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),NotesDatabase::class.java).build();repo=LocalNotesRepository(db)}
    @After fun cleanup(){db.close()}
    private suspend fun seed(){repo.savePlannedTask(null,"task","Attività","Testo",details)}
    @Test fun snoozeUpdatesOnlyMatchingReminder()=runTest {seed();assertTrue(repo.snoozeReminder("task",at,at+600000));assertEquals(at+600000,repo.get("task")!!.task!!.reminderAt)}
    @Test fun staleSnoozeCannotOverwriteNewDate()=runTest {seed();repo.snoozeReminder("task",at,at+600000);assertFalse(repo.snoozeReminder("task",at,at+1200000));assertEquals(at+600000,repo.get("task")!!.task!!.reminderAt)}
    @Test fun completedTaskRejectsSnooze()=runTest {seed();val old=repo.get("task")!!;repo.updatePlannedTask(old,changeTaskStatus(old.task!!,TaskStatus.DONE,at,LocalDate.of(2026,9,16)));assertFalse(repo.snoozeReminder("task",at,at+600000))}
    @Test fun trashedTaskRejectsSnooze()=runTest {seed();val old=repo.get("task")!!;repo.updatePlannedTask(old,old.task!!,true);assertFalse(repo.snoozeReminder("task",at,at+600000))}
    @Test fun datedSessionIsTransactionalAndIdempotent()=runTest {seed();val session=FocusSession("session",60,at);repo.addFocusSession("task",session);repo.addFocusSession("task",session);val t=repo.get("task")!!.task!!;assertEquals(60,t.focusSeconds);assertEquals(listOf(session),t.focusHistory);assertEquals(listOf("session"),t.focusReceipts)}
    @Test fun staleKanbanWriteCannotEraseNewFocusSession()=runTest {
        seed();val old=repo.get("task")!!;repo.addFocusSession("task",FocusSession("s",60,at))
        try {repo.updatePlannedTask(old,old.task!!.copy(stage=TaskStage.WAITING));fail("Expected conflict")}catch(_:IllegalStateException){}
        assertEquals(60,repo.get("task")!!.task!!.focusSeconds)
    }
    @Test fun importPreservesHistoryStatusAndReminder()=runTest {
        seed();repo.addFocusSession("task",FocusSession("s",60,at));repo.importCopies(repo.snapshot())
        val rows=repo.snapshot().notes;val copy=rows.single {it.id!="task"};assertEquals(repo.get("task")!!.task,copy.task)
        assertEquals(1,focusHistory(rows).size)
    }
}

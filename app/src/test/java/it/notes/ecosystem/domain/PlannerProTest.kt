package it.notes.ecosystem.domain

import org.junit.Assert.*
import org.junit.Test
import java.time.LocalDate
import java.time.LocalTime
import java.time.YearMonth

class PlannerProTest {

    private fun task(
        id: String,
        details: TaskDetails,
        title: String = id,
    ) = Note(
        id = id,
        title = title,
        body = "",
        createdAt = 1,
        updatedAt = 1,
        task = details,
    )

    @Test
    fun scheduleDoesNotChangeDueDate() {
        val original = TaskDetails(
            due = "2026-09-20"
        )

        val result = PlannerPro.schedule(
            original,
            date = LocalDate.of(2026, 9, 18),
            time = LocalTime.of(15, 30),
            minutes = 60,
        )

        assertEquals("2026-09-20", result.due)
        assertEquals("2026-09-18", result.plannedDate)
        assertEquals("15:30", result.plannedTime)
        assertEquals(60, result.plannedMinutes)
    }

    @Test
    fun unscheduleKeepsDueDate() {
        val original = TaskDetails(
            due = "2026-09-20",
            plannedDate = "2026-09-18",
            plannedTime = "15:30",
            plannedMinutes = 60,
        )

        val result = PlannerPro.unschedule(original)

        assertEquals("2026-09-20", result.due)
        assertNull(result.plannedDate)
        assertNull(result.plannedTime)
    }

    @Test
    fun timeRequiresDate() {
        val result = runCatching {
            validateTask(
                TaskDetails(
                    plannedTime = "12:30"
                )
            )
        }

        assertTrue(result.isFailure)
    }

    @Test
    fun dayNotesSortTimedBeforeUntimed() {
        val notes = listOf(
            task(
                "untimed",
                TaskDetails(plannedDate = "2026-09-18"),
            ),
            task(
                "late",
                TaskDetails(
                    plannedDate = "2026-09-18",
                    plannedTime = "16:00",
                ),
            ),
            task(
                "early",
                TaskDetails(
                    plannedDate = "2026-09-18",
                    plannedTime = "09:00",
                ),
            ),
        )

        assertEquals(
            listOf("early", "late", "untimed"),
            PlannerPro.dayNotes(
                notes,
                LocalDate.of(2026, 9, 18),
            ).map { it.id }
        )
    }

    @Test
    fun overlappingBlocksAreDetected() {
        val notes = listOf(
            task(
                "a",
                TaskDetails(
                    plannedDate = "2026-09-18",
                    plannedTime = "10:00",
                    plannedMinutes = 60,
                ),
            ),
            task(
                "b",
                TaskDetails(
                    plannedDate = "2026-09-18",
                    plannedTime = "10:30",
                    plannedMinutes = 30,
                ),
            ),
        )

        val blocks = PlannerPro.timeBlocks(
            notes,
            LocalDate.of(2026, 9, 18),
        )

        assertEquals(
            1,
            PlannerPro.collisions(blocks).size
        )
    }

    @Test
    fun adjacentBlocksDoNotCollide() {
        val notes = listOf(
            task(
                "a",
                TaskDetails(
                    plannedDate = "2026-09-18",
                    plannedTime = "10:00",
                    plannedMinutes = 30,
                ),
            ),
            task(
                "b",
                TaskDetails(
                    plannedDate = "2026-09-18",
                    plannedTime = "10:30",
                    plannedMinutes = 30,
                ),
            ),
        )

        assertTrue(
            PlannerPro.collisions(
                PlannerPro.timeBlocks(
                    notes,
                    LocalDate.of(2026, 9, 18),
                )
            ).isEmpty()
        )
    }

    @Test
    fun recurringCompletionClearsOldTimeBlock() {
        val input = TaskDetails(
            due = "2026-09-17",
            repeat = RepeatRule.DAILY,
            plannedDate = "2026-09-17",
            plannedTime = "09:00",
            plannedMinutes = 30,
        )

        val result = completePlannedTask(
            task = input,
            completed = true,
            now = 1_789_630_000_000,
            today = LocalDate.of(2026, 9, 17),
        )

        assertEquals("2026-09-18", result.due)
        assertNull(result.plannedDate)
        assertNull(result.plannedTime)
    }

    @Test
    fun monthGridAlwaysHas42Days() {
        assertEquals(
            42,
            PlannerPro.monthGrid(
                YearMonth.of(2026, 9)
            ).size
        )
    }
}

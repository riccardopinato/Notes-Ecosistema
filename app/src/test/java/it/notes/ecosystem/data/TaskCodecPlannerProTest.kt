package it.notes.ecosystem.data

import it.notes.ecosystem.domain.*
import org.junit.Assert.*
import org.junit.Test

class TaskCodecPlannerProTest {

    @Test
    fun plannerFieldsRoundTrip() {
        val original = TaskDetails(
            due = "2026-09-20",
            plannedDate = "2026-09-18",
            plannedTime = "15:30",
            plannedMinutes = 60,
        )

        assertEquals(
            original,
            TaskCodec.decode(TaskCodec.encode(original))
        )
    }

    @Test
    fun legacyJsonGetsPlannerDefaults() {
        val legacy =
            """{
                "due":null,
                "priority":0,
                "repeat":"NONE",
                "completedAt":null,
                "linkedNoteId":null,
                "reminderTime":null,
                "stage":"TODO",
                "reminderAt":null,
                "reminderZone":null,
                "focusHistory":[],
                "focusSeconds":0,
                "focusReceipts":[],
                "completedCycles":0
            }""".trimIndent()

        val decoded = checkNotNull(TaskCodec.decode(legacy))

        assertNull(decoded.plannedDate)
        assertNull(decoded.plannedTime)
        assertEquals(
            PlannerPro.DEFAULT_BLOCK_MINUTES,
            decoded.plannedMinutes
        )
    }
}

package it.notes.ecosystem.domain

import org.junit.Assert.*
import org.junit.Test
import java.time.LocalDate

class PerformanceHotPathTest {

    @Test
    fun checklistMarkerFindsOpenAndDoneItems() {
        assertTrue(
            Checklist.hasMarker(
                "Titolo\n- [ ] uno\nTesto"
            )
        )

        assertTrue(
            Checklist.hasMarker(
                "* [x] fatto"
            )
        )

        assertFalse(
            Checklist.hasMarker(
                "- normale\n[link](url)"
            )
        )
    }

    @Test
    fun plannerIndexKeepsPlannedAndDueSeparate() {
        val note =
            Note(
                id = "a",
                title = "Task",
                body = "",
                createdAt = 1,
                updatedAt = 1,
                task =
                    TaskDetails(
                        due = "2026-09-20",
                        plannedDate = "2026-09-18",
                        plannedTime = "10:00",
                        plannedMinutes = 60,
                    ),
            )

        val index =
            PlannerPro.plannerIndex(
                listOf(note)
            )

        assertEquals(
            listOf(note),
            PlannerPro.dayNotes(
                index,
                LocalDate.of(
                    2026,
                    9,
                    18,
                ),
            )
        )

        assertEquals(
            listOf(note),
            PlannerPro.dueOn(
                index,
                LocalDate.of(
                    2026,
                    9,
                    20,
                ),
            )
        )

        assertTrue(
            PlannerPro.dueOn(
                index,
                LocalDate.of(
                    2026,
                    9,
                    18,
                ),
            ).isEmpty()
        )
    }

    @Test
    fun plannerIndexExcludesCompletedDeletedAndArchived() {
        val active =
            Note(
                id = "active",
                title = "A",
                body = "",
                createdAt = 1,
                updatedAt = 1,
                task =
                    TaskDetails(
                        plannedDate =
                            "2026-09-18",
                    ),
            )

        val completed =
            active.copy(
                id = "completed",
                task =
                    TaskDetails(
                        plannedDate =
                            "2026-09-18",
                        completedAt = 10L,
                    ),
            )

        val deleted =
            active.copy(
                id = "deleted",
                deletedAt = 20L,
            )

        val archived =
            active.copy(
                id = "archived",
                archived = true,
            )

        val index =
            PlannerPro.plannerIndex(
                listOf(
                    active,
                    completed,
                    deleted,
                    archived,
                )
            )

        assertEquals(
            listOf(active),
            index.planned[
                "2026-09-18"
            ]
        )
    }

    @Test
    fun plannerIndexKeepsUnplannedTasks() {
        val note =
            Note(
                id = "u",
                title = "Unplanned",
                body = "",
                createdAt = 1,
                updatedAt = 1,
                task =
                    TaskDetails(
                        due = "2026-09-21"
                    ),
            )

        val index =
            PlannerPro.plannerIndex(
                listOf(note)
            )

        assertEquals(
            listOf(note),
            index.unplanned,
        )
    }
}

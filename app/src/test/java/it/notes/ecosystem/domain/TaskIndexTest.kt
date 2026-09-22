package it.notes.ecosystem.domain

import org.junit.Assert.*
import org.junit.Test

class TaskIndexTest {
    private fun note(id: String = "a", body: String = "- [ ] Uno") =
        Note(id = id, title = "Titolo", body = body, createdAt = 1L, updatedAt = 1L)

    @Test fun metadataChangesReuseParsingButRefreshTaskTitle() {
        var calls = 0
        val index = TaskIndex { calls++; Checklist.parse(it) }
        val original = note()
        index.update(listOf(original))
        val updated = index.update(listOf(original.copy(title = "Nuovo", favorite = true)))
        assertEquals(1, calls)
        assertEquals("Nuovo", updated.single().noteTitle)
    }

    @Test fun onlyChangedBodyIsParsedAndSourceBodyIsCurrent() {
        var calls = 0
        val index = TaskIndex { calls++; Checklist.parse(it) }
        val a = note()
        val b = note(id = "b")
        index.update(listOf(a, b))
        val changed = a.copy(body = "- [x] Uno")
        val tasks = index.update(listOf(changed, b))
        assertEquals(3, calls)
        assertTrue(tasks.first().item.completed)
        assertEquals(changed.body, tasks.first().sourceBody)
        assertFalse(tasks.last().item.completed)
    }

    @Test fun trashEvictsEntryAndRestoreRebuildsIt() {
        var calls = 0
        val index = TaskIndex { calls++; Checklist.parse(it) }
        val a = note()
        index.update(listOf(a))
        assertTrue(index.update(listOf(a.copy(deletedAt = 2L))).isEmpty())
        assertEquals(1, calls)
        assertEquals(1, index.update(listOf(a)).size)
        assertEquals(2, calls)
    }

    @Test fun removalEvictsEntryAndDuplicateLabelsRemainSeparate() {
        var calls = 0
        val index = TaskIndex { calls++; Checklist.parse(it) }
        val a = note(body = "- [ ] Uno\n- [ ] Uno")
        assertEquals(listOf(0, 1), index.update(listOf(a)).map { it.item.lineIndex })
        assertTrue(index.update(emptyList()).isEmpty())
        index.update(listOf(a))
        assertEquals(2, calls)
    }
}

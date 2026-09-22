package it.notes.ecosystem.domain

import org.junit.Assert.*
import org.junit.Test

class ChecklistTest {
    @Test fun parsesOnlySupportedChecklistRowsAndTracksDuplicateLabels() {
        val body = "Testo\n- [ ] Caffè\n* [X] Fatto\n+ [x] Fatto\n- [] No\n- [ ]   \n    - [ ] Codice"
        val items = Checklist.parse(body)
        assertEquals(listOf("Caffè", "Fatto", "Fatto"), items.map { it.label })
        assertEquals(listOf(false, true, true), items.map { it.completed })
        assertEquals(listOf(1, 2, 3), items.map { it.lineIndex })
    }

    @Test fun ignoresFencedCodeAndResumesAfterClosingFence() {
        val tick = 96.toChar().toString().repeat(3)
        val body = tick + "kotlin\n- [ ] Esempio\n" + tick + "\n- [ ] Vera\n~~~\n- [x] Altro esempio\n~~~"
        assertEquals(listOf("Vera"), Checklist.parse(body).map { it.label })
    }

    @Test fun togglePreservesUnicodeLineEndingsAndEveryOtherCharacter() {
        val body = "🙂 Introduzione\r\n  - [ ] Caffè  \r\n- [x] Già fatto\r\n"
        val changed = Checklist.setCompleted(body, 1, true)
        assertEquals("🙂 Introduzione\r\n  - [x] Caffè  \r\n- [x] Già fatto\r\n", changed)
        assertEquals(body, Checklist.setCompleted(changed, 1, false))
    }

    @Test fun togglingDuplicateLabelChangesOnlySelectedRow() {
        val body = "- [ ] Uguale\n- [ ] Uguale"
        assertEquals("- [ ] Uguale\n- [x] Uguale", Checklist.setCompleted(body, 1, true))
    }

    @Test fun appendSeparatesFromExistingTextAndPreservesCrLf() {
        assertEquals("Testo\r\n- [ ] Nuova", Checklist.append("Testo\r\n", " Nuova "))
        assertEquals("Testo\n- [ ] Nuova", Checklist.append("Testo", "Nuova"))
        assertEquals("- [ ] Prima", Checklist.append("", "Prima"))
    }

    @Test fun rejectsMultilineTaskAndAppendInsideUnclosedCode() {
        try { Checklist.append("", "Prima\nSeconda"); fail("Multiline accepted") }
        catch (_: IllegalArgumentException) { }
        try { Checklist.append("~~~\nCodice", "Task"); fail("Unclosed code accepted") }
        catch (_: IllegalArgumentException) { }
    }

    @Test fun invalidTaskPositionFailsInsteadOfEditingOrdinaryText() {
        try { Checklist.setCompleted("Testo\n- [ ] Task", 0, true); fail("Wrong row accepted") }
        catch (_: IllegalStateException) { }
    }

    @Test fun aggregationExcludesTrashedNotes() {
        val active = Note("a", "Attiva", "- [ ] Task", null, false, 1, 2)
        val trashed = active.copy(id = "b", deletedAt = 3)
        assertEquals(listOf("a"), collectTasks(listOf(active, trashed)).map { it.noteId })
    }
}

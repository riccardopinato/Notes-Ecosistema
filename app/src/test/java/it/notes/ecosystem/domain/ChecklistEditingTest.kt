package it.notes.ecosystem.domain

import org.junit.Assert.*
import org.junit.Test

class ChecklistEditingTest {
    @Test fun detectsOneLevelOfChildrenButNotIndentedCode() {
        val items = Checklist.parse("- [ ] Padre\n  - [ ] Figlio\n    - [ ] Codice\n- [ ] Altro")
        assertEquals(listOf(0, 1, 0), items.map { it.depth })
        assertEquals(0, items[1].parentLine)
    }
    @Test fun renamesOnlySelectedDuplicateAndPreservesCrLf() {
        assertEquals("- [ ] Uguale\r\n- [x] Nuova\r\n", ChecklistEditing.rename("- [ ] Uguale\r\n- [x] Uguale\r\n", 1, "Nuova"))
    }
    @Test fun addsChildBeforeFollowingRootAndKeepsFinalNewline() {
        assertEquals("- [ ] A\r\n  - [ ] Figlio\r\n- [ ] B\r\n", ChecklistEditing.addChild("- [ ] A\r\n- [ ] B\r\n", 0, "Figlio"))
    }
    @Test fun addsChildToFinalLineWithoutJoiningLabels() {
        assertEquals("- [ ] A\n  - [ ] Figlio", ChecklistEditing.addChild("- [ ] A", 0, "Figlio"))
    }
    @Test fun movesParentWithChildren() {
        val body = "Testo\n- [ ] A\n  - [ ] Figlio\n- [ ] B"
        assertEquals("Testo\n- [ ] B\n- [ ] A\n  - [ ] Figlio", ChecklistEditing.move(body, 1, 3))
    }
    @Test fun movesChildrenInsideSameParent() {
        val body = "- [ ] A\n  - [ ] Uno\n  - [ ] Due"
        assertEquals("- [ ] A\n  - [ ] Due\n  - [ ] Uno", ChecklistEditing.move(body, 1, 2))
    }
    @Test fun refusesMovingAcrossProse() {
        try { ChecklistEditing.move("- [ ] A\nTesto\n- [ ] B", 0, 2); fail() } catch (_: IllegalArgumentException) {}
    }
    @Test fun refusesMovingBetweenDifferentParents() {
        try { ChecklistEditing.move("- [ ] A\n  - [ ] Uno\n- [ ] B\n  - [ ] Due", 1, 3); fail() } catch (_: IllegalArgumentException) {}
    }
    @Test fun completedLastPreservesSectionsAndHierarchy() {
        val body = "- [x] A\n  - [ ] Figlio\n- [ ] B\n\nTesto\n- [x] C\n- [ ] D\n"
        assertEquals("- [ ] B\n- [x] A\n  - [ ] Figlio\n\nTesto\n- [ ] D\n- [x] C\n", ChecklistEditing.completedLast(body))
    }
    @Test fun rejectsMultilineRenameAndKeepsFencedCode() {
        try { ChecklistEditing.rename("- [ ] A", 0, "B\nC"); fail() } catch (_: IllegalArgumentException) {}
        val code = "~~~\n- [x] Codice\n~~~\n- [ ] Vera"
        assertEquals(code, ChecklistEditing.completedLast(code))
    }
}

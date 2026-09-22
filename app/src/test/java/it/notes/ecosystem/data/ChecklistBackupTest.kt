package it.notes.ecosystem.data

import it.notes.ecosystem.domain.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class ChecklistBackupTest {
    @Test fun jsonRoundTripPreservesChecklistStateAndFormatting() {
        val body = "Intro\r\n- [ ] Caffè\r\n- [X] Fatto\r\n"
        val data = BackupSnapshot(listOf(Note("a", "Lista", body, null, true, 1, 2)), emptyList(), emptyList())
        val restored = BackupReader.parse(BackupWriter.json(data))
        assertEquals(data, restored)
        assertEquals(listOf(false, true), Checklist.parse(restored.notes.single().body).map { it.completed })
    }
}

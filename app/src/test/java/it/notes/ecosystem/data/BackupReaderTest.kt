package it.notes.ecosystem.data

import it.notes.ecosystem.domain.*
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class BackupReaderTest {
    private val data = BackupSnapshot(
        listOf(Note("n", "Caffè", "Riga\n\"citazione\" %_", "c", true, 1, 2),
            Note("t", "Cestino", "Testo", null, false, 1, 3, 3)),
        listOf(it.notes.ecosystem.domain.Collection("c", "Lavoro")),
        listOf(Draft("n", "Modifica", "Bozza", null, 4), Draft("new", "", "Nuova", "c", 5))
    )
    @Test fun writerReaderRoundTripPreservesAllData() {
        assertEquals(data, BackupReader.read(BackupWriter.json(data).byteInputStream()))
    }
    private fun rejected(text: String) {
        try { BackupReader.parse(text); fail("Invalid backup accepted") }
        catch (_: IllegalArgumentException) { }
        catch (_: IllegalStateException) { }
    }
    @Test fun rejectsUnknownVersionAndTypeCoercion() {
        rejected(JSONObject(BackupWriter.json(data)).put("formatVersion", 999).toString())
        val value = JSONObject(BackupWriter.json(data))
        value.getJSONArray("notes").getJSONObject(0).put("favorite", "true")
        rejected(value.toString())
    }
    @Test fun rejectsDuplicateIdsAndBrokenCollectionLinks() {
        val duplicate = JSONObject(BackupWriter.json(data))
        duplicate.getJSONArray("notes").getJSONObject(1).put("id", "n")
        rejected(duplicate.toString())
        val broken = JSONObject(BackupWriter.json(data))
        broken.getJSONArray("notes").getJSONObject(0).put("collectionId", "missing")
        rejected(broken.toString())
    }
    @Test fun rejectsTrailingDataAndExcessiveNesting() {
        rejected(BackupWriter.json(data) + "{}")
        rejected("[".repeat(33) + "0" + "]".repeat(33))
    }
    @Test fun sizeLimitIsEnforcedDuringRead() {
        try {
            BackupReader.read(ByteArray(BackupReader.MAX_BYTES + 1).inputStream())
            fail("Oversized backup accepted")
        } catch (_: IllegalArgumentException) { }
    }
}

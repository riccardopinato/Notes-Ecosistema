package it.notes.ecosystem.data

import it.notes.ecosystem.domain.*
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.io.ByteArrayOutputStream
import java.util.zip.ZipInputStream

@RunWith(RobolectricTestRunner::class)
class BackupWriterTest {
    private val snapshot = BackupSnapshot(
        listOf(Note("../bad", "Titolo / particolare", "Caffè\n\"citazione\" %_", null, true, 1, 2),
            Note("deleted", "Cestino", "Da conservare", null, false, 1, 3, 3)),
        listOf(it.notes.ecosystem.domain.Collection("a", "Lavoro")),
        listOf(Draft("new", "Bozza", "Ancora da salvare", null, 4))
    )
    @Test fun jsonPreservesUnicodeNullsTrashAndDrafts() {
        val parsed = JSONObject(BackupWriter.json(snapshot))
        assertEquals(6, parsed.getInt("formatVersion"))
        assertEquals("Caffè\n\"citazione\" %_", parsed.getJSONArray("notes").getJSONObject(0).getString("body"))
        assertTrue(parsed.getJSONArray("notes").getJSONObject(0).isNull("collectionId"))
        assertEquals(3L, parsed.getJSONArray("notes").getJSONObject(1).getLong("deletedAt"))
        assertEquals("new", parsed.getJSONArray("drafts").getJSONObject(0).getString("id"))
    }
    @Test fun zipContainsFullDataAndOnlyActiveMarkdownWithSafePaths() {
        val output = ByteArrayOutputStream()
        BackupWriter.write(snapshot, output, true)
        val entries = mutableMapOf<String, String>()
        ZipInputStream(output.toByteArray().inputStream()).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                entries[entry.name] = zip.readBytes().toString(Charsets.UTF_8)
            }
        }
        assertEquals(setOf("backup.json", "note/1.md", "LEGGIMI.txt"), entries.keys)
        assertTrue(entries.getValue("note/1.md").contains(snapshot.notes[0].body))
        assertEquals(2, JSONObject(entries.getValue("backup.json")).getJSONArray("notes").length())
    }
}

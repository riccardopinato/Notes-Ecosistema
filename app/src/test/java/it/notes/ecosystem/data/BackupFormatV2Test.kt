package it.notes.ecosystem.data
import it.notes.ecosystem.domain.*
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.util.zip.ZipInputStream
class BackupFormatV2Test {
    private val data=BackupSnapshot(listOf(Note("id","Titolo","# Markdown",createdAt=1,updatedAt=2,pinned=true,archived=true)),emptyList(),emptyList())
    @Test fun versionTwoRoundTripPreservesProperties() { val text=BackupWriter.json(data);assertEquals(6,JSONObject(text).getInt("formatVersion"));assertEquals(data,BackupReader.parse(text)) }
    @Test fun legacyDefaultsAreFalse() {
        val root=JSONObject(BackupWriter.json(data)).put("formatVersion",1);val n=root.getJSONArray("notes").getJSONObject(0);n.remove("pinned");n.remove("archived")
        val note=BackupReader.parse(root.toString()).notes.single();assertFalse(note.pinned);assertFalse(note.archived)
    }
    @Test fun v2RequiresBooleanFields() {
        for (bad in listOf(JSONObject.NULL,"true",1)) {
            val root=JSONObject(BackupWriter.json(data));root.getJSONArray("notes").getJSONObject(0).put("pinned",bad)
            try { BackupReader.parse(root.toString());fail() } catch (_:IllegalStateException) {}
        }
    }
    @Test fun markdownZipContainsArchiveAndCompleteBackup() {
        val out=ByteArrayOutputStream();BackupWriter.write(data,out,true)
        val entries=mutableMapOf<String,String>();ZipInputStream(out.toByteArray().inputStream()).use { zip ->
            while(true) { val e=zip.nextEntry?:break;entries[e.name]=zip.readBytes().toString(Charsets.UTF_8) }
        }
        assertTrue(entries.containsKey("archivio/1.md"));assertEquals(data,BackupReader.parse(entries.getValue("backup.json")))
    }
}

package it.notes.ecosystem.data
import it.notes.ecosystem.domain.*
import org.json.JSONObject
import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Test
class TagsBackupTest {
    private val data=BackupSnapshot(listOf(Note("a","Title","Body",createdAt=1,updatedAt=2,pinned=true,archived=true,tags=listOf("work"))),emptyList(),listOf(Draft("a","Draft","Changed",null,3,listOf("draft"))))
    @Test fun v3RoundTripIncludesDraftTags() { val text=BackupWriter.json(data);assertEquals(6,JSONObject(text).getInt("formatVersion"));assertEquals(data,BackupReader.parse(text)) }
    @Test fun v2WithoutTagsPreservesFlags() {
        val root=JSONObject(BackupWriter.json(data)).put("formatVersion",2)
        root.getJSONArray("notes").getJSONObject(0).remove("tags");root.getJSONArray("drafts").getJSONObject(0).remove("tags")
        val loaded=BackupReader.parse(root.toString());assertTrue(loaded.notes.single().pinned);assertTrue(loaded.notes.single().archived);assertTrue(loaded.notes.single().tags.isEmpty());assertTrue(loaded.drafts.single().tags.isEmpty())
    }
    @Test fun v1DefaultsTagsAndFlags() { val root=JSONObject(BackupWriter.json(data)).put("formatVersion",1);val n=BackupReader.parse(root.toString()).notes.single();assertFalse(n.pinned);assertFalse(n.archived);assertTrue(n.tags.isEmpty()) }
    @Test fun v3RejectsWrongTagTypesAndMissingTags() {
        for (value in listOf<Any>(JSONObject.NULL,"work",JSONArray().put(123))) {
            val root=JSONObject(BackupWriter.json(data));root.getJSONArray("notes").getJSONObject(0).put("tags",value)
            rejected { BackupReader.parse(root.toString()) }
        }
        val root=JSONObject(BackupWriter.json(data));root.getJSONArray("drafts").getJSONObject(0).remove("tags");rejected { BackupReader.parse(root.toString()) }
    }
    @Test fun storageCodecNormalizesAndPreservesUnicode() { assertEquals(listOf("caffè","work"),TagCodec.decode(TagCodec.encode(listOf("Work","Caffè","work")))) }
    @Test fun tagCodecRejectsTooManyValues() { rejected { TagCodec.read(JSONArray((1..21).map { "t$it" })) } }
    private fun rejected(block: () -> Unit) { try { block();fail() } catch (_:Exception) {} }
}

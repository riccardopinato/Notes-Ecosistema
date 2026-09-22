package it.notes.ecosystem.cloud

import it.notes.ecosystem.domain.CloudState
import it.notes.ecosystem.domain.Note
import it.notes.ecosystem.domain.NoteVisibility
import it.notes.ecosystem.sync.SyncDocument
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class CloudRecordCodecTest {
    private val note = Note(
        id = "4d89d77a-9081-4db1-9d48-20dc27e9b2e1",
        title = "Cloud",
        body = "# Test\ncontenuto",
        collectionId = null,
        favorite = true,
        createdAt = 10,
        updatedAt = 20,
        pinned = true,
        tags = listOf("sync"),
    )

    @Test fun cloudPayloadRoundTripsCanonicalSyncDocument() {
        val document = SyncDocument.from(note, "Progetti")
        assertEquals(document, CloudRecordCodec.document(CloudRecordCodec.payload(document)))
    }

    @Test fun remoteRecordValidatesMatchingIdAndRevision() {
        val document = SyncDocument.from(note, null)
        val row = JSONObject()
            .put("id", note.id)
            .put("payload", JSONObject(CloudRecordCodec.payload(document)))
            .put("client_updated_at", 20)
            .put("deleted_at", JSONObject.NULL)
            .put("revision", 7)
            .put("updated_by", "account")
        val parsed = CloudRecordCodec.remote(row)
        assertEquals(7, parsed.revision)
        assertEquals(note.id, parsed.document.id)
        assertNull(parsed.deletedAt)
    }

    @Test fun newNotesRemainPrivateAndLocalByDefault() {
        assertEquals(NoteVisibility.PRIVATE, note.visibility)
        assertEquals(CloudState.LOCAL, note.cloudState)
        assertNull(note.spaceId)
        assertNull(note.cloudAccountId)
    }
}

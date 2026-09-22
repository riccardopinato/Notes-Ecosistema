package it.notes.ecosystem.sync

import org.junit.Assert.*
import org.junit.Test

class SyncCodecTest {
    private fun note() = SyncDocument("../id🙂", "Titolo --> e \"quote\"", "# Titolo\r\n- [ ] Caffè🙂\r\n", "Raccolta", true, 0, 9, null)
    @Test fun roundTripPreservesMarkdownAndEscapesCommentDelimiter() {
        val original = note(); val encoded = SyncCodec.encode(original)
        assertEquals(original, SyncCodec.decode(encoded))
        assertEquals(1, encoded.substringBefore('\n').windowed(3).count { it == "-->" })
    }
    @Test fun filenameCannotEscapeFolder() {
        assertTrue(SyncCodec.filename(note().id).matches(Regex("[a-f0-9]{64}\\.md")))
    }
    @Test fun externalMarkdownEditIsReadWithoutChangingMetadata() {
        val original = note(); val text = SyncCodec.encode(original).substringBefore('\n') + "\nNuovo testo"
        assertEquals(original.copy(body = "Nuovo testo"), SyncCodec.decode(text))
    }
    @Test fun incompatibleVersionRejected() {
        try { SyncCodec.decode(SyncCodec.encode(note()).replace("\"version\":6", "\"version\":99")); fail() }
        catch (_: IllegalArgumentException) {}
    }
    @Test fun oversizedNoteRejected() {
        try { SyncCodec.decode(SyncCodec.encode(note().copy(body = "x".repeat(SyncCodec.MAX_BYTES)))); fail() }
        catch (_: IllegalArgumentException) {}
    }
    @Test fun missingHeaderRejected() {
        try { SyncCodec.decode("# Nota\nTesto"); fail() } catch (_: IllegalArgumentException) {}
    }
    @Test fun versionTwoFlagsRoundTrip() { val n=note().copy(pinned=true,archived=true);assertEquals(n,SyncCodec.decode(SyncCodec.encode(n))) }
    @Test fun legacyDocumentDefaultsAreFalse() {
        val text=SyncCodec.encode(note()).replace("\"version\":6","\"version\":1")
        val n=SyncCodec.decode(text);assertFalse(n.pinned);assertFalse(n.archived)
    }
    @Test fun versionTwoRejectsCoercedFlags() {
        try { SyncCodec.decode(SyncCodec.encode(note()).replace("\"pinned\":false","\"pinned\":\"false\""));fail() } catch (_:IllegalStateException) {}
    }
    @Test fun tagMetadataRoundTrip() { val n=note().copy(tags=listOf("app","work"));assertEquals(n,SyncCodec.decode(SyncCodec.encode(n))) }
    @Test fun legacyVersionTwoDefaultsTags() {
        val text=SyncCodec.encode(note().copy(tags=listOf("new"))).replace("\"version\":6","\"version\":2")
        assertTrue(SyncCodec.decode(text).tags.isEmpty())
    }
}

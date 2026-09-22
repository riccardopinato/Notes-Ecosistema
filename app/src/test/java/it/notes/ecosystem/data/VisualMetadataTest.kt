package it.notes.ecosystem.data

import it.notes.ecosystem.domain.*
import org.junit.Assert.*
import org.junit.Test

class VisualMetadataTest {
    @Test fun oldMetadataDefaultsToSketch() {
        val info = checkNotNull(SketchCodec.decodeInfo("""{"linkedNoteId":null}"""))
        assertEquals(VisualDocumentKind.SKETCH, info.kind)
    }

    @Test fun whiteboardKindRoundTrips() {
        val original = SketchInfo(linkedNoteId = "note-1", kind = VisualDocumentKind.WHITEBOARD)
        assertEquals(original, SketchCodec.decodeInfo(SketchCodec.encodeInfo(original)))
    }
}

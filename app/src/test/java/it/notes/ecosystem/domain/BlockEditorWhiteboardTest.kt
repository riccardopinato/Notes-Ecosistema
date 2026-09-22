package it.notes.ecosystem.domain

import org.junit.Assert.assertEquals
import org.junit.Test

class BlockEditorWhiteboardTest {
    @Test fun whiteboardLinkRoundTrips() {
        val markdown = "[Whiteboard: Idee](notes-board://board-123)"
        val blocks = BlockEditorCodec.parse("note-1", markdown)
        assertEquals(ContentBlockType.WHITEBOARD, blocks.single().type)
        assertEquals("board-123", BlockEditorCodec.whiteboardId(blocks.single()))
        assertEquals(markdown, BlockEditorCodec.toMarkdown(blocks))
    }
}

package it.notes.ecosystem.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ContentBlocksTest {
    @Test
    fun legacyMarkdownIsPreservedByteForByteInsideBridgeBlock() {
        val body = "# Titolo\n\nTesto **Markdown**\n- [ ] attività\n[[link interno]]"
        val blocks = ContentBlocks.fromLegacyMarkdown(
            noteId = "note-1",
            body = body,
            now = 100L,
            id = "block-1",
        )

        assertEquals(1, blocks.size)
        val block = blocks.single()
        assertEquals("block-1", block.id)
        assertEquals("note-1", block.ownerId)
        assertEquals(ContentBlockType.MARKDOWN, block.type)
        assertEquals(body, block.text)
        assertEquals(0, block.position)
        assertNull(block.checked)
        assertEquals(100L, block.createdAt)
        assertEquals(100L, block.updatedAt)
    }

    @Test
    fun emptyLegacyBodyDoesNotCreateFakeContent() {
        assertTrue(ContentBlocks.fromLegacyMarkdown("note-1", "").isEmpty())
    }

    @Test
    fun normalizationReordersAndKeepsStableIds() {
        val source = listOf(
            ContentBlock("b", "wrong", position = 99, type = ContentBlockType.TEXT, text = "B", createdAt = 1, updatedAt = 1),
            ContentBlock("a", "wrong", position = 77, type = ContentBlockType.TEXT, text = "A", createdAt = 2, updatedAt = 2),
        )

        val normalized = ContentBlocks.normalize("note-1", source, now = 500L)

        assertEquals(listOf("b", "a"), normalized.map { it.id })
        assertEquals(listOf(0, 1), normalized.map { it.position })
        assertTrue(normalized.all { it.ownerId == "note-1" })
        assertTrue(normalized.all { it.updatedAt == 500L })
        assertEquals(listOf(1L, 2L), normalized.map { it.createdAt })
    }

    @Test(expected = IllegalArgumentException::class)
    fun duplicatedBlockIdsAreRejected() {
        val block = ContentBlock("same", "note", position = 0, type = ContentBlockType.TEXT, text = "A", createdAt = 1, updatedAt = 1)
        ContentBlocks.normalize("note", listOf(block, block.copy(text = "B")))
    }

    @Test
    fun supportedBlocksCanBeProjectedToLegacyMarkdown() {
        val blocks = listOf(
            ContentBlock("1", "n", position = 0, type = ContentBlockType.HEADING, text = "Titolo", createdAt = 1, updatedAt = 1),
            ContentBlock("2", "n", position = 1, type = ContentBlockType.TEXT, text = "Paragrafo", createdAt = 1, updatedAt = 1),
            ContentBlock("3", "n", position = 2, type = ContentBlockType.CHECKLIST, text = "Fatto", checked = true, createdAt = 1, updatedAt = 1),
            ContentBlock("4", "n", position = 3, type = ContentBlockType.DIVIDER, createdAt = 1, updatedAt = 1),
        )

        assertEquals(
            "## Titolo\n\nParagrafo\n\n- [x] Fatto\n\n---",
            ContentBlocks.toLegacyMarkdown(blocks),
        )
    }
}

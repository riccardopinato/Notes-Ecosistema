package it.notes.ecosystem.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BlockEditorCodecTest {
    @Test
    fun plainParagraphBecomesTextAndRoundTrips() {
        val source = "Prima riga\nseconda riga"
        val blocks = BlockEditorCodec.parse("n1", source, now = 10L)
        assertEquals(1, blocks.size)
        assertEquals(ContentBlockType.TEXT, blocks.single().type)
        assertEquals(source, blocks.single().text)
        assertEquals(source, BlockEditorCodec.toMarkdown(blocks))
    }

    @Test
    fun commonBlockTypesRoundTrip() {
        val source = "# Titolo\n\nTesto normale\n\n- [ ] Da fare\n\n- [x] Fatto\n\n> Citazione\n\n---\n\n```kotlin\nval x = 1\n```"
        val blocks = BlockEditorCodec.parse("n1", source, now = 10L)

        assertEquals(
            listOf(
                ContentBlockType.HEADING,
                ContentBlockType.TEXT,
                ContentBlockType.CHECKLIST,
                ContentBlockType.CHECKLIST,
                ContentBlockType.QUOTE,
                ContentBlockType.DIVIDER,
                ContentBlockType.CODE,
            ),
            blocks.map { it.type },
        )
        assertEquals(source, BlockEditorCodec.toMarkdown(blocks))
    }

    @Test
    fun richMarkdownIsPreserved() {
        val source = "Testo **grassetto** con [link](https://example.com) e [[nota]]"
        val blocks = BlockEditorCodec.parse("n1", source, now = 10L)
        assertEquals(ContentBlockType.MARKDOWN, blocks.single().type)
        assertEquals(source, BlockEditorCodec.toMarkdown(blocks))
    }

    @Test
    fun attachmentReferenceIsPreservedByteForByte() {
        val key = "a".repeat(64) + ".pdf"
        val source = "[Documento](notes-asset://$key)"
        val blocks = BlockEditorCodec.parse("n1", source, now = 10L)
        assertEquals(1, blocks.size)
        assertEquals(ContentBlockType.FILE, blocks.single().type)
        assertEquals(source, BlockEditorCodec.toMarkdown(blocks))
    }

    @Test
    fun headingLevelCanBeChangedWithoutLosingText() {
        val block = BlockEditorCodec.newBlock("n1", ContentBlockType.HEADING, 0, "Titolo", now = 10L)
        val h1 = BlockEditorCodec.withHeadingLevel(block, 1)
        val h3 = BlockEditorCodec.withHeadingLevel(h1, 3)
        assertEquals(3, BlockEditorCodec.headingLevel(h3))
        assertEquals("### Titolo", BlockEditorCodec.toMarkdown(listOf(h3)))
    }

    @Test
    fun checklistStateIsPortable() {
        val block = BlockEditorCodec.newBlock("n1", ContentBlockType.CHECKLIST, 0, "Comprare latte", now = 10L)
        assertEquals("- [ ] Comprare latte", BlockEditorCodec.toMarkdown(listOf(block)))
        assertEquals("- [x] Comprare latte", BlockEditorCodec.toMarkdown(listOf(block.copy(checked = true))))
    }

    @Test
    fun canonicalizeRestoresSequentialPositionsAndOwner() {
        val source = listOf(
            BlockEditorCodec.newBlock("wrong", ContentBlockType.TEXT, 9, "A", now = 1L),
            BlockEditorCodec.newBlock("wrong", ContentBlockType.TEXT, 4, "B", now = 1L),
        )
        val normalized = BlockEditorCodec.canonicalize("correct", source, now = 20L)
        assertEquals(listOf(0, 1), normalized.map { it.position })
        assertTrue(normalized.all { it.ownerId == "correct" })
        assertTrue(normalized.all { it.updatedAt == 20L })
    }

    @Test
    fun emptyMarkdownDoesNotCreateFakePersistedContent() {
        val blocks = BlockEditorCodec.parse("n1", "")
        assertTrue(blocks.isEmpty())
        assertFalse(BlockEditorCodec.toMarkdown(blocks).isNotEmpty())
    }

    @Test
    fun drawingBlockParsesAndRoundTripsWithMetadata() {
        val source = "[Sketch: Schema del progetto](notes-sketch://sketch-1234)"
        val blocks = BlockEditorCodec.parse("n1", source, now = 10L)
        assertEquals(1, blocks.size)
        val block = blocks.single()
        assertEquals(ContentBlockType.DRAWING, block.type)
        assertEquals("Schema del progetto", block.text)
        assertEquals("sketch-1234", BlockEditorCodec.sketchId(block))
        assertEquals(source, BlockEditorCodec.toMarkdown(blocks))
    }
}

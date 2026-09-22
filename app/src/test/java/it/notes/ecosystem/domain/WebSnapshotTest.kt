package it.notes.ecosystem.domain

import org.junit.Assert.*
import org.junit.Test

class WebSnapshotTest {

    @Test
    fun markdownContainsSourceAndText() {
        val markdown = WebSnapshot(
            requestedUrl = "https://example.com/a",
            finalUrl = "https://example.com/a",
            title = "Titolo",
            description = "Descrizione",
            text = "Corpo articolo",
        ).toMarkdown()

        assertTrue(markdown.contains("## Titolo"))
        assertTrue(markdown.contains("[Apri fonte](https://example.com/a)"))
        assertTrue(markdown.contains("> Descrizione"))
        assertTrue(markdown.contains("Corpo articolo"))
    }

    @Test
    fun emptyDescriptionIsAllowed() {
        val markdown = WebSnapshot(
            requestedUrl = "https://example.com/",
            finalUrl = "https://example.com/",
            title = "Example",
            description = "",
            text = "Text",
        ).toMarkdown()

        assertTrue(markdown.contains("Text"))
        assertFalse(markdown.contains("> \n"))
    }
}

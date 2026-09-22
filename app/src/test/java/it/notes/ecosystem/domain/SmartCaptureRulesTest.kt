package it.notes.ecosystem.domain

import org.junit.Assert.*
import org.junit.Test

class SmartCaptureRulesTest {

    @Test
    fun singleUrlIsDetected() {
        assertEquals(
            "https://example.com/",
            SmartCaptureRules.extractSingleHttpUrl("https://example.com")
        )
    }

    @Test
    fun normalTextIsNotUrl() {
        assertNull(
            SmartCaptureRules.extractSingleHttpUrl("guarda https://example.com")
        )
    }

    @Test
    fun ftpIsRejected() {
        runCatching {
            SmartCaptureRules.normalizeHttpUrl("ftp://example.com/file")
        }.onSuccess {
            fail("FTP deve essere rifiutato")
        }
    }

    @Test
    fun credentialsAreRejected() {
        runCatching {
            SmartCaptureRules.normalizeHttpUrl(
                "https://user:pass@example.com/"
            )
        }.onSuccess {
            fail("Credenziali nell'URL non ammesse")
        }
    }

    @Test
    fun sectionIsAppendedWithoutDestroyingBody() {
        val result = SmartCaptureRules.appendSection(
            body = "Testo iniziale",
            title = "OCR",
            content = "Hello world",
        )

        assertTrue(result.startsWith("Testo iniziale"))
        assertTrue(result.contains("## OCR"))
        assertTrue(result.contains("Hello world"))
    }

    @Test
    fun emptySectionDoesNothing() {
        assertEquals(
            "A",
            SmartCaptureRules.appendSection("A", "OCR", "   ")
        )
    }

    @Test
    fun ocrIsClipped() {
        val input = "a".repeat(
            SmartCaptureRules.MAX_OCR_TEXT_CHARS + 10
        )

        assertEquals(
            SmartCaptureRules.MAX_OCR_TEXT_CHARS,
            SmartCaptureRules.clipOcr(input).length
        )
    }

    @Test
    fun identicalSectionCanBeDetected() {
        val body = "A\n\n## OCR\n\nHello"
        assertTrue(
            SmartCaptureRules.containsSection(
                body,
                "OCR",
                "Hello",
            )
        )
    }
}

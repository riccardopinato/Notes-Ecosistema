package it.notes.ecosystem.domain

import org.junit.Assert.*
import org.junit.Test

class QuickCaptureTest {
    @Test fun urlRemainsExactEditableText() {
        val url = "https://example.org/a?q=1&x=%20#section"
        assertEquals(CaptureSeed("Articolo", url), QuickCapture.shared(url, " Articolo "))
    }
    @Test fun unicodeAndLineEndingsArePreserved() {
        val text = "Caffè ☕\r\n- [ ] Attività\nSeconda riga"
        assertEquals(text, QuickCapture.shared(text, null).body)
    }
    @Test fun subjectOnlyIsAccepted() { assertEquals("Titolo", QuickCapture.shared(null, "Titolo").title) }
    @Test fun emptyContentIsRejected() { rejected { QuickCapture.shared(" \n", null) } }
    @Test fun byteLimitCountsMultibyteCharacters() { rejected { QuickCapture.shared("€".repeat(70000), null) } }
    @Test fun subjectAndBodyShareTheBudget() { rejected { QuickCapture.shared("a".repeat(QuickCapture.MAX_BYTES), "Titolo") } }
    @Test fun exactAsciiLimitIsAcceptedWithoutTruncation() {
        val body = "a".repeat(QuickCapture.MAX_BYTES)
        assertEquals(body, QuickCapture.shared(body, null).body)
    }
    @Test fun excessivelyLongTitleIsRejected() { rejected { QuickCapture.shared("Body", "a".repeat(8001)) } }
    @Test fun binaryNullIsRejected() { rejected { QuickCapture.shared("a\u0000b", null) } }
    @Test fun blankQuickActionsDoNotCreateContent() {
        assertFalse(CaptureSeed().hasContent)
        assertFalse(CaptureSeed(checklist = true).hasContent)
    }
    private fun rejected(block: () -> Unit) {
        try { block(); fail("Invalid capture accepted") } catch (_: IllegalArgumentException) {}
    }
}

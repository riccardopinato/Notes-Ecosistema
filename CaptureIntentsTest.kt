package it.notes.ecosystem.capture

import android.content.Intent
import android.net.Uri
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class CaptureIntentsTest {
    @Test fun acceptsSharedTextAndSubject() {
        val seed = CaptureIntents.read(Intent(Intent.ACTION_SEND).setType("text/plain")
            .putExtra(Intent.EXTRA_TEXT, "https://example.org").putExtra(Intent.EXTRA_SUBJECT, "Titolo"))
        assertEquals("Titolo", seed.title); assertEquals("https://example.org", seed.body)
    }
    @Test fun newChecklistHasNoPlaceholderTask() {
        val seed = CaptureIntents.read(Intent(CaptureIntents.NEW_CHECKLIST))
        assertTrue(seed.checklist); assertFalse(seed.hasContent)
    }
    @Test fun ignoresExternallySuppliedNoteId() {
        val seed = CaptureIntents.read(Intent(CaptureIntents.NEW_NOTE).putExtra("id", "existing-note").putExtra(Intent.EXTRA_TEXT, "Overwrite"))
        assertFalse(seed.hasContent)
    }
    @Test fun attachmentsAreNotSilentlyDiscarded() {
        rejected(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, "Text")
            .putExtra(Intent.EXTRA_STREAM, Uri.parse("content://example/file")))
    }
    @Test fun wrongMimeAndMultipleSharesAreRejected() {
        rejected(Intent(Intent.ACTION_SEND).setType("image/png"))
        rejected(Intent(Intent.ACTION_SEND_MULTIPLE).setType("text/plain"))
    }
    private fun rejected(intent: Intent) {
        try { CaptureIntents.read(intent); fail("Unsupported intent accepted") } catch (_: IllegalArgumentException) {} catch (_: IllegalStateException) {}
    }
}

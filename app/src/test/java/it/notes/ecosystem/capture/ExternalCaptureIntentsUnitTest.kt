package it.notes.ecosystem.capture

import android.content.Intent
import android.net.Uri
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class ExternalCaptureIntentsUnitTest {

    @Test
    fun textShareStillWorks() {
        val request = ExternalCaptureIntents.read(
            Intent(Intent.ACTION_SEND)
                .setType("text/plain")
                .putExtra(Intent.EXTRA_TEXT, "https://example.com")
                .putExtra(Intent.EXTRA_SUBJECT, "Example")
        )

        assertEquals("Example", request.seed.title)
        assertEquals("https://example.com", request.seed.body)
        assertTrue(request.shouldSuggestWebCapture)
        assertTrue(request.uris.isEmpty())
    }

    @Test
    fun imageShareIsAccepted() {
        val uri = Uri.parse("content://provider/photo.jpg")

        val request = ExternalCaptureIntents.read(
            Intent(Intent.ACTION_SEND)
                .setType("image/jpeg")
                .putExtra(Intent.EXTRA_STREAM, uri)
        )

        assertEquals(listOf(uri), request.uris)
        assertTrue(request.shouldSuggestOcr)
    }

    @Test
    fun pdfShareIsAcceptedWithoutOcrSuggestion() {
        val uri = Uri.parse("content://provider/file.pdf")

        val request = ExternalCaptureIntents.read(
            Intent(Intent.ACTION_SEND)
                .setType("application/pdf")
                .putExtra(Intent.EXTRA_STREAM, uri)
        )

        assertEquals(listOf(uri), request.uris)
        assertFalse(request.shouldSuggestOcr)
    }

    @Test
    fun unsupportedSingleMimeIsRejected() {
        val result = runCatching {
            ExternalCaptureIntents.read(
                Intent(Intent.ACTION_SEND)
                    .setType("video/mp4")
                    .putExtra(
                        Intent.EXTRA_STREAM,
                        Uri.parse("content://provider/video.mp4")
                    )
            )
        }

        assertTrue(result.isFailure)
    }
}

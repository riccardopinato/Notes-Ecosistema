package it.notes.ecosystem.capture

import android.content.Context
import android.net.Uri
import com.google.android.gms.tasks.Task
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import it.notes.ecosystem.domain.OcrText
import it.notes.ecosystem.domain.SmartCaptureRules
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.suspendCoroutine

class OcrEngine(private val context: Context) {

    suspend fun recognize(uri: Uri): OcrText {
        require(uri.scheme == "content" || uri.scheme == "file") {
            "Immagine OCR non valida."
        }

        val image = InputImage.fromFilePath(context, uri)
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)

        return try {
            val result = recognizer.process(image).awaitResult()
            OcrText(
                text = SmartCaptureRules.clipOcr(result.text),
                blockCount = result.textBlocks.size,
            )
        } finally {
            recognizer.close()
        }
    }
}

private suspend fun <T> Task<T>.awaitResult(): T =
    suspendCoroutine { continuation ->
        addOnSuccessListener { continuation.resume(it) }
        addOnFailureListener { continuation.resumeWithException(it) }
        addOnCanceledListener {
            continuation.resumeWithException(
                java.util.concurrent.CancellationException("Operazione annullata.")
            )
        }
    }

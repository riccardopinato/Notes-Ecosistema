package it.notes.ecosystem.capture

import android.net.Uri
import android.provider.OpenableColumns
import androidx.compose.runtime.*
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import it.notes.ecosystem.NotesApplication
import it.notes.ecosystem.domain.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class SmartCaptureStatus(
    val message: String? = null,
    val imported: Int = 0,
    val ocrCharacters: Int = 0,
)

class SmartCaptureViewModel(
    private val app: NotesApplication,
    private val editor: it.notes.ecosystem.ui.EditorViewModel,
    private val state: SavedStateHandle,
) : ViewModel() {

    var busy by mutableStateOf(false)
        private set

    var error by mutableStateOf<String?>(null)
        private set

    var status by mutableStateOf(SmartCaptureStatus())
        private set

    private val ocr = OcrEngine(app)
    private val web = WebCapture()

    fun clearMessage() {
        error = null
        status = SmartCaptureStatus()
    }

    fun importExternalOnce(
        sessionId: String,
        uris: List<Uri>,
        autoOcr: Boolean,
    ) {
        if (uris.isEmpty()) return

        val marker = "smartCaptureImported:$sessionId"
        if (state.get<Boolean>(marker) == true) return
        state[marker] = true

        importUris(
            uris = uris,
            runOcr = autoOcr,
            sectionTitle = "Testo estratto",
            rollbackMarkerOnFailure = marker,
        )
    }

    fun importScan(
        pageUris: List<Uri>,
        pdfUri: Uri?,
        extractText: Boolean = true,
    ) {
        if (pageUris.isEmpty() && pdfUri == null) {
            error = "Nessuna pagina acquisita."
            return
        }

        if (busy || !editor.available) return

        busy = true
        editor.setAttachmentWork(true)
        error = null

        viewModelScope.launch {
            try {
                val ocrTexts = mutableListOf<String>()

                if (extractText) {
                    for (page in pageUris) {
                        val recognized = runCatching {
                            ocr.recognize(page)
                        }.getOrNull()

                        if (recognized?.hasText == true) {
                            ocrTexts += recognized.text
                        }
                    }
                }

                var imported = 0

                if (pdfUri != null) {
                    val pdf = ingestUri(pdfUri)

                    val before =
                        Attachments.refs(editor.body)
                            .map { it.key }
                            .toSet()

                    if (pdf.key !in before) {
                        check(editor.attach(pdf.key, pdf.name)) {
                            editor.error ?: "PDF copiato ma non collegato."
                        }
                        editor.awaitAttachmentDraft()
                        imported++
                    }
                } else {
                    /*
                     * Se ML Kit non ha prodotto un PDF, persistiamo le immagini.
                     */
                    for (page in pageUris) {
                        val image = ingestUri(page)

                        val before =
                            Attachments.refs(editor.body)
                                .map { it.key }
                                .toSet()

                        if (image.key !in before) {
                            check(editor.attach(image.key, image.name)) {
                                editor.error ?: "Pagina copiata ma non collegata."
                            }
                            editor.awaitAttachmentDraft()
                            imported++
                        }
                    }
                }

                val combined =
                    ocrTexts.joinToString("\n\n---\n\n").trim()

                if (combined.isNotBlank()) {
                    appendBodySection(
                        "Testo scannerizzato",
                        combined,
                    )
                }

                status = SmartCaptureStatus(
                    message =
                        when {
                            imported > 0 && combined.isNotBlank() ->
                                "Documento acquisito · OCR aggiunto."
                            imported > 0 ->
                                "Documento acquisito."
                            combined.isNotBlank() ->
                                "OCR aggiunto."
                            else ->
                                "Scansione completata."
                        },
                    imported = imported,
                    ocrCharacters = combined.length,
                )
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                error = e.message ?: "Scansione non riuscita."
            } finally {
                busy = false
                editor.setAttachmentWork(false)
            }
        }
    }

    fun extractTextFromAttachedImages() {
        if (busy || !editor.available) return

        val refs = Attachments.refs(editor.body)
            .filter { it.type.image }

        if (refs.isEmpty()) {
            error = "Questa nota non contiene immagini da leggere."
            return
        }

        busy = true
        editor.setAttachmentWork(true)
        error = null

        viewModelScope.launch {
            try {
                val texts = mutableListOf<String>()

                for (ref in refs) {
                    val file = withContext(Dispatchers.IO) {
                        app.attachments.verifiedFile(ref.key)
                    }
                    val recognized = ocr.recognize(Uri.fromFile(file))
                    if (recognized.hasText) {
                        texts += recognized.text
                    }
                }

                val combined = texts
                    .joinToString("\n\n---\n\n")
                    .trim()

                if (combined.isBlank()) {
                    status = SmartCaptureStatus(
                        message = "Nessun testo riconosciuto nelle immagini."
                    )
                } else {
                    appendBodySection(
                        title = "Testo estratto",
                        text = combined,
                    )
                    status = SmartCaptureStatus(
                        message = "Testo estratto dalle immagini.",
                        ocrCharacters = combined.length,
                    )
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                error = e.message ?: "OCR non riuscito."
            } finally {
                busy = false
                editor.setAttachmentWork(false)
            }
        }
    }

    fun captureWeb(rawUrl: String) {
        if (busy || !editor.available) return

        busy = true
        editor.setAttachmentWork(true)
        error = null

        viewModelScope.launch {
            try {
                val snapshot = web.fetch(rawUrl)
                appendBodySection(
                    title = "Pagina acquisita",
                    text = snapshot.toMarkdown(),
                )
                status = SmartCaptureStatus(
                    message = "Pagina salvata nella nota."
                )
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                error = e.message ?: "Impossibile acquisire la pagina web."
            } finally {
                busy = false
                editor.setAttachmentWork(false)
            }
        }
    }

    private fun importUris(
        uris: List<Uri>,
        runOcr: Boolean,
        ocrOnlyUris: Set<Uri>? = null,
        sectionTitle: String,
        rollbackMarkerOnFailure: String? = null,
    ) {
        if (busy || !editor.available) return

        busy = true
        editor.setAttachmentWork(true)
        error = null

        viewModelScope.launch {
            try {
                require(uris.size <= SmartCaptureRules.MAX_SHARED_URIS) {
                    "Puoi acquisire fino a ${SmartCaptureRules.MAX_SHARED_URIS} file per volta."
                }

                val before = Attachments.refs(editor.body).map { it.key }.toSet()
                val importedKeys = mutableSetOf<String>()
                val ocrTexts = mutableListOf<String>()
                var importedCount = 0

                for (uri in uris.distinct()) {
                    val imported = ingestUri(uri)

                    if (imported.key !in before && imported.key !in importedKeys) {
                        check(editor.attach(imported.key, imported.name)) {
                            editor.error ?: "File copiato ma non collegato."
                        }
                        editor.awaitAttachmentDraft()
                        importedKeys += imported.key
                        importedCount++
                    }

                    val shouldOcr =
                        runOcr &&
                            imported.type.image &&
                            (ocrOnlyUris == null || uri in ocrOnlyUris)

                    if (shouldOcr) {
                        val recognized = runCatching {
                            ocr.recognize(imported.localUri)
                        }.getOrNull()

                        if (recognized?.hasText == true) {
                            ocrTexts += recognized.text
                        }
                    }
                }

                val ocrText = ocrTexts
                    .joinToString("\n\n---\n\n")
                    .trim()

                if (ocrText.isNotBlank()) {
                    appendBodySection(sectionTitle, ocrText)
                }

                status = SmartCaptureStatus(
                    message = when {
                        importedCount > 0 && ocrText.isNotBlank() ->
                            "$importedCount allegati acquisiti · testo OCR aggiunto."
                        importedCount > 0 ->
                            "$importedCount allegati acquisiti."
                        ocrText.isNotBlank() ->
                            "Testo OCR aggiunto."
                        else ->
                            "Contenuti già presenti nella nota."
                    },
                    imported = importedCount,
                    ocrCharacters = ocrText.length,
                )
            } catch (e: CancellationException) {
                rollbackMarkerOnFailure?.let { state[it] = false }
                throw e
            } catch (e: Exception) {
                rollbackMarkerOnFailure?.let { state[it] = false }
                error = e.message ?: "Acquisizione non riuscita."
            } finally {
                busy = false
                editor.setAttachmentWork(false)
            }
        }
    }

    private suspend fun ingestUri(uri: Uri): ImportedSmartAttachment =
        withContext(Dispatchers.IO) {
            require(uri.scheme == "content" || uri.scheme == "file") {
                "File condiviso non leggibile."
            }

            val resolver = app.contentResolver

            val displayName =
                if (uri.scheme == "content") {
                    resolver.query(
                        uri,
                        arrayOf(OpenableColumns.DISPLAY_NAME),
                        null,
                        null,
                        null,
                    )?.use { cursor ->
                        if (cursor.moveToFirst()) cursor.getString(0) else null
                    }
                } else {
                    uri.lastPathSegment
                }
                    ?.take(120)
                    ?.trim()
                    .orEmpty()
                    .ifBlank { "Allegato" }

            val mime = resolver.getType(uri)?.lowercase()
            val ext = displayName.substringAfterLast('.', "").lowercase()

            val type = AttachmentType.entries.firstOrNull { it.mime == mime }
                ?: when (mime) {
                    "audio/x-wav" -> AttachmentType.WAV
                    "audio/x-m4a" -> AttachmentType.M4A
                    else -> null
                }
                ?: AttachmentType.entries.firstOrNull {
                    it.ext == ext || (ext == "jpeg" && it == AttachmentType.JPEG)
                }
                ?: error(
                    "Formato non supportato: $displayName. " +
                        "Usa JPEG, PNG, WebP, PDF, TXT, audio o documenti Office supportati."
                )

            val input = resolver.openInputStream(uri)
                ?: error("Impossibile leggere $displayName.")

            val key = input.use {
                app.attachments.ingest(it, type)
            }

            val localFile = app.attachments.verifiedFile(key)

            ImportedSmartAttachment(
                key = key,
                name = displayName,
                type = type,
                localUri = Uri.fromFile(localFile),
            )
        }

    private fun appendBodySection(title: String, text: String) {
        if (!SmartCaptureRules.containsSection(editor.body, title, text)) {
            val next = SmartCaptureRules.appendSection(
                body = editor.body,
                title = title,
                content = text,
            )
            check(editor.applyCapturedBody(next)) {
                "La nota non è disponibile per l'acquisizione."
            }
        }
    }
}

private data class ImportedSmartAttachment(
    val key: String,
    val name: String,
    val type: AttachmentType,
    val localUri: Uri,
)

package it.notes.ecosystem.ui

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import it.notes.ecosystem.NotesApplication
import it.notes.ecosystem.capture.SmartCaptureViewModel
import it.notes.ecosystem.domain.SmartCaptureRules

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun SmartCaptureSheet(
    editor: EditorViewModel,
    visible: Boolean,
    onDismiss: () -> Unit,
) {
    if (!visible) return

    val context = LocalContext.current
    val app = context.applicationContext as NotesApplication
    val activity = context.findActivity()

    val smart: SmartCaptureViewModel = viewModel(
        key = "smart-capture-${editor.noteId}",
        factory = viewModelFactory {
            initializer {
                SmartCaptureViewModel(
                    app = app,
                    editor = editor,
                    state = SavedStateHandle(),
                )
            }
        },
    )

    var scannerError by rememberSaveable {
        mutableStateOf<String?>(null)
    }

    var url by rememberSaveable(editor.noteId) {
        mutableStateOf(
            SmartCaptureRules.extractSingleHttpUrl(editor.body).orEmpty()
        )
    }

    val scannerOptions = remember {
        GmsDocumentScannerOptions.Builder()
            .setGalleryImportAllowed(true)
            .setPageLimit(12)
            .setResultFormats(
                GmsDocumentScannerOptions.RESULT_FORMAT_JPEG,
                GmsDocumentScannerOptions.RESULT_FORMAT_PDF,
            )
            .setScannerMode(
                GmsDocumentScannerOptions.SCANNER_MODE_FULL
            )
            .build()
    }

    val scannerClient = remember {
        GmsDocumentScanning.getClient(scannerOptions)
    }

    val scanLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.StartIntentSenderForResult(),
    ) { result ->
        if (result.resultCode != Activity.RESULT_OK) return@rememberLauncherForActivityResult

        val scan = GmsDocumentScanningResult.fromActivityResultIntent(result.data)
            ?: return@rememberLauncherForActivityResult

        val pages = scan.pages.orEmpty().map { it.imageUri }
        val pdf = scan.pdf?.uri

        smart.importScan(
            pageUris = pages,
            pdfUri = pdf,
            extractText = true,
        )
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text(
                "Smart Capture",
                style = MaterialTheme.typography.headlineSmall,
            )
            Text(
                "Acquisisci carta, immagini e pagine web senza uscire dalla nota.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            smart.error?.let {
                AssistChip(
                    onClick = smart::clearMessage,
                    label = { Text(it) },
                    leadingIcon = {
                        Icon(Icons.Default.ErrorOutline, null)
                    },
                )
            }

            smart.status.message?.let {
                AssistChip(
                    onClick = smart::clearMessage,
                    label = { Text(it) },
                    leadingIcon = {
                        Icon(Icons.Default.CheckCircle, null)
                    },
                )
            }

            if (smart.busy) {
                LinearProgressIndicator(Modifier.fillMaxWidth())
            }

            ElevatedCard(Modifier.fillMaxWidth()) {
                Column(
                    Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Icon(Icons.Default.DocumentScanner, null)
                        Text(
                            "Scanner documenti",
                            style = MaterialTheme.typography.titleMedium,
                        )
                    }

                    Text(
                        "Ritaglio automatico, prospettiva, multipagina, PDF e OCR del testo.",
                        style = MaterialTheme.typography.bodySmall,
                    )

                    Button(
                        enabled = !smart.busy && editor.available,
                        onClick = {
                            if (activity == null) {
                                scannerError = "Scanner non disponibile in questa schermata."
                                return@Button
                            }

                            scannerError = null
                            scannerClient
                                .getStartScanIntent(activity)
                                .addOnSuccessListener { sender ->
                                    scanLauncher.launch(
                                        IntentSenderRequest.Builder(sender).build()
                                    )
                                }
                                .addOnFailureListener { throwable ->
                                    scannerError =
                                        throwable.message
                                            ?.takeIf { it.isNotBlank() }
                                            ?: "Scanner non disponibile. Usa Foto o File per acquisire il documento."
                                }
                        },
                    ) {
                        Icon(Icons.Default.PhotoCamera, null)
                        Spacer(Modifier.width(8.dp))
                        Text("Scansiona")
                    }

                    scannerError?.let {
                        Text(
                            it,
                            color = MaterialTheme.colorScheme.error,
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }

                    Text(
                        "Se lo scanner non è disponibile sul dispositivo, usa Foto/Allegati già presenti nell'editor.",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            ElevatedCard(Modifier.fillMaxWidth()) {
                Column(
                    Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Icon(Icons.Default.TextSnippet, null)
                        Text(
                            "OCR immagini",
                            style = MaterialTheme.typography.titleMedium,
                        )
                    }

                    Text(
                        "Legge tutte le immagini già allegate alla nota e aggiunge il testo riconosciuto.",
                        style = MaterialTheme.typography.bodySmall,
                    )

                    OutlinedButton(
                        enabled = !smart.busy && editor.available,
                        onClick = smart::extractTextFromAttachedImages,
                    ) {
                        Text("Estrai testo dalle immagini")
                    }
                }
            }

            ElevatedCard(Modifier.fillMaxWidth()) {
                Column(
                    Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Icon(Icons.Default.Language, null)
                        Text(
                            "Acquisisci pagina web",
                            style = MaterialTheme.typography.titleMedium,
                        )
                    }

                    Text(
                        "Salva titolo, descrizione, fonte e testo leggibile direttamente nella nota.",
                        style = MaterialTheme.typography.bodySmall,
                    )

                    OutlinedTextField(
                        value = url,
                        onValueChange = { url = it.take(SmartCaptureRules.MAX_URL_LENGTH) },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("https://…") },
                        singleLine = true,
                        enabled = !smart.busy,
                    )

                    Button(
                        enabled = !smart.busy && url.isNotBlank() && editor.available,
                        onClick = {
                            smart.captureWeb(url)
                        },
                    ) {
                        Icon(Icons.Default.Download, null)
                        Spacer(Modifier.width(8.dp))
                        Text("Salva contenuto")
                    }

                    Text(
                        "Lo snapshot è testo Markdown portabile. Script, cookie, pubblicità e codice della pagina non vengono salvati.",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            Spacer(Modifier.height(24.dp))
        }
    }
}

private tailrec fun Context.findActivity(): Activity? =
    when (this) {
        is Activity -> this
        is ContextWrapper -> baseContext.findActivity()
        else -> null
    }

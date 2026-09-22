package it.notes.ecosystem.capture

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.createSavedStateHandle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import it.notes.ecosystem.NotesApplication
import it.notes.ecosystem.ui.EditorScreen
import it.notes.ecosystem.ui.EditorViewModel
import it.notes.ecosystem.ui.NotesTheme
import java.util.UUID

/**
 * Activity separata:
 * una condivisione esterna non sostituisce l'editor già aperto in MainActivity.
 */
class CaptureActivity : ComponentActivity() {

    private lateinit var captureId: String

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putString("captureSessionId", captureId)
        super.onSaveInstanceState(outState)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        captureId =
            savedInstanceState?.getString("captureSessionId")
                ?: UUID.randomUUID().toString()

        enableEdgeToEdge()

        val app = application as NotesApplication

        /*
         * Tutti gli extra esterni sono non fidati.
         * Non accettare MAI un note ID proveniente dal caller.
         */
        val result = runCatching {
            CaptureIntents.readExternal(intent)
        }

        setContent {
            val dark by app.preferences.darkMode.collectAsStateWithLifecycle(
                initialValue = false
            )

            NotesTheme(dark) {
                val request = result.getOrNull()

                if (request == null) {
                    InvalidCapture(
                        message =
                            if (
                                result.exceptionOrNull() is IllegalArgumentException ||
                                result.exceptionOrNull() is IllegalStateException
                            ) {
                                result.exceptionOrNull()?.message
                                    ?: "Contenuto non supportato."
                            } else {
                                "Contenuto non leggibile. Prova a condividere testo, immagini o PDF."
                            },
                        onClose = ::finish,
                    )
                    return@NotesTheme
                }

                val editor: EditorViewModel = viewModel(
                    factory = viewModelFactory {
                        initializer {
                            val state = createSavedStateHandle()
                            state["id"] = captureId
                            state["new"] = true

                            EditorViewModel(
                                app.repository,
                                state,
                                request.seed,
                            )
                        }
                    },
                )

                val smart: SmartCaptureViewModel = viewModel(
                    key = "external-smart-$captureId",
                    factory = viewModelFactory {
                        initializer {
                            SmartCaptureViewModel(
                                app = app,
                                editor = editor,
                                state = createSavedStateHandle(),
                            )
                        }
                    },
                )

                val collections by app.repository.collections.collectAsStateWithLifecycle(
                    initialValue = emptyList()
                )

                LaunchedEffect(
                    captureId,
                    request.uris,
                    request.shouldSuggestOcr,
                    editor.available,
                ) {
                    if (editor.available && request.uris.isNotEmpty()) {
                        smart.importExternalOnce(
                            sessionId = captureId,
                            uris = request.uris,
                            autoOcr = request.shouldSuggestOcr,
                        )
                    }
                }

                Column(Modifier.fillMaxSize()) {
                    if (smart.busy) {
                        LinearProgressIndicator(Modifier.fillMaxWidth())
                    }

                    smart.error?.let {
                        Text(
                            it,
                            color = MaterialTheme.colorScheme.error,
                            modifier = Modifier.padding(horizontal = 16.dp),
                        )
                    }

                    smart.status.message?.let {
                        Text(
                            it,
                            style = MaterialTheme.typography.bodySmall,
                            modifier = Modifier.padding(horizontal = 16.dp),
                        )
                    }

                    Box(Modifier.weight(1f)) {
                        EditorScreen(
                            model = editor,
                            collections = collections,
                            initialChecklist = request.seed.checklist,
                            initialAttachments = request.uris.isNotEmpty(),
                            onBack = ::finish,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun InvalidCapture(
    message: String,
    onClose: () -> Unit,
) {
    Surface(Modifier.fillMaxSize()) {
        Column(
            Modifier
                .safeDrawingPadding()
                .padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(
                "Impossibile acquisire il contenuto",
                style = MaterialTheme.typography.headlineSmall,
            )
            Text(message)
            Button(onClick = onClose) {
                Text("Chiudi")
            }
        }
    }
}

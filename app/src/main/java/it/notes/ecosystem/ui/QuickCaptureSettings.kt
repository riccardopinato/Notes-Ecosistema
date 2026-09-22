package it.notes.ecosystem.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalContext
import it.notes.ecosystem.capture.CaptureShortcuts

@Composable
fun QuickCaptureSettings() {
    val context = LocalContext.current
    var message by remember { mutableStateOf<String?>(null) }
    Column {
        Text("Scrivi al volo", style = MaterialTheme.typography.titleMedium)
        Text("Da un’altra app scegli Condividi → Notes per ricevere testo e link come bozza. Tieni premuta l’icona di Notes per le azioni rapide.")
        TextButton(onClick = {
            message = if (runCatching { CaptureShortcuts.pinNote(context) }.getOrDefault(false))
                "Richiesta inviata alla schermata Home: conferma l’aggiunta se richiesto."
            else "Tieni premuta l’icona di Notes e trascina Nuova nota sulla Home, se il launcher lo supporta."
        }) { Text("Aggiungi scorciatoia Nuova nota") }
        TextButton(onClick = {
            message = if (runCatching { CaptureShortcuts.pinWidget(context) }.getOrDefault(false))
                "Richiesta inviata alla schermata Home: conferma l’aggiunta se richiesto."
            else "Apri il selettore Widget della schermata Home e cerca Notes."
        }) { Text("Aggiungi widget") }
        message?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
    }
}

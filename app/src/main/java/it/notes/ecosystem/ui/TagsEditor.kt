package it.notes.ecosystem.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier

@Composable
fun TagsEditor(model: EditorViewModel) {
    val visibleTags = it.notes.ecosystem.domain.Diary.userTags(model.tags)
    var open by remember { mutableStateOf(false) }
    var text by remember { mutableStateOf("") }
    val enabled = model.available && !model.loading && !model.saving && !model.mediaBusy && !model.checklistWorking
    TextButton(enabled = enabled, onClick = { open = true }) {
        Text(if (visibleTags.isEmpty()) "Aggiungi tag" else "Tag (${visibleTags.size}) · " + visibleTags.take(3).joinToString(" ") { "#$it" })
    }
    if (open) AlertDialog(onDismissRequest = { open = false }, title = { Text("Tag della nota") }, text = {
        Column(Modifier.verticalScroll(rememberScrollState())) {
            Text("Fino a 20 tag complessivi, incluso il collegamento al Diario. Cambia la data da Giorno. Le modifiche restano nella bozza fino a Salva.")
            visibleTags.forEach { tag ->
                Row {
                    Text("#$tag", Modifier.weight(1f))
                    TextButton(enabled = enabled, onClick = { model.removeTag(tag) }) { Text("Rimuovi") }
                }
            }
            OutlinedTextField(text, { text = it }, label = { Text("Nuovo tag, es. lavoro") }, singleLine = true, enabled = enabled)
            TextButton(enabled = enabled && text.isNotBlank(), onClick = { if (model.addTag(text)) text = "" }) { Text("Aggiungi") }
            model.error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        }
    }, confirmButton = { TextButton(onClick = { open = false }) { Text("Chiudi") } })
}

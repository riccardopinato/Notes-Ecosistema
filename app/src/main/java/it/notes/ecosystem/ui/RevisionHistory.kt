package it.notes.ecosystem.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import it.notes.ecosystem.domain.NoteRevision
import it.notes.ecosystem.domain.Collection
import java.text.DateFormat
import java.util.Date

@Composable
fun RevisionHistory(model: EditorViewModel, collections: List<Collection>, close: () -> Unit) {
    var selected by remember { mutableStateOf<NoteRevision?>(null) }
    AlertDialog(onDismissRequest = close, title = { Text("Cronologia locale") },
        text = { Column {
            Text("Ultime 50 versioni precedenti. Il ripristino apre una bozza: premi Salva nell'editor per confermare. La cronologia resta su questo dispositivo e non è inclusa nel backup JSON v1.")
            if (model.historyLoading) LinearProgressIndicator(Modifier.fillMaxWidth())
            if (model.dirty) Text("Salva o scarta le modifiche correnti prima di ripristinare.")
            if (!model.historyLoading && model.revisions.isEmpty()) Text("Nessuna versione precedente.")
            LazyColumn(Modifier.heightIn(max = 320.dp)) {
                items(model.revisions, key = { it.revisionId }) { item ->
                    TextButton(onClick = { selected = item }) { Column(Modifier.fillMaxWidth()) {
                        Text(item.title.ifBlank { "Senza titolo" })
                        Text(DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(Date(item.savedAt)), style = MaterialTheme.typography.labelSmall)
                    } }
                }
            }
        } }, confirmButton = { TextButton(onClick = close) { Text("Chiudi") } })
    selected?.let { item -> AlertDialog(onDismissRequest = { selected = null }, title = { Text(item.title.ifBlank { "Versione precedente" }) },
        text = { Column(Modifier.heightIn(max = 360.dp).verticalScroll(rememberScrollState())) {
            Text(item.body.take(12000)); if (item.body.length > 12000) Text("Anteprima abbreviata; verrà recuperato il testo completo.")
        } }, confirmButton = { TextButton(enabled = !model.dirty && !model.saving && !model.checklistWorking, onClick = {
            if (model.useRevision(item, collections)) close()
        }) { Text("Apri come bozza") } }, dismissButton = { TextButton(onClick = { selected = null }) { Text("Indietro") } }) }
}

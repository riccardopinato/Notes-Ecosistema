package it.notes.ecosystem.ui

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import it.notes.ecosystem.domain.*
import it.notes.ecosystem.domain.Collection

private fun BulkAction.label() = when (this) {
    BulkAction.ARCHIVE -> "Archivia"
    BulkAction.UNARCHIVE -> "Riporta nelle note"
    BulkAction.PIN -> "Fissa in alto"
    BulkAction.UNPIN -> "Non fissare più"
    BulkAction.FAVORITE -> "Aggiungi ai preferiti"
    BulkAction.UNFAVORITE -> "Rimuovi dai preferiti"
    BulkAction.MOVE -> "Sposta in raccolta"
    BulkAction.ADD_TAG -> "Aggiungi tag"
    BulkAction.REMOVE_TAG -> "Rimuovi tag"
    BulkAction.TRASH -> "Sposta nel cestino"
    BulkAction.RESTORE -> "Ripristina dal cestino"
}

@Composable
fun BulkActions(visible: List<Note>, selected: Map<String, Note>, selecting: Boolean, busy: Boolean,
    collections: List<Collection>, onMode: (Boolean) -> Unit, onSelection: (Map<String, Note>) -> Unit,
    onApply: (List<Note>, BulkChange) -> Unit) {
    var menu by remember { mutableStateOf(false) }
    var pending by remember { mutableStateOf<Pair<List<Note>, BulkAction>?>(null) }
    var collectionId by remember { mutableStateOf<String?>(null) }
    var tag by remember { mutableStateOf("") }
    var validation by remember { mutableStateOf<String?>(null) }
    Column {
        Row(Modifier.horizontalScroll(rememberScrollState())) {
            TextButton(enabled = !busy, onClick = { onMode(!selecting); onSelection(emptyMap()) }) {
                Text(if (selecting) "Esci dalla selezione" else "Seleziona note")
            }
            if (selecting) {
                TextButton(enabled = !busy && visible.isNotEmpty() && visible.size <= 500, onClick = { onSelection(visible.associateBy { it.id }) }) { Text("Seleziona risultati") }
                TextButton(enabled = !busy && selected.isNotEmpty(), onClick = { onSelection(emptyMap()) }) { Text("Deseleziona") }
                Box {
                    Button(enabled = !busy && selected.isNotEmpty(), onClick = { menu = true }) { Text("Azioni (${selected.size})") }
                    DropdownMenu(menu, { menu = false }) {
                        val actions = if (selected.values.all { it.deletedAt != null }) listOf(BulkAction.RESTORE)
                            else BulkAction.entries.filter { it != BulkAction.RESTORE }
                        actions.forEach { action ->
                            DropdownMenuItem(text = { Text(action.label()) }, onClick = {
                                menu = false; pending = selected.values.toList() to action; collectionId = null; tag = ""; validation = null
                            })
                        }
                    }
                }
            }
        }
        if (busy) LinearProgressIndicator(Modifier.fillMaxWidth())
        if (selecting) Text("${selected.size} selezionate · massimo 500. Le note aperte o con bozze devono essere chiuse/salvate prima di modificare il gruppo.", style = MaterialTheme.typography.labelSmall)
    }
    pending?.let { (snapshot, action) ->
        AlertDialog(onDismissRequest = { if (!busy) pending = null }, title = { Text(action.label()) }, text = {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                Text("L’operazione riguarda ${snapshot.size} note selezionate:")
                snapshot.take(5).forEach { Text("• " + it.title.ifBlank { "Senza titolo" }) }
                if (snapshot.size > 5) Text("… e altre ${snapshot.size - 5} note.")
                if (action == BulkAction.MOVE) {
                    Text("Destinazione")
                    Row(Modifier.horizontalScroll(rememberScrollState())) {
                        FilterChip(collectionId == null, { collectionId = null }, label = { Text("Inbox") })
                        collections.forEach { c -> FilterChip(collectionId == c.id, { collectionId = c.id }, label = { Text(c.name) }) }
                    }
                }
                if (action == BulkAction.ADD_TAG || action == BulkAction.REMOVE_TAG)
                    OutlinedTextField(tag, { tag = it }, label = { Text("Tag") }, singleLine = true)
                if (action == BulkAction.TRASH) Text("Potrai recuperarle dal Cestino. Nessuna eliminazione definitiva.")
                Text("Se una nota è cambiata o non è modificabile, nessuna nota del gruppo verrà aggiornata.")
                validation?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            }
        }, confirmButton = { TextButton(enabled = !busy, onClick = {
            val change = BulkChange(action, collectionId, tag)
            runCatching { planBulkEdit(snapshot, change, System.currentTimeMillis()) }
                .onSuccess { pending = null; onApply(snapshot, change) }.onFailure { validation = it.message }
        }) { Text("Conferma su ${snapshot.size} note") } }, dismissButton = {
            TextButton(enabled = !busy, onClick = { pending = null }) { Text("Annulla") }
        })
    }
}

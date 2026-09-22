package it.notes.ecosystem.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import it.notes.ecosystem.sync.*
import it.notes.ecosystem.domain.Attachments
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

@Composable
fun GitHubSettings(sync: GitHubSync) {
    val status by sync.status.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    var owner by rememberSaveable { mutableStateOf("") }
    var repo by rememberSaveable { mutableStateOf("") }
    var branch by rememberSaveable { mutableStateOf("main") }
    var folder by rememberSaveable { mutableStateOf("notes-ecosystem") }
    // Do not save the token in saved instance state or in a draft.
    var token by remember { mutableStateOf("") }
    var consent by rememberSaveable { mutableStateOf(false) }
    var allowPublic by rememberSaveable { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var selected by remember { mutableStateOf<SyncConflict?>(null) }
    fun action(block: suspend () -> Unit) {
        busy = true; error = null
        scope.launch {
            try { block() }
            catch (e: CancellationException) { throw e }
            catch (e: Exception) { error = if (e is java.io.IOException) "Collegamento non riuscito. Controlla rete e accesso GitHub." else e.message ?: "Operazione non riuscita." }
            finally { busy = false }
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text("Le tue note, anche su GitHub", style = MaterialTheme.typography.headlineMedium)
        Text(status.message, style = MaterialTheme.typography.bodyMedium)
        error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        Text("Per sincronizzare stati, promemoria, sessioni Focus, disegni, attività, tag, archivio e note fissate, aggiorna tutte le installazioni a Notes 0.17 o successiva. Foto, audio e documenti sono salvati nella sottocartella assets: massimo 8 MiB per file, 64 MiB per passaggio e 500 allegati nel repository. La sincronizzazione è completata solo dopo il controllo dei file. I file non più collegati restano su GitHub.")
        if (busy || status.busy) LinearProgressIndicator(Modifier.fillMaxWidth())
        if (status.connection == null) {
            Text("Crea un repository GitHub con un README iniziale. Crea un token fine-grained per quel solo repository, con Contents: Read and write. Inseriscilo qui: sarà custodito sul telefono.")
            OutlinedTextField(owner, { owner = it }, Modifier.fillMaxWidth(), label = { Text("Proprietario GitHub") }, singleLine = true, enabled = !busy)
            OutlinedTextField(repo, { repo = it }, Modifier.fillMaxWidth(), label = { Text("Nome repository") }, singleLine = true, enabled = !busy)
            OutlinedTextField(branch, { branch = it }, Modifier.fillMaxWidth(), label = { Text("Ramo esistente") }, singleLine = true, enabled = !busy)
            OutlinedTextField(folder, { folder = it }, Modifier.fillMaxWidth(), label = { Text("Cartella dedicata alle note") }, singleLine = true, enabled = !busy)
            OutlinedTextField(token, { token = it }, Modifier.fillMaxWidth(), label = { Text("Token GitHub") },
                singleLine = true, visualTransformation = PasswordVisualTransformation(), enabled = !busy)
            Text("Saranno sincronizzate tutte le note e le attività salvate, con date, ricorrenze e Focus registrato, anche quelle nel cestino, in Markdown non cifrato, insieme ai file degli allegati. Le bozze e le raccolte vuote restano sul telefono. Usa un repository privato per le note personali.")
            Row { Checkbox(consent, { consent = it }, enabled = !busy); Text("Autorizzo lo scambio delle note con questo repository.", Modifier.padding(top = 12.dp).weight(1f)) }
            Row { Checkbox(allowPublic, { allowPublic = it }, enabled = !busy); Text("Consento anche un repository pubblico: i contenuti saranno pubblici.", Modifier.padding(top = 12.dp).weight(1f)) }
            Button(enabled = consent && token.isNotBlank() && !busy, onClick = {
                val c = GitHubConfig(owner.trim(), repo.trim(), branch.trim(), folder.trim(), token.trim())
                action { sync.connect(c, allowPublic); token = "" }
            }) { Text("Collega e sincronizza") }
            TextButton(enabled = !busy, onClick = { action { sync.disconnect(); token = "" } }) { Text("Rimuovi eventuale collegamento precedente") }
        } else {
            Text(status.connection.orEmpty(), style = MaterialTheme.typography.labelLarge)
            Text("Sincronizzazione dopo le modifiche salvate e controllo periodico, quando Android consente il lavoro in rete. Offline puoi continuare a scrivere.")
            Button(enabled = !busy && !status.busy, onClick = sync::schedule) { Text("Sincronizza ora") }
            OutlinedButton(enabled = !busy && !status.busy, onClick = { action { sync.disconnect(); token = "" } }) { Text("Scollega GitHub") }
            if (status.conflicts.isNotEmpty()) {
                Text("${status.conflicts.size} conflitti da risolvere", style = MaterialTheme.typography.titleMedium)
                status.conflicts.take(20).forEach { conflict ->
                    TextButton(enabled = !busy && !status.busy, onClick = { selected = conflict }) {
                        Text(conflict.local?.title?.ifBlank { "Senza titolo" } ?: conflict.remote?.title ?: "Nota")
                    }
                }
                if (status.conflicts.size > 20) Text("Risolvi questi conflitti per mostrare i successivi.")
            }
        }
        Text("Prima versione: massimo 500 elementi tra note e attività, 256 KB per elemento e 5 MB per archivio. Modifica il testo Markdown su GitHub conservando la prima riga dei metadati e il nome del file.", style = MaterialTheme.typography.labelSmall)
    }
    selected?.let { conflict ->
        AlertDialog(onDismissRequest = { if (!busy) selected = null }, title = { Text("Quale versione conservare?") },
            text = { Column(Modifier.heightIn(max = 340.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Sul telefono", style = MaterialTheme.typography.titleMedium)
                Text(conflict.local?.let(::visualConflictSummary) ?: "Assente")
                conflict.local?.let { document ->
                    when (document.sketch?.kind) {
                        it.notes.ecosystem.domain.VisualDocumentKind.SKETCH -> SketchPreview(document.body, Modifier.fillMaxWidth())
                        it.notes.ecosystem.domain.VisualDocumentKind.WHITEBOARD -> WhiteboardPreview(document.body, Modifier.fillMaxWidth())
                        null -> Unit
                    }
                }
                HorizontalDivider()
                Text("Su GitHub", style = MaterialTheme.typography.titleMedium)
                Text(conflict.remote?.let(::visualConflictSummary) ?: "Assente")
                conflict.remote?.let { document ->
                    when (document.sketch?.kind) {
                        it.notes.ecosystem.domain.VisualDocumentKind.SKETCH -> SketchPreview(document.body, Modifier.fillMaxWidth())
                        it.notes.ecosystem.domain.VisualDocumentKind.WHITEBOARD -> WhiteboardPreview(document.body, Modifier.fillMaxWidth())
                        null -> Unit
                    }
                }
                Text("Entrambe conserva GitHub sulla nota originale e crea una copia attiva della versione locale. Per le attività, Entrambe duplica anche i dati Focus delle rispettive versioni. Le anteprime lunghe sono abbreviate.")
            } },
            confirmButton = { Column {
                listOf("both" to "Conserva entrambe", "local" to "Usa telefono", "remote" to "Usa GitHub").forEach { (choice, label) ->
                    TextButton(enabled = !busy, onClick = { action { sync.resolve(conflict, choice); selected = null } }) { Text(label) }
                }
            } }, dismissButton = { TextButton(enabled = !busy, onClick = { selected = null }) { Text("Annulla") } })
    }
}

private fun visualConflictSummary(document: it.notes.ecosystem.sync.SyncDocument): String {
    val prefix = if (document.deletedAt != null) "Nel cestino · " else ""
    val content = when (document.sketch?.kind) {
        it.notes.ecosystem.domain.VisualDocumentKind.SKETCH -> "Disegno · ${document.body.toByteArray(Charsets.UTF_8).size} byte vettoriali"
        it.notes.ecosystem.domain.VisualDocumentKind.WHITEBOARD -> "Lavagna · ${document.body.toByteArray(Charsets.UTF_8).size} byte"
        null -> document.body.take(2000)
    }
    val attachments = if (document.sketch == null) "\nAllegati: ${Attachments.refs(document.body).map { it.key }.distinct().size}" else ""
    return prefix + document.title + "\n" + content + plannerConflictSummary(document) + attachments
}

private fun plannerConflictSummary(document: it.notes.ecosystem.sync.SyncDocument): String {
    val t = document.task ?: return ""
    return "\n\nAttività · " + it.notes.ecosystem.domain.statusLabel(if(t.completedAt!=null) it.notes.ecosystem.domain.TaskStatus.DONE else it.notes.ecosystem.domain.TaskStatus.valueOf(t.stage.name)) +
        "\nData: ${t.due ?: "nessuna"} · Priorità: ${t.priority}" +
        "\nRicorrenza: ${t.repeat.name} · Cicli: ${t.completedCycles}" +
        "\nFocus: ${t.focusSeconds / 60} min · ${t.focusReceipts.size} sessioni (${t.focusHistory.size} datate)" +
        "\nPromemoria: ${t.reminderAt?.let { at -> it.notes.ecosystem.domain.Reminders.display(at,t.reminderZone!!) } ?: "nessuno"}" +
        "\nNota collegata: ${if (t.linkedNoteId == null) "no" else "sì"}"
}

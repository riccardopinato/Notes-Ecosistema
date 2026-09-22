package it.notes.ecosystem.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import it.notes.ecosystem.cloud.CloudSync
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

@Composable
fun CloudSettings(sync: CloudSync) {
    val status by sync.status.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    var createMode by rememberSaveable { mutableStateOf(false) }
    var email by rememberSaveable { mutableStateOf("") }
    var displayName by rememberSaveable { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var localBusy by remember { mutableStateOf(false) }

    fun action(block: suspend () -> Unit) {
        if (localBusy || status.busy) return
        localBusy = true
        error = null
        scope.launch {
            try { block() }
            catch (e: CancellationException) { throw e }
            catch (e: Exception) { error = e.message ?: "Operazione cloud non riuscita." }
            finally { localBusy = false }
        }
    }

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text("Notes Cloud", style = MaterialTheme.typography.headlineMedium)
        Text(status.message)
        error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        if (localBusy || status.busy) LinearProgressIndicator(Modifier.fillMaxWidth())

        if (!status.configured) {
            Text(
                "Il modulo cloud è già presente, ma questa build non contiene ancora URL e publishable key del progetto Supabase. L'app continua a funzionare interamente offline.",
                style = MaterialTheme.typography.bodySmall,
            )
        } else {
            val session = status.session
            if (session == null) {
                Text("L'account è facoltativo. Senza accesso, note, attività, disegni e lavagne restano solo sul dispositivo.")
                if (createMode) {
                    OutlinedTextField(displayName, { displayName = it }, Modifier.fillMaxWidth(), label = { Text("Nome visualizzato") }, singleLine = true)
                }
                OutlinedTextField(email, { email = it }, Modifier.fillMaxWidth(), label = { Text("Email") }, singleLine = true)
                OutlinedTextField(
                    password,
                    { password = it },
                    Modifier.fillMaxWidth(),
                    label = { Text("Password") },
                    singleLine = true,
                    visualTransformation = PasswordVisualTransformation(),
                )
                Button(
                    enabled = !localBusy && !status.busy && email.isNotBlank() && password.isNotBlank() && (!createMode || displayName.isNotBlank()),
                    onClick = {
                        action {
                            if (createMode) sync.signUp(email, password, displayName) else sync.signIn(email, password)
                            password = ""
                        }
                    },
                ) { Text(if (createMode) "Crea account" else "Accedi") }
                TextButton(enabled = !localBusy && !status.busy, onClick = { createMode = !createMode; password = ""; error = null }) {
                    Text(if (createMode) "Ho già un account" else "Crea un account")
                }
            } else {
                Text(session.displayName.ifBlank { session.email }, style = MaterialTheme.typography.titleMedium)
                if (session.displayName.isNotBlank() && session.email.isNotBlank()) Text(session.email, style = MaterialTheme.typography.bodySmall)
                ListItem(
                    headlineContent = { Text("Sincronizzazione personale") },
                    supportingContent = { Text("Disattivata per impostazione predefinita. Il dispositivo resta la sorgente locale finché non scegli di attivarla.") },
                    trailingContent = {
                        Switch(
                            checked = status.personalSyncEnabled,
                            enabled = !localBusy && !status.busy,
                            onCheckedChange = { enabled -> action { if (enabled) sync.enablePersonalSync() else sync.disablePersonalSync() } },
                        )
                    },
                )
                if (status.personalSyncEnabled) {
                    Button(enabled = !localBusy && !status.busy, onClick = { action { sync.syncNow() } }) { Text("Sincronizza ora") }
                    if (status.openConflicts > 0) Text("${status.openConflicts} conflitti cloud richiedono una scelta. Il Conflict Center arriva nel blocco Reliability.")
                }
                OutlinedButton(enabled = !localBusy && !status.busy, onClick = { action { sync.signOut() } }) { Text("Esci dall'account") }
                Text("Uscendo, i dati personali restano sul telefono ma vengono separati dall'account cloud per evitare passaggi accidentali a un account diverso.", style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

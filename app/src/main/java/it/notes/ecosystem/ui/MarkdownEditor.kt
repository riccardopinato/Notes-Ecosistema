package it.notes.ecosystem.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import it.notes.ecosystem.domain.*

@Composable
fun MarkdownEditor(model: EditorViewModel, modifier: Modifier = Modifier, showToolbar: Boolean = true, notes: List<Note> = emptyList()) {
    var field by remember(model.noteId) { mutableStateOf(TextFieldValue(model.body)) }
    val editorFocus = remember { FocusRequester() }
    var focusRequest by remember { mutableIntStateOf(0) }
    LaunchedEffect(focusRequest) { if(focusRequest>0) { withFrameNanos { }; editorFocus.requestFocus() } }
    val enabled = model.available && !model.loading && !model.saving && !model.mediaBusy && !model.checklistWorking
    var error by remember { mutableStateOf<String?>(null) }
    var linkSource by remember { mutableStateOf<TextFieldValue?>(null) }
    var label by remember { mutableStateOf("") }; var url by remember { mutableStateOf("") }
    LaunchedEffect(model.body) {
        if (field.text != model.body) field = TextFieldValue(model.body, TextRange(field.selection.start.coerceAtMost(model.body.length)))
    }
    fun apply(operation: () -> MarkdownEdit) {
        if (!enabled || field.text != model.body) return
        runCatching(operation).onSuccess { edit ->
            field = TextFieldValue(edit.text, TextRange(edit.start, edit.end))
            if (edit.text != model.body) model.editBody(edit.text); error = null; focusRequest++
        }.onFailure { error = it.message ?: "Modifica non riuscita." }
    }
    Column(modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        if(showToolbar) Surface(shape = MaterialTheme.shapes.small, color = MaterialTheme.colorScheme.surfaceContainerLow,
            border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant)) {
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState())) {
            listOf(Triple(MarkdownAction.BOLD, "Grassetto", Icons.Default.FormatBold),
                Triple(MarkdownAction.ITALIC, "Corsivo", Icons.Default.FormatItalic),
                Triple(MarkdownAction.HEADING, "Titolo", Icons.Default.Title),
                Triple(MarkdownAction.BULLET, "Elenco", Icons.Default.FormatListBulleted),
                Triple(MarkdownAction.NUMBERED, "Elenco numerato", Icons.Default.FormatListNumbered),
                Triple(MarkdownAction.QUOTE, "Citazione", Icons.Default.FormatQuote),
                Triple(MarkdownAction.CODE, "Codice", Icons.Default.Code),
                Triple(MarkdownAction.CODE_BLOCK, "Blocco codice", Icons.Default.DeveloperMode)).forEach { (action, title, icon) ->
                IconButton(enabled = enabled, onClick = { apply { MarkdownEditing.apply(field.text, field.selection.start, field.selection.end, action) } }) {
                    Icon(icon, contentDescription = title)
                }
            }
            IconButton(enabled = enabled, onClick = {
                linkSource = field; label = field.text.substring(field.selection.min, field.selection.max); url = "https://"
            }) { Icon(Icons.Default.Link, contentDescription = "Inserisci link") }
        }
        }
        if(showToolbar) KnowledgeTools(field, enabled, notes) { edit -> apply { edit } }
        error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        TextField(field, { value ->
            if (enabled) { field = value; if (value.text != model.body) model.editBody(value.text) }
        }, Modifier.fillMaxWidth().weight(1f).focusRequester(editorFocus), placeholder = { Text("Comincia da un pensiero…") },
            textStyle = MaterialTheme.typography.bodyLarge, colors = pageFieldColors(), enabled = enabled)
    }
    linkSource?.let { source ->
        AlertDialog(onDismissRequest = { linkSource = null }, title = { Text("Inserisci link") }, text = {
            Column {
                OutlinedTextField(label, { label = it }, label = { Text("Testo") }, singleLine = true)
                OutlinedTextField(url, { url = it }, label = { Text("Indirizzo https://") }, singleLine = true)
                error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            }
        }, confirmButton = { TextButton(enabled = enabled && model.body == source.text, onClick = {
            apply { MarkdownEditing.link(source.text, source.selection.start, source.selection.end, label, url) }
            if (error == null) linkSource = null
        }) { Text("Inserisci") } }, dismissButton = { TextButton(onClick = { linkSource = null; error = null }) { Text("Annulla") } })
    }
}

package it.notes.ecosystem.ui

import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import it.notes.ecosystem.domain.*
import kotlin.math.abs

@Composable
fun ChecklistEditor(model: EditorViewModel, body: String, items: List<ChecklistItem>, parsing: Boolean, modifier: Modifier = Modifier) {
    var action by remember { mutableStateOf<Pair<String, ChecklistItem>?>(null) }
    var actionBody by remember { mutableStateOf("") }
    var label by remember { mutableStateOf("") }
    val centers = remember(body) { mutableMapOf<Int, Float>() }
    val enabled = model.available && !model.saving && !model.mediaBusy && !model.checklistWorking && !parsing
    LazyColumn(modifier) {
        item {
            Row {
                TextButton(enabled = enabled && items.isNotEmpty(), onClick = {
                    model.editChecklist(body, ChecklistEditing::completedLast)
                }) { Text("Completate in fondo") }
                TextButton(enabled = enabled, onClick = model::duplicate) { Text("Duplica nota") }
            }
            if (parsing || model.checklistWorking) LinearProgressIndicator(Modifier.fillMaxWidth())
            if (!parsing && items.isEmpty()) Text("Aggiungi la prima attività.")
        }
        items(items, key = { it.lineIndex }, contentType = { "task" }) { task ->
            var menu by remember(body, task.lineIndex) { mutableStateOf(false) }
            val siblings = items.filter { it.parentLine == task.parentLine }
            val index = siblings.indexOf(task)
            Row(Modifier.fillMaxWidth().padding(start = (task.depth * 20).dp)
                .onGloballyPositioned { centers[task.lineIndex] = it.boundsInWindow().center.y },
                verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.DragHandle, "Tieni premuto e trascina la voce", Modifier.size(48.dp)
                    .pointerInput(body, task.lineIndex, enabled) {
                        var distance = 0f
                        var start = 0f
                        detectDragGesturesAfterLongPress(onDragStart = {
                            start = centers[task.lineIndex] ?: 0f; distance = 0f
                        }, onDrag = { change, delta -> if (enabled) { change.consume(); distance += delta.y } },
                            onDragCancel = { distance = 0f }, onDragEnd = {
                                if (enabled && abs(distance) > 16f) {
                                    val target = siblings.filter { centers.containsKey(it.lineIndex) }
                                        .minByOrNull { abs((centers[it.lineIndex] ?: start) - (start + distance)) }
                                    if (target != null) model.editChecklist(body) { ChecklistEditing.move(it, task.lineIndex, target.lineIndex) }
                                }
                            })
                    })
                Checkbox(task.completed, enabled = enabled, modifier = Modifier.semantics { contentDescription = task.label },
                    onCheckedChange = { checked -> model.editChecklist(body) { Checklist.setCompleted(it, task.lineIndex, checked) } })
                TextButton(enabled = enabled, modifier = Modifier.weight(1f), onClick = {
                    actionBody = body; label = task.label; action = "rename" to task
                }) { Text(task.label, Modifier.fillMaxWidth()) }
                Box {
                    IconButton(enabled = enabled, onClick = { menu = true }) { Icon(Icons.Default.MoreVert, "Azioni attività") }
                    DropdownMenu(menu, onDismissRequest = { menu = false }) {
                        DropdownMenuItem(text = { Text("Modifica voce") }, onClick = { menu = false; actionBody = body; label = task.label; action = "rename" to task })
                        DropdownMenuItem(text = { Text("Aggiungi sottoattività") }, onClick = { menu = false; actionBody = body; label = ""; action = "child" to task })
                        DropdownMenuItem(text = { Text("Sposta su") }, enabled = index > 0, onClick = {
                            menu = false; model.editChecklist(body) { ChecklistEditing.move(it, task.lineIndex, siblings[index - 1].lineIndex) }
                        })
                        DropdownMenuItem(text = { Text("Sposta giù") }, enabled = index < siblings.lastIndex, onClick = {
                            menu = false; model.editChecklist(body) { ChecklistEditing.move(it, task.lineIndex, siblings[index + 1].lineIndex) }
                        })
                    }
                }
            }
        }
        item { Text("Tocca una voce per modificarla. Trascina tra le voci visibili oppure usa Sposta su/giù. Un'attività principale si sposta insieme alle sue sottoattività. Premi Salva per confermare.",
            style = MaterialTheme.typography.labelSmall, modifier = Modifier.padding(vertical = 12.dp)) }
    }
    action?.let { (kind, task) ->
        AlertDialog(onDismissRequest = { action = null }, title = { Text(if (kind == "child") "Nuova sottoattività" else "Modifica attività") },
            text = { OutlinedTextField(label, { label = it }, singleLine = true, label = { Text("Testo") }) },
            confirmButton = { TextButton(enabled = label.isNotBlank() && enabled && actionBody == body, onClick = {
                val value = label
                model.editChecklist(actionBody) { if (kind == "child") ChecklistEditing.addChild(it, task.lineIndex, value) else ChecklistEditing.rename(it, task.lineIndex, value) }
                action = null
            }) { Text("Applica") } }, dismissButton = { TextButton(onClick = { action = null }) { Text("Annulla") } })
    }
}

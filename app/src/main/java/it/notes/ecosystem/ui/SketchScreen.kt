package it.notes.ecosystem.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import it.notes.ecosystem.data.SketchCodec
import it.notes.ecosystem.domain.*
import it.notes.ecosystem.sketch.*
import kotlinx.coroutines.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SketchScreen(
    model: SketchViewModel,
    notes: List<Note>,
    onBack: () -> Unit,
    onOpenNote: (String) -> Unit,
    onCopy: (String) -> Unit,
) {
    var tool by rememberSaveable { mutableStateOf("Penna") }
    var shapeKind by rememberSaveable { mutableStateOf(SketchShapeKind.LINE) }
    var ink by rememberSaveable { mutableIntStateOf(0xFF17212B.toInt()) }
    var width by rememberSaveable { mutableIntStateOf(4) }
    var rename by rememberSaveable { mutableStateOf(false) }
    var title by rememberSaveable { mutableStateOf("") }
    var link by rememberSaveable { mutableStateOf(false) }
    var query by rememberSaveable { mutableStateOf("") }
    var sharing by remember { mutableStateOf(false) }
    var canvas by remember { mutableStateOf<SketchCanvasView?>(null) }
    var selectedCount by rememberSaveable { mutableIntStateOf(0) }
    var confirmDeletePage by rememberSaveable { mutableStateOf(false) }
    var addTextDialog by rememberSaveable { mutableStateOf(false) }
    var textDraft by rememberSaveable { mutableStateOf("") }
    var editingTextId by rememberSaveable { mutableStateOf<String?>(null) }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    BackHandler { model.close(onBack) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { EditorialAppTitle("Sketchbook Pro") },
                navigationIcon = { TextButton(onClick = { model.close(onBack) }) { Text("Chiudi") } },
                actions = {
                    TextButton(
                        enabled = model.ready && !sharing,
                        onClick = {
                            sharing = true
                            scope.launch {
                                try {
                                    SketchShare.png(context, model.document, model.title)
                                } catch (e: CancellationException) {
                                    throw e
                                } catch (e: Exception) {
                                    model.warn(e.message ?: "Esportazione non riuscita")
                                } finally {
                                    sharing = false
                                }
                            }
                        },
                    ) { Text(if (sharing) "Esporto…" else "Condividi PNG") }
                },
            )
        },
    ) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Row(Modifier.horizontalScroll(rememberScrollState())) {
                TextButton(enabled = model.ready, onClick = { title = model.title; rename = true }) { Text(model.title) }
                TextButton(enabled = model.ready, onClick = { link = true }) { Text(if (model.info.linkedNoteId == null) "Collega nota" else "Nota collegata") }
                TextButton(enabled = model.canUndo, onClick = model::undo) { Text("Annulla") }
                TextButton(enabled = model.canRedo, onClick = model::redo) { Text("Ripeti") }
            }

            Text(model.status, style = MaterialTheme.typography.labelSmall)
            model.error?.let {
                Text(it, color = MaterialTheme.colorScheme.error)
                TextButton(enabled = model.ready, onClick = { model.saveCopy(onCopy) }) { Text("Salva una copia") }
            }

            Row(
                Modifier.horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                listOf("Penna", "Evidenziatore", "Gomma", "Forma", "Lasso", "Muovi").forEach { label ->
                    FilterChip(tool == label, { tool = label; if (label != "Lasso") canvas?.clearSelection() }, enabled = model.ready, label = { Text(label) })
                }
                TextButton(onClick = { canvas?.resetViewport() }) { Text("Centra") }
            }

            if (tool == "Forma") {
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    listOf(
                        "Linea" to SketchShapeKind.LINE,
                        "Rettangolo" to SketchShapeKind.RECTANGLE,
                        "Ellisse" to SketchShapeKind.ELLIPSE,
                        "Freccia" to SketchShapeKind.ARROW,
                    ).forEach { (label, kind) ->
                        FilterChip(shapeKind == kind, { shapeKind = kind }, label = { Text(label) })
                    }
                }
            }

            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                listOf(
                    "Inchiostro" to 0xFF17212B.toInt(),
                    "Cobalto" to 0xFF3559E0.toInt(),
                    "Terra" to 0xFF8B573A.toInt(),
                    "Rosso" to 0xFFBB3434.toInt(),
                    "Verde" to 0xFF25734C.toInt(),
                ).forEach { (label, color) ->
                    FilterChip(
                        ink == color,
                        { ink = color },
                        enabled = model.ready,
                        label = { Text(label) },
                        leadingIcon = { Surface(color = Color(color), shape = MaterialTheme.shapes.small, modifier = Modifier.size(12.dp)) {} },
                    )
                }
                listOf(2, 4, 8, 16, 24).forEach { value ->
                    FilterChip(width == value, { width = value }, enabled = model.ready, label = { Text("$value") })
                }
            }

            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("Pagina ${model.document.activePage + 1}/${model.document.pages.size}", style = MaterialTheme.typography.labelMedium)
                TextButton(enabled = model.document.activePage > 0, onClick = { model.selectPage(model.document.activePage - 1); canvas?.clearSelection() }) { Text("←") }
                TextButton(enabled = model.document.activePage < model.document.pages.lastIndex, onClick = { model.selectPage(model.document.activePage + 1); canvas?.clearSelection() }) { Text("→") }
                TextButton(enabled = model.ready && model.document.pages.size < SketchRules.MAX_PAGES, onClick = { model.addPage(); canvas?.clearSelection() }) { Text("+ Pagina") }
                TextButton(enabled = model.ready && model.document.pages.size < SketchRules.MAX_PAGES, onClick = { model.duplicatePage(); canvas?.clearSelection() }) { Text("Duplica pagina") }
                TextButton(enabled = model.ready, onClick = { if (model.document.pages.size > 1) confirmDeletePage = true else model.deletePage() }) { Text("Elimina pagina") }
            }

            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                listOf(
                    "Bianca" to SketchPaper.PLAIN,
                    "Righe" to SketchPaper.RULED,
                    "Quadretti" to SketchPaper.GRID,
                    "Puntini" to SketchPaper.DOTS,
                    "Cornell" to SketchPaper.CORNELL,
                ).forEach { (label, paper) ->
                    FilterChip(model.page.paper == paper, { model.setPaper(paper) }, enabled = model.ready, label = { Text(label) })
                }
                OutlinedButton(enabled = model.ready, onClick = { editingTextId = null; textDraft = ""; addTextDialog = true }) { Text("+ Testo") }
            }

            if (selectedCount > 0) {
                Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                    Text("$selectedCount tratti selezionati", modifier = Modifier.weight(1f), style = MaterialTheme.typography.labelMedium)
                    TextButton(onClick = { canvas?.clearSelection() }) { Text("Deseleziona") }
                    TextButton(onClick = { canvas?.deleteSelection() }) { Text("Elimina") }
                }
            }

            if (model.page.texts.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    model.page.texts.take(5).forEach { item ->
                        Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                            Text(item.text.lineSequence().firstOrNull().orEmpty().take(32).ifBlank { "Testo" }, modifier = Modifier.weight(1f), style = MaterialTheme.typography.labelSmall)
                            TextButton(onClick = { editingTextId = item.id; textDraft = item.text; addTextDialog = true }) { Text("Modifica") }
                            TextButton(onClick = { model.deleteText(item.id) }) { Text("Elimina") }
                        }
                    }
                    if (model.page.texts.size > 5) Text("+ ${model.page.texts.size - 5} altri testi", style = MaterialTheme.typography.labelSmall)
                }
            }

            Text(
                when (tool) {
                    "Muovi" -> "Trascina per spostare. Pinch con due dita per zoom."
                    "Gomma" -> "La gomma rimuove il tratto, la forma o il testo toccato."
                    "Forma" -> "Trascina per disegnare la forma selezionata."
                    "Lasso" -> "Trascina un rettangolo attorno ai tratti; trascina di nuovo per spostarli."
                    else -> "Pressione stylus supportata quando disponibile. Ogni tratto viene salvato automaticamente."
                },
                style = MaterialTheme.typography.labelSmall,
            )

            Surface(
                Modifier.fillMaxWidth().weight(1f),
                shape = MaterialTheme.shapes.medium,
                color = MaterialTheme.colorScheme.surfaceContainer,
            ) {
                AndroidView(
                    factory = { SketchCanvasView(it).also { v -> canvas = v } },
                    modifier = Modifier.fillMaxSize(),
                    update = { v ->
                        v.setPage(model.page)
                        v.tool = tool
                        v.shapeKind = shapeKind
                        v.inkColor = ink
                        v.inkWidth = width
                        v.editable = model.ready
                        v.onCommit = model::commitPage
                        v.onLimit = model::warn
                        v.onSelectionChanged = { selectedCount = it }
                    },
                )
            }
        }
    }

    if (rename) AlertDialog(
        onDismissRequest = { rename = false },
        title = { Text("Nome del disegno") },
        text = { OutlinedTextField(title, { title = it }, singleLine = true) },
        confirmButton = { TextButton(onClick = { model.rename(title); rename = false }) { Text("Salva") } },
        dismissButton = { TextButton(onClick = { rename = false }) { Text("Annulla") } },
    )

    if (link) AlertDialog(
        onDismissRequest = { link = false },
        title = { Text("Collega a una nota") },
        text = {
            Column {
                model.info.linkedNoteId?.let { id ->
                    TextButton(onClick = { link = false; model.close { onOpenNote(id) } }) { Text("Apri nota collegata") }
                    TextButton(onClick = { model.link(null); link = false }) { Text("Rimuovi collegamento") }
                }
                OutlinedTextField(query, { query = it }, label = { Text("Cerca titolo") }, singleLine = true)
                notes.asSequence()
                    .filter { it.task == null && it.sketch == null && it.deletedAt == null && it.title.contains(query, true) }
                    .take(8)
                    .forEach { n -> TextButton(onClick = { model.link(n.id); link = false }) { Text(n.title.ifBlank { "Senza titolo" }) } }
            }
        },
        confirmButton = { TextButton(onClick = { link = false }) { Text("Chiudi") } },
    )

    if (confirmDeletePage) AlertDialog(
        onDismissRequest = { confirmDeletePage = false },
        title = { Text("Eliminare questa pagina?") },
        text = { Text("Tratti, forme e testi della pagina verranno rimossi dal disegno.") },
        confirmButton = { TextButton(onClick = { confirmDeletePage = false; model.deletePage(); canvas?.clearSelection() }) { Text("Elimina") } },
        dismissButton = { TextButton(onClick = { confirmDeletePage = false }) { Text("Annulla") } },
    )

    if (addTextDialog) AlertDialog(
        onDismissRequest = { addTextDialog = false },
        title = { Text(if (editingTextId == null) "Aggiungi testo" else "Modifica testo") },
        text = { OutlinedTextField(textDraft, { if (it.length <= SketchRules.MAX_TEXT_LENGTH) textDraft = it }, minLines = 2, maxLines = 6) },
        confirmButton = {
            TextButton(
                enabled = textDraft.isNotBlank(),
                onClick = {
                    val id = editingTextId
                    if (id == null) model.addText(value = textDraft.trim()) else model.updateText(id, textDraft.trim())
                    addTextDialog = false
                },
            ) { Text("Salva") }
        },
        dismissButton = { TextButton(onClick = { addTextDialog = false }) { Text("Annulla") } },
    )
}

@Composable
internal fun SketchPreview(body: String, modifier: Modifier = Modifier) {
    val result by produceState<Pair<String, SketchPage?>?>(null, body) {
        value = body to withContext(Dispatchers.Default) { runCatching { SketchCodec.decodeDocument(body).page }.getOrNull() }
    }
    val page = if (result?.first == body) result?.second else null
    if (page == null) {
        Box(modifier.height(150.dp)) { Text("Anteprima disegno", style = MaterialTheme.typography.labelSmall) }
    } else {
        AndroidView(
            factory = { SketchCanvasView(it).apply { editable = false; contentDescription = "Anteprima del disegno" } },
            modifier = modifier.height(150.dp),
            update = { it.setPage(page); it.editable = false },
        )
    }
}

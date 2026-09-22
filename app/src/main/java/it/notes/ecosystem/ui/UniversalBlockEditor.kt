package it.notes.ecosystem.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import it.notes.ecosystem.domain.BlockEditorCodec
import it.notes.ecosystem.domain.ContentBlock
import it.notes.ecosystem.domain.ContentBlockType
import kotlinx.coroutines.delay

@Composable
private fun BufferedBlockTextField(
    blockId: String,
    modelValue: String,
    enabled: Boolean,
    modifier: Modifier = Modifier,
    placeholder: @Composable (() -> Unit)? = null,
    textStyle: TextStyle = LocalTextStyle.current,
    minLines: Int = 1,
    maxLines: Int = Int.MAX_VALUE,
    singleLine: Boolean = false,
    onLocalChange: (String) -> Unit = {},
    onCommit: (String) -> Unit,
) {
    var local by remember(blockId) {
        mutableStateOf(modelValue)
    }

    var focused by remember(blockId) {
        mutableStateOf(false)
    }

    val latestModel by rememberUpdatedState(modelValue)
    val latestCommit by rememberUpdatedState(onCommit)

    /*
     * Cambiamenti esterni (undo, tipo blocco, revisione, ecc.)
     * aggiornano il campo solo quando non stiamo digitando.
     */
    LaunchedEffect(modelValue, focused) {
        if (!focused && local != modelValue) {
            local = modelValue
        }
    }

    /*
     * 120 ms è abbastanza rapido da sembrare realtime
     * ma evita un update globale per ogni battuta.
     */
    LaunchedEffect(local) {
        if (local != latestModel) {
            delay(120)
            if (local != latestModel) {
                latestCommit(local)
            }
        }
    }

    DisposableEffect(blockId) {
        onDispose {
            if (local != latestModel) {
                latestCommit(local)
            }
        }
    }

    OutlinedTextField(
        value = local,
        onValueChange = {
            local = it
            onLocalChange(it)
        },
        enabled = enabled,
        modifier = modifier.onFocusChanged { state ->
            val wasFocused = focused
            focused = state.isFocused

            if (
                wasFocused &&
                !focused &&
                local != latestModel
            ) {
                latestCommit(local)
            }
        },
        placeholder = placeholder,
        textStyle = textStyle,
        minLines = minLines,
        maxLines = maxLines,
        singleLine = singleLine,
        colors = blockFieldColors(),
    )
}

private data class BlockCommand(
    val label: String,
    val hint: String,
    val type: ContentBlockType,
)

private val blockCommands = listOf(
    BlockCommand("Testo", "Paragrafo normale", ContentBlockType.TEXT),
    BlockCommand("Titolo", "Intestazione H2", ContentBlockType.HEADING),
    BlockCommand("Checklist", "Voce da spuntare", ContentBlockType.CHECKLIST),
    BlockCommand("Citazione", "Citazione o estratto", ContentBlockType.QUOTE),
    BlockCommand("Codice", "Blocco monospazio", ContentBlockType.CODE),
    BlockCommand("Callout", "Nota in evidenza", ContentBlockType.CALLOUT),
    BlockCommand("Separatore", "Linea di separazione", ContentBlockType.DIVIDER),
    BlockCommand("Disegno", "Sketchbook collegato alla nota", ContentBlockType.DRAWING),
    BlockCommand("Lavagna", "Whiteboard o mind map collegata alla nota", ContentBlockType.WHITEBOARD),
    BlockCommand("Markdown", "Contenuto Markdown libero", ContentBlockType.MARKDOWN),
)

@Composable
fun UniversalBlockEditor(
    model: EditorViewModel,
    modifier: Modifier = Modifier,
    showControls: Boolean = true,
    onCreateDrawing: ((blockId: String) -> Unit)? = null,
    onOpenDrawing: ((sketchId: String) -> Unit)? = null,
    onWhiteboardCreate: ((blockId: String) -> Unit)? = null,
    onOpenWhiteboard: (String) -> Unit = {},
) {
    Column(modifier) {
        if (model.blocksLoading) {
            LinearProgressIndicator(Modifier.fillMaxWidth())
        }

        if (showControls) {
            Row(
                Modifier.fillMaxWidth().padding(bottom = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    "${model.blocks.size} ${if (model.blocks.size == 1) "blocco" else "blocchi"}",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f),
                )
                AddBlockMenu(enabled = model.blockEditingEnabled) { type ->
                    model.addBlock(type)
                }
            }
        }

        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            verticalArrangement = Arrangement.spacedBy(8.dp),
            contentPadding = PaddingValues(bottom = 96.dp),
        ) {
            itemsIndexed(
                items = model.blocks,
                key = { _, item -> item.id },
                contentType = { _, item -> item.type },
            ) { index, block ->
                BlockCard(
                    block = block,
                    index = index,
                    total = model.blocks.size,
                    enabled = model.blockEditingEnabled,
                    showControls = showControls,
                    onText = { model.updateBlockText(block.id, it) },
                    onChecked = { model.setBlockChecked(block.id, it) },
                    onType = { model.changeBlockType(block.id, it) },
                    onHeadingLevel = { model.setBlockHeadingLevel(block.id, it) },
                    onAddAfter = { type -> model.addBlock(type, block.id) },
                    onDuplicate = { model.duplicateBlock(block.id) },
                    onDelete = { model.deleteBlock(block.id) },
                    onMoveUp = { model.moveBlock(block.id, -1) },
                    onMoveDown = { model.moveBlock(block.id, +1) },
                    onCreateDrawing = onCreateDrawing,
                    onOpenDrawing = onOpenDrawing,
                    onWhiteboardCreate = onWhiteboardCreate,
                    onOpenWhiteboard = onOpenWhiteboard,
                )
            }
        }
    }
}

@Composable
private fun AddBlockMenu(
    enabled: Boolean,
    onAdd: (ContentBlockType) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    Box {
        OutlinedButton(enabled = enabled, onClick = { open = true }) {
            Text("+ Blocco")
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            blockCommands.forEach { command ->
                DropdownMenuItem(
                    text = {
                        Column {
                            Text(command.label)
                            Text(command.hint, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    },
                    onClick = {
                        open = false
                        onAdd(command.type)
                    },
                )
            }
        }
    }
}

@Composable
private fun BlockCard(
    block: ContentBlock,
    index: Int,
    total: Int,
    enabled: Boolean,
    showControls: Boolean,
    onText: (String) -> Unit,
    onChecked: (Boolean) -> Unit,
    onType: (ContentBlockType) -> Unit,
    onHeadingLevel: (Int) -> Unit,
    onAddAfter: (ContentBlockType) -> Unit,
    onDuplicate: () -> Unit,
    onDelete: () -> Unit,
    onMoveUp: () -> Unit,
    onMoveDown: () -> Unit,
    onCreateDrawing: ((blockId: String) -> Unit)? = null,
    onOpenDrawing: ((sketchId: String) -> Unit)? = null,
    onWhiteboardCreate: ((blockId: String) -> Unit)? = null,
    onOpenWhiteboard: (String) -> Unit = {},
) {
    var menu by remember { mutableStateOf(false) }
    var slashMenu by remember(block.id, block.text) {
        mutableStateOf(block.text.trimStart().startsWith("/") && block.type in listOf(ContentBlockType.TEXT, ContentBlockType.MARKDOWN))
    }

    Surface(
        tonalElevation = 0.dp,
        shape = RoundedCornerShape(14.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            if (showControls) {
                Row(
                    Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Text(
                        blockLabel(block),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.weight(1f),
                    )
                    TextButton(enabled = enabled, onClick = { menu = true }) { Text("•••") }
                    DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                        DropdownMenuItem(text = { Text("Aggiungi sotto") }, onClick = {
                            menu = false
                            onAddAfter(ContentBlockType.TEXT)
                        })
                        DropdownMenuItem(text = { Text("Duplica") }, onClick = { menu = false; onDuplicate() })
                        DropdownMenuItem(text = { Text("Sposta su") }, enabled = index > 0, onClick = { menu = false; onMoveUp() })
                        DropdownMenuItem(text = { Text("Sposta giù") }, enabled = index < total - 1, onClick = { menu = false; onMoveDown() })
                        HorizontalDivider()
                        DropdownMenuItem(text = { Text("Elimina") }, onClick = { menu = false; onDelete() })
                    }
                }
            }

            when (block.type) {
                ContentBlockType.DIVIDER -> {
                    HorizontalDivider(Modifier.padding(vertical = 12.dp))
                }

                ContentBlockType.CHECKLIST,
                ContentBlockType.TASK -> {
                    Row(verticalAlignment = Alignment.Top) {
                        Checkbox(
                            checked = block.checked == true,
                            enabled = enabled,
                            onCheckedChange = onChecked,
                        )
                        BufferedBlockTextField(
                            blockId = block.id,
                            modelValue = block.text,
                            enabled = enabled,
                            modifier = Modifier.weight(1f),
                            placeholder = { Text("Attività…") },
                            onCommit = onText,
                        )
                    }
                }

                ContentBlockType.HEADING -> {
                    if (showControls) {
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            (1..3).forEach { level ->
                                FilterChip(
                                    selected = BlockEditorCodec.headingLevel(block) == level,
                                    enabled = enabled,
                                    onClick = { onHeadingLevel(level) },
                                    label = { Text("H$level") },
                                )
                            }
                        }
                    }
                    BufferedBlockTextField(
                        blockId = block.id,
                        modelValue = block.text,
                        enabled = enabled,
                        modifier = Modifier.fillMaxWidth(),
                        placeholder = { Text("Titolo…") },
                        textStyle = when (BlockEditorCodec.headingLevel(block)) {
                            1 -> MaterialTheme.typography.headlineLarge
                            2 -> MaterialTheme.typography.headlineMedium
                            else -> MaterialTheme.typography.headlineSmall
                        },
                        onCommit = onText,
                    )
                }

                ContentBlockType.CODE -> {
                    BufferedBlockTextField(
                        blockId = block.id,
                        modelValue = block.text,
                        enabled = enabled,
                        modifier = Modifier.fillMaxWidth(),
                        minLines = 3,
                        textStyle = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
                        placeholder = { Text("Codice…") },
                        onCommit = onText,
                    )
                }

                ContentBlockType.QUOTE -> {
                    Row {
                        Box(
                            Modifier.width(4.dp).heightIn(min = 56.dp)
                                .background(MaterialTheme.colorScheme.primary, RoundedCornerShape(4.dp))
                        )
                        Spacer(Modifier.width(10.dp))
                        BufferedBlockTextField(
                            blockId = block.id,
                            modelValue = block.text,
                            enabled = enabled,
                            modifier = Modifier.weight(1f),
                            placeholder = { Text("Citazione…") },
                            onCommit = onText,
                        )
                    }
                }

                ContentBlockType.CALLOUT -> {
                    Surface(
                        color = MaterialTheme.colorScheme.secondaryContainer,
                        shape = RoundedCornerShape(12.dp),
                    ) {
                        BufferedBlockTextField(
                            blockId = block.id,
                            modelValue = block.text,
                            enabled = enabled,
                            modifier = Modifier.fillMaxWidth().padding(4.dp),
                            placeholder = { Text("Nota in evidenza…") },
                            onCommit = onText,
                        )
                    }
                }

                ContentBlockType.DRAWING -> {
                    val drawingId = BlockEditorCodec.sketchId(block)
                    Surface(
                        color = MaterialTheme.colorScheme.surfaceVariant,
                        shape = RoundedCornerShape(12.dp),
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Column(
                            Modifier.fillMaxWidth().padding(12.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                Text(
                                    "✏ ${block.text.ifBlank { "Disegno" }}",
                                    style = MaterialTheme.typography.titleMedium,
                                    modifier = Modifier.weight(1f),
                                )
                                if (drawingId != null) {
                                    AssistChip(
                                        onClick = {},
                                        label = { Text("Sketchbook") },
                                    )
                                    OutlinedButton(
                                        onClick = { onOpenDrawing?.invoke(drawingId) },
                                        enabled = enabled && onOpenDrawing != null,
                                    ) {
                                        Text("Apri")
                                    }
                                } else {
                                    Button(
                                        onClick = { onCreateDrawing?.invoke(block.id) },
                                        enabled = enabled && onCreateDrawing != null,
                                    ) {
                                        Text("Crea disegno")
                                    }
                                }
                            }

                            BufferedBlockTextField(
                                blockId = block.id,
                                modelValue = block.text,
                                enabled = enabled,
                                modifier = Modifier.fillMaxWidth(),
                                placeholder = { Text("Titolo disegno…") },
                                singleLine = true,
                                onCommit = onText,
                            )

                            if (showControls) {
                                Text(
                                    if (drawingId != null) "Tocca Apri per modificare nello Sketchbook"
                                    else "Nessun disegno collegato. Tocca Crea disegno per iniziare.",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    }
                }

                ContentBlockType.WHITEBOARD -> {
                    val whiteboardId = BlockEditorCodec.whiteboardId(block)
                    Surface(
                        color = MaterialTheme.colorScheme.surfaceVariant,
                        shape = RoundedCornerShape(12.dp),
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Column(
                            Modifier.fillMaxWidth().padding(12.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                Text(
                                    "▦ ${block.text.ifBlank { "Lavagna" }}",
                                    style = MaterialTheme.typography.titleMedium,
                                    modifier = Modifier.weight(1f),
                                )
                                if (whiteboardId != null) {
                                    AssistChip(onClick = {}, label = { Text("Whiteboard") })
                                    OutlinedButton(
                                        onClick = { onOpenWhiteboard(whiteboardId) },
                                        enabled = enabled,
                                    ) { Text("Apri lavagna") }
                                } else {
                                    Button(
                                        onClick = { onWhiteboardCreate?.invoke(block.id) },
                                        enabled = enabled && onWhiteboardCreate != null,
                                    ) { Text("Crea lavagna") }
                                }
                            }
                            BufferedBlockTextField(
                                blockId = block.id,
                                modelValue = block.text,
                                enabled = enabled,
                                modifier = Modifier.fillMaxWidth(),
                                placeholder = { Text("Titolo lavagna…") },
                                singleLine = true,
                                onCommit = onText,
                            )
                        }
                    }
                }

                ContentBlockType.IMAGE,
                ContentBlockType.AUDIO,
                ContentBlockType.FILE -> {
                    // Nella 0.20 gli allegati restano gestiti dal pannello Allegati esistente.
                    // Qui mostriamo il riferimento senza reinterpretarlo o perdere informazioni.
                    Surface(
                        color = MaterialTheme.colorScheme.surfaceVariant,
                        shape = RoundedCornerShape(10.dp),
                    ) {
                        Column(Modifier.fillMaxWidth().padding(12.dp)) {
                            Text(
                                when (block.type) {
                                    ContentBlockType.IMAGE -> "Immagine allegata"
                                    ContentBlockType.AUDIO -> "Audio allegato"
                                    else -> "File allegato"
                                },
                                style = MaterialTheme.typography.titleSmall,
                            )
                            Text(block.text, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }

                else -> {
                    Box {
                        BufferedBlockTextField(
                            blockId = block.id,
                            modelValue = block.text,
                            enabled = enabled,
                            modifier = Modifier.fillMaxWidth(),
                            placeholder = { Text(if (index == 0) "Scrivi oppure digita / per i blocchi…" else "Scrivi…") },
                            minLines = if (block.type == ContentBlockType.MARKDOWN) 2 else 1,
                            textStyle = if (block.type == ContentBlockType.MARKDOWN)
                                MaterialTheme.typography.bodyLarge.copy(fontFamily = FontFamily.Monospace)
                            else MaterialTheme.typography.bodyLarge,
                            onLocalChange = { value ->
                                slashMenu = value.trimStart().startsWith("/") && block.type in listOf(ContentBlockType.TEXT, ContentBlockType.MARKDOWN)
                            },
                            onCommit = onText,
                        )
                        DropdownMenu(
                            expanded = slashMenu && enabled,
                            onDismissRequest = { slashMenu = false },
                        ) {
                            blockCommands.forEach { command ->
                                DropdownMenuItem(
                                    text = {
                                        Column {
                                            Text("/${command.label.lowercase()}")
                                            Text(command.hint, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                        }
                                    },
                                    onClick = {
                                        slashMenu = false
                                        onText("")
                                        onType(command.type)
                                    },
                                )
                            }
                        }
                    }
                }
            }

            if (showControls && block.type !in listOf(
                    ContentBlockType.IMAGE,
                    ContentBlockType.AUDIO,
                    ContentBlockType.FILE,
                    ContentBlockType.DRAWING,
                    ContentBlockType.WHITEBOARD,
                    ContentBlockType.BOOKMARK,
                    ContentBlockType.TABLE,
                    ContentBlockType.DIVIDER,
                )
            ) {
                BlockTypeMenu(enabled = enabled, current = block.type, onType = onType)
            }
        }
    }
}

@Composable
private fun BlockTypeMenu(
    enabled: Boolean,
    current: ContentBlockType,
    onType: (ContentBlockType) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    Box {
        TextButton(enabled = enabled, onClick = { open = true }) {
            Text("Trasforma · ${blockTypeName(current)}")
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            blockCommands.forEach { command ->
                DropdownMenuItem(
                    text = { Text(command.label) },
                    onClick = {
                        open = false
                        onType(command.type)
                    },
                )
            }
        }
    }
}

private fun blockLabel(block: ContentBlock): String = when (block.type) {
    ContentBlockType.TEXT -> "TESTO"
    ContentBlockType.MARKDOWN -> "MARKDOWN"
    ContentBlockType.HEADING -> "H${BlockEditorCodec.headingLevel(block)}"
    ContentBlockType.CHECKLIST -> "CHECKLIST"
    ContentBlockType.TASK -> "ATTIVITÀ"
    ContentBlockType.IMAGE -> "IMMAGINE"
    ContentBlockType.AUDIO -> "AUDIO"
    ContentBlockType.FILE -> "FILE"
    ContentBlockType.DRAWING -> "DISEGNO"
    ContentBlockType.WHITEBOARD -> "LAVAGNA"
    ContentBlockType.BOOKMARK -> "BOOKMARK"
    ContentBlockType.TABLE -> "TABELLA"
    ContentBlockType.CODE -> "CODICE"
    ContentBlockType.QUOTE -> "CITAZIONE"
    ContentBlockType.CALLOUT -> "CALLOUT"
    ContentBlockType.DIVIDER -> "SEPARATORE"
}

private fun blockTypeName(type: ContentBlockType): String = when (type) {
    ContentBlockType.TEXT -> "Testo"
    ContentBlockType.MARKDOWN -> "Markdown"
    ContentBlockType.HEADING -> "Titolo"
    ContentBlockType.CHECKLIST -> "Checklist"
    ContentBlockType.TASK -> "Attività"
    ContentBlockType.IMAGE -> "Immagine"
    ContentBlockType.AUDIO -> "Audio"
    ContentBlockType.FILE -> "File"
    ContentBlockType.DRAWING -> "Disegno"
    ContentBlockType.WHITEBOARD -> "Lavagna"
    ContentBlockType.BOOKMARK -> "Bookmark"
    ContentBlockType.TABLE -> "Tabella"
    ContentBlockType.CODE -> "Codice"
    ContentBlockType.QUOTE -> "Citazione"
    ContentBlockType.CALLOUT -> "Callout"
    ContentBlockType.DIVIDER -> "Separatore"
}

@Composable
private fun blockFieldColors() = OutlinedTextFieldDefaults.colors(
    focusedBorderColor = MaterialTheme.colorScheme.outlineVariant,
    unfocusedBorderColor = MaterialTheme.colorScheme.outlineVariant,
    disabledBorderColor = MaterialTheme.colorScheme.outlineVariant,
)

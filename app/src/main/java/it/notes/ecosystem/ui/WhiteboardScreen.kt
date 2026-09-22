package it.notes.ecosystem.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import it.notes.ecosystem.data.WhiteboardCodec
import it.notes.ecosystem.domain.*
import it.notes.ecosystem.whiteboard.WhiteboardCanvasView
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WhiteboardScreen(
    model: WhiteboardViewModel,
    notes: List<Note>,
    onBack: () -> Unit,
    onOpenNote: (String) -> Unit,
    onCopy: (String) -> Unit,
) {
    var toolName by rememberSaveable {
        mutableStateOf(WhiteboardTool.SELECT.name)
    }
    val tool = WhiteboardTool.valueOf(toolName)

    var ink by rememberSaveable {
        mutableIntStateOf(0xFF17212B.toInt())
    }
    var width by rememberSaveable {
        mutableIntStateOf(4)
    }
    var canvas by remember {
        mutableStateOf<WhiteboardCanvasView?>(null)
    }
    var selectedId by rememberSaveable {
        mutableStateOf<String?>(null)
    }
    var renameOpen by rememberSaveable {
        mutableStateOf(false)
    }
    var renameDraft by rememberSaveable {
        mutableStateOf("")
    }
    var nodeEditOpen by rememberSaveable {
        mutableStateOf(false)
    }
    var linkPickerOpen by rememberSaveable {
        mutableStateOf(false)
    }
    var linkQuery by rememberSaveable {
        mutableStateOf("")
    }

    val selectedNode =
        model.document.nodes.firstOrNull {
            it.id == selectedId
        }

    BackHandler {
        model.close(onBack)
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    EditorialAppTitle(
                        if (model.document.mode == WhiteboardMode.MIND_MAP) {
                            "Mind Map"
                        } else {
                            "Whiteboard"
                        }
                    )
                },
                navigationIcon = {
                    TextButton(
                        onClick = {
                            model.close(onBack)
                        }
                    ) {
                        Text("Chiudi")
                    }
                },
            )
        },
    ) { padding ->
        Column(
            Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 10.dp),
            verticalArrangement = Arrangement.spacedBy(5.dp),
        ) {
            Row(
                Modifier.horizontalScroll(
                    rememberScrollState()
                ),
                horizontalArrangement = Arrangement.spacedBy(5.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                TextButton(
                    enabled = model.ready,
                    onClick = {
                        renameDraft = model.title
                        renameOpen = true
                    },
                ) {
                    Text(model.title)
                }

                FilterChip(
                    selected = model.document.mode == WhiteboardMode.FREEFORM,
                    enabled = model.ready,
                    onClick = {
                        model.setMode(WhiteboardMode.FREEFORM)
                    },
                    label = { Text("Lavagna") },
                )

                FilterChip(
                    selected = model.document.mode == WhiteboardMode.MIND_MAP,
                    enabled = model.ready,
                    onClick = {
                        model.setMode(WhiteboardMode.MIND_MAP)
                    },
                    label = { Text("Mind Map") },
                )

                TextButton(
                    enabled = model.canUndo,
                    onClick = model::undo,
                ) {
                    Text("Annulla")
                }

                TextButton(
                    enabled = model.canRedo,
                    onClick = model::redo,
                ) {
                    Text("Ripeti")
                }
            }

            Text(
                model.status,
                style = MaterialTheme.typography.labelSmall,
            )

            model.error?.let {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        it,
                        color = MaterialTheme.colorScheme.error,
                        modifier = Modifier.weight(1f),
                    )
                    TextButton(
                        enabled = model.ready,
                        onClick = {
                            model.saveCopy(onCopy)
                        },
                    ) {
                        Text("Salva copia")
                    }
                }
            }

            Row(
                Modifier.horizontalScroll(
                    rememberScrollState()
                ),
                horizontalArrangement = Arrangement.spacedBy(5.dp),
            ) {
                listOf(
                    "Seleziona" to WhiteboardTool.SELECT,
                    "Muovi" to WhiteboardTool.PAN,
                    "Penna" to WhiteboardTool.PEN,
                    "Evidenziatore" to WhiteboardTool.HIGHLIGHTER,
                    "Gomma" to WhiteboardTool.ERASER,
                    "Connetti" to WhiteboardTool.CONNECT,
                    "Rettangolo" to WhiteboardTool.RECTANGLE,
                    "Ellisse" to WhiteboardTool.ELLIPSE,
                ).forEach { (label, value) ->
                    FilterChip(
                        selected = tool == value,
                        enabled = model.ready,
                        onClick = {
                            toolName = value.name
                        },
                        label = { Text(label) },
                    )
                }

                TextButton(
                    onClick = {
                        canvas?.centerViewport()
                    },
                ) {
                    Text("Centra")
                }
            }

            Row(
                Modifier.horizontalScroll(
                    rememberScrollState()
                ),
                horizontalArrangement = Arrangement.spacedBy(5.dp),
            ) {
                listOf(
                    "Nero" to 0xFF17212B.toInt(),
                    "Blu" to 0xFF3559E0.toInt(),
                    "Rosso" to 0xFFB73737.toInt(),
                    "Verde" to 0xFF25734C.toInt(),
                ).forEach { (label, color) ->
                    FilterChip(
                        selected = ink == color,
                        onClick = { ink = color },
                        label = { Text(label) },
                        leadingIcon = {
                            Surface(
                                color = Color(color),
                                shape = MaterialTheme.shapes.small,
                                modifier = Modifier.size(12.dp),
                            ) {}
                        },
                    )
                }

                listOf(2, 4, 8, 16, 24).forEach { value ->
                    FilterChip(
                        selected = width == value,
                        onClick = { width = value },
                        label = { Text("$value") },
                    )
                }
            }

            Row(
                Modifier.horizontalScroll(
                    rememberScrollState()
                ),
                horizontalArrangement = Arrangement.spacedBy(5.dp),
            ) {
                Button(
                    enabled = model.ready,
                    onClick = model::addSticky,
                ) {
                    Text("+ Sticky")
                }

                OutlinedButton(
                    enabled = model.ready,
                    onClick = model::addText,
                ) {
                    Text("+ Testo")
                }

                OutlinedButton(
                    enabled = model.ready,
                    onClick = {
                        linkPickerOpen = true
                    },
                ) {
                    Text("+ Nota/Task")
                }

                if (
                    model.document.mode == WhiteboardMode.MIND_MAP
                ) {
                    OutlinedButton(
                        enabled = model.ready && selectedNode != null,
                        onClick = {
                            selectedNode?.let {
                                model.addMindChild(it.id)
                            }
                        },
                    ) {
                        Text("+ Figlio")
                    }

                    OutlinedButton(
                        enabled = model.ready,
                        onClick = model::autoLayoutMindMap,
                    ) {
                        Text("Auto-layout")
                    }
                }

                if (selectedNode != null) {
                    OutlinedButton(
                        onClick = {
                            nodeEditOpen = true
                        },
                    ) {
                        Text("Modifica nodo")
                    }

                    TextButton(
                        onClick = {
                            canvas?.deleteSelection()
                        },
                    ) {
                        Text("Elimina")
                    }

                    selectedNode.linkedNoteId?.let { linked ->
                        TextButton(
                            onClick = {
                                onOpenNote(linked)
                            },
                        ) {
                            Text("Apri collegamento")
                        }
                    }
                }
            }

            AndroidView(
                factory = { context ->
                    WhiteboardCanvasView(context).also { view ->
                        canvas = view
                        view.onCommit = model::commit
                        view.onSelection = {
                            selectedId = it
                        }
                    }
                },
                modifier =
                    Modifier
                        .fillMaxWidth()
                        .weight(1f),
                update = { view ->
                    view.setTool(tool)
                    view.setInk(ink, width)
                    view.setDocument(model.document)
                },
            )
        }
    }

    if (renameOpen) {
        AlertDialog(
            onDismissRequest = {
                renameOpen = false
            },
            title = { Text("Titolo") },
            text = {
                OutlinedTextField(
                    value = renameDraft,
                    onValueChange = {
                        renameDraft = it.take(8000)
                    },
                    singleLine = true,
                )
            },
            confirmButton = {
                Button(
                    onClick = {
                        model.rename(renameDraft)
                        renameOpen = false
                    },
                ) {
                    Text("Salva")
                }
            },
            dismissButton = {
                TextButton(
                    onClick = {
                        renameOpen = false
                    },
                ) {
                    Text("Annulla")
                }
            },
        )
    }

    selectedNode?.let { node ->
        if (nodeEditOpen) {
            NodeEditDialog(
                node = node,
                onDismiss = {
                    nodeEditOpen = false
                },
                onSave = {
                    model.updateNode(it)
                    nodeEditOpen = false
                },
                onDelete = {
                    model.deleteNode(node.id)
                    selectedId = null
                    nodeEditOpen = false
                },
            )
        }
    }

    if (linkPickerOpen) {
        val candidates = remember(notes, linkQuery) {
            notes
                .filter {
                    it.deletedAt == null &&
                        it.sketch == null &&
                        (
                            linkQuery.isBlank() ||
                                it.title.contains(
                                    linkQuery,
                                    ignoreCase = true,
                                )
                        )
                }
                .take(40)
        }

        AlertDialog(
            onDismissRequest = {
                linkPickerOpen = false
                linkQuery = ""
            },
            title = { Text("Collega contenuto") },
            text = {
                Column(
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    OutlinedTextField(
                        value = linkQuery,
                        onValueChange = { linkQuery = it },
                        label = { Text("Cerca nota o attività") },
                        singleLine = true,
                    )

                    candidates.take(12).forEach { note ->
                        TextButton(
                            onClick = {
                                model.addLinked(note)
                                linkPickerOpen = false
                                linkQuery = ""
                            },
                        ) {
                            Text(
                                (if (note.task != null) "Task · " else "Nota · ") +
                                    note.title.ifBlank { "Senza titolo" }
                            )
                        }
                    }
                }
            },
            confirmButton = {},
            dismissButton = {
                TextButton(
                    onClick = {
                        linkPickerOpen = false
                        linkQuery = ""
                    },
                ) {
                    Text("Chiudi")
                }
            },
        )
    }
}

@Composable
private fun NodeEditDialog(
    node: BoardNode,
    onDismiss: () -> Unit,
    onSave: (BoardNode) -> Unit,
    onDelete: () -> Unit,
) {
    var text by remember(node.id) {
        mutableStateOf(node.text)
    }
    var color by remember(node.id) {
        mutableIntStateOf(node.color)
    }
    var nodeWidth by remember(node.id) {
        mutableIntStateOf(node.width)
    }
    var nodeHeight by remember(node.id) {
        mutableIntStateOf(node.height)
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Modifica nodo") },
        text = {
            Column(
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                OutlinedTextField(
                    value = text,
                    onValueChange = {
                        text = it.take(
                            WhiteboardRules.MAX_TEXT_LENGTH
                        )
                    },
                    label = { Text("Testo") },
                    minLines = 3,
                )

                Text("Colore")
                Row(
                    Modifier.horizontalScroll(
                        rememberScrollState()
                    ),
                ) {
                    listOf(
                        0xFFFFE7A3.toInt(),
                        0xFFDDEBFF.toInt(),
                        0xFFE7F4E8.toInt(),
                        0xFFFFE1E1.toInt(),
                        0xFFF1E5FF.toInt(),
                        0xFFFFFFFF.toInt(),
                    ).forEach { value ->
                        FilterChip(
                            selected = color == value,
                            onClick = { color = value },
                            label = { Text("●") },
                            leadingIcon = {
                                Surface(
                                    color = Color(value),
                                    modifier = Modifier.size(14.dp),
                                    shape = MaterialTheme.shapes.small,
                                ) {}
                            },
                        )
                    }
                }

                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    OutlinedTextField(
                        value = nodeWidth.toString(),
                        onValueChange = {
                            it.toIntOrNull()?.let { value ->
                                nodeWidth = value.coerceIn(
                                    WhiteboardRules.MIN_NODE_WIDTH,
                                    WhiteboardRules.MAX_NODE_WIDTH,
                                )
                            }
                        },
                        label = { Text("Larghezza") },
                        modifier = Modifier.weight(1f),
                    )

                    OutlinedTextField(
                        value = nodeHeight.toString(),
                        onValueChange = {
                            it.toIntOrNull()?.let { value ->
                                nodeHeight = value.coerceIn(
                                    WhiteboardRules.MIN_NODE_HEIGHT,
                                    WhiteboardRules.MAX_NODE_HEIGHT,
                                )
                            }
                        },
                        label = { Text("Altezza") },
                        modifier = Modifier.weight(1f),
                    )
                }
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    onSave(
                        node.copy(
                            text = text,
                            color = color,
                            width = nodeWidth,
                            height = nodeHeight,
                        )
                    )
                },
            ) {
                Text("Salva")
            }
        },
        dismissButton = {
            Row {
                TextButton(onClick = onDelete) {
                    Text("Elimina")
                }
                TextButton(onClick = onDismiss) {
                    Text("Annulla")
                }
            }
        },
    )
}

@Composable
internal fun WhiteboardPreview(
    body: String,
    modifier: Modifier = Modifier,
) {
    val document by produceState<WhiteboardDocument?>(
        initialValue = null,
        key1 = body,
    ) {
        value = withContext(Dispatchers.Default) {
            runCatching {
                WhiteboardCodec.decode(body)
            }.getOrNull()
        }
    }

    val board = document ?: return

    androidx.compose.foundation.Canvas(
        modifier = modifier.height(150.dp),
    ) {
        drawRect(
            color = androidx.compose.ui.graphics.Color(0xFFF5F7FA)
        )

        if (board.nodes.isEmpty()) return@Canvas

        val minX = board.nodes.minOf { it.x }.toFloat()
        val maxX = board.nodes.maxOf { it.x + it.width }.toFloat()
        val minY = board.nodes.minOf { it.y }.toFloat()
        val maxY = board.nodes.maxOf { it.y + it.height }.toFloat()

        val boardWidth = (maxX - minX).coerceAtLeast(1f)
        val boardHeight = (maxY - minY).coerceAtLeast(1f)
        val scale = minOf(
            size.width / boardWidth,
            size.height / boardHeight,
        ) * 0.84f

        val offsetX =
            (size.width - boardWidth * scale) / 2f -
                minX * scale
        val offsetY =
            (size.height - boardHeight * scale) / 2f -
                minY * scale

        val nodes = board.nodes.associateBy { it.id }

        board.edges.forEach { edge ->
            val from = nodes[edge.fromNodeId] ?: return@forEach
            val to = nodes[edge.toNodeId] ?: return@forEach
            drawLine(
                color = androidx.compose.ui.graphics.Color(edge.color),
                start = androidx.compose.ui.geometry.Offset(
                    offsetX + (from.x + from.width / 2f) * scale,
                    offsetY + (from.y + from.height / 2f) * scale,
                ),
                end = androidx.compose.ui.geometry.Offset(
                    offsetX + (to.x + to.width / 2f) * scale,
                    offsetY + (to.y + to.height / 2f) * scale,
                ),
                strokeWidth = 2.dp.toPx(),
            )
        }

        board.nodes.take(120).forEach { node ->
            drawRoundRect(
                color = androidx.compose.ui.graphics.Color(node.color),
                topLeft = androidx.compose.ui.geometry.Offset(
                    offsetX + node.x * scale,
                    offsetY + node.y * scale,
                ),
                size = androidx.compose.ui.geometry.Size(
                    node.width * scale,
                    node.height * scale,
                ),
                cornerRadius = androidx.compose.ui.geometry.CornerRadius(
                    8.dp.toPx()
                ),
            )
        }
    }
}

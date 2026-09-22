package it.notes.ecosystem.domain

import java.util.UUID
import kotlin.math.max
import kotlin.math.min

enum class WhiteboardMode {
    FREEFORM,
    MIND_MAP,
}

enum class BoardNodeKind {
    STICKY,
    TEXT,
    NOTE_LINK,
    TASK_LINK,
    MIND_NODE,
}

enum class BoardShapeKind {
    RECTANGLE,
    ELLIPSE,
}

enum class BoardEdgeKind {
    LINE,
    ARROW,
}

enum class WhiteboardTool {
    SELECT,
    PAN,
    PEN,
    HIGHLIGHTER,
    ERASER,
    CONNECT,
    RECTANGLE,
    ELLIPSE,
}

data class BoardPoint(
    val x: Int,
    val y: Int,
    val pressure: Int = 1000,
)

data class BoardStroke(
    val id: String = UUID.randomUUID().toString(),
    val color: Int,
    val width: Int,
    val marker: Boolean,
    val points: List<BoardPoint>,
)

data class BoardNode(
    val id: String = UUID.randomUUID().toString(),
    val kind: BoardNodeKind,
    val text: String,
    val x: Int,
    val y: Int,
    val width: Int = 260,
    val height: Int = 160,
    val color: Int = 0xFFFFE7A3.toInt(),
    val linkedNoteId: String? = null,
)

data class BoardShape(
    val id: String = UUID.randomUUID().toString(),
    val kind: BoardShapeKind,
    val color: Int,
    val width: Int,
    val x1: Int,
    val y1: Int,
    val x2: Int,
    val y2: Int,
)

data class BoardEdge(
    val id: String = UUID.randomUUID().toString(),
    val fromNodeId: String,
    val toNodeId: String,
    val kind: BoardEdgeKind = BoardEdgeKind.ARROW,
    val color: Int = 0xFF52606D.toInt(),
    val width: Int = 3,
    val label: String = "",
)

data class WhiteboardCamera(
    val x: Float = 0f,
    val y: Float = 0f,
    val zoom: Float = 1f,
)

data class WhiteboardDocument(
    val mode: WhiteboardMode = WhiteboardMode.FREEFORM,
    val nodes: List<BoardNode> = emptyList(),
    val edges: List<BoardEdge> = emptyList(),
    val strokes: List<BoardStroke> = emptyList(),
    val shapes: List<BoardShape> = emptyList(),
    val camera: WhiteboardCamera = WhiteboardCamera(),
)

object WhiteboardRules {
    const val MIN_WORLD = -100_000
    const val MAX_WORLD = 100_000

    const val MAX_NODES = 800
    const val MAX_EDGES = 1_600
    const val MAX_STROKES = 1_200
    const val MAX_SHAPES = 800
    const val MAX_POINTS = 50_000

    const val MAX_TEXT_LENGTH = 8_000
    const val MIN_NODE_WIDTH = 120
    const val MAX_NODE_WIDTH = 900
    const val MIN_NODE_HEIGHT = 72
    const val MAX_NODE_HEIGHT = 700

    const val MIN_ZOOM = 0.18f
    const val MAX_ZOOM = 5f

    fun validate(
        document: WhiteboardDocument,
    ): WhiteboardDocument {
        require(document.nodes.size <= MAX_NODES) {
            "Troppi elementi nella lavagna."
        }
        require(document.edges.size <= MAX_EDGES) {
            "Troppe connessioni nella lavagna."
        }
        require(document.strokes.size <= MAX_STROKES) {
            "Troppi tratti nella lavagna."
        }
        require(document.shapes.size <= MAX_SHAPES) {
            "Troppe forme nella lavagna."
        }
        require(
            document.strokes.sumOf {
                it.points.size.toLong()
            } <= MAX_POINTS
        ) {
            "Lavagna troppo complessa: crea una nuova lavagna."
        }

        val nodeIds = HashSet<String>()
        document.nodes.forEach { node ->
            require(node.id.isNotBlank() && nodeIds.add(node.id)) {
                "Nodo duplicato o non valido."
            }
            require(node.text.length <= MAX_TEXT_LENGTH)
            require(node.x in MIN_WORLD..MAX_WORLD)
            require(node.y in MIN_WORLD..MAX_WORLD)
            require(node.width in MIN_NODE_WIDTH..MAX_NODE_WIDTH)
            require(node.height in MIN_NODE_HEIGHT..MAX_NODE_HEIGHT)
            require(
                node.linkedNoteId == null ||
                    node.linkedNoteId.isNotBlank() &&
                    node.linkedNoteId.length <= 200
            )
        }

        val edgeIds = HashSet<String>()
        document.edges.forEach { edge ->
            require(edge.id.isNotBlank() && edgeIds.add(edge.id))
            require(edge.fromNodeId in nodeIds)
            require(edge.toNodeId in nodeIds)
            require(edge.fromNodeId != edge.toNodeId)
            require(edge.width in 1..24)
            require(edge.label.length <= 1_000)
        }

        val strokeIds = HashSet<String>()
        document.strokes.forEach { stroke ->
            require(stroke.id.isNotBlank() && strokeIds.add(stroke.id))
            require(stroke.width in 1..80)
            require(stroke.points.isNotEmpty())
            stroke.points.forEach { point ->
                require(point.x in MIN_WORLD..MAX_WORLD)
                require(point.y in MIN_WORLD..MAX_WORLD)
                require(point.pressure in 0..1000)
            }
        }

        val shapeIds = HashSet<String>()
        document.shapes.forEach { shape ->
            require(shape.id.isNotBlank() && shapeIds.add(shape.id))
            require(shape.width in 1..80)
            require(shape.x1 in MIN_WORLD..MAX_WORLD)
            require(shape.x2 in MIN_WORLD..MAX_WORLD)
            require(shape.y1 in MIN_WORLD..MAX_WORLD)
            require(shape.y2 in MIN_WORLD..MAX_WORLD)
        }

        require(document.camera.x.isFinite())
        require(document.camera.y.isFinite())
        require(document.camera.zoom.isFinite())
        require(document.camera.zoom in MIN_ZOOM..MAX_ZOOM)

        return document
    }

    fun clampX(value: Int): Int =
        value.coerceIn(MIN_WORLD, MAX_WORLD)

    fun clampY(value: Int): Int =
        value.coerceIn(MIN_WORLD, MAX_WORLD)
}

object WhiteboardOps {

    fun empty(
        mode: WhiteboardMode,
    ): WhiteboardDocument {
        return if (mode == WhiteboardMode.MIND_MAP) {
            val root = BoardNode(
                kind = BoardNodeKind.MIND_NODE,
                text = "Idea principale",
                x = -140,
                y = -80,
                width = 280,
                height = 160,
                color = 0xFFDDEBFF.toInt(),
            )
            WhiteboardDocument(
                mode = mode,
                nodes = listOf(root),
            )
        } else {
            WhiteboardDocument(mode = mode)
        }
    }

    fun setMode(
        source: WhiteboardDocument,
        mode: WhiteboardMode,
    ): WhiteboardDocument {
        if (source.mode == mode) return source

        var next = source.copy(mode = mode)

        if (
            mode == WhiteboardMode.MIND_MAP &&
            next.nodes.isEmpty()
        ) {
            next = empty(mode).copy(
                camera = source.camera,
                strokes = source.strokes,
                shapes = source.shapes,
            )
        }

        return WhiteboardRules.validate(next)
    }

    fun addNode(
        source: WhiteboardDocument,
        kind: BoardNodeKind,
        text: String,
        x: Int,
        y: Int,
        color: Int = 0xFFFFE7A3.toInt(),
        linkedNoteId: String? = null,
    ): WhiteboardDocument {
        require(source.nodes.size < WhiteboardRules.MAX_NODES)

        val node = BoardNode(
            kind = kind,
            text = text.take(WhiteboardRules.MAX_TEXT_LENGTH),
            x = WhiteboardRules.clampX(x),
            y = WhiteboardRules.clampY(y),
            color = color,
            linkedNoteId = linkedNoteId,
        )

        return WhiteboardRules.validate(
            source.copy(nodes = source.nodes + node)
        )
    }

    fun updateNode(
        source: WhiteboardDocument,
        nextNode: BoardNode,
    ): WhiteboardDocument =
        WhiteboardRules.validate(
            source.copy(
                nodes = source.nodes.map {
                    if (it.id == nextNode.id) {
                        nextNode.copy(
                            x = WhiteboardRules.clampX(nextNode.x),
                            y = WhiteboardRules.clampY(nextNode.y),
                            width = nextNode.width.coerceIn(
                                WhiteboardRules.MIN_NODE_WIDTH,
                                WhiteboardRules.MAX_NODE_WIDTH,
                            ),
                            height = nextNode.height.coerceIn(
                                WhiteboardRules.MIN_NODE_HEIGHT,
                                WhiteboardRules.MAX_NODE_HEIGHT,
                            ),
                            text = nextNode.text.take(
                                WhiteboardRules.MAX_TEXT_LENGTH
                            ),
                        )
                    } else {
                        it
                    }
                }
            )
        )

    fun moveNode(
        source: WhiteboardDocument,
        id: String,
        x: Int,
        y: Int,
    ): WhiteboardDocument {
        val node = source.nodes.firstOrNull { it.id == id }
            ?: return source

        return updateNode(
            source,
            node.copy(
                x = WhiteboardRules.clampX(x),
                y = WhiteboardRules.clampY(y),
            )
        )
    }

    fun deleteNode(
        source: WhiteboardDocument,
        id: String,
    ): WhiteboardDocument =
        WhiteboardRules.validate(
            source.copy(
                nodes = source.nodes.filterNot { it.id == id },
                edges = source.edges.filterNot {
                    it.fromNodeId == id ||
                        it.toNodeId == id
                },
            )
        )

    fun connect(
        source: WhiteboardDocument,
        from: String,
        to: String,
        kind: BoardEdgeKind = BoardEdgeKind.ARROW,
    ): WhiteboardDocument {
        require(from != to)
        require(source.nodes.any { it.id == from })
        require(source.nodes.any { it.id == to })

        if (
            source.edges.any {
                it.fromNodeId == from &&
                    it.toNodeId == to
            }
        ) {
            return source
        }

        require(source.edges.size < WhiteboardRules.MAX_EDGES)

        return WhiteboardRules.validate(
            source.copy(
                edges = source.edges +
                    BoardEdge(
                        fromNodeId = from,
                        toNodeId = to,
                        kind = kind,
                    )
            )
        )
    }

    fun addStroke(
        source: WhiteboardDocument,
        stroke: BoardStroke,
    ): WhiteboardDocument =
        WhiteboardRules.validate(
            source.copy(
                strokes = source.strokes + stroke
            )
        )

    fun addShape(
        source: WhiteboardDocument,
        shape: BoardShape,
    ): WhiteboardDocument =
        WhiteboardRules.validate(
            source.copy(
                shapes = source.shapes + shape
            )
        )

    fun eraseAt(
        source: WhiteboardDocument,
        x: Int,
        y: Int,
        radius: Int = 36,
    ): WhiteboardDocument {
        val radius2 = radius.toLong() * radius

        val strokes = source.strokes.filterNot { stroke ->
            stroke.points.any { point ->
                val dx = point.x.toLong() - x
                val dy = point.y.toLong() - y
                dx * dx + dy * dy <= radius2
            }
        }

        val shapes = source.shapes.filterNot { shape ->
            val left = min(shape.x1, shape.x2) - radius
            val right = max(shape.x1, shape.x2) + radius
            val top = min(shape.y1, shape.y2) - radius
            val bottom = max(shape.y1, shape.y2) + radius
            x in left..right && y in top..bottom
        }

        return WhiteboardRules.validate(
            source.copy(
                strokes = strokes,
                shapes = shapes,
            )
        )
    }

    fun addMindChild(
        source: WhiteboardDocument,
        parentId: String,
        text: String = "Nuova idea",
    ): WhiteboardDocument {
        require(source.mode == WhiteboardMode.MIND_MAP)

        val parent = source.nodes.firstOrNull {
            it.id == parentId
        } ?: error("Nodo padre non disponibile.")

        val existingChildren = source.edges.count {
            it.fromNodeId == parentId
        }

        val child = BoardNode(
            kind = BoardNodeKind.MIND_NODE,
            text = text,
            x = WhiteboardRules.clampX(
                parent.x + parent.width + 180
            ),
            y = WhiteboardRules.clampY(
                parent.y + existingChildren * 190
            ),
            width = 260,
            height = 140,
            color = 0xFFE7F4E8.toInt(),
        )

        val withNode = source.copy(
            nodes = source.nodes + child,
        )

        return connect(
            withNode,
            parent.id,
            child.id,
            BoardEdgeKind.ARROW,
        )
    }

    fun autoLayoutMindMap(
        source: WhiteboardDocument,
    ): WhiteboardDocument {
        if (
            source.mode != WhiteboardMode.MIND_MAP ||
            source.nodes.isEmpty()
        ) {
            return source
        }

        val incoming = source.edges
            .groupBy { it.toNodeId }

        val outgoing = source.edges
            .groupBy { it.fromNodeId }

        val roots = source.nodes.filter {
            incoming[it.id].isNullOrEmpty()
        }

        val root = roots.firstOrNull()
            ?: source.nodes.first()

        val depth = mutableMapOf<String, Int>()
        val queue = ArrayDeque<String>()
        depth[root.id] = 0
        queue.add(root.id)

        while (queue.isNotEmpty()) {
            val id = queue.removeFirst()
            val d = depth.getValue(id)

            outgoing[id].orEmpty().forEach { edge ->
                if (edge.toNodeId !in depth) {
                    depth[edge.toNodeId] = d + 1
                    queue.add(edge.toNodeId)
                }
            }
        }

        /*
         * Eventuali nodi scollegati restano disponibili ma vengono messi
         * in una colonna separata dopo i livelli raggiungibili.
         */
        val maxDepth = depth.values.maxOrNull() ?: 0
        source.nodes.forEach { node ->
            if (node.id !in depth) {
                depth[node.id] = maxDepth + 1
            }
        }

        val byDepth = source.nodes.groupBy {
            depth.getValue(it.id)
        }

        val laidOut = source.nodes.map { node ->
            val d = depth.getValue(node.id)
            val column = byDepth.getValue(d)
            val index = column.indexOfFirst { it.id == node.id }
            val total = column.size

            val x = d * 430 - 140
            val y = (index - (total - 1) / 2f) * 210f - 80f

            node.copy(
                x = WhiteboardRules.clampX(x),
                y = WhiteboardRules.clampY(y.toInt()),
            )
        }

        return WhiteboardRules.validate(
            source.copy(nodes = laidOut)
        )
    }
}

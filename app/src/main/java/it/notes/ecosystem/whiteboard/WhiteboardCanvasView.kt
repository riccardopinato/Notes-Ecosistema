package it.notes.ecosystem.whiteboard

import android.content.Context
import android.graphics.*
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.View
import it.notes.ecosystem.domain.*
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

class WhiteboardCanvasView(
    context: Context,
) : View(context) {

    var onCommit: ((WhiteboardDocument) -> Unit)? = null
    var onSelection: ((String?) -> Unit)? = null

    private var working = WhiteboardDocument()
    private var tool = WhiteboardTool.SELECT
    private var inkColor = 0xFF17212B.toInt()
    private var inkWidth = 4

    private var selectedNodeId: String? = null
    private var connectFromId: String? = null

    private var gestureActive = false
    private var downScreenX = 0f
    private var downScreenY = 0f
    private var lastScreenX = 0f
    private var lastScreenY = 0f

    private var dragNodeOffsetX = 0f
    private var dragNodeOffsetY = 0f

    private val livePoints = mutableListOf<BoardPoint>()
    private val livePath = Path()
    private var shapeStart: Pair<Int, Int>? = null
    private var shapeEnd: Pair<Int, Int>? = null

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val gridPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val selectionPaint = Paint(Paint.ANTI_ALIAS_FLAG)

    private val cachedStrokePaths = HashMap<String, Path>()

    private val scaleDetector =
        ScaleGestureDetector(
            context,
            object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
                override fun onScaleBegin(detector: ScaleGestureDetector): Boolean {
                    gestureActive = true
                    return true
                }

                override fun onScale(detector: ScaleGestureDetector): Boolean {
                    val nextZoom =
                        (working.camera.zoom * detector.scaleFactor)
                            .coerceIn(
                                WhiteboardRules.MIN_ZOOM,
                                WhiteboardRules.MAX_ZOOM,
                            )

                    working = working.copy(
                        camera = working.camera.copy(
                            zoom = nextZoom
                        )
                    )
                    requestFrame()
                    return true
                }

                override fun onScaleEnd(detector: ScaleGestureDetector) {
                    gestureActive = false
                    commitCurrent()
                }
            },
        )

    fun setDocument(document: WhiteboardDocument) {
        if (gestureActive) return
        if (document == working) return
        working = document
        pruneStrokeCache()
        requestFrame()
    }

    fun setTool(value: WhiteboardTool) {
        tool = value
        if (tool != WhiteboardTool.CONNECT) {
            connectFromId = null
        }
        requestFrame()
    }

    fun setInk(
        color: Int,
        width: Int,
    ) {
        inkColor = color
        inkWidth = width.coerceIn(1, 80)
    }

    fun centerViewport() {
        val nodes = working.nodes
        if (nodes.isEmpty()) {
            working = working.copy(
                camera = WhiteboardCamera()
            )
        } else {
            val minX = nodes.minOf { it.x }
            val maxX = nodes.maxOf { it.x + it.width }
            val minY = nodes.minOf { it.y }
            val maxY = nodes.maxOf { it.y + it.height }

            working = working.copy(
                camera = working.camera.copy(
                    x = (minX + maxX) / 2f,
                    y = (minY + maxY) / 2f,
                )
            )
        }
        commitCurrent()
    }

    fun selectNode(id: String?) {
        selectedNodeId = id
        onSelection?.invoke(id)
        requestFrame()
    }

    fun deleteSelection() {
        val id = selectedNodeId ?: return
        working = WhiteboardOps.deleteNode(
            working,
            id,
        )
        selectedNodeId = null
        onSelection?.invoke(null)
        commitCurrent()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        canvas.drawColor(Color.rgb(248, 249, 251))
        drawGrid(canvas)

        canvas.save()
        applyCamera(canvas)

        drawEdges(canvas)
        drawShapes(canvas)
        drawStrokes(canvas)
        drawLiveStroke(canvas)
        drawShapePreview(canvas)
        drawNodes(canvas)

        canvas.restore()
    }

    private fun applyCamera(canvas: Canvas) {
        canvas.translate(width / 2f, height / 2f)
        canvas.scale(
            working.camera.zoom,
            working.camera.zoom,
        )
        canvas.translate(
            -working.camera.x,
            -working.camera.y,
        )
    }

    private fun drawGrid(canvas: Canvas) {
        val zoom = working.camera.zoom
        val base = 80f
        val spacing = base * zoom

        if (spacing < 18f) return

        gridPaint.color = Color.argb(35, 70, 85, 105)
        gridPaint.strokeWidth = 1f

        val worldLeft =
            working.camera.x - width / 2f / zoom
        val worldRight =
            working.camera.x + width / 2f / zoom
        val worldTop =
            working.camera.y - height / 2f / zoom
        val worldBottom =
            working.camera.y + height / 2f / zoom

        var x =
            kotlin.math.floor(worldLeft / base).toInt() * base

        while (x <= worldRight) {
            val sx =
                (x - working.camera.x) * zoom + width / 2f
            canvas.drawLine(
                sx,
                0f,
                sx,
                height.toFloat(),
                gridPaint,
            )
            x += base
        }

        var y =
            kotlin.math.floor(worldTop / base).toInt() * base

        while (y <= worldBottom) {
            val sy =
                (y - working.camera.y) * zoom + height / 2f
            canvas.drawLine(
                0f,
                sy,
                width.toFloat(),
                sy,
                gridPaint,
            )
            y += base
        }
    }

    private fun drawEdges(canvas: Canvas) {
        val nodes = working.nodes.associateBy { it.id }

        working.edges.forEach { edge ->
            val from = nodes[edge.fromNodeId] ?: return@forEach
            val to = nodes[edge.toNodeId] ?: return@forEach

            val x1 = from.x + from.width / 2f
            val y1 = from.y + from.height / 2f
            val x2 = to.x + to.width / 2f
            val y2 = to.y + to.height / 2f

            paint.style = Paint.Style.STROKE
            paint.color = edge.color
            paint.strokeWidth = edge.width.toFloat()
            paint.strokeCap = Paint.Cap.ROUND

            canvas.drawLine(x1, y1, x2, y2, paint)

            if (edge.kind == BoardEdgeKind.ARROW) {
                drawArrowHead(
                    canvas,
                    x1,
                    y1,
                    x2,
                    y2,
                    paint,
                )
            }
        }
    }

    private fun drawArrowHead(
        canvas: Canvas,
        x1: Float,
        y1: Float,
        x2: Float,
        y2: Float,
        sourcePaint: Paint,
    ) {
        val angle = atan2(y2 - y1, x2 - x1)
        val length = 22f
        val spread = 0.55f

        val ax1 =
            x2 - length * cos(angle - spread)
        val ay1 =
            y2 - length * sin(angle - spread)
        val ax2 =
            x2 - length * cos(angle + spread)
        val ay2 =
            y2 - length * sin(angle + spread)

        canvas.drawLine(x2, y2, ax1, ay1, sourcePaint)
        canvas.drawLine(x2, y2, ax2, ay2, sourcePaint)
    }

    private fun drawShapes(canvas: Canvas) {
        paint.style = Paint.Style.STROKE

        working.shapes.forEach { shape ->
            paint.color = shape.color
            paint.strokeWidth = shape.width.toFloat()

            val left = min(shape.x1, shape.x2).toFloat()
            val top = min(shape.y1, shape.y2).toFloat()
            val right = max(shape.x1, shape.x2).toFloat()
            val bottom = max(shape.y1, shape.y2).toFloat()

            when (shape.kind) {
                BoardShapeKind.RECTANGLE ->
                    canvas.drawRect(
                        left,
                        top,
                        right,
                        bottom,
                        paint,
                    )

                BoardShapeKind.ELLIPSE ->
                    canvas.drawOval(
                        left,
                        top,
                        right,
                        bottom,
                        paint,
                    )
            }
        }
    }

    private fun drawStrokes(canvas: Canvas) {
        working.strokes.forEach { stroke ->
            val path =
                cachedStrokePaths[stroke.id]
                    ?: buildPath(stroke).also {
                        cachedStrokePaths[stroke.id] = it
                    }

            paint.style = Paint.Style.STROKE
            paint.strokeCap = Paint.Cap.ROUND
            paint.strokeJoin = Paint.Join.ROUND
            paint.color = stroke.color
            paint.alpha = if (stroke.marker) 70 else 255
            paint.strokeWidth = effectiveWidth(stroke)
            canvas.drawPath(path, paint)
        }
        paint.alpha = 255
    }

    private fun buildPath(stroke: BoardStroke): Path {
        val path = Path()
        stroke.points.firstOrNull()?.let {
            path.moveTo(it.x.toFloat(), it.y.toFloat())
        }
        stroke.points.drop(1).forEach {
            path.lineTo(it.x.toFloat(), it.y.toFloat())
        }
        return path
    }

    private fun effectiveWidth(stroke: BoardStroke): Float {
        val average =
            if (stroke.points.isEmpty()) 1000f
            else stroke.points.sumOf {
                it.pressure.toLong()
            }.toFloat() / stroke.points.size

        return stroke.width * (
            0.55f + 0.45f * average / 1000f
        )
    }

    private fun drawLiveStroke(canvas: Canvas) {
        if (livePoints.isEmpty()) return

        paint.style = Paint.Style.STROKE
        paint.strokeCap = Paint.Cap.ROUND
        paint.strokeJoin = Paint.Join.ROUND
        paint.color = inkColor
        paint.alpha =
            if (tool == WhiteboardTool.HIGHLIGHTER) 70
            else 255
        paint.strokeWidth =
            if (tool == WhiteboardTool.HIGHLIGHTER) {
                max(inkWidth, 16).toFloat()
            } else {
                inkWidth.toFloat()
            }

        canvas.drawPath(livePath, paint)
        paint.alpha = 255
    }

    private fun drawShapePreview(canvas: Canvas) {
        val start = shapeStart ?: return
        val end = shapeEnd ?: return

        paint.style = Paint.Style.STROKE
        paint.color = inkColor
        paint.strokeWidth = inkWidth.toFloat()

        val left = min(start.first, end.first).toFloat()
        val top = min(start.second, end.second).toFloat()
        val right = max(start.first, end.first).toFloat()
        val bottom = max(start.second, end.second).toFloat()

        when (tool) {
            WhiteboardTool.RECTANGLE ->
                canvas.drawRect(left, top, right, bottom, paint)

            WhiteboardTool.ELLIPSE ->
                canvas.drawOval(left, top, right, bottom, paint)

            else -> Unit
        }
    }

    private fun drawNodes(canvas: Canvas) {
        working.nodes.forEach { node ->
            val rect = RectF(
                node.x.toFloat(),
                node.y.toFloat(),
                (node.x + node.width).toFloat(),
                (node.y + node.height).toFloat(),
            )

            paint.style = Paint.Style.FILL
            paint.color = node.color
            paint.alpha = 245
            canvas.drawRoundRect(rect, 22f, 22f, paint)
            paint.alpha = 255

            paint.style = Paint.Style.STROKE
            paint.strokeWidth =
                if (node.id == selectedNodeId) 5f else 1.5f
            paint.color =
                if (node.id == selectedNodeId) {
                    Color.rgb(45, 94, 190)
                } else {
                    Color.argb(100, 60, 70, 85)
                }
            canvas.drawRoundRect(rect, 22f, 22f, paint)

            textPaint.color = Color.rgb(31, 41, 55)
            textPaint.textSize =
                if (node.kind == BoardNodeKind.MIND_NODE) 28f
                else 24f
            textPaint.typeface = Typeface.create(
                Typeface.DEFAULT,
                if (node.kind == BoardNodeKind.MIND_NODE) {
                    Typeface.BOLD
                } else {
                    Typeface.NORMAL
                }
            )

            drawNodeText(
                canvas,
                node.text.ifBlank {
                    when (node.kind) {
                        BoardNodeKind.NOTE_LINK -> "Nota"
                        BoardNodeKind.TASK_LINK -> "Attività"
                        BoardNodeKind.MIND_NODE -> "Idea"
                        else -> "Testo"
                    }
                },
                node.x + 18f,
                node.y + 38f,
                node.width - 36f,
                node.height - 28f,
            )
        }
    }

    private fun drawNodeText(
        canvas: Canvas,
        text: String,
        x: Float,
        y: Float,
        maxWidth: Float,
        maxHeight: Float,
    ) {
        val words = text.replace('\n', ' ')
            .split(Regex("\\s+"))
            .filter { it.isNotBlank() }

        val lineHeight = textPaint.textSize * 1.28f
        val maxLines = max(1, (maxHeight / lineHeight).toInt())

        var current = ""
        var lineIndex = 0

        fun drawLine(value: String) {
            if (lineIndex >= maxLines) return
            canvas.drawText(
                value,
                x,
                y + lineIndex * lineHeight,
                textPaint,
            )
            lineIndex++
        }

        words.forEach { word ->
            if (lineIndex >= maxLines) return@forEach

            val candidate =
                if (current.isBlank()) word
                else "$current $word"

            if (textPaint.measureText(candidate) <= maxWidth) {
                current = candidate
            } else {
                if (current.isNotBlank()) {
                    drawLine(current)
                }
                current = word.take(80)
            }
        }

        if (
            current.isNotBlank() &&
            lineIndex < maxLines
        ) {
            drawLine(current)
        }
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        scaleDetector.onTouchEvent(event)

        if (event.pointerCount >= 2) {
            return true
        }

        val world = screenToWorld(event.x, event.y)

        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                parent?.requestDisallowInterceptTouchEvent(true)
                gestureActive = true
                downScreenX = event.x
                downScreenY = event.y
                lastScreenX = event.x
                lastScreenY = event.y

                when (tool) {
                    WhiteboardTool.SELECT -> {
                        val hit = hitNode(world.first, world.second)
                        selectNode(hit?.id)
                        hit?.let {
                            dragNodeOffsetX = world.first - it.x
                            dragNodeOffsetY = world.second - it.y
                        }
                    }

                    WhiteboardTool.PEN,
                    WhiteboardTool.HIGHLIGHTER -> {
                        livePoints.clear()
                        livePath.reset()
                        val point = boardPoint(event, world)
                        livePoints += point
                        livePath.moveTo(
                            point.x.toFloat(),
                            point.y.toFloat(),
                        )
                    }

                    WhiteboardTool.ERASER -> {
                        working = WhiteboardOps.eraseAt(
                            working,
                            world.first.toInt(),
                            world.second.toInt(),
                        )
                    }

                    WhiteboardTool.CONNECT -> {
                        val hit = hitNode(world.first, world.second)
                        if (hit != null) {
                            if (connectFromId == null) {
                                connectFromId = hit.id
                                selectNode(hit.id)
                            } else if (connectFromId != hit.id) {
                                runCatching {
                                    WhiteboardOps.connect(
                                        working,
                                        checkNotNull(connectFromId),
                                        hit.id,
                                    )
                                }.onSuccess {
                                    working = it
                                }
                                connectFromId = null
                                selectNode(hit.id)
                                commitCurrent()
                            }
                        }
                    }

                    WhiteboardTool.RECTANGLE,
                    WhiteboardTool.ELLIPSE -> {
                        shapeStart =
                            world.first.toInt() to world.second.toInt()
                        shapeEnd = shapeStart
                    }

                    WhiteboardTool.PAN -> Unit
                }

                requestFrame()
                return true
            }

            MotionEvent.ACTION_MOVE -> {
                val dxScreen = event.x - lastScreenX
                val dyScreen = event.y - lastScreenY
                lastScreenX = event.x
                lastScreenY = event.y

                when (tool) {
                    WhiteboardTool.PAN -> {
                        val zoom = working.camera.zoom
                        working = working.copy(
                            camera = working.camera.copy(
                                x = working.camera.x - dxScreen / zoom,
                                y = working.camera.y - dyScreen / zoom,
                            )
                        )
                    }

                    WhiteboardTool.SELECT -> {
                        val id = selectedNodeId
                        if (id != null) {
                            working = WhiteboardOps.moveNode(
                                working,
                                id,
                                (world.first - dragNodeOffsetX).toInt(),
                                (world.second - dragNodeOffsetY).toInt(),
                            )
                        }
                    }

                    WhiteboardTool.PEN,
                    WhiteboardTool.HIGHLIGHTER -> {
                        val point = boardPoint(event, world)
                        val last = livePoints.lastOrNull()
                        if (
                            last == null ||
                            kotlin.math.abs(last.x - point.x) +
                                kotlin.math.abs(last.y - point.y) >= 2
                        ) {
                            livePoints += point
                            livePath.lineTo(
                                point.x.toFloat(),
                                point.y.toFloat(),
                            )
                        }
                    }

                    WhiteboardTool.ERASER -> {
                        working = WhiteboardOps.eraseAt(
                            working,
                            world.first.toInt(),
                            world.second.toInt(),
                        )
                    }

                    WhiteboardTool.RECTANGLE,
                    WhiteboardTool.ELLIPSE -> {
                        shapeEnd =
                            world.first.toInt() to world.second.toInt()
                    }

                    WhiteboardTool.CONNECT -> Unit
                }

                requestFrame()
                return true
            }

            MotionEvent.ACTION_UP,
            MotionEvent.ACTION_CANCEL -> {
                when (tool) {
                    WhiteboardTool.PEN,
                    WhiteboardTool.HIGHLIGHTER -> {
                        if (livePoints.isNotEmpty()) {
                            runCatching {
                                WhiteboardOps.addStroke(
                                    working,
                                    BoardStroke(
                                        color = inkColor,
                                        width =
                                            if (tool == WhiteboardTool.HIGHLIGHTER) {
                                                max(inkWidth, 16)
                                            } else {
                                                inkWidth
                                            },
                                        marker =
                                            tool == WhiteboardTool.HIGHLIGHTER,
                                        points = livePoints.toList(),
                                    )
                                )
                            }.onSuccess {
                                working = it
                            }
                        }
                        livePoints.clear()
                        livePath.reset()
                    }

                    WhiteboardTool.RECTANGLE,
                    WhiteboardTool.ELLIPSE -> {
                        val start = shapeStart
                        val end = shapeEnd
                        if (
                            start != null &&
                            end != null &&
                            (
                                kotlin.math.abs(start.first - end.first) > 8 ||
                                    kotlin.math.abs(start.second - end.second) > 8
                            )
                        ) {
                            runCatching {
                                WhiteboardOps.addShape(
                                    working,
                                    BoardShape(
                                        kind =
                                            if (tool == WhiteboardTool.RECTANGLE) {
                                                BoardShapeKind.RECTANGLE
                                            } else {
                                                BoardShapeKind.ELLIPSE
                                            },
                                        color = inkColor,
                                        width = inkWidth,
                                        x1 = start.first,
                                        y1 = start.second,
                                        x2 = end.first,
                                        y2 = end.second,
                                    )
                                )
                            }.onSuccess {
                                working = it
                            }
                        }
                        shapeStart = null
                        shapeEnd = null
                    }

                    else -> Unit
                }

                gestureActive = false
                commitCurrent()
                requestFrame()
                return true
            }
        }

        return super.onTouchEvent(event)
    }

    private fun boardPoint(
        event: MotionEvent,
        world: Pair<Float, Float>,
    ): BoardPoint {
        val pressure =
            (event.pressure.coerceIn(0f, 1f) * 1000f)
                .toInt()
                .coerceIn(0, 1000)
                .takeIf { it > 0 }
                ?: 1000

        return BoardPoint(
            x = WhiteboardRules.clampX(world.first.toInt()),
            y = WhiteboardRules.clampY(world.second.toInt()),
            pressure = pressure,
        )
    }

    private fun screenToWorld(
        sx: Float,
        sy: Float,
    ): Pair<Float, Float> {
        val zoom = working.camera.zoom
        return (
            (sx - width / 2f) / zoom + working.camera.x
        ) to (
            (sy - height / 2f) / zoom + working.camera.y
        )
    }

    private fun hitNode(
        x: Float,
        y: Float,
    ): BoardNode? =
        working.nodes.asReversed().firstOrNull { node ->
            x >= node.x &&
                x <= node.x + node.width &&
                y >= node.y &&
                y <= node.y + node.height
        }

    private fun commitCurrent() {
        pruneStrokeCache()
        onCommit?.invoke(
            WhiteboardRules.validate(working)
        )
    }

    private fun pruneStrokeCache() {
        val ids = working.strokes.mapTo(HashSet()) { it.id }
        cachedStrokePaths.keys.retainAll(ids)
    }

    private fun requestFrame() {
        postInvalidateOnAnimation()
    }
}

package it.notes.ecosystem.sketch

import android.content.Context
import android.graphics.Canvas
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.View
import it.notes.ecosystem.domain.*
import kotlin.math.*

class SketchCanvasView(context: Context) : View(context) {
    var tool = "Penna"
    var shapeKind = SketchShapeKind.LINE
    var inkColor = 0xFF17212B.toInt()
    var inkWidth = 4
    var editable = true
    var onCommit: (SketchPage) -> Unit = {}
    var onLimit: (String) -> Unit = {}
    var onSelectionChanged: (Int) -> Unit = {}

    private var source = SketchPage()
    private var working = source
    private var basePointCount = 0
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val paperPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val guidePaint = Paint(Paint.ANTI_ALIAS_FLAG)

    private data class CachedStroke(
        val stroke: InkStroke,
        val path: Path,
        val width: Float,
    )

    private val cachedById = HashMap<String, CachedStroke>()
    private var cached = emptyList<CachedStroke>()
    private var livePressureSum = 0L
    private var livePressureCount = 0
    private var cachedPaper: SketchPaper? = null
    private val paperGuidePath = Path()

    private var points = mutableListOf<InkPoint>()
    private var activeStroke: InkStroke? = null
    private val livePath = Path()
    private var shapeStart: InkPoint? = null
    private var shapeEnd: InkPoint? = null

    private var zoom = 1f
    private var panX = 0f
    private var panY = 0f
    private var lastX = 0f
    private var lastY = 0f
    private var lastPointers = 0
    private var warned = false

    private val selected = linkedSetOf<String>()
    private var lassoStart: InkPoint? = null
    private var lassoEnd: InkPoint? = null
    private var selectionDragStart: InkPoint? = null
    private var selectionOriginal: SketchPage? = null

    private fun requestFrame() {
        postInvalidateOnAnimation()
    }

    private fun liveWidth(): Float {
        val average =
            if (livePressureCount == 0) {
                1000f
            } else {
                livePressureSum.toFloat() / livePressureCount
            }

        val base =
            if (tool == "Evidenziatore") {
                max(inkWidth, 16)
            } else {
                inkWidth
            }

        return base * (0.55f + 0.45f * (average / 1000f))
    }

    private val detector = ScaleGestureDetector(context, object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
        override fun onScale(d: ScaleGestureDetector): Boolean {
            val next = (zoom * d.scaleFactor).coerceIn(0.75f, 6f)
            val ratio = next / zoom
            panX = panX * ratio + (d.focusX - width / 2f) * (1 - ratio)
            panY = panY * ratio + (d.focusY - height / 2f) * (1 - ratio)
            zoom = next
            clampPan()
            requestFrame()
            return true
        }
    })

    init {
        contentDescription = "Pagina Sketchbook. Usa Muovi per zoom e spostamento."
        isFocusable = true
    }

    fun setPage(page: SketchPage) {
        if (page != source) {
            source = page
            working = page
            basePointCount = page.strokes.sumOf { it.points.size }
            points.clear()
            livePressureSum = 0L
            livePressureCount = 0
            activeStroke = null
            selected.retainAll(page.strokes.map { it.id }.toSet())
            rebuild()
            invalidate()
        }
    }

    fun resetViewport() {
        zoom = 1f
        panX = 0f
        panY = 0f
        invalidate()
    }

    fun clearSelection() {
        selected.clear()
        onSelectionChanged(0)
        invalidate()
    }

    fun deleteSelection() {
        if (selected.isEmpty()) return
        val next = source.copy(strokes = source.strokes.filterNot { it.id in selected })
        selected.clear()
        onSelectionChanged(0)
        onCommit(next)
    }

    private fun fit() = min(width / SketchRules.WIDTH.toFloat(), height / SketchRules.HEIGHT.toFloat()).coerceAtLeast(0.001f)

    private fun clampPan() {
        val dx = max(0f, (SketchRules.WIDTH * fit() * zoom - width) / 2)
        val dy = max(0f, (SketchRules.HEIGHT * fit() * zoom - height) / 2)
        panX = panX.coerceIn(-dx, dx)
        panY = panY.coerceIn(-dy, dy)
    }

    private fun point(x: Float, y: Float, pressure: Float = 1f): InkPoint? {
        val scale = fit() * zoom
        val px = (x - width / 2f - panX) / scale + SketchRules.WIDTH / 2f
        val py = (y - height / 2f - panY) / scale + SketchRules.HEIGHT / 2f
        return if (px in 0f..SketchRules.WIDTH.toFloat() && py in 0f..SketchRules.HEIGHT.toFloat()) {
            InkPoint(px.roundToInt(), py.roundToInt(), (pressure.coerceIn(0f, 1f) * 1000).roundToInt())
        } else null
    }

    private fun path(stroke: InkStroke) = Path().apply {
        val first = stroke.points.first()
        moveTo(first.x.toFloat(), first.y.toFloat())
        stroke.points.drop(1).forEach { lineTo(it.x.toFloat(), it.y.toFloat()) }
    }

    private fun effectiveWidth(stroke: InkStroke): Float {
        val averagePressure =
            if (stroke.points.isEmpty()) {
                1000f
            } else {
                stroke.points.sumOf { it.pressure.toLong() }.toFloat() / stroke.points.size
            }
        return stroke.width * (0.55f + 0.45f * (averagePressure / 1000f))
    }

    private fun rebuild() {
        val activeIds = working.strokes.asSequence().map { it.id }.toHashSet()
        cachedById.keys.retainAll(activeIds)
        cached = working.strokes.map { stroke ->
            val old = cachedById[stroke.id]
            if (old != null && old.stroke == stroke) {
                old
            } else {
                CachedStroke(
                    stroke = stroke,
                    path = path(stroke),
                    width = effectiveWidth(stroke),
                ).also {
                    cachedById[stroke.id] = it
                }
            }
        }
    }

    private fun drawStroke(canvas: Canvas, stroke: InkStroke, path: Path, width: Float) {
        paint.color = stroke.color
        paint.alpha = if (stroke.marker) 72 else 255
        paint.strokeWidth = width
        paint.strokeCap = Paint.Cap.ROUND
        paint.strokeJoin = Paint.Join.ROUND
        if (stroke.points.size == 1) {
            paint.style = Paint.Style.FILL
            canvas.drawCircle(stroke.points[0].x.toFloat(), stroke.points[0].y.toFloat(), width / 2f, paint)
        } else {
            paint.style = Paint.Style.STROKE
            canvas.drawPath(path, paint)
        }
    }

    private fun ensurePaperPath(paper: SketchPaper) {
        if (cachedPaper == paper) return
        cachedPaper = paper
        paperGuidePath.reset()
        when (paper) {
            SketchPaper.PLAIN -> Unit
            SketchPaper.RULED -> {
                var y = 80f
                while (y < SketchRules.HEIGHT) {
                    paperGuidePath.moveTo(0f, y)
                    paperGuidePath.lineTo(SketchRules.WIDTH.toFloat(), y)
                    y += 48f
                }
            }
            SketchPaper.GRID -> {
                var x = 40f
                while (x < SketchRules.WIDTH) {
                    paperGuidePath.moveTo(x, 0f)
                    paperGuidePath.lineTo(x, SketchRules.HEIGHT.toFloat())
                    x += 40f
                }
                var y = 40f
                while (y < SketchRules.HEIGHT) {
                    paperGuidePath.moveTo(0f, y)
                    paperGuidePath.lineTo(SketchRules.WIDTH.toFloat(), y)
                    y += 40f
                }
            }
            SketchPaper.DOTS -> {
                var x = 40f
                while (x < SketchRules.WIDTH) {
                    var y = 40f
                    while (y < SketchRules.HEIGHT) {
                        paperGuidePath.addCircle(x, y, 1.8f, Path.Direction.CW)
                        y += 40f
                    }
                    x += 40f
                }
            }
            SketchPaper.CORNELL -> {
                paperGuidePath.moveTo(220f, 0f)
                paperGuidePath.lineTo(220f, SketchRules.HEIGHT.toFloat())
                paperGuidePath.moveTo(0f, 1080f)
                paperGuidePath.lineTo(SketchRules.WIDTH.toFloat(), 1080f)
                var y = 80f
                while (y < 1080f) {
                    paperGuidePath.moveTo(220f, y)
                    paperGuidePath.lineTo(SketchRules.WIDTH.toFloat(), y)
                    y += 48f
                }
            }
        }
    }

    private fun drawPaper(canvas: Canvas, page: SketchPage) {
        paperPaint.color = 0xFFFFFDFA.toInt()
        canvas.drawRect(0f, 0f, SketchRules.WIDTH.toFloat(), SketchRules.HEIGHT.toFloat(), paperPaint)
        ensurePaperPath(page.paper)
        if (page.paper != SketchPaper.PLAIN) {
            guidePaint.color = 0x1F607D9E
            guidePaint.strokeWidth = 1f
            guidePaint.pathEffect = null
            guidePaint.style = if (page.paper == SketchPaper.DOTS) Paint.Style.FILL else Paint.Style.STROKE
            canvas.drawPath(paperGuidePath, guidePaint)
        }
    }

    private fun drawShape(canvas: Canvas, shape: SketchShape) {
        paint.color = shape.color
        paint.alpha = 255
        paint.strokeWidth = shape.width.toFloat()
        paint.style = Paint.Style.STROKE
        paint.strokeCap = Paint.Cap.ROUND
        paint.strokeJoin = Paint.Join.ROUND
        val left = min(shape.x1, shape.x2).toFloat()
        val right = max(shape.x1, shape.x2).toFloat()
        val top = min(shape.y1, shape.y2).toFloat()
        val bottom = max(shape.y1, shape.y2).toFloat()
        when (shape.kind) {
            SketchShapeKind.LINE -> canvas.drawLine(shape.x1.toFloat(), shape.y1.toFloat(), shape.x2.toFloat(), shape.y2.toFloat(), paint)
            SketchShapeKind.RECTANGLE -> canvas.drawRect(left, top, right, bottom, paint)
            SketchShapeKind.ELLIPSE -> canvas.drawOval(RectF(left, top, right, bottom), paint)
            SketchShapeKind.ARROW -> {
                canvas.drawLine(shape.x1.toFloat(), shape.y1.toFloat(), shape.x2.toFloat(), shape.y2.toFloat(), paint)
                val angle = atan2((shape.y2 - shape.y1).toDouble(), (shape.x2 - shape.x1).toDouble())
                val len = 28f + shape.width * 2f
                val a1 = angle + Math.PI * 0.82
                val a2 = angle - Math.PI * 0.82
                canvas.drawLine(shape.x2.toFloat(), shape.y2.toFloat(), shape.x2 + cos(a1).toFloat() * len, shape.y2 + sin(a1).toFloat() * len, paint)
                canvas.drawLine(shape.x2.toFloat(), shape.y2.toFloat(), shape.x2 + cos(a2).toFloat() * len, shape.y2 + sin(a2).toFloat() * len, paint)
            }
        }
    }

    private fun drawText(canvas: Canvas, item: SketchText) {
        paint.color = item.color
        paint.alpha = 255
        paint.style = Paint.Style.FILL
        paint.textSize = item.size.toFloat()
        item.text.lineSequence().take(12).forEachIndexed { index, line ->
            canvas.drawText(line.take(120), item.x.toFloat(), item.y + index * item.size * 1.25f, paint)
        }
    }

    private fun drawSelection(canvas: Canvas) {
        if (selected.isEmpty()) return
        val selectedStrokes = working.strokes.filter { it.id in selected }
        if (selectedStrokes.isEmpty()) return
        val bounds = selectedStrokes.map(SketchRules::strokeBounds)
        val left = bounds.minOf { it[0] }.toFloat()
        val top = bounds.minOf { it[1] }.toFloat()
        val right = bounds.maxOf { it[2] }.toFloat()
        val bottom = bounds.maxOf { it[3] }.toFloat()
        guidePaint.color = 0xFF3559E0.toInt()
        guidePaint.strokeWidth = 2f
        guidePaint.style = Paint.Style.STROKE
        guidePaint.pathEffect = DashPathEffect(floatArrayOf(12f, 8f), 0f)
        canvas.drawRect(left - 12, top - 12, right + 12, bottom + 12, guidePaint)
        guidePaint.pathEffect = null
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        canvas.save()
        val scale = fit() * zoom
        canvas.translate(width / 2f + panX, height / 2f + panY)
        canvas.scale(scale, scale)
        canvas.translate(-SketchRules.WIDTH / 2f, -SketchRules.HEIGHT / 2f)
        canvas.clipRect(0f, 0f, SketchRules.WIDTH.toFloat(), SketchRules.HEIGHT.toFloat())
        drawPaper(canvas, working)
        working.shapes.forEach { drawShape(canvas, it) }
        cached.forEach { item -> drawStroke(canvas, item.stroke, item.path, item.width) }
        working.texts.forEach { drawText(canvas, it) }
        activeStroke?.let {
            if (points.size == 1) {
                paint.color = it.color
                paint.alpha = if (it.marker) 72 else 255
                val w = liveWidth()
                paint.style = Paint.Style.FILL
                canvas.drawCircle(points[0].x.toFloat(), points[0].y.toFloat(), w / 2f, paint)
            } else if (points.size > 1) {
                drawStroke(canvas, it, livePath, liveWidth())
            }
        }
        if (shapeStart != null && shapeEnd != null) {
            drawShape(canvas, SketchShape(kind = shapeKind, color = inkColor, width = inkWidth, x1 = shapeStart!!.x, y1 = shapeStart!!.y, x2 = shapeEnd!!.x, y2 = shapeEnd!!.y))
        }
        drawSelection(canvas)
        canvas.restore()
    }

    override fun performClick(): Boolean { super.performClick(); return true }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (!editable) return false
        parent?.requestDisallowInterceptTouchEvent(true)

        if (tool == "Muovi") {
            detector.onTouchEvent(event)
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_UP, MotionEvent.ACTION_POINTER_DOWN -> { lastX = event.x; lastY = event.y }
                MotionEvent.ACTION_MOVE -> {
                    if (!detector.isInProgress && event.pointerCount == 1 && lastPointers == 1) {
                        panX += event.x - lastX
                        panY += event.y - lastY
                        clampPan(); requestFrame()
                    }
                    lastX = event.x; lastY = event.y
                }
                MotionEvent.ACTION_UP -> performClick()
            }
            lastPointers = event.pointerCount
            return true
        }

        if (event.pointerCount > 1) {
            points.clear(); livePressureSum = 0L; livePressureCount = 0; activeStroke = null; working = source; rebuild(); invalidate(); return true
        }

        val pressure = if (event.getToolType(0) == MotionEvent.TOOL_TYPE_STYLUS) event.getPressure(0) else 1f
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                working = source
                warned = false
                val p = point(event.x, event.y, pressure) ?: return true
                when (tool) {
                    "Gomma" -> { working = SketchRules.eraseAt(working, p.x.toFloat(), p.y.toFloat(), 18f / zoom); rebuild() }
                    "Forma" -> { shapeStart = p; shapeEnd = p }
                    "Lasso" -> {
                        lassoStart = p; lassoEnd = p
                        if (selected.isNotEmpty()) {
                            selectionDragStart = p
                            selectionOriginal = source
                        }
                    }
                    else -> {
                        if (source.strokes.size >= SketchRules.MAX_STROKES || basePointCount >= SketchRules.MAX_POINTS) {
                            onLimit("Pagina piena: crea una nuova pagina."); return true
                        }
                        points = mutableListOf(p)
                        livePressureSum = p.pressure.toLong()
                        livePressureCount = 1
                        livePath.reset(); livePath.moveTo(p.x.toFloat(), p.y.toFloat())
                        activeStroke = InkStroke(
                            color = inkColor,
                            width = if (tool == "Evidenziatore") max(inkWidth, 16) else inkWidth,
                            marker = tool == "Evidenziatore",
                            points = emptyList(),
                        )
                    }
                }
                invalidate()
            }

            MotionEvent.ACTION_MOVE -> {
                val p = point(event.x, event.y, pressure) ?: return true
                when (tool) {
                    "Gomma" -> {
                        val next = SketchRules.eraseAt(working, p.x.toFloat(), p.y.toFloat(), 18f / zoom)
                        if (next != working) { working = next; rebuild() }
                    }
                    "Forma" -> shapeEnd = p
                    "Lasso" -> {
                        lassoEnd = p
                        if (selected.isNotEmpty() && selectionDragStart != null && selectionOriginal != null) {
                            val dx = p.x - selectionDragStart!!.x
                            val dy = p.y - selectionDragStart!!.y
                            working = SketchRules.moveStrokes(selectionOriginal!!, selected, dx, dy)
                            rebuild()
                        }
                    }
                    else -> if (activeStroke != null && (points.isEmpty() || hypot((p.x - points.last().x).toFloat(), (p.y - points.last().y).toFloat()) >= 1f)) {
                        if (basePointCount + points.size < SketchRules.MAX_POINTS) {
                            points.add(p); livePressureSum += p.pressure; livePressureCount++
                            livePath.lineTo(p.x.toFloat(), p.y.toFloat())
                        } else if (!warned) {
                            warned = true; onLimit("Limite punti raggiunto: crea una nuova pagina.")
                        }
                    }
                }
                requestFrame()
            }

            MotionEvent.ACTION_UP -> {
                when (tool) {
                    "Forma" -> {
                        val a = shapeStart; val b = shapeEnd
                        if (a != null && b != null && (a.x != b.x || a.y != b.y)) {
                            working = source.copy(shapes = source.shapes + SketchShape(kind = shapeKind, color = inkColor, width = inkWidth, x1 = a.x, y1 = a.y, x2 = b.x, y2 = b.y))
                        }
                        shapeStart = null; shapeEnd = null
                    }
                    "Lasso" -> {
                        if (selected.isEmpty()) {
                            val a = lassoStart; val b = lassoEnd
                            if (a != null && b != null) {
                                val left = min(a.x, b.x); val right = max(a.x, b.x)
                                val top = min(a.y, b.y); val bottom = max(a.y, b.y)
                                selected.clear()
                                source.strokes.forEach { stroke ->
                                    val box = SketchRules.strokeBounds(stroke)
                                    if (box[0] >= left && box[2] <= right && box[1] >= top && box[3] <= bottom) selected += stroke.id
                                }
                                onSelectionChanged(selected.size)
                            }
                        }
                        lassoStart = null; lassoEnd = null; selectionDragStart = null; selectionOriginal = null
                    }
                    else -> activeStroke?.let {
                        if (points.isNotEmpty()) working = source.copy(strokes = source.strokes + it.copy(points = points.toList()))
                    }
                }
                activeStroke = null; points.clear(); livePressureSum = 0L; livePressureCount = 0
                if (working != source) onCommit(working)
                working = source; rebuild(); invalidate(); performClick()
            }

            MotionEvent.ACTION_CANCEL -> {
                activeStroke = null; points.clear(); livePressureSum = 0L; livePressureCount = 0; shapeStart = null; shapeEnd = null
                lassoStart = null; lassoEnd = null; selectionDragStart = null; selectionOriginal = null
                working = source; rebuild(); invalidate()
            }
        }
        return true
    }
}

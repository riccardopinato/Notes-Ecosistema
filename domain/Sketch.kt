package it.notes.ecosystem.domain

import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

enum class SketchPaper {
    PLAIN,
    RULED,
    GRID,
    DOTS,
    CORNELL,
}

enum class SketchShapeKind {
    LINE,
    RECTANGLE,
    ELLIPSE,
    ARROW,
}

/**
 * Pressure usa scala 0..1000 per evitare Float instabili nel JSON.
 * 1000 = pressione piena / touch senza pressure support.
 * Il costruttore resta source-compatible con InkPoint(x, y).
 */
data class InkPoint(
    val x: Int,
    val y: Int,
    val pressure: Int = 1000,
)

data class InkStroke(
    val color: Int,
    val width: Int,
    val marker: Boolean,
    val points: List<InkPoint>,
    val id: String = java.util.UUID.randomUUID().toString(),
)

data class SketchShape(
    val id: String = java.util.UUID.randomUUID().toString(),
    val kind: SketchShapeKind,
    val color: Int,
    val width: Int,
    val x1: Int,
    val y1: Int,
    val x2: Int,
    val y2: Int,
)

data class SketchText(
    val id: String = java.util.UUID.randomUUID().toString(),
    val text: String,
    val color: Int,
    val x: Int,
    val y: Int,
    val size: Int = 32,
)

/**
 * Mantiene `strokes` come primo parametro per compatibilità con il codice/test v1.
 */
data class SketchPage(
    val strokes: List<InkStroke> = emptyList(),
    val paper: SketchPaper = SketchPaper.PLAIN,
    val shapes: List<SketchShape> = emptyList(),
    val texts: List<SketchText> = emptyList(),
    val id: String = java.util.UUID.randomUUID().toString(),
)

data class SketchDocument(
    val pages: List<SketchPage> = listOf(SketchPage()),
    val activePage: Int = 0,
) {
    val page: SketchPage get() = pages.getOrElse(activePage) { pages.firstOrNull() ?: SketchPage() }
}

enum class VisualDocumentKind {
    SKETCH,
    WHITEBOARD,
}

data class SketchInfo(
    val linkedNoteId: String? = null,
    val kind: VisualDocumentKind = VisualDocumentKind.SKETCH,
)

object SketchRules {
    const val WIDTH = 1000
    const val HEIGHT = 1400
    const val MAX_POINTS = 24000
    const val MAX_STROKES = 1500
    const val MAX_SHAPES = 400
    const val MAX_TEXTS = 200
    const val MAX_PAGES = 64
    const val MAX_TEXT_LENGTH = 4000

    fun validate(page: SketchPage): SketchPage {
        require(page.strokes.size <= MAX_STROKES) { "Massimo $MAX_STROKES tratti per pagina." }
        require(page.strokes.sumOf { it.points.size.toLong() } <= MAX_POINTS) { "Pagina piena: crea una nuova pagina." }
        require(page.shapes.size <= MAX_SHAPES) { "Troppe forme nella pagina." }
        require(page.texts.size <= MAX_TEXTS) { "Troppi testi nella pagina." }

        page.strokes.forEach { s ->
            require(s.id.isNotBlank()) { "Tratto senza identificatore." }
            require(s.width in 1..80 && s.points.isNotEmpty()) { "Tratto non valido." }
            require(s.points.all {
                it.x in 0..WIDTH && it.y in 0..HEIGHT && it.pressure in 0..1000
            }) { "Punto fuori pagina." }
        }
        page.shapes.forEach { s ->
            require(s.id.isNotBlank())
            require(s.width in 1..80)
            require(s.x1 in 0..WIDTH && s.x2 in 0..WIDTH && s.y1 in 0..HEIGHT && s.y2 in 0..HEIGHT)
        }
        page.texts.forEach { t ->
            require(t.id.isNotBlank())
            require(t.text.length <= MAX_TEXT_LENGTH)
            require(t.x in 0..WIDTH && t.y in 0..HEIGHT)
            require(t.size in 12..120)
        }
        return page
    }

    fun validate(document: SketchDocument): SketchDocument {
        require(document.pages.isNotEmpty()) { "Lo sketch deve avere almeno una pagina." }
        require(document.pages.size <= MAX_PAGES) { "Massimo $MAX_PAGES pagine per sketch." }
        require(document.activePage in document.pages.indices) { "Pagina attiva non valida." }
        document.pages.forEach(::validate)
        return document
    }

    fun eraseAt(page: SketchPage, x: Float, y: Float, radius: Float): SketchPage {
        require(radius > 0 && radius.isFinite() && x.isFinite() && y.isFinite())
        fun distance(a: InkPoint, b: InkPoint): Float {
            val dx = (b.x - a.x).toFloat()
            val dy = (b.y - a.y).toFloat()
            val length = dx * dx + dy * dy
            val t = if (length == 0f) 0f else (((x - a.x) * dx + (y - a.y) * dy) / length).coerceIn(0f, 1f)
            return hypot(x - a.x - t * dx, y - a.y - t * dy)
        }
        val strokes = page.strokes.filterNot { s ->
            val hit = radius + s.width / 2f
            if (s.points.size == 1) distance(s.points[0], s.points[0]) <= hit
            else s.points.zipWithNext().any { (a, b) -> distance(a, b) <= hit }
        }
        val shapes = page.shapes.filterNot { s ->
            val left = min(s.x1, s.x2) - radius
            val right = max(s.x1, s.x2) + radius
            val top = min(s.y1, s.y2) - radius
            val bottom = max(s.y1, s.y2) + radius
            x in left..right && y in top..bottom
        }
        val texts = page.texts.filterNot { t ->
            x in (t.x - radius * 2)..(t.x + 240 + radius * 2) &&
                y in (t.y - 60 - radius)..(t.y + radius)
        }
        return page.copy(strokes = strokes, shapes = shapes, texts = texts)
    }

    fun moveStrokes(page: SketchPage, ids: Set<String>, dx: Int, dy: Int): SketchPage {
        if (ids.isEmpty() || (dx == 0 && dy == 0)) return page
        return page.copy(strokes = page.strokes.map { stroke ->
            if (stroke.id !in ids) stroke else stroke.copy(points = stroke.points.map { point ->
                point.copy(
                    x = (point.x + dx).coerceIn(0, WIDTH),
                    y = (point.y + dy).coerceIn(0, HEIGHT),
                )
            })
        })
    }

    fun strokeBounds(stroke: InkStroke): IntArray {
        val xs = stroke.points.map { it.x }
        val ys = stroke.points.map { it.y }
        return intArrayOf(xs.minOrNull() ?: 0, ys.minOrNull() ?: 0, xs.maxOrNull() ?: 0, ys.maxOrNull() ?: 0)
    }
}

package it.notes.ecosystem.data

import it.notes.ecosystem.domain.*
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener

object SketchCodec {
    const val MAX_BYTES = 1024 * 1024

    /**
     * Compatibilità helper con codice legacy: una singola pagina viene salvata come documento v2.
     */
    fun encode(page: SketchPage): String = encode(SketchDocument(listOf(page), 0))

    fun encode(document: SketchDocument): String {
        SketchRules.validate(document)
        val root = JSONObject()
            .put("format", "notes-sketch")
            .put("version", 2)
            .put("width", SketchRules.WIDTH)
            .put("height", SketchRules.HEIGHT)
            .put("activePage", document.activePage)
            .put("pages", JSONArray().apply {
                document.pages.forEach { page -> put(encodePage(page)) }
            })
        return root.toString().also {
            require(it.toByteArray(Charsets.UTF_8).size <= MAX_BYTES) { "Disegno oltre 1 MiB." }
        }
    }

    /**
     * Compatibilità API v1. Restituisce la pagina attiva.
     */
    fun decode(text: String): SketchPage = decodeDocument(text).page

    fun decodeDocument(text: String): SketchDocument {
        require(text.toByteArray(Charsets.UTF_8).size <= MAX_BYTES) { "Disegno oltre 1 MiB." }
        validateJsonDepth(text)
        val tokener = JSONTokener(text)
        val root = tokener.nextValue() as? JSONObject ?: error("Disegno non valido")
        require(tokener.nextClean() == '\u0000') { "Contenuto extra nel disegno." }
        require(root.get("format") == "notes-sketch") { "Formato disegno non supportato." }
        require(integer(root, "width") == SketchRules.WIDTH && integer(root, "height") == SketchRules.HEIGHT)
        return when (integer(root, "version")) {
            1 -> decodeV1(root)
            2 -> decodeV2(root)
            else -> error("Versione disegno non supportata.")
        }
    }

    private fun decodeV1(root: JSONObject): SketchDocument {
        val strokes = root.getJSONArray("strokes")
        require(strokes.length() <= SketchRules.MAX_STROKES)
        var count = 0
        val page = SketchPage(strokes = (0 until strokes.length()).map { i ->
            val value = strokes.getJSONObject(i)
            val points = value.getJSONArray("points")
            require(points.length() % 2 == 0)
            count += points.length() / 2
            require(count <= SketchRules.MAX_POINTS)
            InkStroke(
                color = integer(value, "color"),
                width = integer(value, "width"),
                marker = value.get("marker") as? Boolean ?: error("Marker non valido"),
                points = (0 until points.length() step 2).map {
                    InkPoint(number(points.get(it)), number(points.get(it + 1)), 1000)
                },
            )
        })
        return SketchRules.validate(SketchDocument(listOf(page), 0))
    }

    private fun decodeV2(root: JSONObject): SketchDocument {
        val pagesJson = root.getJSONArray("pages")
        require(pagesJson.length() in 1..SketchRules.MAX_PAGES)
        val pages = (0 until pagesJson.length()).map { decodePage(pagesJson.getJSONObject(it)) }
        val active = integer(root, "activePage").coerceIn(0, pages.lastIndex)
        return SketchRules.validate(SketchDocument(pages, active))
    }

    private fun encodePage(page: SketchPage): JSONObject = JSONObject()
        .put("id", page.id)
        .put("paper", page.paper.name)
        .put("strokes", JSONArray().apply {
            page.strokes.forEach { stroke ->
                put(JSONObject()
                    .put("id", stroke.id)
                    .put("color", stroke.color)
                    .put("width", stroke.width)
                    .put("marker", stroke.marker)
                    .put("points", JSONArray().apply {
                        stroke.points.forEach { p ->
                            put(p.x); put(p.y); put(p.pressure)
                        }
                    }))
            }
        })
        .put("shapes", JSONArray().apply {
            page.shapes.forEach { shape ->
                put(JSONObject()
                    .put("id", shape.id)
                    .put("kind", shape.kind.name)
                    .put("color", shape.color)
                    .put("width", shape.width)
                    .put("x1", shape.x1).put("y1", shape.y1)
                    .put("x2", shape.x2).put("y2", shape.y2))
            }
        })
        .put("texts", JSONArray().apply {
            page.texts.forEach { text ->
                put(JSONObject()
                    .put("id", text.id)
                    .put("text", text.text)
                    .put("color", text.color)
                    .put("x", text.x).put("y", text.y)
                    .put("size", text.size))
            }
        })

    private fun decodePage(value: JSONObject): SketchPage {
        val strokesJson = value.optJSONArray("strokes") ?: JSONArray()
        val shapesJson = value.optJSONArray("shapes") ?: JSONArray()
        val textsJson = value.optJSONArray("texts") ?: JSONArray()
        var pointCount = 0
        val strokes = (0 until strokesJson.length()).map { index ->
            val stroke = strokesJson.getJSONObject(index)
            val points = stroke.getJSONArray("points")
            require(points.length() % 3 == 0) { "Punti sketch v2 non validi." }
            pointCount += points.length() / 3
            require(pointCount <= SketchRules.MAX_POINTS)
            InkStroke(
                id = stroke.optString("id").takeIf { it.isNotBlank() } ?: java.util.UUID.randomUUID().toString(),
                color = integer(stroke, "color"),
                width = integer(stroke, "width"),
                marker = stroke.get("marker") as? Boolean ?: error("Marker non valido"),
                points = (0 until points.length() step 3).map { p ->
                    InkPoint(number(points.get(p)), number(points.get(p + 1)), number(points.get(p + 2)).coerceIn(0, 1000))
                },
            )
        }
        val shapes = (0 until shapesJson.length()).map { index ->
            val shape = shapesJson.getJSONObject(index)
            SketchShape(
                id = shape.optString("id").takeIf { it.isNotBlank() } ?: java.util.UUID.randomUUID().toString(),
                kind = SketchShapeKind.valueOf(shape.getString("kind")),
                color = integer(shape, "color"),
                width = integer(shape, "width"),
                x1 = integer(shape, "x1"), y1 = integer(shape, "y1"),
                x2 = integer(shape, "x2"), y2 = integer(shape, "y2"),
            )
        }
        val texts = (0 until textsJson.length()).map { index ->
            val text = textsJson.getJSONObject(index)
            SketchText(
                id = text.optString("id").takeIf { it.isNotBlank() } ?: java.util.UUID.randomUUID().toString(),
                text = text.getString("text"),
                color = integer(text, "color"),
                x = integer(text, "x"), y = integer(text, "y"),
                size = integer(text, "size"),
            )
        }
        return SketchRules.validate(SketchPage(
            id = value.optString("id").takeIf { it.isNotBlank() } ?: java.util.UUID.randomUUID().toString(),
            paper = runCatching { SketchPaper.valueOf(value.optString("paper", SketchPaper.PLAIN.name)) }.getOrDefault(SketchPaper.PLAIN),
            strokes = strokes,
            shapes = shapes,
            texts = texts,
        ))
    }

    private fun validateJsonDepth(text: String) {
        var depth = 0
        var quoted = false
        var escaped = false
        text.forEach { c ->
            if (quoted) {
                if (escaped) escaped = false
                else if (c == '\\') escaped = true
                else if (c == '"') quoted = false
            } else when (c) {
                '"' -> quoted = true
                '{', '[' -> { depth++; require(depth <= 12) { "JSON troppo annidato." } }
                '}', ']' -> { depth--; require(depth >= 0) { "JSON non valido." } }
            }
        }
        require(depth == 0 && !quoted) { "JSON non valido." }
    }

    private fun number(value: Any): Int {
        require(value is Int || value is Long)
        val n = (value as Number).toLong()
        require(n in Int.MIN_VALUE..Int.MAX_VALUE)
        return n.toInt()
    }

    private fun integer(o: JSONObject, key: String) = number(o.get(key))

    fun info(value: SketchInfo?): Any =
        value?.let {
            require(
                it.linkedNoteId == null ||
                    it.linkedNoteId.isNotBlank() &&
                    it.linkedNoteId.length <= 200
            )

            JSONObject()
                .put(
                    "linkedNoteId",
                    it.linkedNoteId ?: JSONObject.NULL,
                )
                .put("kind", it.kind.name)
        } ?: JSONObject.NULL

    fun readInfo(value: Any): SketchInfo? {
        if (value === JSONObject.NULL) return null

        val o = value as? JSONObject
            ?: error("Metadati visuali non validi")

        val linked =
            if (
                !o.has("linkedNoteId") ||
                o.get("linkedNoteId") === JSONObject.NULL
            ) {
                null
            } else {
                o.get("linkedNoteId") as? String
                    ?: error("Collegamento non valido")
            }

        val kind =
            if (!o.has("kind")) {
                VisualDocumentKind.SKETCH
            } else {
                runCatching {
                    VisualDocumentKind.valueOf(o.getString("kind"))
                }.getOrElse {
                    error("Tipo documento visuale non supportato")
                }
            }

        return SketchInfo(
            linkedNoteId = linked,
            kind = kind,
        ).also { info(it) }
    }

    fun encodeInfo(value: SketchInfo?): String? =
        value?.let { info(it).toString() }

    fun decodeInfo(value: String?): SketchInfo? =
        value?.let { readInfo(JSONObject(it)) }

}

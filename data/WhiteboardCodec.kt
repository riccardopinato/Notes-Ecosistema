package it.notes.ecosystem.data

import it.notes.ecosystem.domain.*
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener

object WhiteboardCodec {
    const val MAX_BYTES = 2 * 1024 * 1024

    fun encode(
        document: WhiteboardDocument,
    ): String {
        WhiteboardRules.validate(document)

        val root = JSONObject()
            .put("format", "notes-whiteboard")
            .put("version", 1)
            .put("mode", document.mode.name)
            .put(
                "camera",
                JSONObject()
                    .put("x", document.camera.x.toDouble())
                    .put("y", document.camera.y.toDouble())
                    .put("zoom", document.camera.zoom.toDouble())
            )
            .put(
                "nodes",
                JSONArray().apply {
                    document.nodes.forEach { node ->
                        put(
                            JSONObject()
                                .put("id", node.id)
                                .put("kind", node.kind.name)
                                .put("text", node.text)
                                .put("x", node.x)
                                .put("y", node.y)
                                .put("width", node.width)
                                .put("height", node.height)
                                .put("color", node.color)
                                .put(
                                    "linkedNoteId",
                                    node.linkedNoteId ?: JSONObject.NULL,
                                )
                        )
                    }
                }
            )
            .put(
                "edges",
                JSONArray().apply {
                    document.edges.forEach { edge ->
                        put(
                            JSONObject()
                                .put("id", edge.id)
                                .put("from", edge.fromNodeId)
                                .put("to", edge.toNodeId)
                                .put("kind", edge.kind.name)
                                .put("color", edge.color)
                                .put("width", edge.width)
                                .put("label", edge.label)
                        )
                    }
                }
            )
            .put(
                "strokes",
                JSONArray().apply {
                    document.strokes.forEach { stroke ->
                        put(
                            JSONObject()
                                .put("id", stroke.id)
                                .put("color", stroke.color)
                                .put("width", stroke.width)
                                .put("marker", stroke.marker)
                                .put(
                                    "points",
                                    JSONArray().apply {
                                        stroke.points.forEach { point ->
                                            put(point.x)
                                            put(point.y)
                                            put(point.pressure)
                                        }
                                    }
                                )
                        )
                    }
                }
            )
            .put(
                "shapes",
                JSONArray().apply {
                    document.shapes.forEach { shape ->
                        put(
                            JSONObject()
                                .put("id", shape.id)
                                .put("kind", shape.kind.name)
                                .put("color", shape.color)
                                .put("width", shape.width)
                                .put("x1", shape.x1)
                                .put("y1", shape.y1)
                                .put("x2", shape.x2)
                                .put("y2", shape.y2)
                        )
                    }
                }
            )

        return root.toString().also {
            require(
                it.toByteArray(Charsets.UTF_8).size <= MAX_BYTES
            ) {
                "Lavagna oltre 2 MiB."
            }
        }
    }

    fun decode(
        text: String,
    ): WhiteboardDocument {
        require(
            text.toByteArray(Charsets.UTF_8).size <= MAX_BYTES
        ) {
            "Lavagna oltre 2 MiB."
        }

        validateJsonDepth(text)

        val tokener = JSONTokener(text)
        val root = tokener.nextValue() as? JSONObject
            ?: error("Lavagna non valida.")

        require(tokener.nextClean() == '\u0000') {
            "Contenuto extra nella lavagna."
        }

        require(root.getString("format") == "notes-whiteboard") {
            "Formato lavagna non supportato."
        }
        require(root.getInt("version") == 1) {
            "Versione lavagna non supportata."
        }

        val cameraJson = root.optJSONObject("camera")
        val camera = WhiteboardCamera(
            x = cameraJson?.optDouble("x", 0.0)?.toFloat() ?: 0f,
            y = cameraJson?.optDouble("y", 0.0)?.toFloat() ?: 0f,
            zoom = cameraJson?.optDouble("zoom", 1.0)?.toFloat() ?: 1f,
        )

        val nodesJson = root.optJSONArray("nodes") ?: JSONArray()
        val edgesJson = root.optJSONArray("edges") ?: JSONArray()
        val strokesJson = root.optJSONArray("strokes") ?: JSONArray()
        val shapesJson = root.optJSONArray("shapes") ?: JSONArray()

        require(nodesJson.length() <= WhiteboardRules.MAX_NODES)
        require(edgesJson.length() <= WhiteboardRules.MAX_EDGES)
        require(strokesJson.length() <= WhiteboardRules.MAX_STROKES)
        require(shapesJson.length() <= WhiteboardRules.MAX_SHAPES)

        val nodes = (0 until nodesJson.length()).map { index ->
            val node = nodesJson.getJSONObject(index)
            BoardNode(
                id = node.getString("id"),
                kind = BoardNodeKind.valueOf(node.getString("kind")),
                text = node.getString("text"),
                x = node.getInt("x"),
                y = node.getInt("y"),
                width = node.optInt("width", 260),
                height = node.optInt("height", 160),
                color = node.getInt("color"),
                linkedNoteId =
                    if (
                        !node.has("linkedNoteId") ||
                        node.get("linkedNoteId") === JSONObject.NULL
                    ) {
                        null
                    } else {
                        node.getString("linkedNoteId")
                    },
            )
        }

        val edges = (0 until edgesJson.length()).map { index ->
            val edge = edgesJson.getJSONObject(index)
            BoardEdge(
                id = edge.getString("id"),
                fromNodeId = edge.getString("from"),
                toNodeId = edge.getString("to"),
                kind = BoardEdgeKind.valueOf(edge.getString("kind")),
                color = edge.getInt("color"),
                width = edge.getInt("width"),
                label = edge.optString("label", ""),
            )
        }

        var pointCount = 0
        val strokes = (0 until strokesJson.length()).map { index ->
            val stroke = strokesJson.getJSONObject(index)
            val points = stroke.getJSONArray("points")
            require(points.length() % 3 == 0)
            pointCount += points.length() / 3
            require(pointCount <= WhiteboardRules.MAX_POINTS)

            BoardStroke(
                id = stroke.getString("id"),
                color = stroke.getInt("color"),
                width = stroke.getInt("width"),
                marker = stroke.getBoolean("marker"),
                points =
                    (0 until points.length() step 3).map { p ->
                        BoardPoint(
                            x = points.getInt(p),
                            y = points.getInt(p + 1),
                            pressure = points.getInt(p + 2),
                        )
                    },
            )
        }

        val shapes = (0 until shapesJson.length()).map { index ->
            val shape = shapesJson.getJSONObject(index)
            BoardShape(
                id = shape.getString("id"),
                kind = BoardShapeKind.valueOf(shape.getString("kind")),
                color = shape.getInt("color"),
                width = shape.getInt("width"),
                x1 = shape.getInt("x1"),
                y1 = shape.getInt("y1"),
                x2 = shape.getInt("x2"),
                y2 = shape.getInt("y2"),
            )
        }

        return WhiteboardRules.validate(
            WhiteboardDocument(
                mode = WhiteboardMode.valueOf(
                    root.optString(
                        "mode",
                        WhiteboardMode.FREEFORM.name,
                    )
                ),
                nodes = nodes,
                edges = edges,
                strokes = strokes,
                shapes = shapes,
                camera = camera,
            )
        )
    }

    private fun validateJsonDepth(text: String) {
        var depth = 0
        var quoted = false
        var escaped = false

        text.forEach { c ->
            if (quoted) {
                if (escaped) {
                    escaped = false
                } else if (c == '\\') {
                    escaped = true
                } else if (c == '"') {
                    quoted = false
                }
            } else {
                when (c) {
                    '"' -> quoted = true
                    '{', '[' -> {
                        depth++
                        require(depth <= 14) {
                            "JSON troppo annidato."
                        }
                    }
                    '}', ']' -> {
                        depth--
                        require(depth >= 0) {
                            "JSON non valido."
                        }
                    }
                }
            }
        }

        require(depth == 0 && !quoted) {
            "JSON non valido."
        }
    }
}

package it.notes.ecosystem.data

import it.notes.ecosystem.domain.*
import org.junit.Assert.*
import org.junit.Test

class WhiteboardCodecTest {

    @Test
    fun roundTripPreservesDocument() {
        val root = BoardNode(
            id = "root",
            kind = BoardNodeKind.MIND_NODE,
            text = "Root",
            x = 0,
            y = 0,
        )
        val child = BoardNode(
            id = "child",
            kind = BoardNodeKind.MIND_NODE,
            text = "Child",
            x = 400,
            y = 0,
        )

        val original = WhiteboardDocument(
            mode = WhiteboardMode.MIND_MAP,
            nodes = listOf(root, child),
            edges = listOf(
                BoardEdge(
                    id = "edge",
                    fromNodeId = "root",
                    toNodeId = "child",
                )
            ),
            strokes = listOf(
                BoardStroke(
                    id = "stroke",
                    color = 1,
                    width = 4,
                    marker = false,
                    points = listOf(
                        BoardPoint(10, 20),
                        BoardPoint(30, 40, 700),
                    ),
                )
            ),
            shapes = listOf(
                BoardShape(
                    id = "shape",
                    kind = BoardShapeKind.RECTANGLE,
                    color = 2,
                    width = 3,
                    x1 = 0,
                    y1 = 0,
                    x2 = 100,
                    y2 = 120,
                )
            ),
            camera = WhiteboardCamera(
                x = 20f,
                y = 30f,
                zoom = 1.5f,
            ),
        )

        assertEquals(
            original,
            WhiteboardCodec.decode(
                WhiteboardCodec.encode(original)
            )
        )
    }

    @Test
    fun invalidEdgeIsRejected() {
        val result = runCatching {
            WhiteboardRules.validate(
                WhiteboardDocument(
                    edges = listOf(
                        BoardEdge(
                            fromNodeId = "missing-a",
                            toNodeId = "missing-b",
                        )
                    )
                )
            )
        }

        assertTrue(result.isFailure)
    }
}

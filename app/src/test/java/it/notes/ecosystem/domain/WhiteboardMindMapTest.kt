package it.notes.ecosystem.domain

import org.junit.Assert.*
import org.junit.Test

class WhiteboardMindMapTest {

    @Test
    fun mindMapStartsWithRoot() {
        val doc =
            WhiteboardOps.empty(
                WhiteboardMode.MIND_MAP
            )

        assertEquals(
            WhiteboardMode.MIND_MAP,
            doc.mode,
        )
        assertEquals(1, doc.nodes.size)
        assertEquals(
            BoardNodeKind.MIND_NODE,
            doc.nodes.single().kind,
        )
    }

    @Test
    fun childCreatesEdge() {
        val original =
            WhiteboardOps.empty(
                WhiteboardMode.MIND_MAP
            )

        val root = original.nodes.single()
        val next = WhiteboardOps.addMindChild(
            original,
            root.id,
            "Child",
        )

        assertEquals(2, next.nodes.size)
        assertEquals(1, next.edges.size)
        assertEquals(
            root.id,
            next.edges.single().fromNodeId,
        )
    }

    @Test
    fun deletingNodeDeletesEdges() {
        val original =
            WhiteboardOps.empty(
                WhiteboardMode.MIND_MAP
            )
        val root = original.nodes.single()
        val withChild =
            WhiteboardOps.addMindChild(
                original,
                root.id,
            )
        val child = withChild.nodes.last()

        val deleted = WhiteboardOps.deleteNode(
            withChild,
            child.id,
        )

        assertEquals(1, deleted.nodes.size)
        assertTrue(deleted.edges.isEmpty())
    }

    @Test
    fun autoLayoutKeepsAllNodes() {
        var doc = WhiteboardOps.empty(
            WhiteboardMode.MIND_MAP
        )
        val root = doc.nodes.single()
        doc = WhiteboardOps.addMindChild(
            doc,
            root.id,
            "A",
        )
        doc = WhiteboardOps.addMindChild(
            doc,
            root.id,
            "B",
        )

        val laidOut =
            WhiteboardOps.autoLayoutMindMap(doc)

        assertEquals(
            doc.nodes.map { it.id }.toSet(),
            laidOut.nodes.map { it.id }.toSet(),
        )
        assertEquals(doc.edges, laidOut.edges)
    }
}

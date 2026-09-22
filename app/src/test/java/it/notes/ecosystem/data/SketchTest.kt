package it.notes.ecosystem.data
import it.notes.ecosystem.domain.*
import it.notes.ecosystem.sync.*
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class SketchTest {
    private val stroke = InkStroke(0xFF3559E0.toInt(), 4, false, listOf(InkPoint(1, 2), InkPoint(100, 200)))
    private val page = SketchPage(listOf(stroke))
    private fun note() = Note("drawing", "Disegno", SketchCodec.encode(page), createdAt = 1, updatedAt = 2, sketch = SketchInfo("note"))

    @Test fun vectorRoundTrip() {
        val decoded = SketchCodec.decode(SketchCodec.encode(page))
        assertEquals(page.strokes.size, decoded.strokes.size)
        assertEquals(page.strokes.first().color, decoded.strokes.first().color)
        assertEquals(page.strokes.first().width, decoded.strokes.first().width)
        assertEquals(page.strokes.first().marker, decoded.strokes.first().marker)
        assertEquals(page.strokes.first().points, decoded.strokes.first().points)
    }

    @Test fun emptyPageIsValid() {
        val decoded = SketchCodec.decode(SketchCodec.encode(SketchPage()))
        assertTrue(decoded.strokes.isEmpty())
    }

    @Test fun markerAndColorPreserved() {
        val p = page.copy(strokes = listOf(stroke.copy(marker = true, color = -1, width = 20)))
        val decoded = SketchCodec.decode(SketchCodec.encode(p))
        assertEquals(p.strokes.size, decoded.strokes.size)
        assertEquals(-1, decoded.strokes.first().color)
        assertEquals(20, decoded.strokes.first().width)
        assertTrue(decoded.strokes.first().marker)
    }

    @Test fun multiPageDocumentRoundTrip() {
        val page1 = SketchPage(strokes = listOf(stroke), paper = SketchPaper.GRID)
        val page2 = SketchPage(
            paper = SketchPaper.RULED,
            shapes = listOf(SketchShape(kind = SketchShapeKind.RECTANGLE, color = 0xFF17212B.toInt(), width = 2, x1 = 10, y1 = 10, x2 = 100, y2 = 100)),
            texts = listOf(SketchText(text = "Appunto", color = 0xFF17212B.toInt(), x = 120, y = 180)),
        )
        val doc = SketchDocument(listOf(page1, page2), activePage = 1)
        val encoded = SketchCodec.encode(doc)
        val decoded = SketchCodec.decodeDocument(encoded)
        assertEquals(2, decoded.pages.size)
        assertEquals(1, decoded.activePage)
        assertEquals(SketchPaper.GRID, decoded.pages[0].paper)
        assertEquals(SketchPaper.RULED, decoded.pages[1].paper)
        assertEquals(1, decoded.pages[1].shapes.size)
        assertEquals(1, decoded.pages[1].texts.size)
        assertEquals("Appunto", decoded.pages[1].texts.first().text)
    }

    @Test fun legacyV1DecodesCorrectly() {
        val v1Json = JSONObject()
            .put("format", "notes-sketch")
            .put("version", 1)
            .put("width", 1000)
            .put("height", 1400)
            .put("strokes", org.json.JSONArray().put(
                JSONObject().put("color", stroke.color).put("width", stroke.width).put("marker", stroke.marker)
                    .put("points", org.json.JSONArray().put(1).put(2).put(100).put(200))
            ))
            .toString()
        val decoded = SketchCodec.decode(v1Json)
        assertEquals(1, decoded.strokes.size)
        assertEquals(stroke.color, decoded.strokes.first().color)
        assertEquals(listOf(InkPoint(1, 2, 1000), InkPoint(100, 200, 1000)), decoded.strokes.first().points)
    }

    @Test fun rejectsOffPagePoints() { rejected { SketchCodec.encode(SketchPage(listOf(stroke.copy(points = listOf(InkPoint(-1, 5)))))) } }
    @Test fun rejectsEmptyStroke() { rejected { SketchCodec.encode(SketchPage(listOf(stroke.copy(points = emptyList())))) } }
    @Test fun rejectsInvalidWidth() { rejected { SketchCodec.encode(SketchPage(listOf(stroke.copy(width = 0)))) } }
    @Test fun rejectsTooManyStrokes() { rejected { SketchCodec.encode(SketchPage(List(1501) { stroke })) } }
    @Test fun rejectsTooManyPoints() { rejected { SketchCodec.encode(SketchPage(listOf(stroke.copy(points = List(24001) { InkPoint(1, 1) })))) } }
    @Test fun eraserFindsMiddleOfLongSegment() {
        val p = SketchPage(listOf(stroke.copy(points = listOf(InkPoint(0, 0), InkPoint(1000, 0)))))
        assertTrue(SketchRules.eraseAt(p, 500f, 0f, 5f).strokes.isEmpty())
    }
    @Test fun eraserLeavesDistantStroke() { assertEquals(page, SketchRules.eraseAt(page, 900f, 1200f, 5f)) }
    @Test fun eraserHandlesSingleDot() { assertTrue(SketchRules.eraseAt(SketchPage(listOf(stroke.copy(points = listOf(InkPoint(20, 20))))), 20f, 20f, 4f).strokes.isEmpty()) }
    @Test fun backupPreservesEditableDrawing() {
        val snapshot = BackupSnapshot(listOf(note()), emptyList(), emptyList())
        assertEquals(snapshot, BackupReader.parse(BackupWriter.json(snapshot)))
    }
    @Test fun syncPreservesEditableDrawing() {
        val d = SyncDocument.from(note(), null)
        assertEquals(d, SyncCodec.decode(SyncCodec.encode(d)))
    }
    @Test fun sketchCannotAlsoBeTask() { rejected { SyncCodec.encode(SyncDocument.from(note().copy(task = TaskDetails()), null)) } }
    @Test fun jsonBodyNotSearchedAsNoteText() {
        assertTrue(filterNotes(listOf(note()), NoteFilter.ALL, "strokes").isEmpty())
        assertEquals(1, filterNotes(listOf(note()), NoteFilter.ALL, "Disegno").size)
    }
    @Test fun drawingExcludedFromChecklistIndex() { assertTrue(TaskIndex().update(listOf(note())).isEmpty()) }
    @Test fun rejectsUnknownVersion() {
        val o = JSONObject(SketchCodec.encode(page)).put("version", 99)
        rejected { SketchCodec.decode(o.toString()) }
    }
    @Test fun rejectsTrailingAndOversizedInput() {
        rejected { SketchCodec.decode(SketchCodec.encode(page) + "{}") }
        rejected { SketchCodec.decode(" ".repeat(SketchCodec.MAX_BYTES + 1)) }
    }
    @Test fun rejectsDeepNestingBeforeParser() { rejected { SketchCodec.decode("[".repeat(10000) + "]".repeat(10000)) } }
    @Test fun ordinaryV4DocumentsStillRead() {
        val d = SyncDocument.from(note().copy(sketch = null, body = "Testo"), null)
        assertEquals(d, SyncCodec.decode(SyncCodec.encode(d).replace("\"version\":6", "\"version\":4")))
    }
    @Test fun sketchDraftIsRejected() { rejected { validateBackup(BackupSnapshot(listOf(note()), emptyList(), listOf(Draft("drawing", "Draft", "Text", null, 2)))) } }
    @Test fun selfLinkIsRejected() { rejected { validateBackup(BackupSnapshot(listOf(note().copy(sketch = SketchInfo("drawing"))), emptyList(), emptyList())) } }
    private fun rejected(block: () -> Unit) { try { block(); fail("Expected rejection") } catch (_: Exception) {} }
}

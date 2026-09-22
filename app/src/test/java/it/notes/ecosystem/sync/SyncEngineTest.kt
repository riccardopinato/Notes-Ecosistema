package it.notes.ecosystem.sync

import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import java.io.IOException

class SyncEngineTest {
    private fun doc(body: String = "Testo") = SyncDocument("id-a", "Titolo", body, "Lavoro", true, 1, 2, null)
    private class Local(vararg notes: SyncDocument) : SyncLocal {
        val rows = notes.associateBy { it.id }.toMutableMap()
        var protected = false
        override suspend fun syncDocuments() = rows.toMap()
        override suspend fun syncDocument(id: String) = rows[id]
        override suspend fun applySync(id: String, expected: SyncDocument?, incoming: SyncDocument): Boolean {
            if (protected || rows[id] != expected) return false
            rows[id] = incoming; return true
        }
    }
    private class Remote(vararg notes: SyncDocument) : GitHubTransport {
        val rows = notes.associateBy { it.id }.toMutableMap()
        var writes = 0
        var loseResponse = false
        var rejectWrite = false
        var invalidRead = false
        fun sha(d: SyncDocument) = SyncCodec.hash(SyncCodec.encode(d))
        override fun head() = "fixed-head"
        override fun list(head: String) = rows.values.map { RemoteFile(SyncCodec.filename(it.id), sha(it)) }
        override fun read(file: RemoteFile, head: String): SyncDocument {
            if (invalidRead) error("Invalid remote")
            return rows.values.single { SyncCodec.filename(it.id) == file.name }
        }
        override fun write(document: SyncDocument, expectedSha: String?): String {
            if (rejectWrite || rows[document.id]?.let(::sha) != expectedSha) throw GitHubFailure(409)
            rows[document.id] = document; writes++
            if (loseResponse) { loseResponse = false; throw IOException("Response lost") }
            return sha(document)
        }
    }
    @Test fun firstConnectionUploadsAndSecondDeviceDownloads() = runBlocking {
        val note = doc(); val remote = Remote(); val local = Local(note)
        val state = mutableMapOf<String, SyncRecord>()
        SyncEngine(local, remote) {}.run(state)
        assertEquals(note, remote.rows[note.id]); assertEquals(1, remote.writes)
        val second = Local(); SyncEngine(second, remote) {}.run(mutableMapOf())
        assertEquals(note, second.rows[note.id])
    }
    @Test fun unchangedFilesDoNotGenerateCommits() = runBlocking {
        val note = doc(); val remote = Remote(note); val state = mutableMapOf(note.id to SyncRecord(note, remote.sha(note)))
        SyncEngine(Local(note), remote) {}.run(state)
        assertEquals(0, remote.writes)
    }
    @Test fun divergentEditsPreserveBothVersions() = runBlocking {
        val base = doc(); val local = doc("Locale"); val other = doc("Remoto"); val remote = Remote(other)
        val state = mutableMapOf(base.id to SyncRecord(base, "old-sha")); val store = Local(local)
        SyncEngine(store, remote) {}.run(state)
        assertTrue(state.getValue(base.id).conflict)
        assertEquals(local, store.rows[base.id]); assertEquals(other, remote.rows[base.id])
        assertEquals(local, state.getValue(base.id).local); assertEquals(other, state.getValue(base.id).remote)
    }
    @Test fun protectedEditorDoesNotAdvanceBaseOnDownload() = runBlocking {
        val base = doc(); val local = Local(base).apply { protected = true }; val remote = Remote(doc("Nuovo"))
        val state = mutableMapOf(base.id to SyncRecord(base, "old"))
        val result = SyncEngine(local, remote) {}.run(state)
        assertEquals(1, result.waiting); assertEquals(base, local.rows[base.id]); assertEquals(base, state[base.id]?.base)
    }
    @Test fun lostUploadResponseRecoversWithoutDuplicateWrite() = runBlocking {
        val note = doc(); val remote = Remote().apply { loseResponse = true }; val local = Local(note)
        val state = mutableMapOf<String, SyncRecord>()
        try { SyncEngine(local, remote) {}.run(state); fail("Expected lost response") } catch (_: IOException) {}
        assertTrue(state.isEmpty())
        SyncEngine(local, remote) {}.run(state)
        assertEquals(1, remote.writes); assertEquals(note, state[note.id]?.base)
    }
    @Test fun staleRemoteShaDoesNotAdvanceCheckpoint() = runBlocking {
        val base = doc(); val remote = Remote(base).apply { rejectWrite = true }
        val state = mutableMapOf(base.id to SyncRecord(base, remote.sha(base)))
        try { SyncEngine(Local(doc("Changed")), remote) {}.run(state); fail("Expected rejection") } catch (_: GitHubFailure) {}
        assertEquals(base, state[base.id]?.base); assertEquals(base, remote.rows[base.id])
    }
    @Test fun deletedRemoteFileBecomesDurableTombstone() = runBlocking {
        val base = doc(); val other = doc().copy(id = "other"); val remote = Remote(other)
        val state = mutableMapOf(base.id to SyncRecord(base, "old")); val local = Local(base, other)
        SyncEngine(local, remote) {}.run(state)
        assertNotNull(local.rows[base.id]?.deletedAt); assertNotNull(remote.rows[base.id]?.deletedAt)
    }
    @Test fun entirelyRemovedFolderCannotTrashAllLocalNotes() = runBlocking {
        val base = doc(); val local = Local(base); val state = mutableMapOf(base.id to SyncRecord(base, "old"))
        try { SyncEngine(local, Remote()) {}.run(state); fail("Expected safety stop") } catch (_: IllegalStateException) {}
        assertEquals(base, local.rows[base.id])
    }
    @Test fun invalidIncomingBatchDoesNotUploadLocalData() = runBlocking {
        val remote = Remote(doc().copy(id = "remote")).apply { invalidRead = true }
        try { SyncEngine(Local(doc()), remote) {}.run(mutableMapOf()); fail("Expected invalid batch") } catch (_: IllegalStateException) {}
        assertEquals(0, remote.writes)
    }
    @Test fun trashThenRestorePropagates() = runBlocking {
        val base = doc(); val remote = Remote(base); val local = Local(base.tombstone())
        val state = mutableMapOf(base.id to SyncRecord(base, remote.sha(base)))
        SyncEngine(local, remote) {}.run(state); assertNotNull(remote.rows[base.id]?.deletedAt)
        local.rows[base.id] = base.copy(updatedAt = 3)
        SyncEngine(local, remote) {}.run(state); assertNull(remote.rows[base.id]?.deletedAt)
    }
    @Test fun individuallyValidArchivesCannotMergeBeyondLimit() = runBlocking {
        val local = Local(*(0 until 15).map { doc("a".repeat(200000)).copy(id = "local-$it") }.toTypedArray())
        val remote = Remote(*(0 until 15).map { doc("b".repeat(200000)).copy(id = "remote-$it") }.toTypedArray())
        val before = local.rows.toMap(); val records = mutableMapOf<String, SyncRecord>()
        try { SyncEngine(local, remote) {}.run(records); fail("Expected combined limit") } catch (_: IllegalArgumentException) {}
        assertEquals(before, local.rows); assertEquals(0, remote.writes); assertTrue(records.isEmpty())
    }
    @Test fun sameIdsAreCountedOnceInCombinedBudget() = runBlocking {
        val docs = (0 until 15).map { doc("a".repeat(200000)).copy(id = "id-$it") }.toTypedArray()
        val remote = Remote(*docs); val local = Local(*docs)
        val result = SyncEngine(local, remote) {}.run(mutableMapOf())
        assertFalse(result.pending); assertEquals(0, remote.writes)
    }
    @Test fun releasedEditorDownloadsOnNextPass() = runBlocking {
        val base = doc(); val local = Local(base).apply { protected = true }; val remote = Remote(doc("Remoto"))
        val records = mutableMapOf(base.id to SyncRecord(base, "old"))
        assertEquals(1, SyncEngine(local, remote) {}.run(records).waiting)
        local.protected = false
        assertEquals(0, SyncEngine(local, remote) {}.run(records).waiting)
        assertEquals(remote.rows[base.id], local.rows[base.id])
    }
    @Test fun flagsUploadAndDownloadAcrossDevices() = runBlocking {
        val base=doc();val updated=base.copy(pinned=true,archived=true,updatedAt=4)
        val remote=Remote(base);val local=Local(updated)
        val state=mutableMapOf(base.id to SyncRecord(base,remote.sha(base)))
        SyncEngine(local,remote) {}.run(state)
        val second=Local(base);val secondState=mutableMapOf(base.id to SyncRecord(base,"old"))
        SyncEngine(second,remote) {}.run(secondState)
        assertEquals(updated,second.rows[base.id])
    }
    @Test fun flagsAgainstConcurrentBodyEditAreConflict() = runBlocking {
        val base=doc();val local=Local(base.copy(archived=true));val remote=Remote(base.copy(body="Nuovo"))
        val state=mutableMapOf(base.id to SyncRecord(base,"old"))
        SyncEngine(local,remote) {}.run(state)
        assertTrue(state.getValue(base.id).conflict);assertTrue(local.rows.getValue(base.id).archived)
    }
    @Test fun tagEditTravelsToSecondDevice() = runBlocking {
        val base=doc();val tagged=base.copy(tags=listOf("work"),updatedAt=4);val remote=Remote(base)
        val state=mutableMapOf(base.id to SyncRecord(base,remote.sha(base)))
        SyncEngine(Local(tagged),remote) {}.run(state)
        val second=Local();SyncEngine(second,remote) {}.run(mutableMapOf())
        assertEquals(tagged,second.rows[base.id])
    }
    @Test fun concurrentTagChangesPreserveConflictVersions() = runBlocking {
        val base=doc();val local=Local(base.copy(tags=listOf("local")));val remote=Remote(base.copy(tags=listOf("remote")))
        val state=mutableMapOf(base.id to SyncRecord(base,"old"));SyncEngine(local,remote) {}.run(state)
        val conflict=state.getValue(base.id);assertTrue(conflict.conflict)
        assertEquals(listOf("local"),conflict.local!!.tags);assertEquals(listOf("remote"),conflict.remote!!.tags)
    }

    @Test fun plannedTaskAndFocusTravelThroughEngine() = runBlocking {
        val task = doc().copy(task = it.notes.ecosystem.domain.TaskDetails(due="2026-09-15", focusSeconds=1500, focusReceipts=listOf("focus-a")))
        val remote=Remote();SyncEngine(Local(task),remote) {}.run(mutableMapOf())
        val second=Local();SyncEngine(second,remote) {}.run(mutableMapOf())
        assertEquals(task,second.rows[task.id])
    }
    @Test fun concurrentTaskDatesProduceConflictWithoutOverwrite() = runBlocking {
        val base=doc().copy(task=it.notes.ecosystem.domain.TaskDetails(due="2026-09-15"))
        val local=base.copy(task=base.task!!.copy(due="2026-09-16"));val other=base.copy(task=base.task!!.copy(due="2026-09-17"))
        val remote=Remote(other);val store=Local(local);val records=mutableMapOf(base.id to SyncRecord(base,"previous"))
        SyncEngine(store,remote) {}.run(records)
        assertTrue(records.getValue(base.id).conflict);assertEquals(local,store.rows[base.id]);assertEquals(other,remote.rows[base.id])
    }

    @Test fun sketchTransfersWithoutBinaryAttachments()=runBlocking {
        val body=it.notes.ecosystem.data.SketchCodec.encode(it.notes.ecosystem.domain.SketchPage())
        val sketch=doc(body).copy(sketch=it.notes.ecosystem.domain.SketchInfo())
        val remote=Remote();SyncEngine(Local(sketch),remote){}.run(mutableMapOf())
        val second=Local();SyncEngine(second,remote){}.run(mutableMapOf());assertEquals(sketch,second.rows[sketch.id])
    }
    @Test fun concurrentSketchEditsKeepBothSidesAsConflict()=runBlocking {
        val base=doc(it.notes.ecosystem.data.SketchCodec.encode(it.notes.ecosystem.domain.SketchPage())).copy(sketch=it.notes.ecosystem.domain.SketchInfo())
        val local=base.copy(title="Locale");val other=base.copy(title="Remoto");val remote=Remote(other);val rows=Local(local)
        val records=mutableMapOf(base.id to SyncRecord(base,"old"));SyncEngine(rows,remote){}.run(records)
        assertTrue(records.getValue(base.id).conflict);assertEquals(local,rows.rows[base.id]);assertEquals(other,remote.rows[base.id])
    }
}

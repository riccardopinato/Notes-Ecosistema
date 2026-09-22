package it.notes.ecosystem.data
import it.notes.ecosystem.domain.*
import it.notes.ecosystem.sync.*
import org.json.JSONObject
import org.junit.Test
import org.junit.Assert.*
class PlannerCodecTest {
    private val task=TaskDetails("2026-09-15",3,RepeatRule.WEEKLY,linkedNoteId="note",focusSeconds=1500,focusReceipts=listOf("s"))
    private val note=Note("task","Attività","Descrizione",createdAt=1,updatedAt=2,task=task)
    @Test fun storageRoundTrip() { assertEquals(task,TaskCodec.decode(TaskCodec.encode(task)));assertNull(TaskCodec.decode(null)) }
    @Test fun backupV4RoundTrip() { val data=BackupSnapshot(listOf(note),emptyList(),emptyList());assertEquals(data,BackupReader.parse(BackupWriter.json(data))) }
    @Test fun syncV4RoundTrip() { val d=SyncDocument.from(note,null);assertEquals(d,SyncCodec.decode(SyncCodec.encode(d))) }
    @Test fun legacyV3RemainsOrdinaryNote() { val o=JSONObject(BackupWriter.json(BackupSnapshot(listOf(note.copy(task=null)),emptyList(),emptyList()))).put("formatVersion",3);o.getJSONArray("notes").getJSONObject(0).remove("task");assertNull(BackupReader.parse(o.toString()).notes.single().task) }
    @Test fun legacySyncV3RemainsReadable() { val d=SyncDocument.from(note.copy(task=null),null);assertEquals(d,SyncCodec.decode(SyncCodec.encode(d).replace("\"version\":6","\"version\":3"))) }
    @Test fun rejectsFractionalPriority() { val o=TaskCodec.json(task) as JSONObject;o.put("priority",1.5);rejected { TaskCodec.read(o) } }
    @Test fun rejectsUnknownRecurrence() { val o=TaskCodec.json(task) as JSONObject;o.put("repeat","HOURLY");rejected { TaskCodec.read(o) } }
    @Test fun rejectsDuplicateReceipts() { rejected { TaskCodec.encode(task.copy(focusReceipts=listOf("s","s"))) } }
    @Test fun taskChangesParticipateInThreeWayConflict() { val d=SyncDocument.from(note,null);assertEquals(SyncDecision.CONFLICT,decideSync(d,d.copy(task=task.copy(priority=1)),d.copy(task=task.copy(due="2026-09-16")))) }
    @Test fun taskDraftRejected() { rejected { validateBackup(BackupSnapshot(listOf(note),emptyList(),listOf(Draft("task","T","B",null,2)))) } }
    private fun rejected(block:()->Unit) { try { block();fail("Expected rejection") } catch(_:Exception) {} }
}

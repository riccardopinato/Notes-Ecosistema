package it.notes.ecosystem.domain

import it.notes.ecosystem.data.BackupReader
import it.notes.ecosystem.data.BackupWriter
import it.notes.ecosystem.sync.SyncDocument
import it.notes.ecosystem.sync.SyncCodec
import org.junit.Test
import org.junit.Assert.*
import java.time.ZonedDateTime

class PersonalTemplatesTest {
    private val now=ZonedDateTime.parse("2026-09-16T09:05:00+02:00[Europe/Rome]")
    private fun note()=Note("source","Riunione {{data}}","- [x] Preparare\n  - [X] Materiali",createdAt=1,updatedAt=1,tags=listOf("lavoro","modello"))
    @Test fun expandsItalianDateTimeAndDay(){assertEquals("16/09/2026 09:05 mercoledì",PersonalTemplates.expand("{{data}} {{ora}} {{giorno}}",now))}
    @Test fun unknownVariablesAreLiteral(){assertEquals("{{nome}} {{DATA}}",PersonalTemplates.expand("{{nome}} {{DATA}}",now))}
    @Test fun sameInstantUsesProvidedZone(){assertEquals("07:05",PersonalTemplates.expand("{{ora}}",now.withZoneSameInstant(java.time.ZoneOffset.UTC)))}
    @Test fun resetIncludesNestedAndUppercaseChecks(){assertEquals("- [ ] Preparare\n  - [ ] Materiali",PersonalTemplates.from(note(),now,true).body)}
    @Test fun resetCanBeDisabled(){assertEquals(note().body,PersonalTemplates.from(note(),now,false).body)}
    @Test fun fencedCodeAndCrlfPreserved(){val body="- [x] Sì\r\n```\r\n- [x] Codice\r\n```";assertEquals(body.replace("[x] Sì","[ ] Sì"),PersonalTemplates.instantiate("T",body,emptyList(),now,true).body)}
    @Test fun removesOnlyModelTagFromNewNote(){assertEquals(listOf("lavoro"),PersonalTemplates.from(note(),now,true).tags)}
    @Test fun archivedModelsRemainAvailable(){assertTrue(PersonalTemplates.eligible(note().copy(archived=true)))}
    @Test fun deletedModelsExcluded(){assertTrue(PersonalTemplates.catalog(listOf(note().copy(deletedAt=2))).isEmpty())}
    @Test(expected=IllegalArgumentException::class) fun trashedSourceCannotInstantiate(){PersonalTemplates.from(note().copy(deletedAt=2),now,true)}
    @Test fun ordinaryNotesAreNotTemplates(){assertFalse(PersonalTemplates.eligible(note().copy(tags=emptyList())))}
    @Test fun searchIgnoresCase(){assertEquals(1,PersonalTemplates.catalog(listOf(note())," RIUNIONE ").size)}
    @Test fun duplicateTitlesRemainDistinct(){val a=note();assertEquals(listOf("a","b"),PersonalTemplates.catalog(listOf(a.copy(id="b"),a.copy(id="a"))).map {it.id})}
    @Test fun capturePreservesVariablesAndChecks(){val n=note();val result=PersonalTemplates.capture(n.title,n.body,n.tags);assertEquals(n.title,result.title);assertEquals(n.body,result.body)}
    @Test(expected=IllegalArgumentException::class) fun emptyCaptureRejected(){PersonalTemplates.capture(" "," ",emptyList())}
    @Test fun bodyOnlyGetsDefaultTitle(){assertEquals("Modello personale",PersonalTemplates.capture("","Appunti",emptyList()).title)}
    @Test(expected=IllegalArgumentException::class) fun doesNotDropTwentiethTagSilently(){PersonalTemplates.capture("T","B",(1..20).map {"tag$it"})}
    @Test fun alreadyModelCanKeepTwentyTags(){assertEquals(20,PersonalTemplates.capture("T","B",(1..19).map {"tag$it"}+"modello").tags.size)}
    @Test(expected=IllegalArgumentException::class) fun expandedTitleOverLimitRejected(){PersonalTemplates.instantiate("{{giorno}}".repeat(1100),"",emptyList(),now,true)}
    @Test(expected=IllegalArgumentException::class) fun oversizedBodyRejected(){PersonalTemplates.instantiate("T","a".repeat(200001),emptyList(),now,true)}
    @Test fun attachmentAndNoteLinksPreserved(){val key="a".repeat(64)+".pdf";val body="[PDF](notes-asset://$key) [Nota](notes://note/00000000-0000-0000-0000-000000000001)";assertEquals(body,PersonalTemplates.instantiate("T",body,emptyList(),now,true).body)}
    @Test fun creationDoesNotMutateSource(){val source=note();PersonalTemplates.from(source,now,true);assertEquals("- [x] Preparare\n  - [X] Materiali",source.body);assertTrue("modello" in source.tags)}
    @Test fun backupKeepsTemplateEligibilityAndVariables(){val snapshot=BackupSnapshot(listOf(note().copy(archived=true)),emptyList(),emptyList());val read=BackupReader.read(BackupWriter.json(snapshot).toByteArray().inputStream());assertEquals(snapshot,read);assertTrue(PersonalTemplates.eligible(read.notes.single()))}
    @Test fun syncPreservesTemplates(){val source=SyncDocument.from(note().copy(archived=true),null);assertEquals(source,SyncCodec.decode(SyncCodec.encode(source)))}
}

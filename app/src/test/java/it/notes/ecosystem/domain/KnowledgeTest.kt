package it.notes.ecosystem.domain
import it.notes.ecosystem.data.BackupReader
import it.notes.ecosystem.data.BackupWriter
import it.notes.ecosystem.sync.*
import java.time.LocalDate
import org.junit.Test
import org.junit.Assert.*

class KnowledgeTest {
    private val a="11111111-1111-4111-8111-111111111111"
    private val b="22222222-2222-4222-8222-222222222222"
    private fun link(id:String=a,label:String="Nota")=Knowledge.insert("",0,0,id,label).text
    @Test fun insertsAtSelection() {val e=Knowledge.insert("prima DOPO",6,10,a,"Nota");assertEquals("prima "+link(),e.text);assertEquals(e.text.length,e.start)}
    @Test fun reversedSelection() {assertEquals(link(),Knowledge.insert("abc",3,0,a,"Nota").text)}
    @Test fun safeLabels() {assertEquals("a[b]\\x",Knowledge.links(link(label="a[b]\\x")).single().label)}
    @Test fun multilineLabelBecomesSingleLine() {assertFalse(link(label="a\nb\rc").contains('\n'))}
    @Test fun requiresExactLocalUri() {assertEquals(a,Knowledge.targetId(Knowledge.url(a)));assertNull(Knowledge.targetId(Knowledge.url(a)+"?x=1"));assertNull(Knowledge.targetId("https://example.com"))}
    @Test(expected=IllegalArgumentException::class) fun invalidIdRejected() {Knowledge.url("../something")}
    @Test fun detectsDuplicatesAndOffsets() {val text="a "+link()+"\n"+link();val refs=Knowledge.links(text);assertEquals(2,refs.size);assertEquals(2,refs[0].start);assertEquals(link(),text.substring(refs[0].start,refs[0].end))}
    @Test fun ignoresFencedCode() {assertTrue(Knowledge.links("```md\n"+link()+"\n```\n~~~\n"+link()+"\n~~~").isEmpty())}
    @Test fun shorterFenceDoesNotClose() {assertTrue(Knowledge.links("````\n```\n"+link()+"\n````").isEmpty())}
    @Test fun ignoresIndentedCode() {assertTrue(Knowledge.links("    "+link()+"\n\t"+link()).isEmpty())}
    @Test fun ignoresInlineCode() {assertEquals(1,Knowledge.links("`"+link()+"` "+link()).size)}
    @Test fun ignoresImageAndEscapedLink() {assertTrue(Knowledge.links("!"+link()+" \\"+link()).isEmpty())}
    @Test fun remapsOnlyActualLinks() {val text=link()+" `"+link()+"`";assertEquals(link(b)+" `"+link()+"`",Knowledge.remap(text,mapOf(a to b)))}
    @Test fun missingTargetRemainsUnchanged() {assertEquals(link(),Knowledge.remap(link(),emptyMap()))}
    @Test fun headingsIgnoreCodeAndKeepCrLfOffsets() {val text="# Uno\r\n```\r\n# Falso\r\n```\r\n## Due ##";val h=Knowledge.headings(text);assertEquals(listOf("Uno","Due"),h.map {it.title});assertEquals(text.indexOf("## Due"),h[1].offset)}
    @Test fun requiresHeadingWhitespace() {assertTrue(Knowledge.headings("#hashtag\n####### no").isEmpty())}
    @Test fun literalSearchDoesNotTreatRegexAsCode() {assertEquals(listOf(2..3),LiteralSearch.ranges("x .* y",".*"))}
    @Test fun ignoresCaseByDefault() {assertEquals(2,LiteralSearch.ranges("Ab aB","ab").size);assertEquals(0,LiteralSearch.ranges("Ab aB","ab",false).size)}
    @Test fun emptyQueryNeverMatches() {assertTrue(LiteralSearch.ranges("abc","").isEmpty())}
    @Test fun nonOverlappingMatches() {assertEquals(listOf(0..1),LiteralSearch.ranges("aaa","aa"))}
    @Test fun literalReplacementKeepsDollarAndSlash() {assertEquals("$1\\ $1\\",LiteralSearch.replaceAll("a a","a","$1\\").text)}
    @Test(expected=IllegalArgumentException::class) fun replacementBudgetIsChecked() {LiteralSearch.replaceAll("a".repeat(1000),"a","x".repeat(1000))}
    @Test fun dailyIdentityStableAndDateSpecific() {val day=LocalDate.of(2026,9,16);assertEquals(PageTemplates.dailyId(day),PageTemplates.dailyId(day));assertNotEquals(PageTemplates.dailyId(day),PageTemplates.dailyId(day.plusDays(1)))}
    @Test fun allTemplatesHaveUniqueKeysAndContent() {assertEquals(4,PageTemplates.all.map {it.key}.toSet().size);assertTrue(PageTemplates.all.all {it.body.isNotBlank()})}
    @Test fun linksSurviveBackup() {val note=Note(a,"Nota",link(b),createdAt=1,updatedAt=2);val data=BackupSnapshot(listOf(note),emptyList(),emptyList());assertEquals(data,BackupReader.parse(BackupWriter.json(data)))}
    @Test fun linksSurviveGitHubCodec() {val doc=SyncDocument.from(Note(a,"Nota",link(b),createdAt=1,updatedAt=2),null);assertEquals(doc,SyncCodec.decode(SyncCodec.encode(doc)))}
    @Test fun longEscapedLabelStillParses() {assertEquals(300,Knowledge.links(link(label="[".repeat(400))).single().label.length)}
}

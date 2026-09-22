package it.notes.ecosystem.domain
import org.junit.Assert.*
import org.junit.Test
class TagsTest {
    @Test fun namesAreCanonicalAndStable() { assertEquals(listOf("caffè","lavoro"), Tags.normalize(listOf(" #Lavoro ","CAFFE\u0300","lavoro"))) }
    @Test fun canonicalNameIsIdempotent() { assertEquals("studio",Tags.name(Tags.name("#Studio"))) }
    @Test fun duplicateAtLimitDoesNotFail() { val all=(1..20).map { "tag$it" };assertEquals(20,Tags.add(all,"tag1").size) }
    @Test fun newTagAtLimitIsRejected() { rejected { Tags.add((1..20).map { "t$it" },"new") } }
    @Test fun spacesAndPunctuationAreRejected() { for (s in listOf("", "two words", "a,b", "a/b", "a\nb", "#")) rejected { Tags.name(s) } }
    @Test fun longNamesRejected() { rejected { Tags.name("a".repeat(41)) } }
    @Test fun hyphensAndUnderscoresSupported() { assertEquals("work_2026-app",Tags.name("Work_2026-App")) }
    private fun rejected(block: () -> Unit) { try { block();fail("Expected rejection") } catch (_: IllegalArgumentException) {} }
}

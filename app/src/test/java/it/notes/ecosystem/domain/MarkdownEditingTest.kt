package it.notes.ecosystem.domain
import org.junit.Assert.*
import org.junit.Test
class MarkdownEditingTest {
    @Test fun boldUsesSelectedRange() { assertEquals(MarkdownEdit("a **word** z",4,8), MarkdownEditing.apply("a word z",2,6,MarkdownAction.BOLD)) }
    @Test fun reversedSelectionWorks() { assertEquals("**hello**", MarkdownEditing.apply("hello",5,0,MarkdownAction.BOLD).text) }
    @Test fun emptySelectionSelectsPlaceholder() { assertEquals(MarkdownEdit("*testo*",1,6),MarkdownEditing.apply("",0,0,MarkdownAction.ITALIC)) }
    @Test fun prefixPreservesCrLf() { assertEquals("> a\r\n> b",MarkdownEditing.apply("a\r\nb",0,4,MarkdownAction.QUOTE).text) }
    @Test fun selectionEndingAtNextLineDoesNotPrefixNextLine() { assertEquals("- a\nb",MarkdownEditing.apply("a\nb",0,2,MarkdownAction.BULLET).text) }
    @Test fun numberedMultiline() { assertEquals("1. a\n2. b",MarkdownEditing.apply("a\nb",0,3,MarkdownAction.NUMBERED).text) }
    @Test fun codeBlockCannotBeClosedBySelectedFence() { assertTrue(MarkdownEditing.apply("```",0,3,MarkdownAction.CODE_BLOCK).text.startsWith("````\n")) }
    @Test fun inlineCodeEscapesBackticks() { assertEquals("`` `x` ``",MarkdownEditing.apply("`x`",0,3,MarkdownAction.CODE).text) }
    @Test fun linkEscapesLabelAndParentheses() { assertEquals("[a\\]b](<https://example.org/a(b)>)",MarkdownEditing.link("old",0,3,"a]b","https://example.org/a(b)").text) }
    @Test fun dangerousLinkRejected() { try { MarkdownEditing.link("",0,0,"x","javascript:alert(1)");fail() } catch (_:IllegalArgumentException) {} }
    @Test fun invalidSelectionClamped() { assertEquals("**text**",MarkdownEditing.apply("text",-5,99,MarkdownAction.BOLD).text) }
    @Test fun codeDoesNotAcceptMultipleLines() { try { MarkdownEditing.apply("a\nb",0,3,MarkdownAction.CODE);fail() } catch (_:IllegalArgumentException) {} }
}

package it.notes.ecosystem.domain

import java.time.LocalDate
import java.time.YearMonth

/** A reserved ordinary tag transports the calendar date through existing backups and sync.
 * The calendar date is deliberately independent of creation/update timestamps and time zones. */
object Diary {
    private const val PREFIX = "diario_"
    fun validDate(value: String): LocalDate {
        require(Regex("[0-9]{4}-[0-9]{2}-[0-9]{2}").matches(value)) { "Usa una data AAAA-MM-GG." }
        return LocalDate.parse(value).also { require(it.year in 1900..2200) { "Scegli un anno tra 1900 e 2200." } }
    }
    fun tagDate(tag: String): LocalDate? = if (!tag.startsWith(PREFIX)) null else runCatching {validDate(tag.removePrefix(PREFIX))}.getOrNull()
    fun date(tags: List<String>): LocalDate? = tags.mapNotNull(::tagDate).distinct().singleOrNull()
    fun datedTags(tags: List<String>, date: LocalDate?): List<String> {
        date?.let {validDate(it.toString())}
        return Tags.normalize(tags.filter {tagDate(it)==null} + listOfNotNull(date?.let {PREFIX+it}))
    }
    fun userTags(tags: List<String>) = tags.filter {tagDate(it)==null}
    fun noteDate(note: Note): LocalDate? = if(note.deletedAt!=null || note.task!=null || note.sketch!=null || PersonalTemplates.TAG in note.tags) null else date(note.tags)
    fun monthCells(month: YearMonth): List<LocalDate?> {
        require(month.year in 1900..2200)
        val offset=month.atDay(1).dayOfWeek.value-1
        val size=((offset+month.lengthOfMonth()+6)/7)*7
        return List(size) {index->(index-offset+1).takeIf {it in 1..month.lengthOfMonth()}?.let(month::atDay)}
    }
    fun index(notes: List<Note>, bookId: String? = null): DiaryIndex {
        val entries=notes.mapNotNull {note->
            val date=noteDate(note) ?: return@mapNotNull null
            if(bookId!=null && note.collectionId!=bookId)return@mapNotNull null
            DiaryEntry(note,date,Attachments.refs(note.body).filter {it.type in listOf(AttachmentType.JPEG,AttachmentType.PNG,AttachmentType.WEBP)})
        }.sortedWith(compareByDescending<DiaryEntry>{it.date}.thenByDescending {it.note.createdAt}.thenBy {it.note.id})
        val tasks=notes.filter {it.deletedAt==null && !it.archived && it.task?.due!=null}.groupBy {LocalDate.parse(it.task!!.due)}
        return DiaryIndex(entries,entries.groupBy {it.date},tasks)
    }
}
data class DiaryEntry(val note: Note,val date: LocalDate,val photos: List<AttachmentRef>)
data class DiaryIndex(val entries: List<DiaryEntry>,val days: Map<LocalDate,List<DiaryEntry>>,val tasks: Map<LocalDate,List<Note>>)

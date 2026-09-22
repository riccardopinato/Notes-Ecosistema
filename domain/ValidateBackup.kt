package it.notes.ecosystem.domain

import it.notes.ecosystem.data.SketchCodec
import it.notes.ecosystem.data.WhiteboardCodec

fun validateBackup(data: BackupSnapshot) {
    require(data.notes.size <= 10000 && data.collections.size <= 10000 && data.drafts.size <= 10000) { "Troppi elementi nel backup." }
    fun ids(values: List<String>): Set<String> {
        require(values.all { it.isNotBlank() && it.length <= 200 }) { "Identificativo non valido." }
        require(values.size == values.toSet().size) { "Identificativi duplicati nel backup." }
        return values.toSet()
    }
    ids(data.notes.map { it.id })
    val collectionIds = ids(data.collections.map { it.id })
    ids(data.drafts.map { it.id })
    fun checkCollection(id: String?) {
        require(id == null || id in collectionIds) { "Il backup fa riferimento a una raccolta mancante." }
    }
    data.collections.forEach { require(it.name.isNotBlank()) { "Nome raccolta vuoto." } }
    data.notes.forEach {
        checkCollection(it.collectionId)
        Tags.normalize(it.tags)
        require(it.task == null || it.sketch == null)
        it.sketch?.let { info ->
            require(info.linkedNoteId != it.id) { "Il disegno non può collegare se stesso." }
            require(data.notes.none { n -> n.id==info.linkedNoteId && (n.task!=null || n.sketch!=null) }) { "Collega il disegno a una nota di testo." }
            SketchCodec.info(info)
            when (info.kind) {
                VisualDocumentKind.SKETCH -> SketchCodec.decodeDocument(it.body)
                VisualDocumentKind.WHITEBOARD -> WhiteboardCodec.decode(it.body)
            }
        }
        it.task?.let { task ->
            validateTask(task)
            require(task.linkedNoteId != it.id) { "Un’attività non può collegare se stessa." }
            require(data.notes.none { n -> n.id == task.linkedNoteId && n.task != null }) { "Il collegamento deve riferirsi a una nota." }
        }
        require(it.createdAt >= 0 && it.updatedAt >= 0 && (it.deletedAt == null || it.deletedAt >= 0)) { "Data nota non valida." }
    }
    val deleted = data.notes.filter { it.deletedAt != null }.map { it.id }.toSet()
    data.drafts.forEach {
        checkCollection(it.collectionId)
        Tags.normalize(it.tags)
        require(it.updatedAt >= 0) { "Data bozza non valida." }
        require(data.notes.none { n -> n.id == it.id && (n.task != null || n.sketch != null) }) { "Bozza associata a un’attività autonoma." }
        require(it.id !in deleted) { "Bozza associata a una nota nel cestino." }
    }
}

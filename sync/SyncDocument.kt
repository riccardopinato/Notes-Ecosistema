package it.notes.ecosystem.sync

import it.notes.ecosystem.domain.Note
import org.json.JSONObject
import it.notes.ecosystem.data.SketchCodec
import it.notes.ecosystem.data.WhiteboardCodec
import it.notes.ecosystem.domain.VisualDocumentKind
import java.security.MessageDigest

/** Collection names travel with notes; empty collections and drafts remain local. */
data class SyncDocument(val id: String, val title: String, val body: String,
    val collection: String?, val favorite: Boolean, val createdAt: Long,
    val updatedAt: Long, val deletedAt: Long?, val pinned: Boolean = false, val archived: Boolean = false, val tags: List<String> = emptyList(), val task: it.notes.ecosystem.domain.TaskDetails? = null, val sketch: it.notes.ecosystem.domain.SketchInfo? = null) {
    fun tombstone() = copy(deletedAt = deletedAt ?: updatedAt, body = body)
    companion object {
        fun from(note: Note, collection: String?) = SyncDocument(note.id, note.title, note.body,
            collection, note.favorite, note.createdAt, note.updatedAt, note.deletedAt, note.pinned, note.archived, note.tags, note.task, note.sketch)
    }
}

object SyncCodec {
    const val MAX_BYTES = 256 * 1024
    fun hash(value: String): String = MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
    fun filename(id: String) = hash(id) + ".md"
    fun encode(n: SyncDocument): String {
        require(n.task == null || n.sketch == null)
        when (n.sketch?.kind) {
            VisualDocumentKind.SKETCH -> SketchCodec.decodeDocument(n.body)
            VisualDocumentKind.WHITEBOARD -> WhiteboardCodec.decode(n.body)
            null -> Unit
        }
        require(n.id.isNotBlank() && n.id.length <= 200 && n.title.length <= 8000) { "ID o titolo oltre i limiti della sincronizzazione." }
        require(n.collection == null || (n.collection.isNotBlank() && n.collection.length <= 200)) { "Nome raccolta oltre i limiti della sincronizzazione." }
        require(n.createdAt >= 0 && n.updatedAt >= 0 && (n.deletedAt == null || n.deletedAt >= 0))
        val meta = JSONObject().put("format", "notes-ecosystem-sync").put("version", 6)
            .put("id", n.id).put("title", n.title).put("collection", n.collection ?: JSONObject.NULL)
            .put("tags", it.notes.ecosystem.data.TagCodec.array(n.tags))
            .put("task", it.notes.ecosystem.data.TaskCodec.json(n.task))
            .put("sketch", it.notes.ecosystem.data.SketchCodec.info(n.sketch))
            .put("pinned", n.pinned).put("archived", n.archived)
            .put("favorite", n.favorite).put("createdAt", n.createdAt).put("updatedAt", n.updatedAt)
            .put("deletedAt", n.deletedAt ?: JSONObject.NULL)
        // One metadata line; the remaining bytes are the exact editable Markdown body.
        val header = "<!-- notes-ecosystem " + meta.toString().replace("--", "\\u002d\\u002d") + " -->"
        require(header.length <= 32768) { "Metadati troppo grandi per la sincronizzazione." }
        return header + "\n" + n.body
    }
    fun decode(text: String): SyncDocument {
        require(text.toByteArray(Charsets.UTF_8).size <= MAX_BYTES) { "Nota GitHub oltre 256 KB." }
        val end = text.indexOf('\n')
        require(end in 1..32768) { "Metadati Markdown mancanti o troppo grandi." }
        val header = text.substring(0, end).removeSuffix("\r")
        require(header.startsWith("<!-- notes-ecosystem ") && header.endsWith(" -->")) { "Formato Markdown non riconosciuto." }
        val m = JSONObject(header.removePrefix("<!-- notes-ecosystem ").removeSuffix(" -->"))
        val version = m.get("version")
        require(m.get("format") == "notes-ecosystem-sync" && (version == 1 || version == 2 || version == 3 || version == 4 || version == 5 || version == 6)) { "Versione sync non supportata." }
        fun str(key: String) = (m.get(key) as? String) ?: error("Metadato non valido: $key")
        fun number(key: String): Long {
            val v = m.get(key)
            require(v is Int || v is Long) { "Data non valida." }
            return (v as Number).toLong().also { require(it >= 0) { "Data negativa." } }
        }
        val id = str("id"); require(id.isNotBlank() && id.length <= 200)
        val collection = if (m.isNull("collection")) null else str("collection").also { require(it.isNotBlank() && it.length <= 200) }
        return SyncDocument(id, str("title"), text.substring(end + 1), collection,
            m.get("favorite") as? Boolean ?: error("Preferito non valido."), number("createdAt"), number("updatedAt"),
            if (m.isNull("deletedAt")) null else number("deletedAt"),
            if (version != 1) m.get("pinned") as? Boolean ?: error("Fissata non valida.") else false,
            if (version != 1) m.get("archived") as? Boolean ?: error("Archivio non valido.") else false,
            if (version != 1 && version != 2) it.notes.ecosystem.data.TagCodec.read(m.getJSONArray("tags")) else emptyList(),
            if (version == 4 || version == 5 || version == 6) it.notes.ecosystem.data.TaskCodec.read(m.get("task")) else null,
            if (version == 5 || version == 6) it.notes.ecosystem.data.SketchCodec.readInfo(m.get("sketch")) else null).also {
                require(it.task == null || it.sketch == null)
                when (it.sketch?.kind) {
                    VisualDocumentKind.SKETCH -> SketchCodec.decodeDocument(it.body)
                    VisualDocumentKind.WHITEBOARD -> WhiteboardCodec.decode(it.body)
                    null -> Unit
                }
            }
    }
}

enum class SyncDecision { SAME, UPLOAD, DOWNLOAD, CONFLICT }
fun decideSync(base: SyncDocument?, local: SyncDocument?, remote: SyncDocument?): SyncDecision = when {
    local == remote -> SyncDecision.SAME
    local == base -> SyncDecision.DOWNLOAD
    remote == base -> SyncDecision.UPLOAD
    else -> SyncDecision.CONFLICT
}

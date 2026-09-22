package it.notes.ecosystem.data

import it.notes.ecosystem.domain.*
import org.json.JSONArray
import org.json.JSONObject
import java.io.OutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

object BackupWriter {
    fun json(snapshot: BackupSnapshot): String = JSONObject().apply {
        put("format", "notes-ecosystem")
        put("formatVersion", 6)
        put("exportedAt", System.currentTimeMillis())
        put("notes", JSONArray().apply { snapshot.notes.forEach { n ->
            put(JSONObject().apply {
                put("id", n.id); put("title", n.title); put("body", n.body)
                put("collectionId", n.collectionId ?: JSONObject.NULL)
                put("tags", TagCodec.array(n.tags)); put("task", TaskCodec.json(n.task)); put("sketch", SketchCodec.info(n.sketch))
                put("pinned", n.pinned); put("archived", n.archived)
                put("favorite", n.favorite); put("createdAt", n.createdAt)
                put("updatedAt", n.updatedAt); put("deletedAt", n.deletedAt ?: JSONObject.NULL)
            })
        } })
        put("collections", JSONArray().apply { snapshot.collections.forEach {
            put(JSONObject().put("id", it.id).put("name", it.name))
        } })
        put("drafts", JSONArray().apply { snapshot.drafts.forEach {
            put(JSONObject().put("id", it.id).put("title", it.title).put("body", it.body)
                .put("collectionId", it.collectionId ?: JSONObject.NULL).put("updatedAt", it.updatedAt).put("tags", TagCodec.array(it.tags)))
        } })
    }.toString(2)

    fun write(snapshot: BackupSnapshot, output: OutputStream, markdownZip: Boolean) {
        if (!markdownZip) {
            output.write(json(snapshot).toByteArray(Charsets.UTF_8))
            output.flush()
            return
        }
        ZipOutputStream(output).use { zip ->
            fun entry(name: String, content: String) {
                zip.putNextEntry(ZipEntry(name))
                zip.write(content.toByteArray(Charsets.UTF_8))
                zip.closeEntry()
            }
            entry("backup.json", json(snapshot))
            snapshot.notes.filter { it.deletedAt == null }.forEachIndexed { index, note ->
                when (note.sketch?.kind) {
                    VisualDocumentKind.SKETCH -> { entry("disegni/${index + 1}.sketch.json", note.body); return@forEachIndexed }
                    VisualDocumentKind.WHITEBOARD -> { entry("lavagne/${index + 1}.whiteboard.json", note.body); return@forEachIndexed }
                    null -> Unit
                }
                // Index prevents collisions; no user-controlled text enters archive paths.
                entry("${if (note.task != null) "attivita" else if (note.archived) "archivio" else "note"}/${index + 1}.md", "# ${note.title.ifBlank { "Senza titolo" }}\n\n${note.body}")
            }
            entry("LEGGIMI.txt", "backup.json v6 conserva stati, promemoria, storico Focus, disegni vettoriali modificabili, attività, Focus, tag, note, fissate, archiviate, cestino, raccolte e bozze. Le cartelle note e archivio contengono il Markdown; disegni contiene i file .sketch.json e lavagne i file .whiteboard.json. Per ripristinare tutte le proprietà importa backup.json in Notes 0.15 o successiva. La cronologia delle revisioni delle note rimane locale; lo storico Focus è incluso.")
        }
    }
}

package it.notes.ecosystem.data

import it.notes.ecosystem.domain.*
import it.notes.ecosystem.domain.Collection
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction

object BackupReader {
    const val MAX_BYTES = 5 * 1024 * 1024

    fun read(input: InputStream): BackupSnapshot {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (true) {
            val size = input.read(buffer)
            if (size < 0) break
            require(output.size() + size <= MAX_BYTES) { "Il backup supera 5 MB." }
            output.write(buffer, 0, size)
        }
        val text = Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(output.toByteArray())).toString()
        return parse(text)
    }

    fun parse(text: String): BackupSnapshot {
        require(text.toByteArray(Charsets.UTF_8).size <= MAX_BYTES) { "Il backup supera 5 MB." }
        // Limit nesting before calling the recursive JSON parser.
        var depth = 0
        var inString = false
        var escaped = false
        text.forEach { c ->
            if (inString) {
                if (escaped) escaped = false
                else if (c == '\\') escaped = true
                else if (c == '"') inString = false
            } else when (c) {
                '"' -> inString = true
                '{', '[' -> { depth++; require(depth <= 32) { "JSON troppo annidato." } }
                '}', ']' -> { depth--; require(depth >= 0) { "JSON non valido." } }
            }
        }
        require(depth == 0 && !inString) { "JSON incompleto." }
        val tokener = JSONTokener(text.removePrefix("\uFEFF"))
        val root = tokener.nextValue() as? JSONObject ?: error("Il file non contiene un backup JSON.")
        require(tokener.nextClean() == '\u0000') { "Dati aggiuntivi dopo il JSON." }
        require(root.string("format") == "notes-ecosystem") { "Formato backup non riconosciuto." }
        val version = root.number("formatVersion")
        require(version in 1L..6L) { "Versione backup non supportata." }

        val notes = root.array("notes").objects().map {
            Note(it.string("id"), it.string("title"), it.string("body"), it.nullableString("collectionId"),
                it.boolean("favorite"), it.number("createdAt"), it.number("updatedAt"), it.nullableNumber("deletedAt"),
                if (version >= 2) it.boolean("pinned") else false,
                if (version >= 2) it.boolean("archived") else false,
                if (version >= 3) TagCodec.read(it.array("tags")) else emptyList(),
                if (version >= 4) TaskCodec.read(it.get("task")) else null,
                if (version >= 5) SketchCodec.readInfo(it.get("sketch")) else null)
        }
        val collections = root.array("collections").objects().map { Collection(it.string("id"), it.string("name")) }
        val drafts = root.array("drafts").objects().map {
            Draft(it.string("id"), it.string("title"), it.string("body"), it.nullableString("collectionId"), it.number("updatedAt"),
                if (version >= 3) TagCodec.read(it.array("tags")) else emptyList())
        }
        return BackupSnapshot(notes, collections, drafts).also(::validateBackup)
    }

    private fun JSONObject.string(key: String): String =
        get(key) as? String ?: error("Campo $key: testo richiesto.")
    private fun JSONObject.boolean(key: String): Boolean =
        get(key) as? Boolean ?: error("Campo $key: booleano richiesto.")
    private fun JSONObject.number(key: String): Long {
        val value = get(key)
        require(value is Int || value is Long) { "Campo $key: intero richiesto." }
        return (value as Number).toLong()
    }
    private fun JSONObject.nullableString(key: String): String? =
        if (get(key) === JSONObject.NULL) null else string(key)
    private fun JSONObject.nullableNumber(key: String): Long? =
        if (get(key) === JSONObject.NULL) null else number(key)
    private fun JSONObject.array(key: String): JSONArray =
        get(key) as? JSONArray ?: error("Campo $key: elenco richiesto.")
    private fun JSONArray.objects(): List<JSONObject> {
        require(length() <= 10000) { "Troppi elementi nel backup (massimo 10000 per elenco)." }
        return (0 until length()).map { get(it) as? JSONObject ?: error("Elemento backup non valido.") }
    }
}

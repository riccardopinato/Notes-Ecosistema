package it.notes.ecosystem.domain

import java.util.UUID

/**
 * Codec loss-aware fra Markdown legacy e Universal Blocks.
 *
 * `notes.body` rimane il formato portabile/canonico nella 0.20.
 * Il parser riconosce soltanto strutture che può ricostruire senza ambiguità.
 * Tutto il resto resta TEXT/MARKDOWN e viene quindi preservato.
 */
object BlockEditorCodec {
    private val checklist = Regex("^\\s*- \\[([ xX])\\]\\s*(.*)$")
    private val heading = Regex("^(#{1,3})\\s+(.*)$")
    private val divider = Regex("^\\s*(---|\\*\\*\\*|___)\\s*$")
    private val attachmentOnly = Regex("^\\s*\\[[^\\]]+]\\(notes-asset://[^)]+\\)\\s*$")
    private val sketchLink = Regex("^\\s*\\[Sketch: ([^\\]]*)]\\(notes-sketch://([A-Za-z0-9-]+)\\)\\s*$")
    private val whiteboardLink = Regex("^\\s*\\[Whiteboard: ([^\\]]*)]\\(notes-board://([A-Za-z0-9-]+)\\)\\s*$")

    fun parse(
        noteId: String,
        markdown: String,
        now: Long = System.currentTimeMillis(),
    ): List<ContentBlock> {
        require(noteId.isNotBlank()) { "Nota mancante." }
        if (markdown.isEmpty()) return emptyList()

        val normalized = markdown.replace("\r\n", "\n").replace('\r', '\n')
        val lines = normalized.split('\n')
        val result = mutableListOf<ContentBlock>()
        val paragraph = mutableListOf<String>()
        var index = 0

        fun add(type: ContentBlockType, text: String = "", checked: Boolean? = null, metadata: String = "{}") {
            result += ContentBlock(
                id = UUID.randomUUID().toString(),
                ownerId = noteId,
                position = result.size,
                type = type,
                text = text,
                checked = checked,
                metadataJson = metadata,
                createdAt = now,
                updatedAt = now,
            )
        }

        fun flushParagraph() {
            if (paragraph.isEmpty()) return
            val text = paragraph.joinToString("\n")
            val type = if (looksLikeRichMarkdown(text)) ContentBlockType.MARKDOWN else ContentBlockType.TEXT
            add(type, text)
            paragraph.clear()
        }

        while (index < lines.size) {
            val line = lines[index]

            if (line.startsWith("```")) {
                flushParagraph()
                val fence = line.takeWhile { it == '`' }
                val language = line.removePrefix(fence).trim()
                index++
                val code = mutableListOf<String>()
                while (index < lines.size && !lines[index].startsWith(fence)) {
                    code += lines[index]
                    index++
                }
                if (index < lines.size) index++
                add(ContentBlockType.CODE, code.joinToString("\n"), metadata = metadata("language", language))
                continue
            }

            if (line.isBlank()) {
                flushParagraph()
                index++
                continue
            }

            heading.matchEntire(line)?.let { match ->
                flushParagraph()
                val level = match.groupValues[1].length.coerceIn(1, 3)
                add(ContentBlockType.HEADING, match.groupValues[2], metadata = metadata("level", level.toString()))
                index++
                continue
            }

            checklist.matchEntire(line)?.let { match ->
                flushParagraph()
                add(
                    type = ContentBlockType.CHECKLIST,
                    text = match.groupValues[2],
                    checked = match.groupValues[1].equals("x", ignoreCase = true),
                )
                index++
                continue
            }

            if (divider.matches(line)) {
                flushParagraph()
                add(ContentBlockType.DIVIDER)
                index++
                continue
            }

            if (line.startsWith("> ") || line == ">") {
                flushParagraph()
                val quote = mutableListOf<String>()
                while (index < lines.size && (lines[index].startsWith("> ") || lines[index] == ">")) {
                    quote += lines[index].removePrefix("> ").removePrefix(">")
                    index++
                }
                add(ContentBlockType.QUOTE, quote.joinToString("\n"))
                continue
            }

            if (attachmentOnly.matches(line)) {
                flushParagraph()
                val ref = Attachments.refs(line).firstOrNull()
                val type = when {
                    ref?.type?.image == true -> ContentBlockType.IMAGE
                    ref?.type?.audio == true -> ContentBlockType.AUDIO
                    else -> ContentBlockType.FILE
                }
                // Conserviamo l'intera sintassi Markdown nel campo text: nessuna perdita dati.
                add(type, line)
                index++
                continue
            }

            sketchLink.matchEntire(line)?.let { match ->
                flushParagraph()
                add(
                    type = ContentBlockType.DRAWING,
                    text = match.groupValues[1].ifBlank { "Disegno" },
                    metadata = metadata("sketchId", match.groupValues[2]),
                )
                index++
                continue
            }

            whiteboardLink.matchEntire(line)?.let { match ->
                flushParagraph()
                add(
                    type = ContentBlockType.WHITEBOARD,
                    text = match.groupValues[1].ifBlank { "Lavagna" },
                    metadata = metadata("whiteboardId", match.groupValues[2]),
                )
                index++
                continue
            }

            paragraph += line
            index++
        }

        flushParagraph()
        return canonicalize(noteId, result, now)
    }

    fun toMarkdown(blocks: List<ContentBlock>): String = blocks
        .sortedBy { it.position }
        .mapNotNull { block ->
            when (block.type) {
                ContentBlockType.TEXT,
                ContentBlockType.MARKDOWN -> block.text

                ContentBlockType.HEADING -> {
                    val level = metadataValue(block.metadataJson, "level")?.toIntOrNull()?.coerceIn(1, 3) ?: 2
                    if (block.text.isBlank()) "#".repeat(level) else "${"#".repeat(level)} ${block.text}"
                }

                ContentBlockType.CHECKLIST,
                ContentBlockType.TASK -> "- [${if (block.checked == true) "x" else " "}] ${block.text}"

                ContentBlockType.QUOTE -> block.text.lineSequence().joinToString("\n") { "> $it" }

                ContentBlockType.CODE -> {
                    val language = metadataValue(block.metadataJson, "language").orEmpty()
                    val longest = Regex("`+").findAll(block.text).maxOfOrNull { it.value.length } ?: 0
                    val fence = "`".repeat(maxOf(3, longest + 1))
                    "$fence$language\n${block.text}\n$fence"
                }

                ContentBlockType.CALLOUT -> {
                    if (block.text.isBlank()) ">" else block.text.lineSequence().joinToString("\n") { "> $it" }
                }

                ContentBlockType.DIVIDER -> "---"

                ContentBlockType.DRAWING -> {
                    val sketchId = metadataValue(block.metadataJson, "sketchId")
                    if (sketchId.isNullOrBlank()) {
                        block.text.takeIf { it.startsWith("[") && it.contains("notes-sketch://") }.orEmpty()
                    } else {
                        "[Sketch: ${block.text.ifBlank { "Disegno" }}](notes-sketch://$sketchId)"
                    }
                }

                ContentBlockType.WHITEBOARD -> {
                    val id = metadataValue(block.metadataJson, "whiteboardId")
                    if (id.isNullOrBlank()) {
                        block.text.takeIf { it.startsWith("[") && it.contains("notes-board://") }.orEmpty()
                    } else {
                        "[Whiteboard: ${block.text.ifBlank { "Lavagna" }}](notes-board://$id)"
                    }
                }

                // Nella 0.20 questi blocchi conservano la sintassi Markdown originale nel text.
                ContentBlockType.IMAGE,
                ContentBlockType.AUDIO,
                ContentBlockType.FILE,
                ContentBlockType.BOOKMARK,
                ContentBlockType.TABLE -> block.text.takeIf { it.isNotBlank() }
            }
        }
        .joinToString("\n\n")
        .trimEnd()

    fun canonicalize(
        noteId: String,
        blocks: List<ContentBlock>,
        now: Long = System.currentTimeMillis(),
    ): List<ContentBlock> = ContentBlocks.normalize(
        ownerId = noteId,
        blocks = blocks,
        now = now,
    )

    fun emptyTextBlock(noteId: String, now: Long = System.currentTimeMillis()): ContentBlock = ContentBlock(
        id = UUID.randomUUID().toString(),
        ownerId = noteId,
        position = 0,
        type = ContentBlockType.TEXT,
        text = "",
        createdAt = now,
        updatedAt = now,
    )

    fun newBlock(
        noteId: String,
        type: ContentBlockType,
        position: Int,
        text: String = "",
        now: Long = System.currentTimeMillis(),
    ): ContentBlock = ContentBlock(
        id = UUID.randomUUID().toString(),
        ownerId = noteId,
        position = position,
        type = type,
        text = text,
        checked = if (type == ContentBlockType.CHECKLIST || type == ContentBlockType.TASK) false else null,
        metadataJson = if (type == ContentBlockType.HEADING) metadata("level", "2") else "{}",
        createdAt = now,
        updatedAt = now,
    )

    fun changeType(block: ContentBlock, type: ContentBlockType): ContentBlock = block.copy(
        type = type,
        checked = if (type == ContentBlockType.CHECKLIST || type == ContentBlockType.TASK) block.checked ?: false else null,
        metadataJson = when (type) {
            ContentBlockType.HEADING -> if (metadataValue(block.metadataJson, "level") == null) metadata("level", "2") else block.metadataJson
            else -> if (block.type == ContentBlockType.HEADING) "{}" else block.metadataJson
        },
    )

    fun withHeadingLevel(block: ContentBlock, level: Int): ContentBlock = block.copy(
        type = ContentBlockType.HEADING,
        checked = null,
        metadataJson = metadata("level", level.coerceIn(1, 3).toString()),
    )

    fun headingLevel(block: ContentBlock): Int =
        metadataValue(block.metadataJson, "level")?.toIntOrNull()?.coerceIn(1, 3) ?: 2

    private fun looksLikeRichMarkdown(text: String): Boolean =
        text.contains("[[") ||
            text.contains("**") ||
            text.contains("__") ||
            text.contains("](") ||
            Regex("(^|\n)\\s*[-*+]\\s+").containsMatchIn(text) ||
            Regex("(^|\n)\\s*\\d+\\.\\s+").containsMatchIn(text) ||
            Regex("\\[[^]]+]\\([^)]+\\)").containsMatchIn(text)

    fun sketchId(block: ContentBlock): String? =
        if (block.type == ContentBlockType.DRAWING) metadataValue(block.metadataJson, "sketchId") else null

    fun whiteboardId(block: ContentBlock): String? =
        if (block.type == ContentBlockType.WHITEBOARD) metadataValue(block.metadataJson, "whiteboardId") else null

    fun drawingMetadata(sketchId: String): String {
        require(sketchId.isNotBlank())
        return metadata("sketchId", sketchId)
    }

    fun whiteboardMetadata(whiteboardId: String): String {
        require(whiteboardId.isNotBlank())
        return metadata("whiteboardId", whiteboardId)
    }

    private fun metadata(key: String, value: String): String {
        val safeKey = key.replace("\\", "\\\\").replace("\"", "\\\"")
        val safeValue = value.replace("\\", "\\\\").replace("\"", "\\\"")
        return "{\"$safeKey\":\"$safeValue\"}"
    }

    private fun metadataValue(json: String, key: String): String? {
        val escaped = Regex.escape(key)
        val match = Regex("\"$escaped\"\\s*:\\s*\"((?:\\\\.|[^\"])*)\"").find(json) ?: return null
        return match.groupValues[1]
            .replace("\\\"", "\"")
            .replace("\\\\", "\\")
    }
}

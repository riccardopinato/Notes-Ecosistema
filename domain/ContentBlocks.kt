package it.notes.ecosystem.domain

import java.util.UUID

/**
 * Tipi di blocco supportati dal modello universale.
 *
 * Nello Step 0.19 soltanto MARKDOWN viene usato come bridge verso le note legacy.
 * Gli altri valori sono già definiti per rendere stabile il contratto dati dei prossimi step.
 */
enum class ContentBlockType {
    MARKDOWN,
    TEXT,
    HEADING,
    CHECKLIST,
    TASK,
    IMAGE,
    AUDIO,
    FILE,
    DRAWING,
    WHITEBOARD,
    BOOKMARK,
    TABLE,
    CODE,
    QUOTE,
    CALLOUT,
    DIVIDER,
}

/**
 * Blocco universale persistibile.
 *
 * ownerType rende il modello riutilizzabile in futuro anche da workspace item,
 * whiteboard, meeting e database, senza vincolare lo schema esclusivamente a NoteEntity.
 */
data class ContentBlock(
    val id: String,
    val ownerId: String,
    val ownerType: String = OWNER_NOTE,
    val parentBlockId: String? = null,
    val position: Int,
    val type: ContentBlockType,
    val text: String = "",
    val checked: Boolean? = null,
    val metadataJson: String = "{}",
    val createdAt: Long,
    val updatedAt: Long,
) {
    companion object {
        const val OWNER_NOTE = "note"
    }
}

object ContentBlocks {
    const val MAX_BLOCKS_PER_OWNER = 2_000
    const val MAX_TEXT_BYTES = 512 * 1024
    const val MAX_METADATA_BYTES = 128 * 1024

    fun validate(block: ContentBlock) {
        require(block.id.isNotBlank()) { "ID blocco mancante." }
        require(block.ownerId.isNotBlank()) { "Contenitore blocco mancante." }
        require(block.ownerType.isNotBlank()) { "Tipo contenitore mancante." }
        require(block.position >= 0) { "Posizione blocco non valida." }
        require(block.text.toByteArray(Charsets.UTF_8).size <= MAX_TEXT_BYTES) {
            "Il contenuto del blocco è troppo grande."
        }
        require(block.metadataJson.toByteArray(Charsets.UTF_8).size <= MAX_METADATA_BYTES) {
            "I metadati del blocco sono troppo grandi."
        }
        require(block.parentBlockId != block.id) { "Un blocco non può contenere sé stesso." }
        if (block.type != ContentBlockType.CHECKLIST && block.type != ContentBlockType.TASK) {
            require(block.checked == null) { "Lo stato completato è valido solo per checklist e attività." }
        }
    }

    /**
     * Normalizza ordine e ownership prima della persistenza.
     * Gli ID esistenti vengono mantenuti; blocchi senza ID ricevono un UUID.
     */
    fun normalize(
        ownerId: String,
        blocks: List<ContentBlock>,
        ownerType: String = ContentBlock.OWNER_NOTE,
        now: Long = System.currentTimeMillis(),
    ): List<ContentBlock> {
        require(ownerId.isNotBlank()) { "Contenitore blocchi mancante." }
        require(ownerType.isNotBlank()) { "Tipo contenitore mancante." }
        require(blocks.size <= MAX_BLOCKS_PER_OWNER) { "Troppi blocchi nello stesso contenitore." }

        val ids = HashSet<String>(blocks.size)
        return blocks.mapIndexed { index, source ->
            val id = source.id.ifBlank { UUID.randomUUID().toString() }
            require(ids.add(id)) { "ID blocco duplicato: $id" }
            val normalized = source.copy(
                id = id,
                ownerId = ownerId,
                ownerType = ownerType,
                position = index,
                createdAt = source.createdAt.takeIf { it > 0L } ?: now,
                updatedAt = now,
            )
            validate(normalized)
            normalized
        }
    }

    /**
     * Bridge NON distruttivo da una nota 0.18: l'intero body Markdown diventa un solo
     * blocco MARKDOWN. Non cambia il body originale e non elimina nessuna informazione.
     */
    fun fromLegacyMarkdown(
        noteId: String,
        body: String,
        now: Long = System.currentTimeMillis(),
        id: String = UUID.randomUUID().toString(),
    ): List<ContentBlock> {
        require(noteId.isNotBlank()) { "Nota mancante." }
        if (body.isEmpty()) return emptyList()
        val block = ContentBlock(
            id = id,
            ownerId = noteId,
            position = 0,
            type = ContentBlockType.MARKDOWN,
            text = body,
            createdAt = now,
            updatedAt = now,
        )
        validate(block)
        return listOf(block)
    }

    /**
     * Compatibilità temporanea con il body Markdown legacy.
     * MARKDOWN/TEXT/HEADING/QUOTE/CODE/CALLOUT vengono serializzati in testo;
     * i blocchi ancora non rappresentabili sono ignorati intenzionalmente nello Step 0.19.
     */
    fun toLegacyMarkdown(blocks: List<ContentBlock>): String = blocks
        .sortedBy { it.position }
        .mapNotNull { block ->
            when (block.type) {
                ContentBlockType.MARKDOWN,
                ContentBlockType.TEXT -> block.text
                ContentBlockType.HEADING -> if (block.text.isBlank()) "" else "## ${block.text}"
                ContentBlockType.CHECKLIST,
                ContentBlockType.TASK -> "- [${if (block.checked == true) "x" else " "}] ${block.text}"
                ContentBlockType.QUOTE -> block.text.lineSequence().joinToString("\n") { "> $it" }
                ContentBlockType.CODE -> "```\n${block.text}\n```"
                ContentBlockType.CALLOUT -> if (block.text.isBlank()) "" else "> ${block.text}"
                ContentBlockType.DIVIDER -> "---"
                ContentBlockType.IMAGE,
                ContentBlockType.AUDIO,
                ContentBlockType.FILE,
                ContentBlockType.DRAWING,
                ContentBlockType.WHITEBOARD,
                ContentBlockType.BOOKMARK,
                ContentBlockType.TABLE -> block.text.takeIf { it.isNotBlank() }
            }
        }
        .joinToString("\n\n")
}

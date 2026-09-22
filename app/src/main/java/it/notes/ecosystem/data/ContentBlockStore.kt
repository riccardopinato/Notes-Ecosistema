package it.notes.ecosystem.data

import androidx.room.Dao
import androidx.room.Entity
import androidx.room.Index
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Upsert
import androidx.room.withTransaction
import it.notes.ecosystem.domain.ContentBlock
import it.notes.ecosystem.domain.ContentBlockType
import it.notes.ecosystem.domain.ContentBlocks
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map

@Entity(
    tableName = "content_blocks",
    indices = [
        Index(value = ["ownerType", "ownerId", "position"]),
        Index(value = ["ownerType", "ownerId"]),
        Index(value = ["parentBlockId"]),
        Index(value = ["type"]),
    ],
)
data class ContentBlockEntity(
    @androidx.room.PrimaryKey val id: String,
    val ownerId: String,
    val ownerType: String,
    val parentBlockId: String?,
    val position: Int,
    val type: String,
    val text: String,
    val checked: Boolean?,
    val metadataJson: String,
    val createdAt: Long,
    val updatedAt: Long,
)

@Dao
interface ContentBlocksDao {
    @Query("SELECT * FROM content_blocks WHERE ownerType = :ownerType AND ownerId = :ownerId ORDER BY position ASC, id ASC")
    fun observe(ownerType: String, ownerId: String): Flow<List<ContentBlockEntity>>

    @Query("SELECT * FROM content_blocks WHERE ownerType = :ownerType AND ownerId = :ownerId ORDER BY position ASC, id ASC")
    suspend fun list(ownerType: String, ownerId: String): List<ContentBlockEntity>

    @Query("SELECT COUNT(*) FROM content_blocks WHERE ownerType = :ownerType AND ownerId = :ownerId")
    suspend fun count(ownerType: String, ownerId: String): Int

    @Query("SELECT * FROM content_blocks WHERE id = :id LIMIT 1")
    suspend fun get(id: String): ContentBlockEntity?

    @Upsert
    suspend fun upsert(block: ContentBlockEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(blocks: List<ContentBlockEntity>)

    @Query("DELETE FROM content_blocks WHERE id = :id")
    suspend fun delete(id: String)

    @Query("DELETE FROM content_blocks WHERE ownerType = :ownerType AND ownerId = :ownerId")
    suspend fun deleteForOwner(ownerType: String, ownerId: String)
}

/**
 * Storage separato dal repository legacy.
 *
 * In 0.19 non è ancora la fonte canonica delle note: serve a preparare lo schema v8 e a
 * consentire allo Step 0.20 di attivare il block editor in modo controllato.
 */
class ContentBlockStore(private val database: NotesDatabase) {
    private val blocks = database.contentBlocksDao()
    private val notes = database.notesDao()

    fun observeNote(noteId: String): Flow<List<ContentBlock>> =
        blocks.observe(ContentBlock.OWNER_NOTE, noteId)
            .map { rows -> rows.map(ContentBlockEntity::toDomain) }
            .flowOn(Dispatchers.Default)

    suspend fun listNote(noteId: String): List<ContentBlock> =
        blocks.list(ContentBlock.OWNER_NOTE, noteId).map(ContentBlockEntity::toDomain)

    /**
     * Crea il bridge iniziale soltanto su richiesta esplicita.
     * Non viene chiamato all'avvio e non effettua migrazioni massive.
     */
    suspend fun ensureLegacyMarkdown(noteId: String): List<ContentBlock> = database.withTransaction {
        val existing = blocks.list(ContentBlock.OWNER_NOTE, noteId)
        if (existing.isNotEmpty()) return@withTransaction existing.map(ContentBlockEntity::toDomain)

        val note = notes.get(noteId) ?: error("Nota non trovata.")
        check(note.deletedAt == null) { "Ripristina la nota prima di modificarla." }
        check(note.taskJson == null && note.sketchJson == null) {
            "I blocchi sono disponibili solo per le note di testo."
        }

        val seeded = ContentBlocks.fromLegacyMarkdown(noteId, note.body)
        if (seeded.isNotEmpty()) blocks.upsertAll(seeded.map(ContentBlock::toEntity))
        seeded
    }

    /**
     * API di persistenza pronta per il futuro editor.
     * Non modifica NoteEntity.body nello Step 0.19: il collegamento canonico viene introdotto
     * nello Step 0.20 insieme a cronologia, bozza e salvataggio atomico.
     */
    suspend fun replaceNoteBlocks(noteId: String, source: List<ContentBlock>): List<ContentBlock> =
        database.withTransaction {
            val note = notes.get(noteId) ?: error("Nota non trovata.")
            check(note.deletedAt == null) { "Ripristina la nota prima di modificarla." }
            check(note.taskJson == null && note.sketchJson == null) {
                "I blocchi sono disponibili solo per le note di testo."
            }
            val normalized = ContentBlocks.normalize(noteId, source)
            blocks.deleteForOwner(ContentBlock.OWNER_NOTE, noteId)
            if (normalized.isNotEmpty()) blocks.upsertAll(normalized.map(ContentBlock::toEntity))
            normalized
        }

    suspend fun clearNote(noteId: String) = database.withTransaction {
        blocks.deleteForOwner(ContentBlock.OWNER_NOTE, noteId)
    }
}

private fun ContentBlockEntity.toDomain(): ContentBlock = ContentBlock(
    id = id,
    ownerId = ownerId,
    ownerType = ownerType,
    parentBlockId = parentBlockId,
    position = position,
    type = runCatching { ContentBlockType.valueOf(type) }.getOrElse { ContentBlockType.MARKDOWN },
    text = text,
    checked = checked,
    metadataJson = metadataJson,
    createdAt = createdAt,
    updatedAt = updatedAt,
)

private fun ContentBlock.toEntity(): ContentBlockEntity {
    ContentBlocks.validate(this)
    return ContentBlockEntity(
        id = id,
        ownerId = ownerId,
        ownerType = ownerType,
        parentBlockId = parentBlockId,
        position = position,
        type = type.name,
        text = text,
        checked = checked,
        metadataJson = metadataJson,
        createdAt = createdAt,
        updatedAt = updatedAt,
    )
}

package it.notes.ecosystem.data

import androidx.room.*
import kotlinx.coroutines.flow.Flow

@Entity(tableName = "collections", indices = [Index(value = ["name"], unique = true)])
data class CollectionEntity(@PrimaryKey val id: String, val name: String)

@Entity(
    tableName = "notes",
    foreignKeys = [ForeignKey(entity = CollectionEntity::class, parentColumns = ["id"], childColumns = ["collectionId"], onDelete = ForeignKey.SET_NULL)],
    indices = [Index("collectionId"), Index("deletedAt"), Index("updatedAt")],
)
data class NoteEntity(
    @PrimaryKey val id: String,
    val title: String,
    val body: String,
    val collectionId: String?,
    val favorite: Boolean,
    val createdAt: Long,
    val updatedAt: Long,
    val deletedAt: Long? = null,
    @ColumnInfo(defaultValue = "0") val pinned: Boolean = false,
    @ColumnInfo(defaultValue = "0") val archived: Boolean = false,
    @ColumnInfo(defaultValue = "'[]'") val tagsJson: String = "[]",
    @ColumnInfo(defaultValue = "NULL") val taskJson: String? = null,
    @ColumnInfo(defaultValue = "NULL") val sketchJson: String? = null,
)

@Entity(tableName = "drafts")
data class DraftEntity(@PrimaryKey val id: String, val title: String, val body: String, val collectionId: String?, val updatedAt: Long, @ColumnInfo(defaultValue = "'[]'") val tagsJson: String = "[]")

@Entity(tableName = "note_revisions", indices = [Index("noteId")])
data class RevisionEntity(@PrimaryKey val revisionId: String, val noteId: String, val title: String,
    val body: String, val collectionId: String?, val savedAt: Long, @ColumnInfo(defaultValue = "'[]'") val tagsJson: String = "[]")

data class RevisionAttachmentPage(val position:Long,val body:String)

@Dao
interface NotesDao {
    @Query("SELECT rowid AS position, body FROM note_revisions WHERE rowid > :after ORDER BY rowid LIMIT 16")
    suspend fun revisionAttachmentPage(after:Long): List<RevisionAttachmentPage>

    @Query("UPDATE collections SET name = :name WHERE id = :id")
    suspend fun renameCollection(id: String, name: String)
    @Query("DELETE FROM collections WHERE id = :id")
    suspend fun deleteCollection(id: String)
    @Query("SELECT COUNT(*) FROM note_revisions WHERE collectionId = :id")
    suspend fun collectionRevisionCount(id: String): Int

    @Query("SELECT * FROM note_revisions WHERE noteId = :id ORDER BY savedAt DESC, rowid DESC LIMIT 50")
    suspend fun history(id: String): List<RevisionEntity>
    @Query("SELECT * FROM note_revisions WHERE noteId = :id ORDER BY savedAt DESC, rowid DESC LIMIT 1")
    suspend fun latestRevision(id: String): RevisionEntity?
    @Insert suspend fun addRevision(revision: RevisionEntity)
    @Query("DELETE FROM note_revisions WHERE noteId = :id AND revisionId NOT IN (SELECT revisionId FROM note_revisions WHERE noteId = :id ORDER BY savedAt DESC, rowid DESC LIMIT 50)")
    suspend fun trimHistory(id: String)
    @Query("SELECT * FROM drafts ORDER BY updatedAt DESC, id ASC")
    fun observeDrafts(): Flow<List<DraftEntity>>
    @Query("SELECT * FROM drafts WHERE id = :id")
    suspend fun getDraft(id: String): DraftEntity?
    @Upsert suspend fun upsertDraft(draft: DraftEntity)
    @Query("DELETE FROM drafts WHERE id = :id")
    suspend fun deleteDraft(id: String)
    @Query("SELECT * FROM notes ORDER BY id")
    suspend fun allNotes(): List<NoteEntity>
    @Query("SELECT * FROM collections ORDER BY id")
    suspend fun allCollections(): List<CollectionEntity>
    @Query("SELECT EXISTS(SELECT 1 FROM collections WHERE id = :id LIMIT 1)")
    suspend fun collectionExists(id: String): Boolean
    @Query("SELECT * FROM drafts ORDER BY id")
    suspend fun allDrafts(): List<DraftEntity>
    @Query("SELECT * FROM notes ORDER BY favorite DESC, updatedAt DESC, id ASC")
    fun observeNotes(): Flow<List<NoteEntity>>
    @Query("SELECT * FROM collections ORDER BY name COLLATE NOCASE")
    fun observeCollections(): Flow<List<CollectionEntity>>
    @Query("SELECT * FROM notes WHERE id = :id")
    suspend fun get(id: String): NoteEntity?
    @Insert suspend fun insertImportedNote(note: NoteEntity)
    @Insert suspend fun insertImportedDraft(draft: DraftEntity)
    @Upsert suspend fun upsert(note: NoteEntity)
    @Insert(onConflict = OnConflictStrategy.IGNORE) suspend fun addCollection(collection: CollectionEntity): Long
    @Query("UPDATE notes SET favorite = NOT favorite, updatedAt = :now WHERE id = :id AND deletedAt IS NULL")
    suspend fun toggleFavorite(id: String, now: Long)
    @Query("UPDATE notes SET deletedAt = :now, updatedAt = :now WHERE id = :id AND deletedAt IS NULL")
    suspend fun trash(id: String, now: Long)
    @Query("UPDATE notes SET deletedAt = NULL, updatedAt = :now WHERE id = :id AND deletedAt IS NOT NULL")
    suspend fun restore(id: String, now: Long)
}

@Database(
    entities = [
        NoteEntity::class,
        CollectionEntity::class,
        DraftEntity::class,
        RevisionEntity::class,
        ContentBlockEntity::class,
    ],
    version = 8,
    exportSchema = true,
)
abstract class NotesDatabase : RoomDatabase() {
    abstract fun notesDao(): NotesDao
    abstract fun contentBlocksDao(): ContentBlocksDao

    companion object {
        val MIGRATION_7_8 = object : androidx.room.migration.Migration(7, 8) {
            override fun migrate(db: androidx.sqlite.db.SupportSQLiteDatabase) {
                // IMPORTANTE: non copiare automaticamente i body Markdown nella nuova tabella.
                // Il bridge è lazy/on-demand tramite ContentBlockStore.ensureLegacyMarkdown().
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS content_blocks (
                        id TEXT NOT NULL,
                        ownerId TEXT NOT NULL,
                        ownerType TEXT NOT NULL,
                        parentBlockId TEXT,
                        position INTEGER NOT NULL,
                        type TEXT NOT NULL,
                        text TEXT NOT NULL,
                        checked INTEGER,
                        metadataJson TEXT NOT NULL,
                        createdAt INTEGER NOT NULL,
                        updatedAt INTEGER NOT NULL,
                        PRIMARY KEY(id)
                    )
                    """.trimIndent()
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS index_content_blocks_ownerType_ownerId_position ON content_blocks (ownerType, ownerId, position)")
                db.execSQL("CREATE INDEX IF NOT EXISTS index_content_blocks_ownerType_ownerId ON content_blocks (ownerType, ownerId)")
                db.execSQL("CREATE INDEX IF NOT EXISTS index_content_blocks_parentBlockId ON content_blocks (parentBlockId)")
                db.execSQL("CREATE INDEX IF NOT EXISTS index_content_blocks_type ON content_blocks (type)")
            }
        }

        val MIGRATION_6_7 = object : androidx.room.migration.Migration(6, 7) {
            override fun migrate(db: androidx.sqlite.db.SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE notes ADD COLUMN sketchJson TEXT DEFAULT NULL")
            }
        }

        val MIGRATION_5_6 = object : androidx.room.migration.Migration(5, 6) {
            override fun migrate(db: androidx.sqlite.db.SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE notes ADD COLUMN taskJson TEXT DEFAULT NULL")
            }
        }

        val MIGRATION_4_5 = object : androidx.room.migration.Migration(4, 5) {
            override fun migrate(db: androidx.sqlite.db.SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE notes ADD COLUMN tagsJson TEXT NOT NULL DEFAULT '[]'")
                db.execSQL("ALTER TABLE drafts ADD COLUMN tagsJson TEXT NOT NULL DEFAULT '[]'")
                db.execSQL("ALTER TABLE note_revisions ADD COLUMN tagsJson TEXT NOT NULL DEFAULT '[]'")
            }
        }
        val MIGRATION_3_4 = object : androidx.room.migration.Migration(3, 4) {
            override fun migrate(db: androidx.sqlite.db.SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE notes ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0")
                db.execSQL("ALTER TABLE notes ADD COLUMN archived INTEGER NOT NULL DEFAULT 0")
            }
        }
        val MIGRATION_2_3 = object : androidx.room.migration.Migration(2, 3) {
            override fun migrate(db: androidx.sqlite.db.SupportSQLiteDatabase) {
                db.execSQL("CREATE TABLE IF NOT EXISTS note_revisions (revisionId TEXT NOT NULL, noteId TEXT NOT NULL, title TEXT NOT NULL, body TEXT NOT NULL, collectionId TEXT, savedAt INTEGER NOT NULL, PRIMARY KEY(revisionId))")
                db.execSQL("CREATE INDEX IF NOT EXISTS index_note_revisions_noteId ON note_revisions (noteId)")
            }
        }
        val MIGRATION_1_2 = object : androidx.room.migration.Migration(1, 2) {
            override fun migrate(db: androidx.sqlite.db.SupportSQLiteDatabase) {
                db.execSQL("CREATE TABLE IF NOT EXISTS drafts (id TEXT NOT NULL, title TEXT NOT NULL, body TEXT NOT NULL, collectionId TEXT, updatedAt INTEGER NOT NULL, PRIMARY KEY(id))")
            }
        }
    }
}

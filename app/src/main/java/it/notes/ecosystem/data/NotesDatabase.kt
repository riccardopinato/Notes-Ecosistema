package it.notes.ecosystem.data

import androidx.room.*
import kotlinx.coroutines.flow.Flow

@Entity(tableName = "collections", indices = [Index(value = ["name"], unique = true)])
data class CollectionEntity(@PrimaryKey val id: String, val name: String)

@Entity(
    tableName = "notes",
    foreignKeys = [ForeignKey(entity = CollectionEntity::class, parentColumns = ["id"], childColumns = ["collectionId"], onDelete = ForeignKey.SET_NULL)],
    indices = [Index("collectionId"), Index("deletedAt"), Index("updatedAt"), Index("visibility"), Index("spaceId"), Index("cloudAccountId"), Index("cloudState")],
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
    @ColumnInfo(defaultValue = "'PRIVATE'") val visibility: String = "PRIVATE",
    @ColumnInfo(defaultValue = "NULL") val spaceId: String? = null,
    @ColumnInfo(defaultValue = "NULL") val cloudAccountId: String? = null,
    @ColumnInfo(defaultValue = "0") val remoteRevision: Long = 0L,
    @ColumnInfo(defaultValue = "NULL") val updatedBy: String? = null,
    @ColumnInfo(defaultValue = "'LOCAL'") val cloudState: String = "LOCAL",
)

@Entity(tableName = "sync_outbox", indices = [Index("accountId"), Index("createdAt")])
data class SyncOutboxEntity(
    @PrimaryKey val recordId: String,
    val accountId: String,
    val operation: String,
    val baseRevision: Long,
    val createdAt: Long,
    val attempts: Int = 0,
    val lastError: String? = null,
)

@Entity(tableName = "sync_conflicts", indices = [Index("recordId"), Index("accountId"), Index("status")])
data class SyncConflictEntity(
    @PrimaryKey val conflictId: String,
    val recordId: String,
    val accountId: String,
    val localPayload: String,
    val remotePayload: String,
    val baseRevision: Long,
    val remoteRevision: Long,
    val createdAt: Long,
    val status: String = "OPEN",
)

@Entity(tableName = "shared_spaces_cache", indices = [Index("ownerId")])
data class SharedSpaceCacheEntity(
    @PrimaryKey val id: String,
    val name: String,
    val ownerId: String,
    val role: String,
    val updatedAt: Long,
)

@Entity(tableName = "space_members_cache", primaryKeys = ["spaceId", "userId"], indices = [Index("userId")])
data class SpaceMemberCacheEntity(
    val spaceId: String,
    val userId: String,
    val displayName: String,
    val role: String,
    val updatedAt: Long,
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

@Dao
interface CloudDao {
    @Query("SELECT * FROM sync_outbox WHERE accountId = :accountId ORDER BY createdAt, recordId LIMIT :limit")
    suspend fun outbox(accountId: String, limit: Int = 50): List<SyncOutboxEntity>
    @Upsert suspend fun enqueue(item: SyncOutboxEntity)
    @Query("DELETE FROM sync_outbox WHERE recordId = :recordId AND accountId = :accountId")
    suspend fun removeOutbox(recordId: String, accountId: String)
    @Query("UPDATE sync_outbox SET attempts = attempts + 1, lastError = :message WHERE recordId = :recordId AND accountId = :accountId")
    suspend fun failOutbox(recordId: String, accountId: String, message: String)
    @Query("SELECT * FROM sync_conflicts WHERE accountId = :accountId AND status = 'OPEN' ORDER BY createdAt DESC")
    fun observeConflicts(accountId: String): Flow<List<SyncConflictEntity>>
    @Upsert suspend fun upsertConflict(conflict: SyncConflictEntity)
    @Query("UPDATE sync_conflicts SET status = :status WHERE conflictId = :conflictId")
    suspend fun setConflictStatus(conflictId: String, status: String)
    @Query("SELECT * FROM notes WHERE visibility = 'PRIVATE' AND cloudAccountId = :accountId ORDER BY id")
    suspend fun privateNotes(accountId: String): List<NoteEntity>
    @Query("UPDATE notes SET cloudAccountId = :accountId, cloudState = 'DIRTY' WHERE visibility = 'PRIVATE' AND (cloudAccountId IS NULL OR (cloudAccountId = :accountId AND cloudState = 'DETACHED'))")
    suspend fun claimPrivateNotes(accountId: String)
    @Query("INSERT OR REPLACE INTO sync_outbox(recordId, accountId, operation, baseRevision, createdAt, attempts, lastError) SELECT id, :accountId, 'UPSERT', remoteRevision, :now, 0, NULL FROM notes WHERE visibility = 'PRIVATE' AND cloudAccountId = :accountId AND cloudState = 'DIRTY'")
    suspend fun enqueueDirtyPrivateNotes(accountId: String, now: Long)
    @Query("UPDATE notes SET cloudState = 'DETACHED' WHERE visibility = 'PRIVATE' AND cloudAccountId = :accountId")
    suspend fun detachAccount(accountId: String)
    @Query("UPDATE notes SET cloudState = 'CONFLICT' WHERE id = :recordId AND cloudAccountId = :accountId")
    suspend fun markConflict(recordId: String, accountId: String)
    @Query("DELETE FROM sync_outbox WHERE accountId = :accountId")
    suspend fun clearOutbox(accountId: String)
    @Query("DELETE FROM sync_conflicts WHERE accountId = :accountId")
    suspend fun clearConflicts(accountId: String)
    @Query("DELETE FROM shared_spaces_cache")
    suspend fun clearSpaces()
    @Query("DELETE FROM space_members_cache")
    suspend fun clearMembers()
}

@Database(
    entities = [
        NoteEntity::class,
        CollectionEntity::class,
        DraftEntity::class,
        RevisionEntity::class,
        ContentBlockEntity::class,
        SyncOutboxEntity::class,
        SyncConflictEntity::class,
        SharedSpaceCacheEntity::class,
        SpaceMemberCacheEntity::class,
    ],
    version = 9,
    exportSchema = true,
)
abstract class NotesDatabase : RoomDatabase() {
    abstract fun notesDao(): NotesDao
    abstract fun contentBlocksDao(): ContentBlocksDao
    abstract fun cloudDao(): CloudDao

    companion object {
        val MIGRATION_8_9 = object : androidx.room.migration.Migration(8, 9) {
            override fun migrate(db: androidx.sqlite.db.SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE notes ADD COLUMN visibility TEXT NOT NULL DEFAULT 'PRIVATE'")
                db.execSQL("ALTER TABLE notes ADD COLUMN spaceId TEXT DEFAULT NULL")
                db.execSQL("ALTER TABLE notes ADD COLUMN cloudAccountId TEXT DEFAULT NULL")
                db.execSQL("ALTER TABLE notes ADD COLUMN remoteRevision INTEGER NOT NULL DEFAULT 0")
                db.execSQL("ALTER TABLE notes ADD COLUMN updatedBy TEXT DEFAULT NULL")
                db.execSQL("ALTER TABLE notes ADD COLUMN cloudState TEXT NOT NULL DEFAULT 'LOCAL'")
                db.execSQL("CREATE INDEX IF NOT EXISTS index_notes_visibility ON notes (visibility)")
                db.execSQL("CREATE INDEX IF NOT EXISTS index_notes_spaceId ON notes (spaceId)")
                db.execSQL("CREATE INDEX IF NOT EXISTS index_notes_cloudAccountId ON notes (cloudAccountId)")
                db.execSQL("CREATE INDEX IF NOT EXISTS index_notes_cloudState ON notes (cloudState)")
                db.execSQL("CREATE TABLE IF NOT EXISTS sync_outbox (recordId TEXT NOT NULL, accountId TEXT NOT NULL, operation TEXT NOT NULL, baseRevision INTEGER NOT NULL, createdAt INTEGER NOT NULL, attempts INTEGER NOT NULL, lastError TEXT, PRIMARY KEY(recordId))")
                db.execSQL("CREATE INDEX IF NOT EXISTS index_sync_outbox_accountId ON sync_outbox (accountId)")
                db.execSQL("CREATE INDEX IF NOT EXISTS index_sync_outbox_createdAt ON sync_outbox (createdAt)")
                db.execSQL("CREATE TABLE IF NOT EXISTS sync_conflicts (conflictId TEXT NOT NULL, recordId TEXT NOT NULL, accountId TEXT NOT NULL, localPayload TEXT NOT NULL, remotePayload TEXT NOT NULL, baseRevision INTEGER NOT NULL, remoteRevision INTEGER NOT NULL, createdAt INTEGER NOT NULL, status TEXT NOT NULL, PRIMARY KEY(conflictId))")
                db.execSQL("CREATE INDEX IF NOT EXISTS index_sync_conflicts_recordId ON sync_conflicts (recordId)")
                db.execSQL("CREATE INDEX IF NOT EXISTS index_sync_conflicts_accountId ON sync_conflicts (accountId)")
                db.execSQL("CREATE INDEX IF NOT EXISTS index_sync_conflicts_status ON sync_conflicts (status)")
                db.execSQL("CREATE TABLE IF NOT EXISTS shared_spaces_cache (id TEXT NOT NULL, name TEXT NOT NULL, ownerId TEXT NOT NULL, role TEXT NOT NULL, updatedAt INTEGER NOT NULL, PRIMARY KEY(id))")
                db.execSQL("CREATE INDEX IF NOT EXISTS index_shared_spaces_cache_ownerId ON shared_spaces_cache (ownerId)")
                db.execSQL("CREATE TABLE IF NOT EXISTS space_members_cache (spaceId TEXT NOT NULL, userId TEXT NOT NULL, displayName TEXT NOT NULL, role TEXT NOT NULL, updatedAt INTEGER NOT NULL, PRIMARY KEY(spaceId, userId))")
                db.execSQL("CREATE INDEX IF NOT EXISTS index_space_members_cache_userId ON space_members_cache (userId)")
            }
        }

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

package it.notes.ecosystem.data

import androidx.room.withTransaction
import it.notes.ecosystem.sync.SyncDocument
import it.notes.ecosystem.domain.Collection
import it.notes.ecosystem.domain.Note
import it.notes.ecosystem.domain.NotesRepository
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import java.util.UUID
import it.notes.ecosystem.domain.Draft
import it.notes.ecosystem.domain.BackupSnapshot
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

class LocalNotesRepository(
    private val database: NotesDatabase,
    private val cloudContext: () -> it.notes.ecosystem.cloud.CloudWriteContext? = { null },
    private val cloudWriteNotifier: () -> Unit = {},
) : NotesRepository, it.notes.ecosystem.sync.SyncLocal {
    private val dao = database.notesDao()
    private val cloudDao = database.cloudDao()

    private suspend fun upsertLocal(note: NoteEntity): NoteEntity {
        val context = cloudContext()
        val next = if (context != null && note.visibility == "PRIVATE") {
            note.copy(cloudAccountId = context.accountId, cloudState = "DIRTY")
        } else if (note.visibility == "PRIVATE" && note.cloudAccountId != null && note.cloudState != "CONFLICT") {
            note.copy(cloudState = "DETACHED")
        } else note
        dao.upsert(next)
        if (context != null && next.visibility == "PRIVATE") {
            cloudDao.enqueue(SyncOutboxEntity(next.id, context.accountId, "UPSERT", next.remoteRevision, System.currentTimeMillis()))
            cloudWriteNotifier()
        }
        return next
    }
    override suspend fun createTemplate(content: it.notes.ecosystem.domain.TemplateContent): String {
        val valid=it.notes.ecosystem.domain.PersonalTemplates.capture(content.title,content.body,content.tags)
        return writes.withLock { database.withTransaction {
            val id=UUID.randomUUID().toString(); val now=System.currentTimeMillis()
            upsertLocal(NoteEntity(id,valid.title,valid.body,null,false,now,now,archived=true,tagsJson=TagCodec.encode(valid.tags)))
            id
        } }
    }
    override suspend fun cleanupAttachments(cleanup: (Set<String>)->Int): Int = writes.withLock { database.withTransaction {
        val references=mutableSetOf<String>()
        fun collect(body:String) { references.addAll(it.notes.ecosystem.domain.Attachments.refs(body).map {it.key}) }
        dao.allNotes().filter {it.sketchJson==null}.forEach {collect(it.body)}
        dao.allDrafts().forEach {collect(it.body)}
        var after=0L
        while(true) {
            val page=dao.revisionAttachmentPage(after)
            if(page.isEmpty())break
            page.forEach {collect(it.body)};after=page.last().position
        }
        cleanup(references)
    } }

    override suspend fun history(id: String) = writes.withLock { dao.history(id).map { revision ->
        it.notes.ecosystem.domain.NoteRevision(revision.revisionId, revision.noteId, revision.title, revision.body, revision.collectionId, revision.savedAt, TagCodec.decode(revision.tagsJson))
    } }
    private suspend fun preserve(old: NoteEntity?) {
        if (old == null) return
        val latest = dao.latestRevision(old.id)
        if (latest != null && latest.title == old.title && latest.body == old.body && latest.collectionId == old.collectionId && latest.tagsJson == old.tagsJson) return
        dao.addRevision(RevisionEntity(UUID.randomUUID().toString(), old.id, old.title, old.body, old.collectionId, System.currentTimeMillis(), old.tagsJson))
        dao.trimHistory(old.id)
    }
    private val editors = java.util.concurrent.ConcurrentHashMap<String, Int>()
    override fun beginEditing(id: String) { editors.compute(id) { _, count -> (count ?: 0) + 1 } }
    private val _editorClosures = MutableStateFlow(0L)
    val editorClosures = _editorClosures.asStateFlow()
    override fun endEditing(id: String) {
        var released = false
        editors.computeIfPresent(id) { _, count ->
            if (count <= 1) { released = true; null } else count - 1
        }
        if (released) _editorClosures.update { it + 1 }
    }
    private suspend fun syncDocumentLocked(id: String): SyncDocument? {
        val note = dao.get(id)?.takeIf { it.visibility == "PRIVATE" }?.toDomain() ?: return null
        val collection = dao.allCollections().firstOrNull { it.id == note.collectionId }?.name
        return SyncDocument.from(note, collection)
    }
    override suspend fun syncDocument(id: String) = writes.withLock { database.withTransaction { syncDocumentLocked(id) } }
    override suspend fun syncDocuments(): Map<String, SyncDocument> = writes.withLock { database.withTransaction {
        val names = dao.allCollections().associate { it.id to it.name }
        dao.allNotes().filter { it.visibility == "PRIVATE" }.associate { it.id to SyncDocument.from(it.toDomain(), names[it.collectionId]) }
    } }
    private suspend fun putSynced(document: SyncDocument) {
        preserve(dao.get(document.id))
        val collectionId = document.collection?.let { name ->
            dao.allCollections().firstOrNull { it.name == name }?.id ?: run {
                val id = UUID.randomUUID().toString()
                check(dao.addCollection(CollectionEntity(id, name)) != -1L)
                id
            }
        }
        upsertLocal(NoteEntity(document.id, document.title, document.body, collectionId,
            document.favorite, document.createdAt, document.updatedAt, document.deletedAt, document.pinned, document.archived, TagCodec.encode(document.tags), TaskCodec.encode(document.task), SketchCodec.encodeInfo(document.sketch),
            cloudAccountId = dao.get(document.id)?.cloudAccountId, remoteRevision = dao.get(document.id)?.remoteRevision ?: 0L, updatedBy = dao.get(document.id)?.updatedBy, cloudState = dao.get(document.id)?.cloudState ?: "LOCAL"))
    }
    override suspend fun applySync(id: String, expected: SyncDocument?, incoming: SyncDocument): Boolean = writes.withLock {
        database.withTransaction {
            if (editors.containsKey(id) || dao.getDraft(id) != null || syncDocumentLocked(id) != expected) false
            else { check(incoming.id == id); putSynced(incoming); true }
        }
    }
    suspend fun resolveSync(id: String, expected: SyncDocument?, remote: SyncDocument, choice: String): Boolean = writes.withLock {
        database.withTransaction {
            require(choice in listOf("local", "remote", "both"))
            if (editors.containsKey(id) || dao.getDraft(id) != null || syncDocumentLocked(id) != expected) false
            else {
                check(remote.id == id)
                if (choice == "both" && expected != null) putSynced(expected.copy(id = UUID.randomUUID().toString(),
                    title = expected.title + " (copia locale)", deletedAt = null))
                if (choice != "local") putSynced(remote)
                true
            }
        }
    }
    // The Application owns this repository. Queued writes survive editor navigation.
    private val writeScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val writes = Mutex()
    override val drafts = dao.observeDrafts().map { rows -> rows.map { it.toDomain() } }.flowOn(Dispatchers.Default)
    override suspend fun getDraft(id: String) = writes.withLock { dao.getDraft(id)?.toDomain() }
    override fun queueDraft(draft: Draft): Deferred<Unit> =
        writeScope.async {
            writes.withLock {
                val existing = dao.get(draft.id)

                check(
                    existing?.taskJson == null &&
                        existing?.sketchJson == null
                ) {
                    "Le attività usano il loro editor dedicato."
                }

                check(existing?.deletedAt == null) {
                    "La nota è nel cestino."
                }

                check(
                    draft.collectionId == null ||
                        dao.collectionExists(draft.collectionId)
                ) {
                    "La raccolta non è più disponibile. Scegli Inbox o un’altra raccolta."
                }

                dao.upsertDraft(
                    DraftEntity(
                        draft.id,
                        draft.title,
                        draft.body,
                        draft.collectionId,
                        draft.updatedAt,
                        TagCodec.encode(draft.tags),
                    )
                )
            }
        }
    override suspend fun discardDraft(id: String) = writes.withLock { dao.deleteDraft(id) }
    override suspend fun snapshot() = writes.withLock {
        database.withTransaction {
            BackupSnapshot(dao.allNotes().map { it.toDomain() },
                dao.allCollections().map { Collection(it.id, it.name) }, dao.allDrafts().map { it.toDomain() })
        }
    }
    override suspend fun importCopies(data: BackupSnapshot) {
        it.notes.ecosystem.domain.validateBackup(data)
        writes.withLock {
            database.withTransaction {
                val collectionMap = data.collections.associate { it.id to UUID.randomUUID().toString() }
                val noteMap = (data.notes.map { it.id } + data.drafts.map { it.id })
                    .distinct().associateWith { UUID.randomUUID().toString() }
                val names = dao.allCollections().map { it.name }.toMutableSet()
                data.collections.forEach { collection ->
                    val base = collection.name
                    var name = base
                    var suffix = 1
                    while (name in names) { name = "$base (importata $suffix)"; suffix++ }
                    names.add(name)
                    check(dao.addCollection(CollectionEntity(collectionMap.getValue(collection.id), name)) != -1L) {
                        "Impossibile creare una raccolta importata."
                    }
                }
                val importedNoteIds = data.notes.filter { it.task == null }.map { it.id }.toSet()
                val importedTextIds=data.notes.filter {it.task==null && it.sketch==null}.map {it.id}.toSet()
                data.notes.forEach { n ->
                    upsertLocal(NoteEntity(noteMap.getValue(n.id), n.title, if(n.sketch==null) it.notes.ecosystem.domain.Knowledge.remap(n.body,noteMap) else n.body,
                        n.collectionId?.let { collectionMap.getValue(it) }, n.favorite, n.createdAt, n.updatedAt, n.deletedAt, n.pinned, n.archived, TagCodec.encode(n.tags), TaskCodec.encode(n.task?.let { task -> task.copy(linkedNoteId = task.linkedNoteId?.takeIf { it in importedNoteIds }?.let { noteMap[it] }) }), SketchCodec.encodeInfo(n.sketch?.copy(linkedNoteId = n.sketch.linkedNoteId?.takeIf { it in importedTextIds }?.let { noteMap[it] }))))
                }
                data.drafts.forEach { d ->
                    dao.insertImportedDraft(DraftEntity(noteMap.getValue(d.id), d.title, it.notes.ecosystem.domain.Knowledge.remap(d.body,noteMap),
                        d.collectionId?.let { collectionMap.getValue(it) }, d.updatedAt, TagCodec.encode(d.tags)))
                }
            }
        }
    }
    override val notes = dao.observeNotes().map { rows -> rows.map { it.toDomain() } }.flowOn(Dispatchers.Default)
    override val collections = dao.observeCollections().map { rows -> rows.map { Collection(it.id, it.name) } }
    override suspend fun get(id: String) = writes.withLock { dao.get(id)?.toDomain() }
    override suspend fun save(id: String, title: String, body: String, collectionId: String?) = saveInternal(id, title, body, collectionId, null)
    override suspend fun saveTagged(id: String, title: String, body: String, collectionId: String?, tags: List<String>) =
        saveInternal(id, title, body, collectionId, TagCodec.encode(tags))
    private suspend fun saveInternal(id: String, title: String, body: String, collectionId: String?, tagsJson: String?) {
        writes.withLock { database.withTransaction {
            val old = dao.get(id)
            check(old?.deletedAt == null) { "La nota è nel cestino. Ripristinala prima di modificarla." }
            check(old?.taskJson == null && old?.sketchJson == null) { "Apri questa attività nella sezione Attività." }
            preserve(old)
            val now = System.currentTimeMillis()
            upsertLocal(old?.copy(title = title, body = body, collectionId = collectionId, updatedAt = now, tagsJson = tagsJson ?: old.tagsJson)
                ?: NoteEntity(id, title, body, collectionId, false, now, now, tagsJson = tagsJson ?: "[]"))
            dao.deleteDraft(id)
        } }
    }
    override suspend fun bulkEdit(expected: List<Note>, change: it.notes.ecosystem.domain.BulkChange): Int = writes.withLock {
        database.withTransaction {
            // Validate all rows before the first write; any failure rolls back the whole batch.
            require(expected.all { it.task == null }) { "Usa la sezione Attività per questi elementi." }
            val plan = it.notes.ecosystem.domain.planBulkEdit(expected, change, System.currentTimeMillis())
            if (change.action == it.notes.ecosystem.domain.BulkAction.MOVE && change.collectionId != null)
                check(dao.allCollections().any { it.id == change.collectionId }) { "Raccolta non più disponibile." }
            val current = expected.associate { snapshot ->
                val row = dao.get(snapshot.id) ?: error("Una nota non esiste più. Aggiorna la selezione.")
                check(!editors.containsKey(snapshot.id) && dao.getDraft(snapshot.id) == null) {
                    "Una nota è aperta o ha una bozza. Chiudi/salva le bozze prima di modificare il gruppo."
                }
                check(row.toDomain() == snapshot) { "Una nota è cambiata. Nessuna modifica applicata: seleziona di nuovo le note." }
                snapshot.id to row
            }
            var changed = 0
            plan.forEach { n ->
                val old = current.getValue(n.id)
                if (old.toDomain() != n) {
                    preserve(old)
                    upsertLocal(old.copy(collectionId = n.collectionId, favorite = n.favorite, pinned = n.pinned,
                        archived = n.archived, deletedAt = n.deletedAt, updatedAt = n.updatedAt, tagsJson = TagCodec.encode(n.tags)))
                    changed++
                }
            }
            changed
        }
    }
    override fun beginSketchEditing(id: String): Boolean = editors.putIfAbsent(id, 1) == null

    override fun beginWhiteboardEditing(id: String): Boolean = beginSketchEditing(id)

    override fun queueSketch(
        id: String,
        expectedBody: String?,
        title: String,
        body: String,
        info: it.notes.ecosystem.domain.SketchInfo,
    ): Deferred<Note> {
        require(info.kind == it.notes.ecosystem.domain.VisualDocumentKind.SKETCH)
        return queueVisual(id, expectedBody, title, body, info)
    }

    override fun queueWhiteboard(
        id: String,
        expectedBody: String?,
        title: String,
        body: String,
        info: it.notes.ecosystem.domain.SketchInfo,
    ): Deferred<Note> {
        require(info.kind == it.notes.ecosystem.domain.VisualDocumentKind.WHITEBOARD)
        return queueVisual(id, expectedBody, title, body, info)
    }

    private fun queueVisual(
        id: String,
        expectedBody: String?,
        title: String,
        body: String,
        info: it.notes.ecosystem.domain.SketchInfo,
    ): Deferred<Note> = writeScope.async {
        writes.withLock {
            database.withTransaction {
                withContext(Dispatchers.Default) {
                    when (info.kind) {
                        it.notes.ecosystem.domain.VisualDocumentKind.SKETCH -> SketchCodec.decodeDocument(body)
                        it.notes.ecosystem.domain.VisualDocumentKind.WHITEBOARD -> WhiteboardCodec.decode(body)
                    }
                    SketchCodec.info(info)
                }
                require(title.length <= 8000 && id.isNotBlank())
                val current = dao.get(id)
                val currentInfo = SketchCodec.decodeInfo(current?.sketchJson)
                check(
                    current?.body == expectedBody &&
                        (current == null || current.sketchJson != null && current.deletedAt == null && currentInfo?.kind == info.kind)
                ) {
                    "Documento visuale cambiato o non disponibile. Salva una copia per conservare le modifiche."
                }
                if (info.linkedNoteId != null && info.linkedNoteId != currentInfo?.linkedNoteId) {
                    check(
                        info.linkedNoteId != id && dao.get(info.linkedNoteId)?.let {
                            it.deletedAt == null && it.taskJson == null && it.sketchJson == null
                        } == true
                    ) { "Nota collegata non disponibile." }
                }
                val now = System.currentTimeMillis()
                val defaultTitle = when (info.kind) {
                    it.notes.ecosystem.domain.VisualDocumentKind.SKETCH -> "Nuovo disegno"
                    it.notes.ecosystem.domain.VisualDocumentKind.WHITEBOARD -> "Nuova lavagna"
                }
                val next = current?.copy(
                    title = title.ifBlank { "Senza titolo" },
                    body = body,
                    sketchJson = SketchCodec.encodeInfo(info),
                    updatedAt = now,
                ) ?: NoteEntity(
                    id = id,
                    title = title.ifBlank { defaultTitle },
                    body = body,
                    collectionId = null,
                    favorite = false,
                    createdAt = now,
                    updatedAt = now,
                    sketchJson = SketchCodec.encodeInfo(info),
                )
                val saved = upsertLocal(next)
                saved.toDomain()
            }
        }
    }

    override suspend fun savePlannedTask(expected: Note?, id: String, title: String, body: String, details: it.notes.ecosystem.domain.TaskDetails) {
        require(title.isNotBlank() && title.length <= 8000 && body.toByteArray(Charsets.UTF_8).size <= 32 * 1024)
        it.notes.ecosystem.domain.validateTask(details)
        writes.withLock { database.withTransaction {
            val current = dao.get(id)
            check(current?.toDomain() == expected) { "Attività cambiata: riaprila prima di salvare." }
            check(expected == null || expected.task != null && expected.deletedAt == null)
            check(!editors.containsKey(id) && dao.getDraft(id) == null) { "Elemento aperto o con bozza." }
            details.linkedNoteId?.let { linked ->
                check(linked != id && dao.get(linked)?.let { it.taskJson == null && it.deletedAt == null } == true) { "Nota collegata non disponibile." }
            }
            val now = System.currentTimeMillis()
            upsertLocal(if (current == null) NoteEntity(id, title.trim(), body, null, false, now, now, taskJson = TaskCodec.encode(details))
                else current.copy(title = title.trim(), body = body, taskJson = TaskCodec.encode(details), updatedAt = now))
        } }
    }
    override suspend fun updatePlannedTask(expected: Note, details: it.notes.ecosystem.domain.TaskDetails, deleted: Boolean) {
        require(expected.task != null); it.notes.ecosystem.domain.validateTask(details)
        writes.withLock { database.withTransaction {
            val current = dao.get(expected.id) ?: error("Attività mancante")
            check(current.toDomain() == expected) { "Attività cambiata: aggiorna e riprova." }
            check(!editors.containsKey(expected.id) && dao.getDraft(expected.id) == null)
            val now = System.currentTimeMillis()
            upsertLocal(current.copy(taskJson = TaskCodec.encode(details), updatedAt = now, deletedAt = if (deleted) now else null))
        } }
    }
    override suspend fun addFocusSession(id:String,session:it.notes.ecosystem.domain.FocusSession) {
        writes.withLock { database.withTransaction {
            val current=dao.get(id) ?: error("Attività non disponibile.")
            check(current.deletedAt==null && !editors.containsKey(id) && dao.getDraft(id)==null)
            val task=TaskCodec.decode(current.taskJson) ?: error("Non è un’attività.")
            val next=it.notes.ecosystem.domain.recordFocusSession(task,session)
            if(next!=task) upsertLocal(current.copy(taskJson=TaskCodec.encode(next),updatedAt=System.currentTimeMillis()))
        } }
    }
    override suspend fun snoozeReminder(id:String,expectedAt:Long,nextAt:Long):Boolean = writes.withLock {
        database.withTransaction {
            val current=dao.get(id) ?: return@withTransaction false
            val task=TaskCodec.decode(current.taskJson) ?: return@withTransaction false
            if(current.deletedAt!=null || current.archived || task.completedAt!=null || task.reminderAt!=expectedAt || editors.containsKey(id) || dao.getDraft(id)!=null) return@withTransaction false
            val next=it.notes.ecosystem.domain.validateTask(task.copy(reminderAt=nextAt,reminderTime=task.reminderTime ?: it.notes.ecosystem.domain.Reminders.display(expectedAt,task.reminderZone!!).takeLast(5)))
            upsertLocal(current.copy(taskJson=TaskCodec.encode(next),updatedAt=System.currentTimeMillis()));true
        }
    }
    override suspend fun addFocus(id: String, sessionId: String, seconds: Long) {
        writes.withLock { database.withTransaction {
            val current = dao.get(id) ?: error("Attività non disponibile.")
            check(current.deletedAt == null && !editors.containsKey(id) && dao.getDraft(id) == null)
            val task = TaskCodec.decode(current.taskJson) ?: error("Non è un’attività.")
            val next = it.notes.ecosystem.domain.recordFocus(task, sessionId, seconds)
            if (next != task) upsertLocal(current.copy(taskJson = TaskCodec.encode(next), updatedAt = System.currentTimeMillis()))
        } }
    }
    override suspend fun setTaskCompleted(id: String, expectedBody: String, lineIndex: Int, completed: Boolean) {
        writes.withLock {
            database.withTransaction {
                val old = dao.get(id) ?: error("Nota non trovata.")
                check(old.deletedAt == null) { "La nota è nel cestino." }
                check(dao.getDraft(id) == null) { "Questa nota ha una bozza: aprila e modifica la checklist nell'editor." }
                check(!old.archived) { "La nota è archiviata. Aprila dall’Archivio." }
                check(old.body == expectedBody) { "La nota è cambiata. Riprova dalla lista aggiornata." }
                val body = it.notes.ecosystem.domain.Checklist.setCompleted(old.body, lineIndex, completed)
                if (body != old.body) { preserve(old); upsertLocal(old.copy(body = body, updatedAt = System.currentTimeMillis())) }
            }
        }
    }
    override suspend fun setPinned(id: String, pinned: Boolean) = writes.withLock {
        database.withTransaction {
            val old = dao.get(id) ?: error("Nota non trovata.")
            check(old.deletedAt == null) { "La nota è nel cestino." }
            if (old.pinned != pinned) upsertLocal(old.copy(pinned = pinned, updatedAt = System.currentTimeMillis()))
        }
    }
    override suspend fun setArchived(id: String, archived: Boolean) = writes.withLock {
        database.withTransaction {
            val old = dao.get(id) ?: error("Nota non trovata.")
            check(old.deletedAt == null) { "La nota è nel cestino." }
            if (old.archived != archived) upsertLocal(old.copy(archived = archived, updatedAt = System.currentTimeMillis()))
        }
    }
    override suspend fun toggleFavorite(id: String) = writes.withLock { database.withTransaction {
        val old = dao.get(id) ?: error("Nota non trovata.")
        check(old.deletedAt == null) { "La nota è nel cestino." }
        upsertLocal(old.copy(favorite = !old.favorite, updatedAt = System.currentTimeMillis()))
    } }
    override suspend fun trash(id: String) = writes.withLock {
        database.withTransaction {
            val old = dao.get(id) ?: error("Nota non trovata.")
            preserve(old)
            if (old.deletedAt == null) upsertLocal(old.copy(deletedAt = System.currentTimeMillis(), updatedAt = System.currentTimeMillis()))
            dao.deleteDraft(id)
        }
    }
    override suspend fun restore(id: String) = writes.withLock { database.withTransaction {
        val old = dao.get(id) ?: error("Nota non trovata.")
        if (old.deletedAt != null) upsertLocal(old.copy(deletedAt = null, updatedAt = System.currentTimeMillis()))
    } }
    override suspend fun createCollection(name: String) { writes.withLock { database.withTransaction {
        val value = it.notes.ecosystem.domain.collectionName(name, dao.allCollections().map { Collection(it.id,it.name) })
        check(dao.addCollection(CollectionEntity(UUID.randomUUID().toString(), value)) != -1L) {
            "Esiste già una raccolta con questo nome."
        }
    } } }
    override suspend fun renameCollection(expected: Collection, name: String) { writes.withLock { database.withTransaction {
        val collections = dao.allCollections().map { Collection(it.id,it.name) }
        check(collections.firstOrNull { it.id == expected.id } == expected) { "La raccolta è cambiata. Riapri il pannello." }
        val value = it.notes.ecosystem.domain.collectionName(name,collections,expected.id)
        if(value != expected.name) {
            dao.renameCollection(expected.id,value)
            // GitHubSync already observes collections; changing the name updates each derived SyncDocument.
        }
    } } }
    override suspend fun deleteEmptyCollection(expected: Collection) { writes.withLock { database.withTransaction {
        check(dao.allCollections().firstOrNull { it.id == expected.id }?.let { Collection(it.id,it.name) } == expected) {
            "La raccolta è cambiata. Riapri il pannello."
        }
        check(editors.isEmpty()) { "Chiudi gli editor prima di eliminare una raccolta." }
        check(dao.allNotes().none { it.collectionId == expected.id } && dao.allDrafts().none { it.collectionId == expected.id }) {
            "La raccolta contiene elementi, anche archiviati, nel cestino o in bozza. Spostali prima di eliminarla."
        }
        check(dao.collectionRevisionCount(expected.id) == 0) { "La raccolta è ancora usata nella cronologia locale: viene conservata per il ripristino delle versioni." }
        dao.deleteCollection(expected.id)
    } } }

    suspend fun cloudDocument(id: String, accountId: String): SyncDocument? = writes.withLock { database.withTransaction {
        val row = dao.get(id)?.takeIf { it.visibility == "PRIVATE" && it.cloudAccountId == accountId } ?: return@withTransaction null
        val collection = dao.allCollections().firstOrNull { it.id == row.collectionId }?.name
        SyncDocument.from(row.toDomain(), collection)
    } }

    suspend fun markCloudSynced(id: String, accountId: String, expectedUpdatedAt: Long, revision: Long, updatedBy: String?): Boolean = writes.withLock {
        database.withTransaction {
            val row = dao.get(id) ?: return@withTransaction false
            if (row.visibility != "PRIVATE" || row.cloudAccountId != accountId) return@withTransaction false
            if (row.updatedAt == expectedUpdatedAt) {
                dao.upsert(row.copy(remoteRevision = revision, updatedBy = updatedBy, cloudState = "CLEAN"))
                cloudDao.removeOutbox(id, accountId)
            } else {
                dao.upsert(row.copy(remoteRevision = revision, updatedBy = updatedBy, cloudState = "DIRTY"))
                cloudDao.enqueue(SyncOutboxEntity(id, accountId, "UPSERT", revision, System.currentTimeMillis()))
            }
            true
        }
    }

    suspend fun applyCloudRemote(accountId: String, remote: it.notes.ecosystem.cloud.CloudRemoteRecord): Boolean = writes.withLock {
        database.withTransaction {
            val current = dao.get(remote.id)
            if (editors.containsKey(remote.id) || dao.getDraft(remote.id) != null) return@withTransaction false
            if (current?.cloudAccountId != null && current.cloudAccountId != accountId) return@withTransaction false
            if (current?.cloudState == "CONFLICT") return@withTransaction false
            if (current?.cloudState == "DIRTY" && remote.revision > current.remoteRevision) return@withTransaction false
            val collectionId = remote.document.collection?.let { name ->
                dao.allCollections().firstOrNull { it.name == name }?.id ?: UUID.randomUUID().toString().also {
                    check(dao.addCollection(CollectionEntity(it, name)) != -1L)
                }
            }
            preserve(current)
            val d = remote.document
            dao.upsert(NoteEntity(
                id = d.id, title = d.title, body = d.body, collectionId = collectionId, favorite = d.favorite,
                createdAt = d.createdAt, updatedAt = d.updatedAt, deletedAt = d.deletedAt, pinned = d.pinned, archived = d.archived,
                tagsJson = TagCodec.encode(d.tags), taskJson = TaskCodec.encode(d.task), sketchJson = SketchCodec.encodeInfo(d.sketch),
                visibility = "PRIVATE", spaceId = null, cloudAccountId = accountId, remoteRevision = remote.revision,
                updatedBy = remote.updatedBy, cloudState = "CLEAN",
            ))
            cloudDao.removeOutbox(remote.id, accountId)
            true
        }
    }

    suspend fun cloudLocalState(id: String): NoteEntity? = writes.withLock { dao.get(id) }


}

private fun NoteEntity.toDomain() = Note(
    id, title, body, collectionId, favorite, createdAt, updatedAt, deletedAt, pinned, archived,
    TagCodec.decode(tagsJson), TaskCodec.decode(taskJson), SketchCodec.decodeInfo(sketchJson),
    it.notes.ecosystem.domain.NoteVisibility.valueOf(visibility), spaceId, cloudAccountId, remoteRevision, updatedBy,
    it.notes.ecosystem.domain.CloudState.valueOf(cloudState),
)

private fun DraftEntity.toDomain() = Draft(id, title, body, collectionId, updatedAt, TagCodec.decode(tagsJson))

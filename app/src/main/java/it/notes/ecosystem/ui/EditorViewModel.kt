package it.notes.ecosystem.ui

import androidx.compose.runtime.*
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import it.notes.ecosystem.data.ContentBlockStore
import it.notes.ecosystem.domain.*
import it.notes.ecosystem.domain.Collection
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.first

class EditorViewModel(
    private val repository: NotesRepository,
    state: SavedStateHandle,
    captureSeed: CaptureSeed? = null,
    private val blockStore: ContentBlockStore? = null,
) : ViewModel() {
    val noteId: String get() = id
    private val id: String = checkNotNull(state["id"])
    var title by mutableStateOf("")
        private set
    var body by mutableStateOf("")
        private set
    var collectionId by mutableStateOf<String?>(null)
        private set
    var tags by mutableStateOf<List<String>>(emptyList())
        private set
    var dirty by mutableStateOf(false)
        private set
    var loading by mutableStateOf(true)
        private set
    var saving by mutableStateOf(false)
        private set
    var error by mutableStateOf<String?>(null)
        private set
    var available by mutableStateOf(false)
        private set
    var draftStatus by mutableStateOf("Usa Salva per conservare l’appunto")
        private set
    var revisions by mutableStateOf<List<NoteRevision>>(emptyList())
        private set
    var historyLoading by mutableStateOf(false)
        private set
    var checklistWorking by mutableStateOf(false)
        private set
    var mediaBusy by mutableStateOf(false)
        private set

    var blockMode by mutableStateOf(false)
        private set
    var blocks by mutableStateOf<List<ContentBlock>>(emptyList())
        private set
    var blocksLoading by mutableStateOf(false)
        private set
    private var blocksInitialized = false
    private var blocksStaleFromBody = false

    private var draftDebounceJob: Job? = null
    private var pendingDraftSnapshot: Draft? = null
    private var lastDraftWrite: kotlinx.coroutines.Deferred<Unit>? = null

    private companion object {
        const val DRAFT_DEBOUNCE_MS = 280L
    }

    val blockEditingEnabled: Boolean
        get() = available && !loading && !saving && !checklistWorking && !mediaBusy && !blocksLoading

    fun enableBlockMode() {
        if (!available || saving || checklistWorking || mediaBusy || blocksLoading) return
        blocksLoading = true
        viewModelScope.launch {
            try {
                val stored =
                    if (!blocksInitialized) {
                        blockStore?.listNote(id).orEmpty()
                    } else {
                        blocks
                    }

                val source = withContext(Dispatchers.Default) {
                    val storedMarkdown =
                        if (stored.isEmpty()) null
                        else BlockEditorCodec.toMarkdown(stored)

                    if (
                        !blocksStaleFromBody &&
                        stored.isNotEmpty() &&
                        storedMarkdown == body
                    ) {
                        stored
                    } else {
                        BlockEditorCodec.parse(id, body)
                    }
                }

                blocks =
                    source.ifEmpty {
                        listOf(BlockEditorCodec.emptyTextBlock(id))
                    }

                blocksInitialized = true
                blocksStaleFromBody = false
                blockMode = true
                error = null
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                error = e.message ?: "Impossibile aprire l'editor a blocchi."
            } finally {
                blocksLoading = false
            }
        }
    }

    fun disableBlockMode() {
        if (saving || blocksLoading) return
        blockMode = false
    }

    private fun commitBlocks(source: List<ContentBlock>) {
        if (!blockEditingEnabled || !blocksInitialized) return
        val normalized = BlockEditorCodec.canonicalize(
            noteId = id,
            blocks = source.ifEmpty { listOf(BlockEditorCodec.emptyTextBlock(id)) },
        )
        blocks = normalized
        val nextBody = BlockEditorCodec.toMarkdown(normalized)
        if (body != nextBody) {
            body = nextBody
            blocksStaleFromBody = false
            rememberDraft()
        }
    }

    fun updateBlockText(blockId: String, value: String) {
        if (!blockEditingEnabled) return
        val index = blocks.indexOfFirst { it.id == blockId }
        if (index < 0) return
        val old = blocks[index]
        if (old.text == value) return
        val next = blocks.toMutableList()
        next[index] = old.copy(text = value, updatedAt = System.currentTimeMillis())
        blocks = next
        val nextBody = BlockEditorCodec.toMarkdown(next)
        if (body != nextBody) {
            body = nextBody
            blocksStaleFromBody = false
            rememberDraft()
        }
    }

    fun setBlockChecked(blockId: String, checked: Boolean) {
        if (!blockEditingEnabled) return
        val next = blocks.map { block ->
            if (block.id == blockId && block.type in listOf(ContentBlockType.CHECKLIST, ContentBlockType.TASK)) {
                block.copy(checked = checked)
            } else block
        }
        if (next != blocks) commitBlocks(next)
    }

    fun changeBlockType(blockId: String, type: ContentBlockType) {
        if (!blockEditingEnabled) return
        val next = blocks.map { block ->
            if (block.id == blockId) BlockEditorCodec.changeType(block, type) else block
        }
        if (next != blocks) commitBlocks(next)
    }

    fun setBlockHeadingLevel(blockId: String, level: Int) {
        if (!blockEditingEnabled) return
        val next = blocks.map { block ->
            if (block.id == blockId) BlockEditorCodec.withHeadingLevel(block, level) else block
        }
        if (next != blocks) commitBlocks(next)
    }

    fun addBlock(type: ContentBlockType, afterBlockId: String? = null) {
        if (!blockEditingEnabled) return
        val insertAt = afterBlockId
            ?.let { key -> blocks.indexOfFirst { it.id == key }.takeIf { it >= 0 }?.plus(1) }
            ?: blocks.size
        val next = blocks.toMutableList()
        next.add(insertAt.coerceIn(0, next.size), BlockEditorCodec.newBlock(id, type, insertAt))
        commitBlocks(next)
    }

    fun duplicateBlock(blockId: String) {
        if (!blockEditingEnabled) return
        val sourceIndex = blocks.indexOfFirst { it.id == blockId }
        if (sourceIndex < 0) return
        val source = blocks[sourceIndex]
        val now = System.currentTimeMillis()
        val copy = source.copy(
            id = java.util.UUID.randomUUID().toString(),
            position = sourceIndex + 1,
            createdAt = now,
            updatedAt = now,
        )
        val next = blocks.toMutableList()
        next.add(sourceIndex + 1, copy)
        commitBlocks(next)
    }

    fun deleteBlock(blockId: String) {
        if (!blockEditingEnabled) return
        commitBlocks(blocks.filterNot { it.id == blockId })
    }

    fun moveBlock(blockId: String, delta: Int) {
        if (!blockEditingEnabled || delta == 0) return
        val from = blocks.indexOfFirst { it.id == blockId }
        if (from < 0) return
        val to = (from + delta).coerceIn(0, blocks.lastIndex)
        if (from == to) return
        val next = blocks.toMutableList()
        val moved = next.removeAt(from)
        next.add(to, moved)
        commitBlocks(next)
    }

    fun attachSketchToBlock(blockId: String, sketchId: String, title: String = "Disegno") {
        if (!blockEditingEnabled || sketchId.isBlank()) return
        val next = blocks.map { block ->
            if (block.id != blockId) block
            else block.copy(
                type = ContentBlockType.DRAWING,
                text = block.text.ifBlank { title.ifBlank { "Disegno" } },
                metadataJson = BlockEditorCodec.drawingMetadata(sketchId),
                updatedAt = System.currentTimeMillis(),
            )
        }
        if (next != blocks) commitBlocks(next)
    }

    fun drawingBlock(blockId: String): ContentBlock? =
        blocks.firstOrNull { it.id == blockId && it.type == ContentBlockType.DRAWING }

    fun attachWhiteboardToBlock(blockId: String, whiteboardId: String, title: String = "Lavagna") {
        if (!blockEditingEnabled || whiteboardId.isBlank()) return
        val index = blocks.indexOfFirst { it.id == blockId }
        if (index < 0) return
        val source = blocks[index]
        val next = blocks.toMutableList()
        next[index] = source.copy(
            type = ContentBlockType.WHITEBOARD,
            text = title.ifBlank { "Lavagna" },
            checked = null,
            metadataJson = BlockEditorCodec.whiteboardMetadata(whiteboardId),
            updatedAt = System.currentTimeMillis(),
        )
        commitBlocks(next)
    }

    fun whiteboardId(blockId: String): String? =
        blocks.firstOrNull {
            it.id == blockId && it.type == ContentBlockType.WHITEBOARD
        }?.let(BlockEditorCodec::whiteboardId)

    fun setAttachmentWork(value: Boolean) { mediaBusy = value }
    fun attach(key: String, name: String): Boolean {
        if (!available || saving || checklistWorking) return false
        return try {
            body = Attachments.append(body, key, name)
            if (blocksInitialized) {
                blocksStaleFromBody = true
            }
            rememberDraft()
            true
        } catch (e: Exception) {
            error = e.message
            false
        }
    }
    private var attachmentDraftWrite: kotlinx.coroutines.Deferred<Unit>? = null
    suspend fun awaitAttachmentDraft() { attachmentDraftWrite?.await() }
    private var revision = 0
    fun loadHistory() {
        if (historyLoading) return
        historyLoading = true
        viewModelScope.launch {
            try { revisions = repository.history(id) }
            catch (e: CancellationException) { throw e }
            catch (e: Exception) { error = "Impossibile leggere la cronologia." }
            finally { historyLoading = false }
        }
    }
    fun useRevision(item: NoteRevision, collections: List<Collection>): Boolean {
        if (dirty || saving || checklistWorking || mediaBusy || !available || item.noteId != id) return false
        title = item.title; body = item.body; tags = item.tags
        if (blocksInitialized) {
            blocksStaleFromBody = true
        }
        collectionId = item.collectionId?.takeIf { candidate -> collections.any { it.id == candidate } }
        rememberDraft()
        return true
    }
    fun editChecklist(expected: String, operation: (String) -> String) {
        if (!available || saving || checklistWorking || mediaBusy || body != expected) return
        checklistWorking = true
        viewModelScope.launch {
            try {
                val result = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) { operation(expected) }
                check(body == expected && !saving) { "La nota è cambiata. Riprova." }
                if (result != body) { body = result; rememberDraft() }
            } catch (e: CancellationException) { throw e }
            catch (e: Exception) { error = e.message ?: "Modifica non riuscita." }
            finally { checklistWorking = false }
        }
    }
    fun duplicate() {
        if (!available || saving || checklistWorking || mediaBusy) return
        val copyTitle = title.ifBlank { "Lista" } + " (copia)"
        val copyBody = body; val copyCollection = collectionId; val copyTags = tags.toList()
        saving = true
        viewModelScope.launch {
            try {
                SaveNote(repository)(java.util.UUID.randomUUID().toString(), copyTitle, copyBody, copyCollection, copyTags)
                draftStatus = "Copia creata nella libreria."
            } catch (e: CancellationException) { throw e }
            catch (e: Exception) { error = e.message ?: "Duplicazione non riuscita." }
            finally { saving = false }
        }
    }

    fun assignDiaryDate(value: java.time.LocalDate?): Boolean {
        if (!available || saving || checklistWorking || mediaBusy) return false
        return try { tags = Diary.datedTags(tags, value); rememberDraft(); true }
        catch (e: Exception) { error = e.message; false }
    }
    fun saveAsTemplate() {
        if (!available || saving || checklistWorking || mediaBusy) return
        val content = try { PersonalTemplates.capture(title, body, tags) }
        catch (e: Exception) { error = e.message; return }
        saving = true
        viewModelScope.launch {
            try {
                repository.createTemplate(content)
                draftStatus = "Modello creato: lo trovi in Crea → Modelli."
            } catch (e: CancellationException) { throw e }
            catch (e: Exception) { error = e.message ?: "Modello non salvato." }
            finally { saving = false }
        }
    }

    private fun draftSnapshot(): Draft =
        Draft(
            id = id,
            title = title,
            body = body,
            collectionId = collectionId,
            updatedAt = System.currentTimeMillis(),
            tags = tags,
        )

    private fun submitDraft(
        snapshot: Draft,
        token: Int,
    ) {
        val write = repository.queueDraft(snapshot)
        lastDraftWrite = write
        attachmentDraftWrite = write

        viewModelScope.launch {
            try {
                write.await()

                if (token == revision) {
                    draftStatus = "Bozza conservata sul dispositivo"
                    error = null
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (token == revision) {
                    draftStatus =
                        "Bozza non memorizzata: premi Salva per riprovare"
                    error =
                        e.message ?: "Errore di scrittura della bozza."
                }
            }
        }
    }

    private fun rememberDraft(
        immediate: Boolean = false,
    ) {
        dirty = true
        val token = ++revision
        val snapshot = draftSnapshot()
        pendingDraftSnapshot = snapshot
        draftStatus = "Memorizzazione bozza…"

        draftDebounceJob?.cancel()
        draftDebounceJob = null

        if (immediate) {
            submitDraft(snapshot, token)
        } else {
            draftDebounceJob = viewModelScope.launch {
                delay(DRAFT_DEBOUNCE_MS)

                if (
                    token == revision &&
                    pendingDraftSnapshot == snapshot
                ) {
                    submitDraft(snapshot, token)
                }
            }
        }
    }

    override fun onCleared() {
        draftDebounceJob?.cancel()

        if (dirty && !saving) {
            pendingDraftSnapshot?.let { repository.queueDraft(it) }
        }

        repository.endEditing(id)
        super.onCleared()
    }

    init {
        repository.beginEditing(id)
        viewModelScope.launch {
            try {
                val existing = repository.get(id)
                check(existing?.task == null && existing?.sketch == null) { "Apri questa attività dalla sezione Attività." }
                val restoredDraft = repository.getDraft(id)
                // Recover the destination draft before reading a source that may have changed/deleted.
                val content = if (existing == null && restoredDraft == null && state.get<Boolean>("new") == true && captureSeed == null) {
                    val instant = state.get<Long>("templateTime") ?: System.currentTimeMillis().also { state["templateTime"] = it }
                    val zone = state.get<String>("templateZone") ?: java.time.ZoneId.systemDefault().id.also { state["templateZone"] = it }
                    val now = java.time.Instant.ofEpochMilli(instant).atZone(java.time.ZoneId.of(zone))
                    val key = state.get<String>("template").orEmpty()
                    val reset = state.get<Boolean>("reset") ?: true
                    if (key.startsWith("personal:")) {
                        val source = repository.get(key.removePrefix("personal:")) ?: error("Modello non trovato.")
                        PersonalTemplates.from(source, now, reset)
                    } else {
                        val day = state.get<String>("day")?.takeIf { it.isNotBlank() }?.let { java.time.LocalDate.parse(it) }
                        val template = if (day != null) { check(id == PageTemplates.dailyId(day)); PageTemplates.daily(day) }
                        else PageTemplates.all.firstOrNull { it.key == key }
                        template?.let { PersonalTemplates.instantiate(it.title, it.body, emptyList(), now, reset) }
                    }
                } else null
                val diaryDate = if (existing == null && restoredDraft == null && state.get<Boolean>("new") == true)
                    (state.get<String>("diary")?.takeIf { it.isNotBlank() } ?: state.get<String>("day")?.takeIf { it.isNotBlank() })?.let(Diary::validDate) else null
                val diaryBook = if (diaryDate != null) state.get<String>("book")?.takeIf { it.isNotBlank() }?.takeIf { book -> repository.collections.first().any { it.id == book } } else null
                val seed = captureSeed ?: content?.let { CaptureSeed(it.title, it.body) }
                ?: diaryDate?.let { CaptureSeed("${if (state.get<Boolean>("media") == true) "Ricordo" else "Pensieri"} · $it", "") }
                val seedTags = if (diaryDate != null) Diary.datedTags(content?.tags.orEmpty(), diaryDate) else content?.tags.orEmpty()
                val draft = restoredDraft ?: if (existing == null && seed?.hasContent == true) {
                    Draft(id, seed.title, seed.body, diaryBook, System.currentTimeMillis(), seedTags)
                } else null
                check(existing?.deletedAt == null) { "Questa nota è nel cestino." }
                check(existing != null || draft != null || state.get<Boolean>("new") == true) { "Nota non trovata." }
                title = draft?.title ?: existing?.title ?: ""
                body = draft?.body ?: existing?.body ?: ""
                collectionId = if (draft != null) draft.collectionId else existing?.collectionId
                tags = draft?.tags ?: existing?.tags ?: emptyList()
                dirty = draft != null
                if (dirty) draftStatus = "Bozza recuperata dal dispositivo"
                available = true
                if (restoredDraft == null && existing == null && draft != null) rememberDraft()
            } catch (e: CancellationException) { throw e }
            catch (e: Exception) { error = e.message ?: "Impossibile aprire la nota." }
            finally { loading = false }
        }
    }

    fun addTag(raw: String): Boolean {
        if (!available || saving || checklistWorking || mediaBusy) return false
        return try {
            require(!Tags.name(raw).startsWith("diario_")) { "Per cambiare la data usa il pulsante Giorno." }
            val next = Tags.add(tags, raw)
            if (next != tags) { tags = next; rememberDraft() }
            true
        } catch (e: IllegalArgumentException) { error = e.message; false }
    }
    fun removeTag(tag: String) {
        if (!available || saving || checklistWorking || mediaBusy || tag !in tags) return
        tags = tags.filterNot { it == tag }; rememberDraft()
    }
    fun editTitle(value: String) { if (available && !saving && !checklistWorking && !mediaBusy) { title = value; rememberDraft() } }
    fun editBody(value: String) {
        if (
            available &&
            !saving &&
            !checklistWorking &&
            !mediaBusy
        ) {
            if (body == value) return

            body = value

            /*
             * Se l'utente sta scrivendo nel Markdown editor non parsare
             * l'intero documento ad ogni carattere.
             * I blocchi verranno riallineati quando serve davvero.
             */
            if (blocksInitialized) {
                blocksStaleFromBody = true
            }

            rememberDraft()
        }
    }

    fun applyCapturedBody(
        value: String,
    ): Boolean {
        if (
            !available ||
            saving ||
            checklistWorking
        ) {
            return false
        }

        if (body == value) return true

        body = value

        if (blocksInitialized) {
            blocksStaleFromBody = true
        }

        /*
         * Smart Capture è già un'operazione esplicita:
         * persistiamo subito il risultato per sicurezza.
         */
        rememberDraft(immediate = true)

        return true
    }

    fun assignCollection(value: String?) { if (available && !saving && !checklistWorking && !mediaBusy) { collectionId = value; rememberDraft() } }
    fun addTask(label: String): Boolean {
        if (!available || saving || checklistWorking || mediaBusy) return false
        return try {
            if (blockMode && blocksInitialized) {
                val clean = label.trim()
                require(clean.isNotEmpty()) { "Scrivi un'attività." }
                val next = blocks.toMutableList()
                next += BlockEditorCodec.newBlock(id, ContentBlockType.CHECKLIST, next.size, clean)
                commitBlocks(next)
            } else {
                editBody(Checklist.append(body, label))
            }
            true
        } catch (e: IllegalArgumentException) {
            error = e.message
            false
        }
    }
    fun completeTask(expectedBody: String, lineIndex: Int, completed: Boolean) {
        if (!available || saving || checklistWorking || mediaBusy) return
        try {
            check(body == expectedBody) { "Il testo è cambiato. Riprova." }
            editBody(Checklist.setCompleted(body, lineIndex, completed))
        } catch (e: IllegalStateException) { error = e.message }
    }
    fun save(onSaved: () -> Unit) = finish(onSaved) {
        SaveNote(repository)(id, title, body, collectionId, tags)
        if (blocksInitialized && blockStore != null) {
            val normalized = BlockEditorCodec.canonicalize(
                noteId = id,
                blocks = blocks.ifEmpty { BlockEditorCodec.parse(id, body) },
            )
            // Persistiamo la rappresentazione strutturata DOPO il salvataggio canonico della nota.
            // Se questa scrittura fallisce, notes.body resta valido e alla prossima apertura i blocchi
            // verranno rigenerati automaticamente dal Markdown.
            blockStore.replaceNoteBlocks(id, normalized)
            blocks = normalized
        }
    }
    fun discard(onDiscarded: () -> Unit) = finish(onDiscarded) { repository.discardDraft(id) }

    private fun finish(onSuccess: () -> Unit, block: suspend () -> Unit) {
        if (loading || saving || checklistWorking || mediaBusy || !available) return
        saving = true
        error = null

        draftDebounceJob?.cancel()
        draftDebounceJob = null

        viewModelScope.launch {
            try {
                lastDraftWrite?.let { pending ->
                    runCatching { pending.await() }
                }

                block()
                dirty = false
                ++revision
                onSuccess()
            } catch (e: CancellationException) { throw e }
            catch (e: Exception) { error = e.message ?: "Operazione non riuscita. Riprova." }
            finally { saving = false }
        }
    }
}

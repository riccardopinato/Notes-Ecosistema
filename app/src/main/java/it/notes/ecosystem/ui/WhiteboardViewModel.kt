package it.notes.ecosystem.ui

import androidx.compose.runtime.*
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import it.notes.ecosystem.data.WhiteboardCodec
import it.notes.ecosystem.domain.*
import kotlinx.coroutines.*

class WhiteboardViewModel(
    private val repository: NotesRepository,
    state: SavedStateHandle,
) : ViewModel() {

    val id: String = checkNotNull(state["id"])

    private val initialMindMap: Boolean =
        state.get<Boolean>("mind") == true

    var document by mutableStateOf(
        WhiteboardOps.empty(
            if (initialMindMap) {
                WhiteboardMode.MIND_MAP
            } else {
                WhiteboardMode.FREEFORM
            }
        )
    )
        private set

    var title by mutableStateOf(
        if (initialMindMap) "Nuova mappa mentale"
        else "Nuova lavagna"
    )
        private set

    var info by mutableStateOf(
        SketchInfo(
            linkedNoteId = state.get<String>("linked"),
            kind = VisualDocumentKind.WHITEBOARD,
        )
    )
        private set

    var ready by mutableStateOf(false)
        private set

    var status by mutableStateOf("Apertura…")
        private set

    var error by mutableStateOf<String?>(null)
        private set

    var canUndo by mutableStateOf(false)
        private set

    var canRedo by mutableStateOf(false)
        private set

    private val undo = ArrayDeque<WhiteboardDocument>()
    private val redo = ArrayDeque<WhiteboardDocument>()

    private var expectedBody: String? = null
    private var persistedTitle: String? = null
    private var persistedInfo: SketchInfo? = null

    private var pending: Deferred<Note>? = null
    private var persistJob: Job? = null
    private var serial = 0

    private val owned =
        repository.beginWhiteboardEditing(id)

    private companion object {
        const val PERSIST_DEBOUNCE_MS = 180L
    }

    init {
        viewModelScope.launch {
            try {
                check(owned) {
                    "Lavagna già aperta in un altro editor."
                }

                val note = repository.get(id)

                check(
                    note == null ||
                        note.sketch?.kind == VisualDocumentKind.WHITEBOARD &&
                        note.deletedAt == null
                ) {
                    "Lavagna non disponibile."
                }

                if (note != null) {
                    document =
                        withContext(Dispatchers.Default) {
                            WhiteboardCodec.decode(note.body)
                        }
                    title = note.title
                    info = checkNotNull(note.sketch)
                    expectedBody = note.body
                    persistedTitle = note.title
                    persistedInfo = note.sketch
                }

                ready = true
                status = "Salvato sul dispositivo"

                if (note == null) {
                    persist(immediate = true)
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                status = "Apertura non riuscita"
                error = e.message
            }
        }
    }

    fun warn(message: String) {
        error = message
    }

    fun rename(value: String) {
        if (!ready || value.length > 8000) return
        val next = value.ifBlank { "Senza titolo" }
        if (next == title) return
        title = next
        persist()
    }

    fun link(value: String?) {
        if (!ready) return
        val next = info.copy(linkedNoteId = value)
        if (next == info) return
        info = next
        persist()
    }

    fun commit(
        next: WhiteboardDocument,
        addUndo: Boolean = true,
    ) {
        if (!ready || next == document) return

        val valid = WhiteboardRules.validate(next)

        if (addUndo) {
            undo.addLast(document)
            while (undo.size > 40) {
                undo.removeFirst()
            }
            redo.clear()
        }

        document = valid
        flags()
        persist()
    }

    fun updateCamera(camera: WhiteboardCamera) {
        val next = document.copy(
            camera = camera.copy(
                zoom = camera.zoom.coerceIn(
                    WhiteboardRules.MIN_ZOOM,
                    WhiteboardRules.MAX_ZOOM,
                )
            )
        )

        /*
         * Camera non deve riempire l'undo stack.
         */
        commit(next, addUndo = false)
    }

    fun setMode(mode: WhiteboardMode) {
        commit(
            WhiteboardOps.setMode(
                document,
                mode,
            )
        )
    }

    fun addSticky() {
        commit(
            WhiteboardOps.addNode(
                source = document,
                kind = BoardNodeKind.STICKY,
                text = "Nuova nota",
                x = document.camera.x.toInt() - 130,
                y = document.camera.y.toInt() - 80,
            )
        )
    }

    fun addText() {
        commit(
            WhiteboardOps.addNode(
                source = document,
                kind = BoardNodeKind.TEXT,
                text = "Testo",
                x = document.camera.x.toInt() - 130,
                y = document.camera.y.toInt() - 60,
                color = 0xFFFFFFFF.toInt(),
            )
        )
    }

    fun addLinked(
        note: Note,
    ) {
        require(note.deletedAt == null)

        val kind =
            if (note.task != null) {
                BoardNodeKind.TASK_LINK
            } else {
                BoardNodeKind.NOTE_LINK
            }

        commit(
            WhiteboardOps.addNode(
                source = document,
                kind = kind,
                text = note.title.ifBlank {
                    if (kind == BoardNodeKind.TASK_LINK) "Attività"
                    else "Nota"
                },
                x = document.camera.x.toInt() - 130,
                y = document.camera.y.toInt() - 80,
                color =
                    if (kind == BoardNodeKind.TASK_LINK) {
                        0xFFE8F5E9.toInt()
                    } else {
                        0xFFE8EEFF.toInt()
                    },
                linkedNoteId = note.id,
            )
        )
    }

    fun updateNode(node: BoardNode) {
        commit(
            WhiteboardOps.updateNode(
                document,
                node,
            )
        )
    }

    fun deleteNode(id: String) {
        commit(
            WhiteboardOps.deleteNode(
                document,
                id,
            )
        )
    }

    fun addMindChild(
        parentId: String,
    ) {
        runCatching {
            WhiteboardOps.addMindChild(
                document,
                parentId,
            )
        }
            .onSuccess(::commit)
            .onFailure {
                error = it.message
            }
    }

    fun autoLayoutMindMap() {
        commit(
            WhiteboardOps.autoLayoutMindMap(
                document
            )
        )
    }

    fun undo() {
        if (!ready || undo.isEmpty()) return
        redo.addLast(document)
        document = undo.removeLast()
        flags()
        persist()
    }

    fun redo() {
        if (!ready || redo.isEmpty()) return
        undo.addLast(document)
        document = redo.removeLast()
        flags()
        persist()
    }

    private fun flags() {
        canUndo = undo.isNotEmpty()
        canRedo = redo.isNotEmpty()
    }

    private fun persist(
        immediate: Boolean = false,
    ) {
        if (!ready) return

        val version = ++serial
        val snapshotDocument = document
        val snapshotTitle = title
        val snapshotInfo = info

        status = "Salvataggio…"
        error = null

        persistJob?.cancel()

        persistJob = viewModelScope.launch {
            if (!immediate) {
                delay(PERSIST_DEBOUNCE_MS)
            }

            persistSnapshot(
                version,
                snapshotDocument,
                snapshotTitle,
                snapshotInfo,
            )
        }
    }

    private suspend fun persistSnapshot(
        version: Int,
        snapshotDocument: WhiteboardDocument,
        snapshotTitle: String,
        snapshotInfo: SketchInfo,
    ) {
        try {
            val body =
                withContext(Dispatchers.Default) {
                    WhiteboardCodec.encode(snapshotDocument)
                }

            pending?.let { previous ->
                val saved = previous.await()
                expectedBody = saved.body
                persistedTitle = saved.title
                persistedInfo = saved.sketch
            }

            val normalizedTitle =
                snapshotTitle.ifBlank { "Senza titolo" }

            if (
                expectedBody == body &&
                persistedTitle == normalizedTitle &&
                persistedInfo == snapshotInfo
            ) {
                if (version == serial) {
                    status = "Salvato sul dispositivo"
                }
                return
            }

            val write = repository.queueWhiteboard(
                id = id,
                expectedBody = expectedBody,
                title = snapshotTitle,
                body = body,
                info = snapshotInfo,
            )

            pending = write
            val saved = write.await()
            expectedBody = saved.body
            persistedTitle = saved.title
            persistedInfo = saved.sketch

            if (version == serial) {
                status = "Salvato sul dispositivo"
                error = null
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (version == serial) {
                status = "Non salvato"
                error = e.message
            }
        }
    }

    private suspend fun flushCurrent() {
        persistJob?.cancelAndJoin()
        persistJob = null

        pending?.let { previous ->
            val saved = previous.await()
            expectedBody = saved.body
            persistedTitle = saved.title
            persistedInfo = saved.sketch
        }

        val snapshotDocument = document
        val snapshotTitle = title
        val snapshotInfo = info

        val body =
            withContext(Dispatchers.Default) {
                WhiteboardCodec.encode(snapshotDocument)
            }

        val normalizedTitle =
            snapshotTitle.ifBlank { "Senza titolo" }

        if (
            expectedBody == body &&
            persistedTitle == normalizedTitle &&
            persistedInfo == snapshotInfo
        ) {
            status = "Salvato sul dispositivo"
            return
        }

        val saved = repository.queueWhiteboard(
            id = id,
            expectedBody = expectedBody,
            title = snapshotTitle,
            body = body,
            info = snapshotInfo,
        ).await()

        expectedBody = saved.body
        persistedTitle = saved.title
        persistedInfo = saved.sketch
        status = "Salvato sul dispositivo"
    }

    fun close(onClosed: () -> Unit) {
        if (!ready) {
            onClosed()
            return
        }

        viewModelScope.launch {
            try {
                flushCurrent()
                onClosed()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                status = "Non salvato"
                error =
                    "Salvataggio non riuscito: salva una copia prima di uscire."
            }
        }
    }

    fun saveCopy(
        onSaved: (String) -> Unit,
    ) {
        if (!ready) return

        val snapshot = document
        val snapshotTitle = title
        val snapshotInfo = info.copy(
            linkedNoteId = null,
            kind = VisualDocumentKind.WHITEBOARD,
        )

        viewModelScope.launch {
            try {
                val body =
                    withContext(Dispatchers.Default) {
                        WhiteboardCodec.encode(snapshot)
                    }

                val newId =
                    java.util.UUID.randomUUID().toString()

                repository.queueWhiteboard(
                    id = newId,
                    expectedBody = null,
                    title = "$snapshotTitle (copia)",
                    body = body,
                    info = snapshotInfo,
                ).await()

                onSaved(newId)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                error = e.message
            }
        }
    }

    override fun onCleared() {
        persistJob?.cancel()

        if (owned) {
            repository.endEditing(id)
        }

        super.onCleared()
    }
}

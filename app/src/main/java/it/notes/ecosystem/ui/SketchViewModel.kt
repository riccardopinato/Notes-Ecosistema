package it.notes.ecosystem.ui

import androidx.compose.runtime.*
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import it.notes.ecosystem.data.SketchCodec
import it.notes.ecosystem.domain.*
import kotlinx.coroutines.*

class SketchViewModel(
    private val repository: NotesRepository,
    state: SavedStateHandle,
) : ViewModel() {

    val id: String = checkNotNull(state["id"])

    var document by mutableStateOf(SketchDocument())
        private set

    val page: SketchPage
        get() = document.page

    var title by mutableStateOf("Nuovo disegno")
        private set

    var info by mutableStateOf(
        SketchInfo(
            linkedNoteId = state.get<String>("linked"),
            kind = VisualDocumentKind.SKETCH,
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

    private val undo = ArrayDeque<SketchDocument>()
    private val redo = ArrayDeque<SketchDocument>()

    /**
     * Body realmente presente nel DB dopo l'ultima write completata.
     * È il valore usato dal repository per optimistic concurrency.
     */
    private var expectedBody: String? = null

    /**
     * Ultimo titolo/metadati confermati dal repository.
     * Servono per evitare write duplicate durante flush/close.
     */
    private var persistedTitle: String? = null
    private var persistedInfo: SketchInfo? = null

    /**
     * Deferred della write repository già partita.
     * Il repository possiede uno scope IO indipendente dal ViewModel:
     * cancellare un Job UI non deve annullare la write già accodata.
     */
    private var pending: Deferred<Note>? = null

    /**
     * Job di debounce/serializzazione corrente.
     */
    private var persistJob: Job? = null

    private var serial = 0

    private val owned =
        repository.beginSketchEditing(id)

    private companion object {
        const val SKETCH_PERSIST_DEBOUNCE_MS = 180L
    }

    init {
        viewModelScope.launch {
            try {
                check(owned) {
                    "Disegno già aperto in un altro editor."
                }

                val note = repository.get(id)

                check(
                    note == null ||
                        note.sketch?.kind == VisualDocumentKind.SKETCH &&
                        note.deletedAt == null
                ) {
                    "Disegno non disponibile."
                }

                if (note != null) {
                    document =
                        withContext(Dispatchers.Default) {
                            SketchCodec.decodeDocument(note.body)
                        }

                    title = note.title
                    info = note.sketch!!
                    expectedBody = note.body
                    persistedTitle = note.title
                    persistedInfo = note.sketch
                }

                ready = true
                status = "Salvato sul dispositivo"

                /*
                 * Uno sketch nuovo deve comunque creare il record persistente.
                 * Questo primo salvataggio non viene ritardato.
                 */
                if (note == null) {
                    persist(immediate = true)
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                error = e.message
                status = "Apertura non riuscita"
            }
        }
    }

    fun warn(message: String) {
        error = message
    }

    fun commitPage(next: SketchPage) {
        if (!ready || next == page) return

        commitDocument(
            SketchDocumentOps.replaceActive(
                document,
                next,
            )
        )
    }

    /** Alias temporaneo per eventuali caller legacy. */
    fun commit(next: SketchPage) =
        commitPage(next)

    private fun commitDocument(
        next: SketchDocument,
    ) {
        if (!ready || next == document) return

        /*
         * NON serializzare JSON qui.
         * SketchDocumentOps + limiti Canvas producono documenti validi;
         * la validazione definitiva avviene nel codec fuori dal main thread.
         */
        undo.addLast(document)

        while (undo.size > 40) {
            undo.removeFirst()
        }

        redo.clear()
        document = next
        flags()
        persist()
    }

    fun undo() {
        if (
            ready &&
            undo.isNotEmpty()
        ) {
            redo.addLast(document)
            document = undo.removeLast()
            flags()
            persist()
        }
    }

    fun redo() {
        if (
            ready &&
            redo.isNotEmpty()
        ) {
            undo.addLast(document)
            document = redo.removeLast()
            flags()
            persist()
        }
    }

    private fun flags() {
        canUndo = undo.isNotEmpty()
        canRedo = redo.isNotEmpty()
    }

    fun addPage() =
        runCatching {
            commitDocument(
                SketchDocumentOps.addPage(document)
            )
        }
            .onFailure {
                error = it.message
            }
            .let { Unit }

    fun duplicatePage() =
        runCatching {
            commitDocument(
                SketchDocumentOps.duplicatePage(document)
            )
        }
            .onFailure {
                error = it.message
            }
            .let { Unit }

    fun deletePage() {
        commitDocument(
            SketchDocumentOps.deleteActivePage(document)
        )
    }

    fun selectPage(index: Int) {
        if (
            index == document.activePage ||
            index !in document.pages.indices
        ) {
            return
        }

        /*
         * Cambiare pagina attiva modifica il documento serializzato,
         * ma non crea una voce Undo.
         */
        document =
            SketchDocumentOps.setActive(
                document,
                index,
            )

        persist()
    }

    fun setPaper(paper: SketchPaper) {
        if (paper == page.paper) return

        commitDocument(
            SketchDocumentOps.setPaper(
                document,
                paper,
            )
        )
    }

    fun addText(
        x: Int = 120,
        y: Int = 180,
        value: String = "Testo",
    ) {
        val next =
            page.copy(
                texts =
                    page.texts +
                        SketchText(
                            text = value,
                            color = 0xFF17212B.toInt(),
                            x = x,
                            y = y,
                        )
            )

        commitPage(next)
    }

    fun updateText(
        id: String,
        value: String,
    ) {
        if (
            value.length >
            SketchRules.MAX_TEXT_LENGTH
        ) {
            return
        }

        val next =
            page.copy(
                texts =
                    page.texts.map {
                        if (it.id == id) {
                            it.copy(text = value)
                        } else {
                            it
                        }
                    }
            )

        commitPage(next)
    }

    fun deleteText(id: String) {
        commitPage(
            page.copy(
                texts =
                    page.texts.filterNot {
                        it.id == id
                    }
            )
        )
    }

    fun rename(value: String) {
        if (
            ready &&
            value.length <= 8000
        ) {
            val next =
                value.ifBlank {
                    "Senza titolo"
                }

            if (next == title) return

            title = next

            /*
             * Digitare il titolo non deve serializzare lo sketch
             * per ogni singolo carattere.
             */
            persist()
        }
    }

    fun link(value: String?) {
        if (!ready) return

        val next = info.copy(linkedNoteId = value)

        if (next == info) return

        info = next
        persist()
    }

    /**
     * Pianifica una persistenza dell'ultima fotografia dello sketch.
     *
     * Ogni modifica aggiorna immediatamente lo stato Compose, mentre
     * serializzazione JSON + Room vengono coalesced entro 180 ms.
     */
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

        persistJob =
            viewModelScope.launch {
                if (!immediate) {
                    delay(
                        SKETCH_PERSIST_DEBOUNCE_MS
                    )
                }

                persistSnapshot(
                    version = version,
                    snapshotDocument = snapshotDocument,
                    snapshotTitle = snapshotTitle,
                    snapshotInfo = snapshotInfo,
                )
            }
    }

    /**
     * Tutto il lavoro costoso di JSON avviene su Default.
     *
     * Le write repository vengono serializzate attraverso il Deferred
     * precedente + il mutex già esistente nel repository.
     */
    private suspend fun persistSnapshot(
        version: Int,
        snapshotDocument: SketchDocument,
        snapshotTitle: String,
        snapshotInfo: SketchInfo,
    ) {
        try {
            val text =
                withContext(
                    Dispatchers.Default
                ) {
                    SketchCodec.encode(
                        snapshotDocument
                    )
                }

            /*
             * Se una write precedente era già partita, aspetta che il DB
             * raggiunga quella versione prima di usare expectedBody.
             */
            pending
                ?.let { previous ->
                    val saved =
                        previous.await()

                    expectedBody =
                        saved.body

                    persistedTitle =
                        saved.title

                    persistedInfo =
                        saved.sketch
                }

            val normalizedTitle =
                snapshotTitle.ifBlank {
                    "Senza titolo"
                }

            /*
             * Evita una write duplicata se il DB contiene già esattamente
             * la fotografia che stiamo tentando di salvare.
             */
            if (
                expectedBody == text &&
                persistedTitle == normalizedTitle &&
                persistedInfo == snapshotInfo
            ) {
                if (version == serial) {
                    status =
                        "Salvato sul dispositivo"
                    error = null
                }

                return
            }

            val write =
                repository.queueSketch(
                    id = id,
                    expectedBody = expectedBody,
                    title = snapshotTitle,
                    body = text,
                    info = snapshotInfo,
                )

            pending = write

            val saved =
                write.await()

            expectedBody =
                saved.body

            persistedTitle =
                saved.title

            persistedInfo =
                saved.sketch

            if (version == serial) {
                status =
                    "Salvato sul dispositivo"
                error = null
            }
        } catch (e: CancellationException) {
            /*
             * Se questo Job viene cancellato perché è arrivata una nuova
             * modifica, una Deferred repository eventualmente già avviata
             * resta nel repository scope e verrà attesa dalla versione
             * successiva tramite pending.
             */
            throw e
        } catch (e: Exception) {
            if (version == serial) {
                status = "Non salvato"
                error = e.message
            }
        }
    }

    /**
     * Flush sincrono DAL PUNTO DI VISTA DELLA COROUTINE, mai del main thread:
     * - annulla il debounce non ancora partito;
     * - aspetta eventuale write già in volo;
     * - serializza l'ultima fotografia su Dispatchers.Default;
     * - esegue al massimo una write finale.
     */
    private suspend fun flushCurrent() {
        persistJob?.cancelAndJoin()
        persistJob = null

        pending
            ?.let { previous ->
                val saved =
                    previous.await()

                expectedBody =
                    saved.body

                persistedTitle =
                    saved.title

                persistedInfo =
                    saved.sketch
            }

        val snapshotDocument =
            document

        val snapshotTitle =
            title

        val snapshotInfo =
            info

        val text =
            withContext(
                Dispatchers.Default
            ) {
                SketchCodec.encode(
                    snapshotDocument
                )
            }

        val normalizedTitle =
            snapshotTitle.ifBlank {
                "Senza titolo"
            }

        if (
            expectedBody == text &&
            persistedTitle == normalizedTitle &&
            persistedInfo == snapshotInfo
        ) {
            status =
                "Salvato sul dispositivo"

            return
        }

        status = "Salvataggio…"

        val write =
            repository.queueSketch(
                id = id,
                expectedBody = expectedBody,
                title = snapshotTitle,
                body = text,
                info = snapshotInfo,
            )

        pending = write

        val saved =
            write.await()

        expectedBody =
            saved.body

        persistedTitle =
            saved.title

        persistedInfo =
            saved.sketch

        status =
            "Salvato sul dispositivo"

        error = null
    }

    fun close(
        onClosed: () -> Unit,
    ) {
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

        val snapshotDocument =
            document

        val snapshotTitle =
            title

        val snapshotInfo =
            info

        viewModelScope.launch {
            try {
                val text =
                    withContext(
                        Dispatchers.Default
                    ) {
                        SketchCodec.encode(
                            snapshotDocument
                        )
                    }

                val newId =
                    java.util.UUID
                        .randomUUID()
                        .toString()

                repository.queueSketch(
                    id = newId,
                    expectedBody = null,
                    title =
                        "$snapshotTitle (copia)",
                    body = text,
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
        /*
         * Il normale percorso di uscita usa close(), che effettua il flush.
         * Qui NON usare runBlocking.
         *
         * Eventuali Deferred già avviate appartengono allo scope IO del
         * repository e possono terminare indipendentemente dal ViewModel.
         */
        persistJob?.cancel()

        if (owned) {
            repository.endEditing(id)
        }

        super.onCleared()
    }
}

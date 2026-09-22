package it.notes.ecosystem.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import it.notes.ecosystem.data.Preferences
import it.notes.ecosystem.data.BackupWriter
import it.notes.ecosystem.media.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import it.notes.ecosystem.domain.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch

class NotesViewModel(private val repository: NotesRepository, private val preferences: Preferences, private val media: AttachmentFiles? = null, private val mediaCache: java.io.File? = null) : ViewModel() {
    private var mediaPreview: MediaBundlePreview? = null
    private val _mediaProgress = MutableStateFlow("")
    val mediaProgress = _mediaProgress.asStateFlow()
    private val _importAssets = MutableStateFlow<Int?>(null)
    val importAssets = _importAssets.asStateFlow()
    private val _mediaUsage = MutableStateFlow<Pair<Int,Long>?>(null)
    val mediaUsage = _mediaUsage.asStateFlow()
    fun refreshMediaUsage() = action { _mediaUsage.value = withContext(Dispatchers.IO) { media?.usage() } }
    fun cleanMedia() = organize({
        val files=checkNotNull(media)
        val removed=withContext(Dispatchers.IO) { repository.cleanupAttachments {files.cleanup(it)} }
        _error.value="$removed file inutilizzati rimossi. Le note e la cronologia sono conservate."
        refreshMediaUsage()
    },{})
    private fun clearMediaPreview() { val old=mediaPreview;mediaPreview=null;_importAssets.value=null
        if(old!=null) viewModelScope.launch(Dispatchers.IO) {old.close()}
    }
    override fun onCleared() {
        val old=mediaPreview;mediaPreview=null
        if(old!=null) kotlinx.coroutines.CoroutineScope(Dispatchers.IO).launch {old.close()}
        super.onCleared()
    }
    fun previewMediaImport(resolver:android.content.ContentResolver,uri:android.net.Uri) {
        if(_importing.value || _exporting.value)return
        clearMediaPreview();_importPreview.value=null;_importing.value=true
        viewModelScope.launch {
            try {
                val preview=withContext(Dispatchers.IO) {
                    val input=resolver.openInputStream(uri) ?: error("Impossibile aprire il file.")
                    input.use {MediaBundle.read(it,checkNotNull(mediaCache))}
                }
                mediaPreview=preview;_importAssets.value=preview.keys.size;_importPreview.value=preview.snapshot
            } catch(e:CancellationException){throw e}
            catch(e:Exception){_error.value="Backup completo non importabile: "+(e.message ?: "file non valido.")}
            finally {_importing.value=false}
        }
    }
    private val _importing = MutableStateFlow(false)
    val importing = _importing.asStateFlow()
    private val _importPreview = MutableStateFlow<BackupSnapshot?>(null)
    val importPreview = _importPreview.asStateFlow()

    fun previewImport(resolver: android.content.ContentResolver, uri: android.net.Uri) {
        if (_importing.value || _exporting.value) return
        _importing.value = true
        _importPreview.value = null
        clearMediaPreview()
        viewModelScope.launch {
            try {
                _importPreview.value = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                    val input = resolver.openInputStream(uri) ?: error("Impossibile aprire il file.")
                    input.use { stream -> it.notes.ecosystem.data.BackupReader.read(stream) }
                }
            } catch (e: CancellationException) { throw e }
            catch (e: Exception) { _error.value = "Backup non importabile: " + (e.message ?: "file non valido.") }
            finally { _importing.value = false }
        }
    }
    fun cancelImport() { if (!_importing.value) { _importPreview.value = null; clearMediaPreview() } }
    fun confirmImport() {
        val data = _importPreview.value ?: return
        if (_importing.value || _exporting.value) return
        _importing.value = true
        viewModelScope.launch {
            try {
                withContext(Dispatchers.IO) { mediaPreview?.install(checkNotNull(media)) }
                repository.importCopies(data)
                _importPreview.value = null
                clearMediaPreview(); refreshMediaUsage()
                _error.value = "Importazione completata: ${data.notes.count { it.task == null }} note, ${data.notes.count { it.task != null }} attività e ${data.drafts.size} bozze aggiunte."
            } catch (e: CancellationException) { throw e }
            catch (e: Exception) { _error.value = "Importazione annullata, nessuna nota aggiunta. Eventuali file preparati restano per un nuovo tentativo. " + (e.message ?: "Riprova.") }
            finally { _importing.value = false }
        }
    }
    val drafts = repository.drafts.catch { report(it); emit(emptyList()) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())
    private val _exporting = MutableStateFlow(false)
    val exporting = _exporting.asStateFlow()
    fun export(resolver: android.content.ContentResolver, uri: android.net.Uri, markdownZip: Boolean) {
        if (_exporting.value || _importing.value || _importPreview.value != null) return
        _exporting.value = true
        viewModelScope.launch {
            try {
                kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                    val data = repository.snapshot()
                    val output = resolver.openOutputStream(uri, "wt") ?: error("Impossibile aprire il file.")
                    output.use { stream ->
                        if(markdownZip) MediaBundle.write(data,checkNotNull(media),stream) {done,total -> _mediaProgress.value="Allegati esportati: $done/$total"}
                        else BackupWriter.write(data,stream,false)
                    }
                }
                _error.value = "Esportazione completata."
            } catch (e: CancellationException) { throw e }
            catch (e: Exception) { _error.value = "Esportazione non completata: il file potrebbe essere parziale. " + (e.message ?: "Riprova.") }
            finally { _exporting.value = false; _mediaProgress.value="" }
        }
    }
    val notes = repository.notes.catch { report(it); emit(emptyList()) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())
    val tasks = flow {
        val index = TaskIndex()
        notes.collect { emit(index.update(it)) }
    }.flowOn(kotlinx.coroutines.Dispatchers.Default)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())
    val collections = repository.collections.catch { report(it); emit(emptyList()) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())
    val savedSearches = preferences.savedSearches.catch { report(it); emit(emptyList()) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())
    val noteOrder = preferences.noteOrder.catch { report(it); emit(NoteOrder.RECENT) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), NoteOrder.RECENT)
    private val _organizationBusy = MutableStateFlow(false)
    val organizationBusy = _organizationBusy.asStateFlow()
    private fun organize(block: suspend () -> Unit, onSuccess: () -> Unit) {
        if(_organizationBusy.value) return
        _organizationBusy.value = true
        viewModelScope.launch {
            try { block(); onSuccess() }
            catch(e: CancellationException) { throw e }
            catch(e: Exception) { report(e) }
            finally { _organizationBusy.value = false }
        }
    }
    fun saveSearch(value: SavedSearch, onSuccess: () -> Unit) = organize({ preferences.saveSearch(value) },onSuccess)
    fun renameSearch(expected: SavedSearch, name: String, onSuccess: () -> Unit) = organize({ preferences.renameSearch(expected,name) },onSuccess)
    fun deleteSearch(expected: SavedSearch, onSuccess: () -> Unit) = organize({ preferences.deleteSearch(expected) },onSuccess)
    fun setNoteOrder(value: NoteOrder) = action { preferences.setNoteOrder(value) }
    fun renameCollection(expected: it.notes.ecosystem.domain.Collection, name: String, onSuccess: () -> Unit) =
        organize({ repository.renameCollection(expected,name) },onSuccess)
    fun deleteEmptyCollection(expected: it.notes.ecosystem.domain.Collection, onSuccess: () -> Unit) =
        organize({ repository.deleteEmptyCollection(expected) },onSuccess)
    fun addCollection(name: String, onSuccess: () -> Unit) = organize({ repository.createCollection(name) },onSuccess)
    val darkMode = preferences.darkMode.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), false)
    private val _error = MutableStateFlow<String?>(null)
    val error = _error.asStateFlow()
    fun clearError() { _error.value = null }
    private fun report(error: Throwable) { _error.value = error.message ?: "Operazione non riuscita." }
    private fun action(block: suspend () -> Unit) { viewModelScope.launch {
        try { block() } catch (e: CancellationException) { throw e } catch (e: Exception) { report(e) }
    } }
    private val _taskWrites = MutableStateFlow<Set<String>>(emptySet())
    val taskWrites = _taskWrites.asStateFlow()
    fun completeTask(task: NoteTask, completed: Boolean) {
        if (task.noteId in _taskWrites.value) return
        _taskWrites.value = _taskWrites.value + task.noteId
        viewModelScope.launch {
            try { repository.setTaskCompleted(task.noteId, task.sourceBody, task.item.lineIndex, completed) }
            catch (e: CancellationException) { throw e }
            catch (e: Exception) { report(e) }
            finally { _taskWrites.value = _taskWrites.value - task.noteId }
        }
    }
    private val _bulkBusy = MutableStateFlow(false)
    val bulkBusy = _bulkBusy.asStateFlow()
    fun bulkEdit(expected: List<Note>, change: BulkChange, onSuccess: () -> Unit) {
        if (_bulkBusy.value) return
        _bulkBusy.value = true
        viewModelScope.launch {
            try {
                val count = repository.bulkEdit(expected, change)
                _error.value = if (count == 0) "Nessuna modifica necessaria." else "$count note aggiornate."
                onSuccess()
            } catch (e: CancellationException) { throw e }
            catch (e: Exception) { report(e) }
            finally { _bulkBusy.value = false }
        }
    }
    fun pin(id: String, value: Boolean) = action { repository.setPinned(id, value) }
    fun archive(id: String, value: Boolean) = action { repository.setArchived(id, value) }
    fun favorite(id: String) = action { repository.toggleFavorite(id) }
    fun trash(id: String) = action { repository.trash(id) }
    fun restore(id: String) = action { repository.restore(id) }
    fun createCollection(name: String) = action { repository.createCollection(name) }
    fun setDarkMode(value: Boolean) = action { preferences.setDarkMode(value) }
}

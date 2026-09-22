package it.notes.ecosystem.sync

import android.content.Context
import androidx.work.*
import it.notes.ecosystem.NotesApplication
import it.notes.ecosystem.data.LocalNotesRepository
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.io.IOException
import java.util.concurrent.TimeUnit

private data class SyncTrigger(
    val notes: List<it.notes.ecosystem.domain.Note>,
    val collections: List<it.notes.ecosystem.domain.Collection>,
    val drafts: Set<String>,
    val editorClosures: Long,
)

class GitHubSync(private val context: Context, private val repository: LocalNotesRepository) {
    private val storage = SyncStorage(context)
    private val mutex = Mutex()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val _status = MutableStateFlow(SyncStatus())
    val status = _status.asStateFlow()
    private val bases = MutableStateFlow<Map<String, SyncRecord>>(emptyMap())
    val noteStates = combine(status, repository.notes, repository.collections, bases) { state, notes, collections, records ->
        val names = collections.associate { it.id to it.name }
        notes.associate { note ->
            val r = records[note.id]
            note.id to when {
                state.connection == null -> "Solo dispositivo"
                r?.conflict == true -> "Conflitto GitHub"
                r?.base == SyncDocument.from(note, names[note.collectionId]) -> "Allineata all'ultimo controllo"
                else -> "In attesa di sincronizzazione"
            }
        }
    }.flowOn(Dispatchers.Default).stateIn(scope, SharingStarted.WhileSubscribed(5000), emptyMap())
    @Volatile private var connected = false
    private val work get() = WorkManager.getInstance(context)
    private val constraints get() = Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()

    @OptIn(FlowPreview::class)
    fun start() {
        scope.launch {
            try { mutex.withLock {
                val c = storage.config()
                connected = c != null
                if (c != null) { publish(c, storage.load(c.key), "In attesa di sincronizzazione"); schedulePeriodic(); schedule() }
            } } catch (_: Exception) { _status.value = SyncStatus(message = "Collegamento non leggibile: scollega e ricollega GitHub.") }
            combine(repository.notes, repository.collections,
                repository.drafts.map { rows -> rows.map { it.id }.toSet() }.distinctUntilChanged(),
                repository.editorClosures) { notes, collections, drafts, closures ->
                SyncTrigger(notes, collections, drafts, closures)
            }.distinctUntilChanged().debounce(2000).collect { if (connected) schedule() }
        }
    }
    private fun schedulePeriodic() {
        work.enqueueUniquePeriodicWork("github-periodic", ExistingPeriodicWorkPolicy.KEEP,
            PeriodicWorkRequestBuilder<GitHubSyncWorker>(15, TimeUnit.MINUTES).setConstraints(constraints).build())
    }
    fun schedule() {
        if (!connected) return
        if (!_status.value.busy) _status.value = _status.value.copy(message = "Modifiche o controllo in attesa di rete")
        work.enqueueUniqueWork("github-now", ExistingWorkPolicy.KEEP,
            OneTimeWorkRequestBuilder<GitHubSyncWorker>().setConstraints(constraints)
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS).build())
    }
    suspend fun connect(config: GitHubConfig, allowPublic: Boolean) = withContext(Dispatchers.IO) {
        mutex.withLock {
            config.validate()
            check(!connected) { "Scollega il repository attuale prima di cambiarlo." }
            val isPrivate = GitHubApi(config).verify()
            currentCoroutineContext().ensureActive()
            check(isPrivate || allowPublic) { "Il repository è pubblico. Abilita esplicitamente la pubblicazione oppure scegli un repository privato." }
            storage.connect(config.copy(allowPublic = allowPublic)); connected = true
            publish(config, storage.load(config.key), "Collegato. Prima sincronizzazione in attesa.")
            schedulePeriodic(); schedule()
        }
    }
    suspend fun disconnect() = withContext(Dispatchers.IO) {
        // Serialize with the worker: after this returns, no old-account write is still running.
        mutex.withLock {
            connected = false; storage.disconnect()
            work.cancelUniqueWork("github-now"); work.cancelUniqueWork("github-periodic")
            _status.value = SyncStatus(message = "GitHub scollegato. Note locali conservate.")
        }
    }
    private fun publish(c: GitHubConfig, records: Map<String, SyncRecord>, message: String, busy: Boolean = false) {
        bases.value = records.toMap()
        _status.value = SyncStatus(c.toString(), message, busy,
            records.filterValues { it.conflict }.map { (id, r) -> SyncConflict(id, r.local, r.remote) })
    }
    suspend fun run(): Boolean = withContext(Dispatchers.IO) {
        mutex.withLock {
            val config = try { storage.config() } catch (_: Exception) {
                _status.value = SyncStatus(message = "Credenziali non leggibili: ricollega GitHub."); return@withLock false
            } ?: return@withLock false
            var records = mutableMapOf<String, SyncRecord>()
            try {
                records = storage.load(config.key)
                if (storage.retryAt(config.key) > System.currentTimeMillis()) {
                    publish(config, records, "In attesa del limite richieste GitHub. Riproveremo automaticamente.")
                    return@withLock true
                }
                publish(config, records, "Sincronizzazione in corso…", true)
                val api = GitHubApi(config)
                check(api.verify() || config.allowPublic) { "Il repository ora è pubblico. Sincronizzazione sospesa: scegli un repository privato o ricollegalo autorizzando la pubblicazione." }
                val attachments = AttachmentSync(api,api,(context.applicationContext as NotesApplication).attachments) { message -> publish(config,records,message,true) }
                val outcome = SyncEngine(repository, attachments) { storage.save(config.key, it) }.run(records)
                // Cached documents can bypass read(); verify their files before declaring success too.
                val assetHead = api.head()
                repository.syncDocuments().values.forEach { attachments.ensurePublished(it) }
                records.values.mapNotNull {if(it.conflict)it.remote else null}.forEach { attachments.download(it,assetHead) }
                val waiting = outcome.waiting
                val changedDuringRun = outcome.pending
                publish(config, records, when {
                    records.values.any { it.conflict } -> "Conflitti da risolvere: entrambe le versioni sono conservate."
                    waiting > 0 -> "Alcune note sono aperte o hanno bozze. Salvale e riprova."
                    changedDuringRun -> "Nuove modifiche in attesa del prossimo passaggio."
                    else -> "Sincronizzazione completata"
                })
                waiting > 0 || (changedDuringRun && records.values.none { it.conflict })
            } catch (e: CancellationException) { publish(config, records, "Sincronizzazione interrotta: verrà ripresa."); throw e }
            catch (e: Exception) {
                if (e is GitHubFailure && e.retryAt > 0) storage.setRetryAt(config.key, e.retryAt)
                val retry = e is IOException && (e !is GitHubFailure || e.retryAt > 0 || e.status == 429 || e.status >= 500 || e.status == 409)
                val message = if (e is GitHubFailure || e is IllegalArgumentException || e is IllegalStateException)
                    e.message ?: "Sincronizzazione interrotta." else "Connessione interrotta. Le note restano sul dispositivo."
                publish(config, records, message + " Le operazioni già concluse sono conservate.")
                retry
            }
        }
    }
    suspend fun resolve(shown: SyncConflict, choice: String) = withContext(Dispatchers.IO) {
        mutex.withLock {
            val c = storage.config() ?: error("Collega GitHub.")
            val id = shown.id
            val records = storage.load(c.key)
            val conflict = records[id] ?: error("Conflitto non trovato.")
            check(conflict.conflict && conflict.local == shown.local && conflict.remote == shown.remote) { "Il conflitto è cambiato. Riapri le versioni prima di scegliere." }
            val remote = conflict.remote ?: error("Versione remota non disponibile.")
            check(repository.resolveSync(id, conflict.local, remote, choice)) { "Nota aperta, bozza presente o nota cambiata. Chiudi l'editor e sincronizza di nuovo." }
            records[id] = SyncRecord(remote, null)
            storage.save(c.key, records)
            publish(c, records, "Scelta salvata. Sincronizzazione in attesa.")
            schedule()
        }
    }
}

class GitHubSyncWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result = if ((applicationContext as NotesApplication).githubSync.run()) Result.retry() else Result.success()
}

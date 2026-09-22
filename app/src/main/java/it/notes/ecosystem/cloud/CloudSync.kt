package it.notes.ecosystem.cloud

import android.content.Context
import androidx.room.withTransaction
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import it.notes.ecosystem.data.LocalNotesRepository
import it.notes.ecosystem.data.NotesDatabase
import it.notes.ecosystem.data.SyncConflictEntity
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.util.UUID
import java.util.concurrent.TimeUnit

class CloudSync(
    private val context: Context,
    private val database: NotesDatabase,
    private val repository: LocalNotesRepository,
    private val sessions: CloudSessionStore,
    private val api: SupabaseHttpClient,
) {
    private val cloudDao = database.cloudDao()
    private val mutex = Mutex()
    private val _status = MutableStateFlow(
        CloudStatus(
            configured = api.configured,
            session = sessions.session.value,
            personalSyncEnabled = sessions.personalSyncEnabled.value,
            message = initialMessage(),
        )
    )
    val status = _status.asStateFlow()

    private fun initialMessage(): String = when {
        !api.configured -> "Cloud non configurato in questa build."
        sessions.session.value == null -> "Account facoltativo: le note restano locali finché non accedi."
        sessions.personalSyncEnabled.value -> "Cloud personale attivo."
        else -> "Account collegato, cloud personale disattivato."
    }

    suspend fun signIn(email: String, password: String) = mutex.withLock {
        require(api.configured) { "Backend cloud non configurato." }
        require(email.isNotBlank() && password.length >= 6) { "Email o password non valide." }
        setBusy("Accesso in corso…")
        try {
            val old = sessions.session.value?.accountId
            val (session0, refresh) = withContext(Dispatchers.IO) { api.signIn(email.trim(), password) }
            if (old != null && old != session0.accountId) detach(old)
            val profile = runCatching { withContext(Dispatchers.IO) { api.profile(session0.accessToken, session0.accountId) } }.getOrNull()
            val session = session0.copy(
                email = profile?.first?.ifBlank { session0.email } ?: session0.email,
                displayName = profile?.second?.ifBlank { session0.displayName } ?: session0.displayName,
            )
            sessions.save(session, refresh)
            if (session.displayName.isNotBlank()) runCatching {
                withContext(Dispatchers.IO) { api.updateProfile(session.accessToken, session.accountId, session.email, session.displayName) }
            }
            _status.value = CloudStatus(api.configured, session, false, false, "Account collegato. La sincronizzazione personale resta disattivata finché non la abiliti.")
        } catch (e: CancellationException) { throw e }
        catch (e: Exception) { fail(e); throw e }
    }

    suspend fun signUp(email: String, password: String, displayName: String): Boolean = mutex.withLock {
        require(api.configured) { "Backend cloud non configurato." }
        require(email.isNotBlank() && password.length >= 8 && displayName.trim().length in 2..80) {
            "Controlla nome, email e password (minimo 8 caratteri)."
        }
        setBusy("Creazione account…")
        try {
            val (session, refresh) = withContext(Dispatchers.IO) { api.signUp(email.trim(), password, displayName.trim()) }
            if (session == null || refresh == null) {
                _status.value = CloudStatus(api.configured, null, false, false, "Account creato. Conferma l'email, poi accedi.")
                false
            } else {
                withContext(Dispatchers.IO) { api.updateProfile(session.accessToken, session.accountId, session.email, displayName.trim()) }
                val saved = session.copy(displayName = displayName.trim())
                sessions.save(saved, refresh)
                _status.value = CloudStatus(api.configured, saved, false, false, "Account creato. Il cloud personale è ancora disattivato.")
                true
            }
        } catch (e: CancellationException) { throw e }
        catch (e: Exception) { fail(e); throw e }
    }

    suspend fun updateProfile(displayName: String) = mutex.withLock {
        val session = requireSession()
        require(displayName.trim().length in 2..80) { "Nome non valido." }
        val active = validSession(session)
        withContext(Dispatchers.IO) { api.updateProfile(active.accessToken, active.accountId, active.email, displayName.trim()) }
        val refresh = sessions.refreshToken() ?: error("Sessione scaduta.")
        val next = active.copy(displayName = displayName.trim())
        sessions.save(next, refresh)
        _status.value = _status.value.copy(session = next, message = "Profilo aggiornato.")
    }

    suspend fun enablePersonalSync() = mutex.withLock {
        val session = validSession(requireSession())
        sessions.setPersonalSyncEnabled(true)
        database.withTransaction {
            cloudDao.claimPrivateNotes(session.accountId)
            cloudDao.enqueueDirtyPrivateNotes(session.accountId, System.currentTimeMillis())
        }
        _status.value = _status.value.copy(
            session = session,
            personalSyncEnabled = true,
            message = "Cloud personale attivato. Prima sincronizzazione in coda.",
        )
        start()
    }

    suspend fun disablePersonalSync() = mutex.withLock {
        sessions.setPersonalSyncEnabled(false)
        WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
        WorkManager.getInstance(context).cancelUniqueWork(PERIODIC_WORK_NAME)
        _status.value = _status.value.copy(
            personalSyncEnabled = false,
            busy = false,
            message = "Cloud personale disattivato. I dati locali restano sul dispositivo.",
        )
    }

    suspend fun signOut() = mutex.withLock {
        val current = sessions.session.value
        setBusy("Disconnessione…")
        try {
            if (current != null) {
                val active = runCatching { validSession(current) }.getOrNull()
                if (active != null) runCatching { withContext(Dispatchers.IO) { api.signOut(active.accessToken) } }
                detach(current.accountId)
            }
        } finally {
            WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
            WorkManager.getInstance(context).cancelUniqueWork(PERIODIC_WORK_NAME)
            sessions.clearSession()
            _status.value = CloudStatus(api.configured, null, false, false, initialMessage())
        }
    }

    fun start() {
        if (!api.configured || !sessions.personalSyncEnabled.value || sessions.session.value == null) return
        val constraints = Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()
        val periodic = PeriodicWorkRequestBuilder<CloudSyncWorker>(6, TimeUnit.HOURS)
            .setConstraints(constraints)
            .build()
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            PERIODIC_WORK_NAME,
            ExistingPeriodicWorkPolicy.UPDATE,
            periodic,
        )
        schedule()
    }

    fun schedule() {
        if (!api.configured || !sessions.personalSyncEnabled.value || sessions.session.value == null) return
        val request = OneTimeWorkRequestBuilder<CloudSyncWorker>()
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(WORK_NAME, ExistingWorkPolicy.KEEP, request)
    }

    suspend fun syncNow(): Boolean = mutex.withLock {
        if (!api.configured || !sessions.personalSyncEnabled.value) return true
        try {
            val session = validSession(requireSession())
            setBusy("Sincronizzazione cloud…")
            database.withTransaction {
                cloudDao.claimPrivateNotes(session.accountId)
                cloudDao.enqueueDirtyPrivateNotes(session.accountId, System.currentTimeMillis())
            }
            push(session)
            pull(session)
            val count = cloudDao.observeConflicts(session.accountId).first().size
            _status.value = CloudStatus(
                api.configured,
                sessions.session.value,
                true,
                false,
                if (count == 0) "Cloud aggiornato." else "Cloud aggiornato · $count conflitti da risolvere.",
                count,
            )
            true
        } catch (e: CancellationException) { throw e }
        catch (e: Exception) {
            fail(e)
            false
        }
    }

    private suspend fun push(session: CloudSession) {
        val pending = cloudDao.outbox(session.accountId, 100)
        for (item in pending) {
            val document = repository.cloudDocument(item.recordId, session.accountId)
            if (document == null) {
                cloudDao.removeOutbox(item.recordId, session.accountId)
                continue
            }
            try {
                val result = withContext(Dispatchers.IO) { api.apply(session.accessToken, document, item.baseRevision) }
                if (result.applied && result.record != null) {
                    repository.markCloudSynced(
                        item.recordId,
                        session.accountId,
                        document.updatedAt,
                        result.record.revision,
                        result.record.updatedBy,
                    )
                } else if (result.record != null) {
                    conflict(session.accountId, document, result.record, item.baseRevision)
                } else error("Risposta cloud incompleta.")
            } catch (e: Exception) {
                cloudDao.failOutbox(item.recordId, session.accountId, e.message?.take(500) ?: "Errore cloud")
                throw e
            }
        }
    }

    private suspend fun pull(session: CloudSession) {
        val remote = withContext(Dispatchers.IO) { api.personalRecords(session.accessToken) }
        for (record in remote) {
            val local = repository.cloudLocalState(record.id)
            if (local != null && local.cloudAccountId != null && local.cloudAccountId != session.accountId) continue
            if (local?.cloudState == "CONFLICT") continue
            if (local?.cloudState == "DIRTY" && record.revision > local.remoteRevision) {
                val document = repository.cloudDocument(record.id, session.accountId)
                if (document != null) conflict(session.accountId, document, record, local.remoteRevision)
                continue
            }
            if (local == null || record.revision > local.remoteRevision) {
                repository.applyCloudRemote(session.accountId, record)
            }
        }
    }

    private suspend fun conflict(
        accountId: String,
        local: it.notes.ecosystem.sync.SyncDocument,
        remote: CloudRemoteRecord,
        baseRevision: Long,
    ) {
        cloudDao.upsertConflict(
            SyncConflictEntity(
                conflictId = UUID.randomUUID().toString(),
                recordId = local.id,
                accountId = accountId,
                localPayload = CloudRecordCodec.payload(local),
                remotePayload = CloudRecordCodec.payload(remote.document),
                baseRevision = baseRevision,
                remoteRevision = remote.revision,
                createdAt = System.currentTimeMillis(),
            )
        )
        cloudDao.markConflict(local.id, accountId)
        cloudDao.removeOutbox(local.id, accountId)
    }

    private suspend fun validSession(current: CloudSession): CloudSession {
        if (current.accessToken.isNotBlank() &&
            current.expiresAtEpochSeconds > System.currentTimeMillis() / 1000L + 60L
        ) return current
        val refresh = sessions.refreshToken() ?: error("Sessione scaduta: accedi di nuovo.")
        val (next, nextRefresh) = withContext(Dispatchers.IO) { api.refresh(refresh) }
        check(next.accountId == current.accountId) { "Account cloud cambiato durante il rinnovo della sessione." }
        val merged = next.copy(displayName = current.displayName.ifBlank { next.displayName })
        sessions.updateAccess(merged, nextRefresh)
        return merged
    }

    private fun requireSession(): CloudSession =
        sessions.session.value ?: error("Accedi prima di usare il cloud.")

    private suspend fun detach(accountId: String) {
        database.withTransaction {
            cloudDao.detachAccount(accountId)
            cloudDao.clearOutbox(accountId)
            cloudDao.clearConflicts(accountId)
            cloudDao.clearMembers()
            cloudDao.clearSpaces()
        }
    }

    private fun setBusy(message: String) {
        _status.value = _status.value.copy(busy = true, message = message)
    }

    private fun fail(error: Exception) {
        _status.value = _status.value.copy(
            busy = false,
            message = error.message ?: "Operazione cloud non riuscita.",
        )
    }

    companion object {
        const val WORK_NAME = "notes-personal-cloud-sync"
        const val PERIODIC_WORK_NAME = "notes-personal-cloud-periodic"
    }
}

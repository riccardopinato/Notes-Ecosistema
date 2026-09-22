package it.notes.ecosystem.sync

import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

interface SyncLocal {
    suspend fun syncDocuments(): Map<String, SyncDocument>
    suspend fun syncDocument(id: String): SyncDocument?
    suspend fun applySync(id: String, expected: SyncDocument?, incoming: SyncDocument): Boolean
}
data class SyncRunResult(val waiting: Int, val pending: Boolean)

/** Sequential per-file compare-and-swap; checkpoints never advance before a completed write. */
class SyncEngine(private val backend: SyncLocal, private val api: GitHubTransport,
    private val checkpoint: (Map<String, SyncRecord>) -> Unit) {
    suspend fun run(records: MutableMap<String, SyncRecord>): SyncRunResult {
        val head = api.head()
        val files = api.list(head).associateBy { it.name }
        check(files.isNotEmpty() || records.isEmpty()) { "Cartella GitHub vuota o rimossa: sincronizzazione sospesa per proteggere le note. Ripristina i file su GitHub." }
        val localStart = backend.syncDocuments()
        require(localStart.size <= 500) { "Questa versione sincronizza fino a 500 note, cestino incluso." }
        // Validate the entire incoming batch before changing local or remote notes.
        val remote = mutableMapOf<String, Pair<SyncDocument, String>>()
        var total = 0
        files.values.forEach { file ->
            currentCoroutineContext().ensureActive()
            val cached = records.values.firstOrNull { it.sha == file.sha && it.base != null }
            val doc = cached?.base ?: api.read(file, head)
            require(SyncCodec.filename(doc.id) == file.name)
            total += SyncCodec.encode(doc).toByteArray(Charsets.UTF_8).size
            require(total <= 5 * 1024 * 1024) { "Archivio sync oltre 5 MB." }
            remote[doc.id] = doc to file.sha
        }
        require((localStart.keys + remote.keys + records.keys).size <= 500)
        require(localStart.values.sumOf { SyncCodec.encode(it).toByteArray(Charsets.UTF_8).size } <= 5 * 1024 * 1024)
        localStart.values.forEach { require(SyncCodec.encode(it).toByteArray(Charsets.UTF_8).size <= SyncCodec.MAX_BYTES) }
        // Reserve the larger version for each ID, including unresolved conflicts and tombstones.
        // This bounds either resulting archive, not only the two starting archives separately.
        fun size(doc: SyncDocument?) = doc?.let { SyncCodec.encode(it).toByteArray(Charsets.UTF_8).size.toLong() } ?: 0L
        val reserved = (localStart.keys + remote.keys + records.keys).associateWith { id ->
            maxOf(size(localStart[id]), size(remote[id]?.first ?: records[id]?.base?.tombstone()))
        }.toMutableMap()
        require(reserved.values.sum() <= 5L * 1024 * 1024) { "Le note unite superano il limite sync di 5 MB. Nessuna nota è stata trasferita." }
        var waiting = 0
        for (id in (localStart.keys + remote.keys + records.keys).sorted()) {
            currentCoroutineContext().ensureActive()
            val old = records[id]
            val local = backend.syncDocument(id)
            val currentSize = size(local)
            require(currentSize <= SyncCodec.MAX_BYTES) { "Nota modificata durante la sincronizzazione oltre 256 KB." }
            reserved[id] = maxOf(reserved[id] ?: 0L, currentSize)
            require(reserved.values.sum() <= 5L * 1024 * 1024) { "Nuove modifiche oltre il limite sync di 5 MB. Le operazioni già concluse sono conservate." }
            val received = remote[id]
            val remoteDoc = received?.first ?: old?.base?.tombstone()
            val sha = received?.second
            val decision = decideSync(old?.base, local, remoteDoc)
            when (decision) {
                SyncDecision.CONFLICT -> records[id] = SyncRecord(old?.base, old?.sha, true, local, remoteDoc)
                SyncDecision.DOWNLOAD -> {
                    if (remoteDoc == null || !backend.applySync(id, local, remoteDoc)) { waiting++; continue }
                    records[id] = SyncRecord(remoteDoc, sha)
                }
                SyncDecision.UPLOAD -> {
                    if (local == null) { waiting++; continue }
                    val writtenSha = api.write(local, sha)
                    records[id] = SyncRecord(local, writtenSha)
                }
                SyncDecision.SAME -> if (local != null) records[id] = SyncRecord(local, sha)
            }
            // Persist after each completed file. A crash before this save is recovered by equality on retry.
            checkpoint(records)
            // Preserve a remote deletion as a durable tombstone for new devices too.
            val merged = records[id]
            if (merged?.sha == null && old?.base != null && merged?.conflict == false && merged.base?.deletedAt != null) {
                records[id] = merged.copy(sha = api.write(merged.base, null))
                checkpoint(records)
            }
        }
        val changedDuringRun = backend.syncDocuments() != records.mapNotNull { (id, r) -> r.base?.let { id to it } }.toMap()
        return SyncRunResult(waiting, changedDuringRun)
    }
}

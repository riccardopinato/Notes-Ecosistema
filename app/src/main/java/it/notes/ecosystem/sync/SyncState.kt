package it.notes.ecosystem.sync

data class SyncRecord(val base: SyncDocument?, val sha: String?, val conflict: Boolean = false,
    val local: SyncDocument? = null, val remote: SyncDocument? = null)
data class SyncConflict(val id: String, val local: SyncDocument?, val remote: SyncDocument?)
data class SyncStatus(val connection: String? = null, val message: String = "GitHub non collegato",
    val busy: Boolean = false, val conflicts: List<SyncConflict> = emptyList())

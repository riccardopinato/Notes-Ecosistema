package it.notes.ecosystem.data

import android.content.Context
import it.notes.ecosystem.domain.FocusClock
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject

class FocusStore(context: Context) {
    private val preferences = context.applicationContext.getSharedPreferences("planner_focus", Context.MODE_PRIVATE)
    companion object { private val lock = Mutex() }
    private fun read(): FocusClock? = preferences.getString("active", null)?.let { raw ->
        FocusClockCodec.decode(raw)
    }
    suspend fun load(): FocusClock? = withContext(Dispatchers.IO) { lock.withLock { read() } }
    suspend fun save(clock: FocusClock?, expected: FocusClock? = null) = withContext(Dispatchers.IO) {
        lock.withLock {
            check(read() == expected) { "La sessione Focus è cambiata. Riapri Attività per aggiornarla." }
            val value = clock?.let(FocusClockCodec::encode)
            check(preferences.edit().putString("active", value).commit()) { "Impossibile memorizzare la sessione Focus." }
        }
    }
}

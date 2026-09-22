package it.notes.ecosystem.data

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import it.notes.ecosystem.domain.*
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.Dispatchers
import java.io.IOException

private val Context.preferences by preferencesDataStore(name = "preferences")
class Preferences(private val context: Context) {
    private val searchesKey = stringPreferencesKey("saved_searches_v1")
    private val orderKey = stringPreferencesKey("library_order")
    val savedSearches = context.preferences.data.map { it[searchesKey] }.distinctUntilChanged()
        .map { SavedSearchCodec.decode(it) }.flowOn(Dispatchers.Default)
    val noteOrder = context.preferences.data.map { values ->
        NoteOrder.entries.firstOrNull { it.name == values[orderKey] } ?: NoteOrder.RECENT
    }
    suspend fun setNoteOrder(order: NoteOrder) { context.preferences.edit { it[orderKey] = order.name } }
    suspend fun saveSearch(search: SavedSearch) {
        context.preferences.edit { values -> values[searchesKey] = SavedSearchCodec.encode(upsertSavedSearch(SavedSearchCodec.decode(values[searchesKey]),search)) }
    }
    suspend fun deleteSearch(expected: SavedSearch) {
        context.preferences.edit { values ->
            val current = SavedSearchCodec.decode(values[searchesKey])
            check(current.firstOrNull { it.id == expected.id } == expected) { "La ricerca è cambiata. Riapri il pannello." }
            values[searchesKey] = SavedSearchCodec.encode(current.filterNot { it.id == expected.id })
        }
    }
    suspend fun renameSearch(expected: SavedSearch, name: String) {
        context.preferences.edit { values ->
            val current = SavedSearchCodec.decode(values[searchesKey])
            check(current.firstOrNull { it.id == expected.id } == expected) { "La ricerca è cambiata. Riapri il pannello." }
            values[searchesKey] = SavedSearchCodec.encode(upsertSavedSearch(current,expected.copy(name=name)))
        }
    }
    private val darkKey = booleanPreferencesKey("dark_mode")
    val darkMode = context.preferences.data.catch { error ->
        if (error is IOException) emit(emptyPreferences()) else throw error
    }.map { it[darkKey] ?: false }
    suspend fun setDarkMode(enabled: Boolean) { context.preferences.edit { it[darkKey] = enabled } }
}

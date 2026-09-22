package it.notes.ecosystem.data

import it.notes.ecosystem.domain.*
import org.json.JSONArray
import org.json.JSONObject

/** Local preferences only. A corrupt or future file is never silently overwritten. */
object SavedSearchCodec {
    fun encode(values: List<SavedSearch>): String {
        require(values.size <= 30 && values.map { it.id }.distinct().size == values.size)
        var checked = emptyList<SavedSearch>()
        values.forEach { checked = upsertSavedSearch(checked, it) }
        val array = JSONArray()
        checked.forEach { s -> array.put(JSONObject().put("id",s.id).put("name",s.name).put("query",s.query)
            .put("filter",s.filter.name).put("collectionId",s.collectionId ?: JSONObject.NULL)
            .put("kind",s.kind).put("order",s.order.name).put("tags",JSONArray(s.options.tags))
            .put("allTags",s.options.allTags).put("favoritesOnly",s.options.favoritesOnly)
            .put("pinnedOnly",s.options.pinnedOnly).put("tasks",s.options.tasks.name)) }
        return JSONObject().put("version",1).put("searches",array).toString().also {
            require(it.length <= 400000) { "Le ricerche salvate sono troppo lunghe. Riduci il testo." }
        }
    }
    fun decode(text: String?): List<SavedSearch> {
        if(text == null) return emptyList()
        require(text.length <= 400000) { "Archivio ricerche troppo grande." }
        val root = JSONObject(text)
        require(root.getInt("version") == 1) { "Versione ricerche non supportata." }
        val rows = root.getJSONArray("searches")
        require(rows.length() <= 30)
        var result = emptyList<SavedSearch>()
        for(i in 0 until rows.length()) {
            val s = rows.getJSONObject(i); val tags = s.getJSONArray("tags")
            val value = SavedSearch(s.getString("id"),s.getString("name"),s.getString("query"),
                NoteFilter.valueOf(s.getString("filter")),if(s.isNull("collectionId")) null else s.getString("collectionId"),
                SearchOptions((0 until tags.length()).map { tags.getString(it) },s.getBoolean("allTags"),
                    s.getBoolean("favoritesOnly"),s.getBoolean("pinnedOnly"),TaskPresence.valueOf(s.getString("tasks"))),
                s.getString("kind"),NoteOrder.valueOf(s.getString("order")))
            require(result.none { it.id == value.id }) { "Ricerca duplicata." }
            result = upsertSavedSearch(result,value)
        }
        return result
    }
}

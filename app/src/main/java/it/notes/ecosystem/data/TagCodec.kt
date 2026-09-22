package it.notes.ecosystem.data

import it.notes.ecosystem.domain.Tags
import org.json.JSONArray

object TagCodec {
    fun encode(tags: List<String>): String = array(tags).toString()
    fun array(tags: List<String>): JSONArray = JSONArray(Tags.normalize(tags))
    fun decode(text: String): List<String> = read(JSONArray(text))
    fun read(array: JSONArray): List<String> {
        require(array.length() <= Tags.MAX_PER_NOTE) { "Massimo 20 tag per nota." }
        return Tags.normalize((0 until array.length()).map {
            array.get(it) as? String ?: error("Il tag deve essere testo.")
        })
    }
}

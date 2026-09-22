package it.notes.ecosystem.domain

import java.text.Normalizer
import java.util.Locale

object Tags {
    const val MAX_PER_NOTE = 20
    fun name(raw: String): String {
        val value = Normalizer.normalize(raw.trim().removePrefix("#"), Normalizer.Form.NFC).lowercase(Locale.ROOT)
        require(value.length in 1..40 && value.matches(Regex("""[\p{L}\p{M}\p{N}_-]+"""))) {
            "Tag: da 1 a 40 caratteri, lettere, numeri, trattino o underscore."
        }
        return value
    }
    fun normalize(values: List<String>): List<String> {
        require(values.size <= MAX_PER_NOTE) { "Massimo 20 tag per nota." }
        return values.map(::name).distinct().sorted()
    }
    fun add(values: List<String>, raw: String): List<String> {
        val tag = name(raw)
        return normalize((normalize(values) + tag).distinct())
    }
}

package it.notes.ecosystem.cloud

import it.notes.ecosystem.sync.SyncCodec
import it.notes.ecosystem.sync.SyncDocument
import org.json.JSONArray
import org.json.JSONObject

data class CloudSession(
    val accountId: String,
    val email: String,
    val displayName: String,
    val accessToken: String,
    val expiresAtEpochSeconds: Long,
)

data class CloudWriteContext(val accountId: String)

data class CloudRemoteRecord(
    val id: String,
    val document: SyncDocument,
    val clientUpdatedAt: Long,
    val deletedAt: Long?,
    val revision: Long,
    val updatedBy: String?,
)

data class CloudApplyResult(
    val applied: Boolean,
    val record: CloudRemoteRecord?,
)

data class CloudStatus(
    val configured: Boolean,
    val session: CloudSession? = null,
    val personalSyncEnabled: Boolean = false,
    val busy: Boolean = false,
    val message: String = "Cloud disattivato",
    val openConflicts: Int = 0,
)

object CloudRecordCodec {
    const val MAX_RECORD_BYTES = 384 * 1024

    fun payload(document: SyncDocument): String = JSONObject()
        .put("format", "notes-ecosystem-cloud")
        .put("version", 1)
        .put("document", SyncCodec.encode(document))
        .toString()
        .also { require(it.toByteArray(Charsets.UTF_8).size <= MAX_RECORD_BYTES) { "Elemento troppo grande per il cloud." } }

    fun document(payload: Any?): SyncDocument {
        val value = when (payload) {
            is JSONObject -> payload
            is String -> JSONObject(payload)
            else -> error("Payload cloud non valido.")
        }
        require(value.optString("format") == "notes-ecosystem-cloud" && value.optInt("version") == 1) {
            "Versione cloud non supportata."
        }
        return SyncCodec.decode(value.getString("document"))
    }

    fun remote(value: JSONObject): CloudRemoteRecord {
        val document = document(value.get("payload"))
        val id = value.getString("id")
        require(document.id == id) { "ID cloud non coerente." }
        return CloudRemoteRecord(
            id = id,
            document = document,
            clientUpdatedAt = value.getLong("client_updated_at"),
            deletedAt = if (value.isNull("deleted_at")) null else value.getLong("deleted_at"),
            revision = value.getLong("revision"),
            updatedBy = if (value.isNull("updated_by")) null else value.getString("updated_by"),
        )
    }

    fun list(text: String): List<CloudRemoteRecord> {
        val array = JSONArray(text)
        require(array.length() <= 10_000) { "Troppi elementi cloud." }
        return (0 until array.length()).map { remote(array.getJSONObject(it)) }
    }
}

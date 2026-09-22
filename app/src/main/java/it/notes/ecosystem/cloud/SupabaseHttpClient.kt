package it.notes.ecosystem.cloud

import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URI
import java.net.URLEncoder

class SupabaseHttpClient(
    private val projectUrl: String,
    private val publishableKey: String,
) {
    val configured: Boolean = runCatching {
        val uri = URI(projectUrl)
        uri.scheme == "https" && !uri.host.isNullOrBlank() && publishableKey.isNotBlank()
    }.getOrDefault(false)

    suspend fun signIn(email: String, password: String): Pair<CloudSession, String> =
        auth("/auth/v1/token?grant_type=password", JSONObject().put("email", email).put("password", password))

    suspend fun signUp(email: String, password: String, displayName: String): Pair<CloudSession?, String?> {
        val root = request(
            method = "POST",
            path = "/auth/v1/signup",
            body = JSONObject().put("email", email).put("password", password)
                .put("data", JSONObject().put("display_name", displayName)).toString(),
            accessToken = null,
        )
        val access = root.optString("access_token")
        val refresh = root.optString("refresh_token")
        if (access.isBlank() || refresh.isBlank()) return null to null
        return session(root) to refresh
    }

    suspend fun refresh(refreshToken: String): Pair<CloudSession, String> =
        auth("/auth/v1/token?grant_type=refresh_token", JSONObject().put("refresh_token", refreshToken))

    suspend fun signOut(accessToken: String) {
        request("POST", "/auth/v1/logout", "{}", accessToken)
    }

    suspend fun profile(accessToken: String, accountId: String): Pair<String, String>? {
        val text = rawRequest(
            "GET",
            "/rest/v1/profiles?id=eq.${encode(accountId)}&select=email,display_name&limit=1",
            null,
            accessToken,
            prefer = null,
        )
        val array = org.json.JSONArray(text)
        if (array.length() == 0) return null
        val row = array.getJSONObject(0)
        return row.optString("email") to row.optString("display_name")
    }

    suspend fun updateProfile(accessToken: String, accountId: String, email: String, displayName: String) {
        rawRequest(
            "POST",
            "/rest/v1/profiles?on_conflict=id",
            JSONObject().put("id", accountId).put("email", email).put("display_name", displayName).toString(),
            accessToken,
            prefer = "resolution=merge-duplicates,return=minimal",
        )
    }

    suspend fun personalRecords(accessToken: String): List<CloudRemoteRecord> = CloudRecordCodec.list(
        rawRequest(
            "GET",
            "/rest/v1/workspace_records?visibility=eq.PRIVATE&space_id=is.null&select=id,payload,client_updated_at,deleted_at,revision,updated_by&order=id.asc",
            null,
            accessToken,
            prefer = null,
        )
    )

    suspend fun apply(accessToken: String, document: it.notes.ecosystem.sync.SyncDocument, baseRevision: Long): CloudApplyResult {
        val payload = JSONObject(CloudRecordCodec.payload(document))
        val record = JSONObject()
            .put("id", document.id)
            .put("visibility", "PRIVATE")
            .put("space_id", JSONObject.NULL)
            .put("payload", payload)
            .put("client_updated_at", document.updatedAt)
            .put("deleted_at", document.deletedAt ?: JSONObject.NULL)
        val response = request(
            "POST",
            "/rest/v1/rpc/apply_workspace_record",
            JSONObject().put("p_record", record).put("p_base_revision", baseRevision).toString(),
            accessToken,
        )
        val applied = response.optBoolean("applied", false)
        val row = response.optJSONObject("record")?.let(CloudRecordCodec::remote)
        return CloudApplyResult(applied, row)
    }

    private suspend fun auth(path: String, body: JSONObject): Pair<CloudSession, String> {
        val root = request("POST", path, body.toString(), null)
        val refresh = root.getString("refresh_token")
        return session(root) to refresh
    }

    private fun session(root: JSONObject): CloudSession {
        val user = root.getJSONObject("user")
        val metadata = user.optJSONObject("user_metadata")
        return CloudSession(
            accountId = user.getString("id"),
            email = user.optString("email"),
            displayName = metadata?.optString("display_name").orEmpty(),
            accessToken = root.getString("access_token"),
            expiresAtEpochSeconds = System.currentTimeMillis() / 1000L + root.optLong("expires_in", 3600L),
        )
    }

    private fun request(method: String, path: String, body: String?, accessToken: String?): JSONObject =
        JSONObject(rawRequest(method, path, body, accessToken, prefer = null))

    private fun rawRequest(
        method: String,
        path: String,
        body: String?,
        accessToken: String?,
        prefer: String?,
    ): String {
        check(configured) { "Backend cloud non configurato in questa build." }
        val base = projectUrl.trimEnd('/')
        val url = URI(base + path).toURL()
        val connection = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = 15_000
            readTimeout = 30_000
            useCaches = false
            setRequestProperty("apikey", publishableKey)
            setRequestProperty("Accept", "application/json")
            setRequestProperty("Content-Type", "application/json; charset=utf-8")
            if (!accessToken.isNullOrBlank()) setRequestProperty("Authorization", "Bearer $accessToken")
            if (!prefer.isNullOrBlank()) setRequestProperty("Prefer", prefer)
            if (body != null) {
                doOutput = true
                outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
            }
        }
        try {
            val code = connection.responseCode
            val stream = if (code in 200..299) connection.inputStream else connection.errorStream
            val text = stream?.use { input ->
                val output = ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    require(output.size() + count <= MAX_RESPONSE_BYTES) { "Risposta cloud troppo grande." }
                    output.write(buffer, 0, count)
                }
                output.toString(Charsets.UTF_8.name())
            }.orEmpty()
            if (code !in 200..299) {
                val message = runCatching { JSONObject(text).optString("msg").ifBlank { JSONObject(text).optString("message") } }.getOrNull()
                throw IOException(message?.takeIf { it.isNotBlank() } ?: "Cloud HTTP $code")
            }
            return text.ifBlank { "{}" }
        } finally {
            connection.disconnect()
        }
    }

    private fun encode(value: String): String = URLEncoder.encode(value, Charsets.UTF_8.name())

    companion object { private const val MAX_RESPONSE_BYTES = 8 * 1024 * 1024 }
}

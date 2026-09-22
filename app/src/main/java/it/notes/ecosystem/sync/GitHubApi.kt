package it.notes.ecosystem.sync

import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.util.Base64
import it.notes.ecosystem.domain.Attachments

class GitHubFailure(val status: Int, val retryAt: Long = 0L) : IOException(when (status) {
    401 -> "Accesso GitHub scaduto o token non valido. Ricollega il repository."
    403 -> "GitHub ha rifiutato l'accesso: controlla permessi, regole del repository o limite richieste."
    404 -> "Repository, ramo o file non accessibile. Controlla nome e autorizzazioni."
    409, 422 -> "GitHub è cambiato o il ramo rifiuta la scrittura. Riprova e controlla le regole del ramo."
    429 -> "Limite GitHub raggiunto. La sincronizzazione verrà ritentata."
    else -> "GitHub non disponibile (HTTP $status)."
})

data class GitHubConfig(val owner: String, val repo: String, val branch: String,
    val folder: String, val token: String, val allowPublic: Boolean = false) {
    val key get() = listOf(owner.lowercase(java.util.Locale.ROOT), repo.lowercase(java.util.Locale.ROOT), branch, folder).joinToString("\u0000")
    fun validate() {
        require(owner.matches(Regex("[A-Za-z0-9-]{1,100}")) && repo.matches(Regex("[A-Za-z0-9_.-]{1,100}"))) { "Indica proprietario e repository validi." }
        require(repo != "." && repo != "..")
        require(branch.isNotBlank() && branch.length <= 200 && !branch.any { it.isISOControl() }) { "Indica il ramo." }
        require(folder.split('/').all { it.matches(Regex("[A-Za-z0-9_-]{1,60}")) } && folder.length <= 160) { "Cartella: usa lettere, numeri, trattini e /, senza spazi." }
        require(token.isNotBlank() && !token.any { it.isWhitespace() }) { "Inserisci un token valido." }
    }
    // Never include the token in logs or UI.
    override fun toString() = "$owner/$repo · $branch · $folder"
}

data class RemoteFile(val name: String, val sha: String)
interface GitHubTransport {
    fun head(): String
    fun list(head: String): List<RemoteFile>
    fun read(file: RemoteFile, head: String): SyncDocument
    fun write(document: SyncDocument, expectedSha: String?): String
}

class GitHubApi(private val config: GitHubConfig) : GitHubTransport, AttachmentRemote {
    private fun enc(s: String) = URLEncoder.encode(s, "UTF-8").replace("+", "%20")
    private val root get() = "/repos/${enc(config.owner)}/${enc(config.repo)}"
    private fun path(name: String = "") = (config.folder + if (name.isEmpty()) "" else "/$name").split('/').joinToString("/") { enc(it) }
    private fun request(method: String, path: String, body: JSONObject? = null, limit: Int = 2 * 1024 * 1024, accept: String = "application/vnd.github+json"): String {
        val c = URL("https://api.github.com$path").openConnection() as HttpURLConnection
        c.requestMethod = method; c.instanceFollowRedirects = false
        c.connectTimeout = 15000; c.readTimeout = 20000
        c.setRequestProperty("Authorization", "Bearer ${config.token}")
        c.setRequestProperty("Accept", accept)
        c.setRequestProperty("X-GitHub-Api-Version", "2026-03-10")
        c.setRequestProperty("User-Agent", "Notes-Ecosistema")
        try {
            if (body != null) {
                c.doOutput = true; c.setRequestProperty("Content-Type", "application/json; charset=utf-8")
                c.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
            }
            val code = c.responseCode
            if (code !in 200..299) {
                val retryAfter = c.getHeaderField("Retry-After")?.toLongOrNull()
                val reset = c.getHeaderField("X-RateLimit-Reset")?.toLongOrNull()
                val limited = code == 429 || (code == 403 && (retryAfter != null || c.getHeaderField("X-RateLimit-Remaining") == "0"))
                val retryAt = if (limited) maxOf(System.currentTimeMillis() + 60000,
                    retryAfter?.let { System.currentTimeMillis() + it.coerceIn(0, 86400) * 1000 } ?: 0,
                    reset?.let { it.coerceAtMost(System.currentTimeMillis() / 1000 + 86400) * 1000 } ?: 0) else 0
                throw GitHubFailure(code, retryAt)
            }
            val bytes = c.inputStream.use { it.readBytesLimited(limit) }
            return strictUtf8(bytes)
        } finally { c.disconnect() }
    }
    private val assetIndexes=mutableMapOf<String,MutableMap<String,JSONObject>>()
    private fun assetIndex(ref:String):MutableMap<String,JSONObject> = assetIndexes.getOrPut(ref) {
        val response=try {request("GET","$root/contents/${path("assets")}?ref=${enc(ref)}")}
            catch(e:GitHubFailure){if(e.status==404)return@getOrPut mutableMapOf() else throw e}
        val array=JSONArray(response);require(array.length()<1000){"Cartella allegati GitHub troppo grande."}
        val result=mutableMapOf<String,JSONObject>()
        for(i in 0 until array.length()) {
            val item=array.getJSONObject(i);val name=item.getString("name")
            if(Attachments.validKey(name)) {
                require(item.getString("type")=="file" && item.getLong("size") in 1..Attachments.FILE_LIMIT.toLong()) {"Allegato remoto non valido o oltre 8 MiB."}
                require(item.getString("sha").matches(Regex("[a-f0-9]{40}")))
                result[name]=item
            }
        }
        require(result.size<=Attachments.MAX_FILES){"Repository oltre 500 allegati."};result
    }
    private fun attachmentInfo(key:String,ref:String):JSONObject? {require(Attachments.validKey(key));return assetIndex(ref)[key]}
    override fun downloadAttachment(key:String,head:String):ByteArray {
        val info=attachmentInfo(key,head) ?: throw IOException("Allegato remoto non ancora disponibile. Ripristina il file o sincronizza il dispositivo originale.")
        val blob=JSONObject(request("GET","$root/git/blobs/${info.getString("sha")}",limit=12*1024*1024))
        require(blob.getString("encoding")=="base64" && blob.getString("sha")==info.getString("sha"))
        val bytes=Base64.getMimeDecoder().decode(blob.getString("content"))
        require(bytes.size.toLong()==info.getLong("size"));Attachments.verify(key,bytes);return bytes
    }
    override fun uploadAttachment(key:String,bytes:ByteArray) {
        Attachments.verify(key,bytes)
        fun matches(info:JSONObject)=info.getString("sha")==Attachments.gitSha(bytes) && info.getLong("size")==bytes.size.toLong()
        val existing=attachmentInfo(key,config.branch)
        if(existing!=null) {check(matches(existing)){"Il file remoto non corrisponde all’impronta dell’allegato: nessuna sovrascrittura eseguita."};return}
        val body=JSONObject().put("message","Notes: aggiungi allegato").put("branch",config.branch)
            .put("content",Base64.getEncoder().encodeToString(bytes))
        require(assetIndex(config.branch).size<Attachments.MAX_FILES){"Repository oltre 500 allegati."}
        try {
            val created=JSONObject(request("PUT","$root/contents/${path("assets/$key")}",body)).getJSONObject("content")
            check(matches(created)){"Verifica allegato caricato non riuscita."}
            assetIndex(config.branch)[key]=created
        }
        catch(e:GitHubFailure) {
            if(e.status !in listOf(409,422))throw e
            assetIndexes.remove(config.branch)
            val raced=attachmentInfo(key,config.branch)
            if(raced==null || !matches(raced))throw e
        }
    }
    fun verify(): Boolean {
        val repo = JSONObject(request("GET", root))
        check(repo.optJSONObject("permissions")?.optBoolean("push", false) == true) { "Serve accesso in scrittura al repository." }
        head() // An initialized repository and existing branch are required.
        return repo.getBoolean("private")
    }
    override fun head() = JSONObject(request("GET", "$root/git/ref/heads/${config.branch.split('/').joinToString("/") { enc(it) }}"))
        .getJSONObject("object").getString("sha")
    override fun list(head: String): List<RemoteFile> {
        val response = try { request("GET", "$root/contents/${path()}?ref=${enc(head)}") }
            catch (e: GitHubFailure) { if (e.status == 404) return emptyList() else throw e }
        val array = JSONArray(response)
        require(array.length() < 1000) { "Cartella troppo grande: impossibile verificare tutte le note." }
        return (0 until array.length()).mapNotNull { i ->
            val o = array.getJSONObject(i); val name = o.getString("name")
            if (!name.matches(Regex("[a-f0-9]{64}\\.md"))) null else {
                require(o.getString("type") == "file" && o.getLong("size") <= SyncCodec.MAX_BYTES) { "File note non valido o troppo grande." }
                RemoteFile(name, o.getString("sha"))
            }
        }.also { require(it.size <= 500) { "Questa versione sincronizza fino a 500 note." } }
    }
    override fun read(file: RemoteFile, head: String): SyncDocument {
        val o = JSONObject(request("GET", "$root/contents/${path(file.name)}?ref=${enc(head)}"))
        require(o.getString("sha") == file.sha && o.getString("encoding") == "base64")
        val bytes = Base64.getMimeDecoder().decode(o.getString("content"))
        require(bytes.size <= SyncCodec.MAX_BYTES)
        return SyncCodec.decode(strictUtf8(bytes)).also { require(SyncCodec.filename(it.id) == file.name) { "ID e nome del file non corrispondono." } }
    }
    override fun write(document: SyncDocument, expectedSha: String?): String {
        val text = SyncCodec.encode(document).toByteArray(Charsets.UTF_8)
        require(text.size <= SyncCodec.MAX_BYTES) { "Nota oltre 256 KB: sincronizzazione sospesa." }
        val body = JSONObject().put("message", "Notes: aggiorna nota")
            .put("branch", config.branch).put("content", Base64.getEncoder().encodeToString(text))
        if (expectedSha != null) body.put("sha", expectedSha)
        return JSONObject(request("PUT", "$root/contents/${path(SyncCodec.filename(document.id))}", body))
            .getJSONObject("content").getString("sha")
    }
}

internal fun java.io.InputStream.readBytesLimited(limit: Int): ByteArray {
    val output = java.io.ByteArrayOutputStream(); val buffer = ByteArray(8192)
    while (true) { val count = read(buffer); if (count < 0) break
        require(output.size() + count <= limit) { "Risposta troppo grande." }; output.write(buffer, 0, count) }
    return output.toByteArray()
}
internal fun strictUtf8(bytes: ByteArray): String = Charsets.UTF_8.newDecoder()
    .onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT)
    .decode(ByteBuffer.wrap(bytes)).toString()

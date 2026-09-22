package it.notes.ecosystem.sync

import it.notes.ecosystem.domain.Attachments
import it.notes.ecosystem.media.AttachmentFiles
import java.io.IOException

interface AttachmentRemote {
    fun downloadAttachment(key:String,head:String):ByteArray
    /** Immutable create or verified reuse. Never replace a different remote file. */
    fun uploadAttachment(key:String,bytes:ByteArray)
}
class AttachmentSync(private val notes:GitHubTransport,private val remote:AttachmentRemote,
    private val files:AttachmentFiles,private val progress:(String)->Unit={}):GitHubTransport {
    private val uploaded=mutableSetOf<String>()
    private val checked=mutableSetOf<String>()
    private val sizes=mutableMapOf<String,Int>()
    private fun reserve(key:String,size:Int) {
        require(size in 1..Attachments.FILE_LIMIT)
        val next=sizes.toMutableMap().apply {put(key,size)}
        require(next.size<=Attachments.MAX_FILES && next.values.sumOf {it.toLong()}<=Attachments.BATCH_LIMIT){"Allegati del passaggio oltre 64 MiB o 500 file."}
        sizes[key]=size
    }
    override fun head()=notes.head()
    override fun list(head:String)=notes.list(head)
    override fun read(file:RemoteFile,head:String):SyncDocument = notes.read(file,head).also {download(it,head)}
    fun download(document:SyncDocument,head:String) {
        if(document.sketch!=null)return
        val keys=Attachments.refs(document.body).map {it.key}.distinct()
        keys.forEachIndexed {i,key->
            if(key !in checked) {
                progress("Allegati: controllo ${i+1}/${keys.size}")
                val existing=runCatching {files.read(key)}.getOrNull()
                val bytes=existing ?: remote.downloadAttachment(key,head)
                Attachments.verify(key,bytes);reserve(key,bytes.size)
                if(existing==null)files.put(key,bytes)
                checked+=key
            }
        }
    }
    fun ensurePublished(document:SyncDocument) {
        if(document.sketch==null) {
            val keys=Attachments.refs(document.body).map {it.key}.distinct()
            keys.forEachIndexed {i,key->if(key !in uploaded) {
                progress("Allegati: invio ${i+1}/${keys.size}")
                val local=runCatching {files.read(key)}.getOrNull()
                val bytes=local ?: remote.downloadAttachment(key,notes.head())
                Attachments.verify(key,bytes);reserve(key,bytes.size)
                if(local==null)files.put(key,bytes)
                remote.uploadAttachment(key,bytes)
                uploaded+=key;checked+=key
            } }
        }
    }
    override fun write(document:SyncDocument,expectedSha:String?):String {
        ensurePublished(document)
        return notes.write(document,expectedSha)
    }
}

package it.notes.ecosystem.media

import it.notes.ecosystem.domain.*
import it.notes.ecosystem.data.BackupReader
import it.notes.ecosystem.data.BackupWriter
import org.json.JSONObject
import org.json.JSONArray
import java.io.*
import java.nio.file.Files
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

class MediaBundlePreview(val snapshot:BackupSnapshot,val staging:File,val keys:Set<String>,val bytes:Long):Closeable {
    fun install(store:AttachmentFiles) {keys.forEach {key->store.put(key,File(staging,key).inputStream().use {readLimited(it,Attachments.FILE_LIMIT)})}}
    override fun close() {staging.listFiles().orEmpty().forEach {it.delete()};staging.delete()}
}
object MediaBundle {
    fun write(snapshot:BackupSnapshot,store:AttachmentFiles,output:OutputStream,onProgress:(Int,Int)->Unit={_,_->}) {
        val keys=Attachments.keys(snapshot).sorted();require(keys.size<=Attachments.MAX_FILES)
        val json=BackupWriter.json(snapshot).toByteArray(Charsets.UTF_8)
        require(json.size<=5*1024*1024){"Il backup delle note supera 5 MiB."}
        // Validate every referenced file before creating a supposedly complete backup.
        var total=0L
        keys.forEach {key->total+=store.read(key).size;require(total<=Attachments.BATCH_LIMIT){"Gli allegati del backup superano 64 MiB."}}
        ZipOutputStream(output).use {zip ->
            fun entry(name:String,bytes:ByteArray) {zip.putNextEntry(ZipEntry(name));zip.write(bytes);zip.closeEntry()}
            entry("bundle.json",JSONObject().put("format","notes-ecosystem-media").put("version",1).put("assets",JSONArray(keys)).toString().toByteArray())
            entry("backup.json",json)
            keys.forEachIndexed {i,key->entry("assets/$key",store.read(key));onProgress(i+1,keys.size)}
            snapshot.notes.filter {it.deletedAt==null}.forEachIndexed {i,n->
                when (n.sketch?.kind) {
                    VisualDocumentKind.SKETCH -> entry("disegni/${i+1}.sketch.json", n.body.toByteArray())
                    VisualDocumentKind.WHITEBOARD -> entry("lavagne/${i+1}.whiteboard.json", n.body.toByteArray())
                    null -> entry("note/${i+1}.md", ("# "+n.title+"\n\n"+Attachments.portable(n.body)).toByteArray())
                }
            }
            entry("LEGGIMI.txt","Importa questo ZIP completo in Notes 0.17+. backup.json da solo non contiene i file multimediali. assets contiene originali verificati SHA-256. Ricerche salvate, revisioni locali e timer attivo non inclusi. File non cifrati.".toByteArray())
        }
    }
    fun read(input:InputStream,tempRoot:File):MediaBundlePreview {
        check(tempRoot.isDirectory || tempRoot.mkdirs())
        val stage=Files.createTempDirectory(tempRoot.toPath(),"bundle-").toFile()
        var snapshot:BackupSnapshot?=null;var manifest:Set<String>?=null;val assets=mutableSetOf<String>();val seen=mutableSetOf<String>()
        var total=0L;var compressed=0L;var assetBytes=0L
        val bounded=object:FilterInputStream(input) {
            override fun read():Int {val v=super.read();if(v>=0){compressed++;require(compressed<=80L*1024*1024)};return v}
            override fun read(b:ByteArray,off:Int,len:Int):Int {val n=`in`.read(b,off,len);if(n>0){compressed+=n;require(compressed<=80L*1024*1024)};return n}
        }
        try {
            ZipInputStream(bounded).use {zip ->
                while(true) {
                    val e=zip.nextEntry ?: break
                    require(!e.isDirectory && seen.add(e.name) && seen.size<=11005){"Voce ZIP duplicata o non valida."}
                    val key=e.name.removePrefix("assets/")
                    val asset=e.name.startsWith("assets/") && Attachments.validKey(key)
                    val allowed=asset || e.name in listOf("bundle.json","backup.json","LEGGIMI.txt") || e.name.matches(Regex("note/[0-9]+\\.md|disegni/[0-9]+\\.sketch\\.json|lavagne/[0-9]+\\.whiteboard\\.json"))
                    require(allowed){"Percorso ZIP non consentito."}
                    val limit=when {asset->Attachments.FILE_LIMIT;e.name=="backup.json"->5*1024*1024;e.name=="bundle.json"->100000;e.name=="LEGGIMI.txt"->10000;else->Attachments.FILE_LIMIT}
                    val bytes=readLimited(zip,limit);total+=bytes.size
                    require(total<=80L*1024*1024){"Archivio espanso oltre 80 MiB."}
                    when {
                        asset->{require(assets.size<Attachments.MAX_FILES);Attachments.verify(key,bytes);assets+=key;assetBytes+=bytes.size;require(assetBytes<=Attachments.BATCH_LIMIT);File(stage,key).writeBytes(bytes)}
                        e.name=="backup.json"->snapshot=BackupReader.parse(strictText(bytes))
                        e.name=="bundle.json"->{val o=JSONObject(strictText(bytes));require(o.getString("format")=="notes-ecosystem-media" && o.getInt("version")==1);val a=o.getJSONArray("assets");require(a.length()<=Attachments.MAX_FILES);val list=(0 until a.length()).map {a.getString(it)};require(list.all(Attachments::validKey) && list.distinct().size==list.size);manifest=list.toSet()}
                    }
                    zip.closeEntry()
                }
            }
            val data=checkNotNull(snapshot){"backup.json mancante."}
            require(manifest!=null && manifest==assets && assets==Attachments.keys(data)){"Allegati mancanti o non coerenti con le note."}
            return MediaBundlePreview(data,stage,assets,assetBytes)
        } catch(t:Throwable) {stage.listFiles().orEmpty().forEach {it.delete()};stage.delete();throw t}
    }
    private fun strictText(bytes:ByteArray)=Charsets.UTF_8.newDecoder().onMalformedInput(java.nio.charset.CodingErrorAction.REPORT)
        .onUnmappableCharacter(java.nio.charset.CodingErrorAction.REPORT).decode(java.nio.ByteBuffer.wrap(bytes)).toString()
}

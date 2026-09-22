package it.notes.ecosystem.media

import it.notes.ecosystem.domain.Attachments
import it.notes.ecosystem.domain.AttachmentType
import java.io.File
import java.io.InputStream
import java.io.ByteArrayOutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption

class AttachmentFiles(val root:File) {
    init {check(root.isDirectory || root.mkdirs()){"Impossibile aprire lo spazio allegati."}}
    fun file(key:String):File {require(Attachments.validKey(key));return File(root,key)}
    @Synchronized fun read(key:String):ByteArray {
        val source=file(key);check(source.isFile){"Allegato non presente: sincronizza o importa il backup completo."}
        val bytes=source.inputStream().use {readLimited(it,Attachments.FILE_LIMIT)}
        Attachments.verify(key,bytes);return bytes
    }
    @Synchronized fun contains(key:String):Boolean = file(key).isFile
    @Synchronized fun verifiedFile(key:String):File {read(key);return file(key)}
    @Synchronized fun ingest(input:InputStream,type:AttachmentType):String {
        val bytes=readLimited(input,Attachments.FILE_LIMIT);val key=Attachments.key(bytes,type);put(key,bytes);return key
    }
    @Synchronized fun put(key:String,bytes:ByteArray) {
        Attachments.verify(key,bytes)
        val target=file(key)
        if(target.isFile && runCatching {read(key).contentEquals(bytes)}.getOrDefault(false)) {
            target.setLastModified(System.currentTimeMillis());return
        }
        val files=root.listFiles().orEmpty().filter {it.isFile && Attachments.validKey(it.name)}
        check(files.size<Attachments.MAX_FILES || target.isFile){"Limite di 500 allegati sul dispositivo. Libera i file inutilizzati nelle Impostazioni."}
        check(files.sumOf {it.length()}-target.length()+bytes.size<=Attachments.STORE_LIMIT){"Spazio allegati oltre 256 MiB. Libera i file inutilizzati nelle Impostazioni."}
        val temp=File.createTempFile("incoming-",".tmp",root)
        try {
            temp.outputStream().use {it.write(bytes);it.fd.sync()}
            Files.move(temp.toPath(),target.toPath(),StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING)
        } finally {temp.delete()}
    }
    @Synchronized fun usage():Pair<Int,Long> {val files=root.listFiles().orEmpty().filter {it.isFile && Attachments.validKey(it.name)};return files.size to files.sumOf {it.length()}}
    /** References include current notes, drafts and every locally retained revision. Seven-day grace protects in-flight imports. */
    @Synchronized fun cleanup(referenced:Set<String>,now:Long=System.currentTimeMillis()):Int {
        val cutoff=now-7L*24*60*60*1000
        return root.listFiles().orEmpty().count {f->f.isFile && Attachments.validKey(f.name) && f.name !in referenced && f.lastModified()<cutoff && f.delete()}
    }
}
fun readLimited(input:InputStream,limit:Int):ByteArray {
    val output=ByteArrayOutputStream();val buffer=ByteArray(8192)
    while(true) {val n=input.read(buffer);if(n<0)break;require(n<=limit-output.size()){"File oltre il limite consentito."};output.write(buffer,0,n)}
    return output.toByteArray()
}

/** Only our named temporary files, older than seven days. Never touches stored attachments. */
fun cleanupMediaTemporaryFiles(cache:File,now:Long=System.currentTimeMillis()) {
    val cutoff=now-7L*24*60*60*1000
    File(cache,"media_capture").listFiles().orEmpty().filter {it.isFile && it.name.matches(Regex("(voice|photo)-[a-zA-Z0-9-]+\\.(m4a|jpg)")) && it.lastModified()<cutoff}.forEach {it.delete()}
    File(cache,"media_imports").listFiles().orEmpty().filter {it.isDirectory && it.name.startsWith("bundle-") && it.lastModified()<cutoff}.forEach {dir->
        dir.listFiles().orEmpty().filter {it.isFile && Attachments.validKey(it.name)}.forEach {it.delete()};dir.delete()
    }
}

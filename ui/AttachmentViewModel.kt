package it.notes.ecosystem.ui

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import android.media.MediaRecorder
import android.media.MediaPlayer
import android.media.MediaMetadataRetriever
import androidx.compose.runtime.*
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import it.notes.ecosystem.NotesApplication
import it.notes.ecosystem.domain.*
import kotlinx.coroutines.*
import java.io.File

class AttachmentViewModel(private val app:NotesApplication,private val editor:EditorViewModel):ViewModel() {
    val store get()=app.attachments
    var busy by mutableStateOf(false);private set
    var recording by mutableStateOf(false);private set
    var startedAt by mutableLongStateOf(0);private set
    var error by mutableStateOf<String?>(null);private set
    var playing by mutableStateOf<String?>(null);private set
    var refresh by mutableIntStateOf(0);private set
    var pendingRecordings by mutableStateOf<List<File>>(emptyList());private set
    private val recordingPrefix="voice-${Attachments.digest(editor.noteId.toByteArray()).take(16)}-"
    private val captureDir get()=File(app.filesDir,"media_pending").apply {mkdirs()}
    companion object {private val activeRecordings=java.util.concurrent.ConcurrentHashMap.newKeySet<String>()}
    init {refreshPending()}
    fun refreshPending(){viewModelScope.launch {pendingRecordings=withContext(Dispatchers.IO){captureDir.listFiles().orEmpty().filter {it.isFile && it.name.startsWith(recordingPrefix) && it.name.endsWith(".m4a") && it.absolutePath !in activeRecordings}.sortedByDescending {it.lastModified()}}}}
    fun discardRecording(file:File){
        if(busy || recording || file !in pendingRecordings)return
        viewModelScope.launch {withContext(Dispatchers.IO){file.delete()};refreshPending()}
    }
    fun recoverRecording(file:File)=operation {check(file in pendingRecordings);attachRecording(file)}
    private suspend fun attachRecording(file:File) {
        val key=withContext(Dispatchers.IO){
            require(file.canonicalFile.parentFile==captureDir.canonicalFile && file.name.startsWith(recordingPrefix))
            require(file.length() in 1..Attachments.FILE_LIMIT.toLong()) {"Registrazione vuota o troppo grande."}
            val metadata=MediaMetadataRetriever()
            try {
                metadata.setDataSource(file.absolutePath)
                require((metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0)>0){"Registrazione troppo breve o non leggibile."}
            } finally {metadata.release()}
            file.inputStream().use {store.ingest(it,AttachmentType.M4A)}
        }
        if(Attachments.refs(editor.body).none {it.key==key})check(editor.attach(key,"Registrazione ${java.time.LocalDateTime.now().withNano(0)}")){editor.error ?: "Registrazione non collegata."}
        editor.awaitAttachmentDraft()
        withContext(Dispatchers.IO){file.delete()}
    }
    private var recorder:MediaRecorder?=null
    private var recordingFile:File?=null
    private var player:MediaPlayer?=null
    private var playJob:Job?=null
    private var stopJob:Job?=null
    fun message(value:String){error=value}
    fun refreshFiles(){refresh++}
    fun requestSync(){
        error=null;refresh++
        if(app.githubSync.status.value.connection==null)error="Per recuperare file mancanti, importa un backup completo o configura GitHub nelle Impostazioni."
        else app.githubSync.schedule()
    }
    private fun operation(block:suspend ()->Unit) {
        if(busy || recording || !editor.available || editor.saving || editor.checklistWorking)return
        busy=true;editor.setAttachmentWork(true);error=null
        viewModelScope.launch {
            try {block();refresh++}
            catch(e:CancellationException){throw e}
            catch(e:Exception){error=e.message ?: "Operazione allegati non riuscita."}
            finally {busy=false;editor.setAttachmentWork(false);refreshPending()}
        }
    }
    fun importUris(uris:List<Uri>) = operation {
        require(uris.size<=20){"Seleziona al massimo 20 file."}
        require(uris.all {it.scheme=="content"}){"Seleziona i file tramite il selettore documenti Android."}
        for(uri in uris) {
            val imported=withContext(Dispatchers.IO) {
                val resolver=app.contentResolver
                val name=resolver.query(uri,arrayOf(OpenableColumns.DISPLAY_NAME),null,null,null)?.use {c->if(c.moveToFirst())c.getString(0) else null} ?: "Allegato"
                val mime=resolver.getType(uri)?.lowercase()
                val ext=name.substringAfterLast('.',"").lowercase()
                val type=AttachmentType.entries.firstOrNull {it.mime==mime}
                    ?: when(mime){"audio/x-wav"->AttachmentType.WAV;"audio/x-m4a"->AttachmentType.M4A;else->null}
                    ?: AttachmentType.entries.firstOrNull {it.ext==ext || ext=="jpeg" && it==AttachmentType.JPEG}
                    ?: error("Formato non supportato. Usa immagini JPEG/PNG/WebP, audio M4A/MP3/WAV/OGG, PDF, TXT o documenti Office moderni.")
                val input=resolver.openInputStream(uri) ?: error("Impossibile leggere il file.")
                val key=input.use {store.ingest(it,type)}
                key to name
            }
            check(editor.attach(imported.first,imported.second)){editor.error ?: "File copiato, ma non collegato: riprova."}
            editor.awaitAttachmentDraft()
        }
    }
    fun importPhoto(file:File) = operation {
        try {
            val key=withContext(Dispatchers.IO){file.inputStream().use {store.ingest(it,AttachmentType.JPEG)}}
            check(editor.attach(key,"Foto ${java.time.LocalDate.now()}")){editor.error ?: "Foto non collegata."}
            editor.awaitAttachmentDraft()
        } finally {withContext(Dispatchers.IO){file.delete()}}
    }
    @Suppress("DEPRECATION")
    fun startRecording() {
        if(busy || recording || !editor.available || editor.saving || editor.checklistWorking)return
        stopPlaying();error=null
        try {
            require(editor.body.length<=199500){"La nota è troppo lunga: riduci il testo prima di registrare."}
            Attachments.append(editor.body,"0".repeat(64)+".m4a","Registrazione")
        } catch(e:Exception){error=e.message;return}
        val dir=captureDir
        val file=try {File.createTempFile(recordingPrefix,".m4a",dir)}catch(e:Exception){error="Spazio per registrare non disponibile.";return}
        val r=try {if(android.os.Build.VERSION.SDK_INT>=31)MediaRecorder(app)else MediaRecorder()}catch(e:Exception){file.delete();error="Registratore non disponibile.";return}
        activeRecordings.add(file.absolutePath)
        try {
            r.setAudioSource(MediaRecorder.AudioSource.MIC);r.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            r.setAudioEncoder(MediaRecorder.AudioEncoder.AAC);r.setAudioEncodingBitRate(96000);r.setAudioSamplingRate(44100)
            r.setOutputFile(file.absolutePath);r.setMaxDuration(5*60*1000);r.setMaxFileSize(Attachments.FILE_LIMIT.toLong())
            r.setOnInfoListener {_,what,_->if(what==MediaRecorder.MEDIA_RECORDER_INFO_MAX_DURATION_REACHED || what==MediaRecorder.MEDIA_RECORDER_INFO_MAX_FILESIZE_REACHED)stopRecording()}
            r.prepare();r.start();recorder=r;recordingFile=file;recording=true;startedAt=android.os.SystemClock.elapsedRealtime();editor.setAttachmentWork(true)
            stopJob=viewModelScope.launch {delay(5*60*1000L);stopRecording()}
        } catch(e:Exception) {r.release();activeRecordings.remove(file.absolutePath);file.delete();error="Microfono non disponibile: "+(e.message ?: "controlla il permesso.")}
    }
    fun stopRecording() {
        val r=recorder ?: return
        recorder=null;recording=false;stopJob?.cancel();stopJob=null
        val file=recordingFile;recordingFile=null
        // Some devices stop themselves at the duration limit. Validate the finalized file instead of discarding it blindly.
        runCatching {r.stop()};r.release();busy=true
        viewModelScope.launch {
            try {
                attachRecording(checkNotNull(file))
                refresh++
            } catch(e:CancellationException){throw e}
            catch(e:Exception){error=e.message ?: "Registrazione non salvata."}
            finally {file?.let {activeRecordings.remove(it.absolutePath)};busy=false;editor.setAttachmentWork(false);refreshPending()}
        }
    }
    fun stopPlaying(){playJob?.cancel();playJob=null;player?.release();player=null;playing=null}
    fun togglePlay(ref:AttachmentRef) {
        if(playing==ref.key){stopPlaying();return}
        stopPlaying()
        playJob=viewModelScope.launch {
            try {
                val file=withContext(Dispatchers.IO){store.verifiedFile(ref.key)}
                val p=MediaPlayer();player=p;playing=ref.key
                p.setOnPreparedListener {if(player===it)it.start()}
                p.setOnCompletionListener {if(player===it)stopPlaying()}
                p.setOnErrorListener {_,_,_->stopPlaying();error="Audio non riproducibile.";true}
                p.setDataSource(file.absolutePath);p.prepareAsync()
            } catch(e:CancellationException){throw e}
            catch(e:Exception){stopPlaying();error=e.message ?: "Audio non disponibile."}
        }
    }
    fun onBackground(){stopPlaying();if(recording)stopRecording()}
    override fun onCleared(){stopJob?.cancel();runCatching{recorder?.stop()};recorder?.release();recorder=null;recordingFile?.let {activeRecordings.remove(it.absolutePath)};stopPlaying();editor.setAttachmentWork(false);super.onCleared()}
}

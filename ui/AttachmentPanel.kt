package it.notes.ecosystem.ui

import android.Manifest
import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import it.notes.ecosystem.domain.*
import kotlinx.coroutines.*
import java.io.File
import java.util.UUID

internal fun decodeAttachmentImage(file:File,edge:Int):Bitmap {
    val bounds=BitmapFactory.Options().apply {inJustDecodeBounds=true}
    BitmapFactory.decodeFile(file.absolutePath,bounds)
    require(bounds.outWidth in 1..30000 && bounds.outHeight in 1..30000){"Dimensioni immagine non supportate."}
    var sample=1
    while(bounds.outWidth/sample>edge || bounds.outHeight/sample>edge)sample*=2
    val bitmap=BitmapFactory.decodeFile(file.absolutePath,BitmapFactory.Options().apply {inSampleSize=sample}) ?: error("Immagine non leggibile.")
    val orientation=runCatching {ExifInterface(file.absolutePath).getAttributeInt(ExifInterface.TAG_ORIENTATION,ExifInterface.ORIENTATION_NORMAL)}.getOrDefault(1)
    val matrix=Matrix()
    when(orientation) {
        2->matrix.setScale(-1f,1f);3->matrix.setRotate(180f);4->matrix.setScale(1f,-1f)
        5->{matrix.setRotate(90f);matrix.postScale(-1f,1f)};6->matrix.setRotate(90f)
        7->{matrix.setRotate(-90f);matrix.postScale(-1f,1f)};8->matrix.setRotate(-90f)
    }
    return if(matrix.isIdentity)bitmap else Bitmap.createBitmap(bitmap,0,0,bitmap.width,bitmap.height,matrix,true).also {if(it!==bitmap)bitmap.recycle()}
}
@Composable
private fun AttachmentImage(ref:AttachmentRef,model:AttachmentViewModel,large:Boolean=false) {
    val state by produceState<Pair<Bitmap?,String?>?>(null,ref.key,model.refresh,large) {
        value=try {withContext(Dispatchers.IO){decodeAttachmentImage(model.store.verifiedFile(ref.key),if(large)2048 else 480) to null}}
        catch(e:CancellationException){throw e}catch(e:Exception){null to (e.message ?: "Immagine non disponibile.")}
    }
    var scale by remember(ref.key){mutableFloatStateOf(1f)}
    var x by remember(ref.key){mutableFloatStateOf(0f)};var y by remember(ref.key){mutableFloatStateOf(0f)}
    Box((if(large)Modifier.fillMaxSize() else Modifier.fillMaxWidth().height(140.dp)).clipToBounds()
        .then(if(large)Modifier.pointerInput(ref.key){detectTransformGestures {_,pan,zoom,_->scale=(scale*zoom).coerceIn(1f,4f);x=(x+pan.x).coerceIn(-size.width.toFloat()*scale,size.width.toFloat()*scale);y=(y+pan.y).coerceIn(-size.height.toFloat()*scale,size.height.toFloat()*scale)}} else Modifier)) {
        val bitmap=state?.first
        if(bitmap!=null)Image(bitmap.asImageBitmap(),ref.name,Modifier.fillMaxSize().graphicsLayer {scaleX=scale;scaleY=scale;translationX=x;translationY=y},contentScale=ContentScale.Fit)
        else if(state==null)LinearProgressIndicator(Modifier.fillMaxWidth())
        else Text(state?.second ?: "Immagine non disponibile.")
    }
}

@OptIn(ExperimentalMaterial3Api::class,ExperimentalLayoutApi::class)
@Composable
fun AttachmentPanel(editor:EditorViewModel,model:AttachmentViewModel,expanded:Boolean,onDismiss:()->Unit) {
    val context=LocalContext.current
    val scope=rememberCoroutineScope()
    val sync=(context.applicationContext as it.notes.ecosystem.NotesApplication).githubSync
    val syncStatus by sync.status.collectAsStateWithLifecycle()
    LaunchedEffect(syncStatus.busy,syncStatus.message){if(!syncStatus.busy)model.refreshFiles()}
    val lifecycle=LocalLifecycleOwner.current
    DisposableEffect(lifecycle,model) {
        val observer=LifecycleEventObserver {_,event->if(event==Lifecycle.Event.ON_STOP)model.onBackground()}
        lifecycle.lifecycle.addObserver(observer)
        onDispose {lifecycle.lifecycle.removeObserver(observer);model.stopPlaying()}
    }
    BackHandler(enabled=model.recording || model.busy) {if(model.recording)model.stopRecording()}
    var cameraName by rememberSaveable {mutableStateOf<String?>(null)}
    val captureDir=remember(context){File(context.cacheDir,"media_capture").apply{mkdirs()}}
    val picker=rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()){uris->if(uris.isNotEmpty())model.importUris(uris)}
    val camera=rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()){success->
        cameraName?.let {name->val file=File(captureDir,name);if(success)model.importPhoto(file)else file.delete()};cameraName=null
    }
    val microphone=rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()){granted->if(granted)model.startRecording()else model.message("Microfono non autorizzato. Puoi abilitarlo nelle impostazioni Android dell’app.")}
    val current=editor.body
    val parsed by produceState<Pair<String,List<AttachmentRef>>?>(null,current) {value=current to withContext(Dispatchers.Default){Attachments.refs(current).distinctBy {it.key}}}
    val refs=parsed?.takeIf{it.first==current}?.second
    var viewing by remember {mutableStateOf<AttachmentRef?>(null)}
    var removing by remember {mutableStateOf<AttachmentRef?>(null)}
    var deletingRecording by remember {mutableStateOf<File?>(null)}
    LaunchedEffect(expanded){if(expanded)model.refreshPending()}
    val available=editor.available && !editor.saving && !editor.checklistWorking && !model.busy && !model.recording
    val canAdd=available && refs!=null && refs.size<20
    fun open(ref:AttachmentRef,share:Boolean) {
        scope.launch {
            try {
                val file=withContext(Dispatchers.IO){model.store.verifiedFile(ref.key)}
                val uri=FileProvider.getUriForFile(context,"${context.packageName}.sketchfiles",file)
                val intent=if(share)Intent(Intent.ACTION_SEND).setType(ref.type.mime).putExtra(Intent.EXTRA_STREAM,uri)
                    else Intent(Intent.ACTION_VIEW).setDataAndType(uri,ref.type.mime)
                intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);intent.clipData=ClipData.newRawUri(ref.name,uri)
                context.startActivity(Intent.createChooser(intent,if(share)"Condividi allegato" else "Apri documento"))
            } catch(e:CancellationException){throw e}catch(e:Exception){model.message(e.message ?: "Nessuna app disponibile per aprire il file.")}
        }
    }
    if(expanded) {
        val height=LocalConfiguration.current.screenHeightDp.dp*0.8f
        ModalBottomSheet(onDismissRequest={if(model.recording)model.stopRecording();model.stopPlaying();onDismiss()},sheetState=rememberModalBottomSheetState(skipPartiallyExpanded=true)) {
            Column(Modifier.fillMaxWidth().heightIn(max=height).padding(horizontal=20.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
                Text("Dentro la tua nota",style=MaterialTheme.typography.headlineSmall)
                Text("Fino a 20 allegati · 8 MiB per file",style=MaterialTheme.typography.bodySmall)
                FlowRow(horizontalArrangement=Arrangement.spacedBy(6.dp)) {
                    OutlinedButton(enabled=canAdd,onClick={picker.launch(AttachmentType.entries.map {it.mime}.toTypedArray())}) {Icon(Icons.Default.AttachFile,null);Text("File")}
                    OutlinedButton(enabled=canAdd,onClick={
                        runCatching {
                            val name="photo-${UUID.randomUUID()}.jpg";cameraName=name
                            camera.launch(FileProvider.getUriForFile(context,"${context.packageName}.sketchfiles",File(captureDir,name)))
                        }.onFailure {cameraName=null;model.message("Fotocamera non disponibile.")}
                    }) {Icon(Icons.Default.PhotoCamera,null);Text("Foto")}
                    OutlinedButton(enabled=canAdd || model.recording,onClick={
                        if(model.recording)model.stopRecording()
                        else if(ContextCompat.checkSelfPermission(context,Manifest.permission.RECORD_AUDIO)==PackageManager.PERMISSION_GRANTED)model.startRecording()
                        else microphone.launch(Manifest.permission.RECORD_AUDIO)
                    }) {Icon(if(model.recording)Icons.Default.Stop else Icons.Default.Mic,null);Text(if(model.recording)"Termina" else "Registra")}
                }
                TextButton(enabled=available,onClick=model::requestSync){Text("Sincronizza / riprova allegati")}
                if(model.recording) {
                    var elapsed by remember {mutableLongStateOf(0)}
                    LaunchedEffect(model.startedAt){while(isActive){elapsed=(android.os.SystemClock.elapsedRealtime()-model.startedAt)/1000;delay(500)}}
                    Text("Registrazione ${elapsed/60}:${(elapsed%60).toString().padStart(2,'0')} · massimo 5 minuti. Si ferma uscendo dall’app.",color=MaterialTheme.colorScheme.primary)
                }
                if(model.busy || refs==null)LinearProgressIndicator(Modifier.fillMaxWidth())
                model.error?.let {Text(it,color=MaterialTheme.colorScheme.error)}
                Text("Salva la nota per sincronizzare i nuovi allegati. Rimuovere un collegamento conserva il file per la cronologia.",style=MaterialTheme.typography.bodySmall)
                LazyColumn(Modifier.fillMaxWidth().weight(1f,fill=false),verticalArrangement=Arrangement.spacedBy(8.dp)) {
                    if(model.pendingRecordings.isNotEmpty())item {Column {Text("Registrazioni da recuperare",style=MaterialTheme.typography.titleMedium);Text("Collegale alla nota per includerle in backup e sincronizzazione.",style=MaterialTheme.typography.bodySmall)}}
                    items(model.pendingRecordings,key={"pending-"+it.name}) {file ->
                        OutlinedCard(Modifier.fillMaxWidth()) {Column(Modifier.padding(12.dp)) {
                            Text("Registrazione non ancora collegata · ${java.text.DateFormat.getDateTimeInstance().format(java.util.Date(file.lastModified()))}",style=MaterialTheme.typography.bodySmall)
                            FlowRow {
                                TextButton(enabled=canAdd,onClick={model.recoverRecording(file)}){Text("Recupera")}
                                TextButton(enabled=available,onClick={
                                    runCatching {
                                        val uri=FileProvider.getUriForFile(context,"${context.packageName}.sketchfiles",file)
                                        val intent=Intent(Intent.ACTION_SEND).setType("audio/mp4").putExtra(Intent.EXTRA_STREAM,uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                        intent.clipData=ClipData.newRawUri("Registrazione",uri);context.startActivity(Intent.createChooser(intent,"Salva registrazione"))
                                    }.onFailure {model.message("Condivisione non disponibile.")}
                                }){Text("Condividi")}
                                TextButton(enabled=available,onClick={deletingRecording=file}){Text("Elimina")}
                            }
                        }}
                    }
                    if(refs?.isEmpty()==true)item {Text("Aggiungi una foto, registra un pensiero o allega un documento.")}
                    items(refs.orEmpty(),key={it.key}) {ref ->
                        OutlinedCard(Modifier.fillMaxWidth()) {
                            Column(Modifier.padding(12.dp),verticalArrangement=Arrangement.spacedBy(4.dp)) {
                                Text(ref.name,style=MaterialTheme.typography.titleSmall)
                                if(ref.type.image)AttachmentImage(ref,model)
                                FlowRow {
                                    TextButton(enabled=available,onClick={when {ref.type.image->viewing=ref;ref.type.audio->model.togglePlay(ref);else->open(ref,false)}}){Text(if(ref.type.audio && model.playing==ref.key)"Ferma" else if(ref.type.audio)"Ascolta" else "Apri")}
                                    TextButton(enabled=available,onClick={open(ref,true)}){Text("Condividi")}
                                    TextButton(enabled=available,onClick={removing=ref}){Text("Rimuovi")}
                                }
                            }
                        }
                    }
                }
                Spacer(Modifier.height(16.dp))
            }
        }
    }
    deletingRecording?.let {file ->AlertDialog(onDismissRequest={deletingRecording=null},title={Text("Eliminare la registrazione non collegata?")},
        text={Text("Il file verrà rimosso dal dispositivo e non potrà essere recuperato. Puoi prima condividerlo per conservarne una copia.")},
        confirmButton={TextButton(enabled=available,onClick={model.discardRecording(file);deletingRecording=null}){Text("Elimina")}},
        dismissButton={TextButton(onClick={deletingRecording=null}){Text("Annulla")}})}
    removing?.let {ref ->AlertDialog(onDismissRequest={removing=null},title={Text("Rimuovere il collegamento?")},text={Text("Il file rimarrà disponibile per altre note e versioni precedenti. Salva la nota per confermare la modifica.")},
        confirmButton={TextButton(enabled=available,onClick={editor.editBody(Attachments.remove(editor.body,ref.key));model.stopPlaying();removing=null}){Text("Rimuovi")}},
        dismissButton={TextButton(onClick={removing=null}){Text("Annulla")}})}
    viewing?.let {ref ->Dialog(onDismissRequest={viewing=null},properties=DialogProperties(usePlatformDefaultWidth=false)) {
        Surface(Modifier.fillMaxSize(),color=MaterialTheme.colorScheme.background) {
            Column(Modifier.safeDrawingPadding().padding(16.dp)) {
                TextButton(onClick={viewing=null}){Text("Chiudi immagine")}
                Text(ref.name,style=MaterialTheme.typography.titleSmall)
                Box(Modifier.weight(1f)){AttachmentImage(ref,model,true)}
            }
        }
    }}
}

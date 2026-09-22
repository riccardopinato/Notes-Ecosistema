package it.notes.ecosystem.ui

import android.graphics.Bitmap
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import it.notes.ecosystem.NotesApplication
import it.notes.ecosystem.domain.*
import it.notes.ecosystem.domain.Collection
import kotlinx.coroutines.*
import java.time.LocalDate
import java.time.YearMonth
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.UUID

private val diaryDateFormat=DateTimeFormatter.ofPattern("d MMMM yyyy",Locale.ITALIAN)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun DiaryScreen(notes:List<Note>,collections:List<Collection>,repository:NotesRepository,
    onOpen:(String)->Unit,onCreate:(String,String?,Boolean)->Unit,onOpenTask:(String)->Unit,
    onSection:(String)->Unit,onManageCollections:()->Unit) {
    var selected by rememberSaveable {mutableStateOf(LocalDate.now().toString())}
    var monthText by rememberSaveable {mutableStateOf(YearMonth.now().toString())}
    var mode by rememberSaveable {mutableStateOf("Calendario")}
    var bookId by rememberSaveable {mutableStateOf<String?>(null)}
    var jump by rememberSaveable {mutableStateOf(false)}
    var newBook by rememberSaveable {mutableStateOf(false)}
    var bookName by rememberSaveable {mutableStateOf("")}
    var newTaskId by rememberSaveable {mutableStateOf<String?>(null)}
    var taskDate by rememberSaveable {mutableStateOf("")}
    var busy by remember {mutableStateOf(false)}
    var error by remember {mutableStateOf<String?>(null)}
    val scope=rememberCoroutineScope()
    val day=LocalDate.parse(selected);val month=YearMonth.parse(monthText)
    val selectedBook=collections.firstOrNull {it.id==bookId}
    // If a book was deleted remotely, expose all memories; do not pass a stale foreign key.
    val effectiveBook=selectedBook?.id
    val indexKey=notes to effectiveBook
    val result by produceState<Pair<Pair<List<Note>,String?>,DiaryIndex>?>(null,indexKey) {
        value=indexKey to withContext(Dispatchers.Default){Diary.index(notes,effectiveBook)}
    }
    val index=result?.takeIf {it.first==indexKey}?.second
    var today by remember {mutableStateOf(LocalDate.now())}
    LaunchedEffect(Unit) {while(true){today=LocalDate.now();delay(60000)}}
    BackHandler {if(!busy)onSection("Home")}
    fun action(block:suspend ()->Unit) {
        if(busy)return
        busy=true;error=null
        scope.launch {try {block()}catch(e:CancellationException){throw e}catch(e:Exception){error=e.message ?: "Operazione non riuscita."}finally{busy=false}}
    }
    Scaffold(topBar={TopAppBar(title={EditorialAppTitle("Diario")})},bottomBar={EcosystemNavigation("Diario",!busy,onSection)}) {padding->
        LazyColumn(Modifier.fillMaxSize().padding(padding),contentPadding=PaddingValues(20.dp),verticalArrangement=Arrangement.spacedBy(14.dp)) {
            item {EditorialSection("I giorni, le tue storie.","Pensieri, ricordi e impegni, ognuno al suo posto.")}
            item {Row(Modifier.horizontalScroll(rememberScrollState()),horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                listOf("Calendario","Galleria","Book").forEach {label->FilterChip(mode==label,{mode=label},label={Text(label)})}
            }}
            if(error!=null) item {Text(error.orEmpty(),color=MaterialTheme.colorScheme.error)}
            if(busy || index==null) item {LinearProgressIndicator(Modifier.fillMaxWidth())}
            item {Row(Modifier.horizontalScroll(rememberScrollState()),horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                FilterChip(effectiveBook==null,{bookId=null},label={Text("Tutti i ricordi")})
                collections.forEach {book->FilterChip(effectiveBook==book.id,{bookId=book.id},label={Text(book.name)})}
            }}
            if(mode=="Calendario") {
                item {Row(verticalAlignment=Alignment.CenterVertically) {
                    IconButton(enabled=month>YearMonth.of(1900,1),onClick={val next=month.minusMonths(1);monthText=next.toString();selected=next.atDay(minOf(day.dayOfMonth,next.lengthOfMonth())).toString()}){Icon(Icons.Default.ChevronLeft,"Mese precedente")}
                    TextButton(onClick={jump=true},modifier=Modifier.weight(1f)){Text(month.format(DateTimeFormatter.ofPattern("MMMM yyyy",Locale.ITALIAN)))}
                    IconButton(enabled=month<YearMonth.of(2200,12),onClick={val next=month.plusMonths(1);monthText=next.toString();selected=next.atDay(minOf(day.dayOfMonth,next.lengthOfMonth())).toString()}){Icon(Icons.Default.ChevronRight,"Mese successivo")}
                }}
                item {DiaryMonthGrid(month,day,today,index){selected=it.toString()}}
                item {Row(Modifier.horizontalScroll(rememberScrollState()),horizontalArrangement=Arrangement.spacedBy(14.dp)) {
                    listOf("Foto" to MaterialTheme.colorScheme.primary,"Pensieri" to MaterialTheme.colorScheme.secondary,"Impegni" to MaterialTheme.colorScheme.tertiary).forEach {(label,color)->
                        Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(5.dp)) {Box(Modifier.size(8.dp).background(color,CircleShape));Text(label,style=MaterialTheme.typography.labelMedium)}
                    }
                }}
                item {TextButton(onClick={selected=today.toString();monthText=YearMonth.from(today).toString()}){Text("Torna a oggi")}}
                item {EditorialSection(day.format(diaryDateFormat),selectedBook?.let {"Ricordi in ${it.name} · impegni di tutti i book"})}
                item {Column(verticalArrangement=Arrangement.spacedBy(8.dp)) {
                    Button(onClick={onCreate(selected,effectiveBook,false)},modifier=Modifier.fillMaxWidth()){Text("Scrivi un pensiero")}
                    OutlinedButton(onClick={onCreate(selected,effectiveBook,true)},modifier=Modifier.fillMaxWidth()){Text("Aggiungi foto")}
                    TextButton(enabled=day.year in 2000..2200,onClick={taskDate=selected;newTaskId=UUID.randomUUID().toString()}){Text("Aggiungi impegno")}
                }}
                val entries=index?.days?.get(day).orEmpty()
                val tasks=index?.tasks?.get(day).orEmpty()
                if(index!=null && entries.isEmpty() && tasks.isEmpty()) item {Text("Questo giorno aspetta la sua prima storia.")}
                items(entries,key={"entry:${it.note.id}"}) {DiaryEntryCard(it,onOpen)}
                if(tasks.isNotEmpty()) item {Text("Impegni",style=MaterialTheme.typography.titleMedium)}
                items(tasks,key={"task:${it.id}"}) {task->
                    OutlinedCard(onClick={onOpenTask(task.id)},modifier=Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(16.dp)) {
                            Text(task.title,style=MaterialTheme.typography.titleMedium)
                            Text(if(task.task?.completedAt!=null) "Completato" else "Da fare",style=MaterialTheme.typography.labelMedium)
                        }
                    }
                }
            } else if(mode=="Book" && effectiveBook==null) {
                item {Text("Un book usa una raccolta: le note datate diventano le sue pagine. Le altre note della raccolta restano nella libreria.")}
                item {Button(enabled=!busy,onClick={newBook=true}){Text("Crea book")};TextButton(onClick=onManageCollections){Text("Gestisci nomi e raccolte")}}
                if(collections.isEmpty()) item {Text("Vacanze, noi due, un anno da ricordare: scegli il nome del primo book.")}
                items(collections,key={"book:${it.id}"}) {book->
                    val entries=index?.entries.orEmpty().filter {it.note.collectionId==book.id}
                    OutlinedCard(onClick={bookId=book.id},modifier=Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(18.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
                            entries.firstOrNull {it.photos.isNotEmpty()}?.photos?.firstOrNull()?.let {DiaryPhoto(it)}
                            Text(book.name,style=MaterialTheme.typography.headlineSmall)
                            Text("${entries.size} pagine · ${entries.sumOf {it.photos.size}} foto")
                        }
                    }
                }
            } else {
                item {EditorialSection(selectedBook?.name ?: "La tua galleria",if(mode=="Galleria") "I ricordi con foto, dal più recente." else "Le pagine del book, dal più recente.")}
                if(mode=="Book") item {
                    OutlinedButton(onClick={mode="Calendario"}){Text("Aggiungi una pagina: scegli il giorno")}
                    TextButton(onClick=onManageCollections){Text("Gestisci book")}
                }
                val entries=index?.entries.orEmpty().filter {mode!="Galleria" || it.photos.isNotEmpty()}
                if(index!=null && entries.isEmpty()) item {Text("Nessun ricordo qui. Apri il calendario per aggiungerne uno o assegna Giorno e Raccolta a una nota esistente.")}
                items(entries,key={"gallery:${it.note.id}"}) {DiaryEntryCard(it,onOpen)}
            }
            item {Text("I ricordi archiviati restano nel Diario. Il cestino e i modelli sono esclusi. Le bozze compaiono dopo Salva.",style=MaterialTheme.typography.bodySmall)}
        }
    }
    if(jump) DiaryDateDialog(day,onDismiss={jump=false},allowRemove=false,onDate={date->
        if(date!=null){selected=date.toString();monthText=YearMonth.from(date).toString()};jump=false
    })
    if(newBook) AlertDialog(onDismissRequest={if(!busy)newBook=false},title={Text("Nuovo book")},text={Column(Modifier.verticalScroll(rememberScrollState())) {
        OutlinedTextField(bookName,{bookName=it},label={Text("Nome del book")},singleLine=true,enabled=!busy)
        Text("Sarà anche una raccolta, accessibile da Note.")
        error?.let {Text(it,color=MaterialTheme.colorScheme.error)}
    }},confirmButton={TextButton(enabled=!busy && bookName.isNotBlank(),onClick={action {repository.createCollection(bookName);bookName="";newBook=false}}){Text("Crea")}},dismissButton={TextButton(enabled=!busy,onClick={newBook=false}){Text("Annulla")}})
    newTaskId?.let {id->TaskEditorDialog(id,null,notes,busy,error,onDismiss={if(!busy)newTaskId=null},onSave={title,body,details,_->
        action {repository.savePlannedTask(null,id,title,body,details);newTaskId=null}
    },initialDue=taskDate)}
}

@Composable
private fun DiaryMonthGrid(month:YearMonth,selected:LocalDate,today:LocalDate,index:DiaryIndex?,onSelect:(LocalDate)->Unit) {
    val cells=remember(month){Diary.monthCells(month)}
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val gridWidth=maxOf(maxWidth,364.dp)
        Box(Modifier.horizontalScroll(rememberScrollState())) {
            Column(Modifier.width(gridWidth)) {
                Row {listOf("L","M","M","G","V","S","D").forEach {Text(it,Modifier.weight(1f),textAlign=androidx.compose.ui.text.style.TextAlign.Center)}}
                cells.chunked(7).forEach {week->Row {
                    week.forEach {date->
                        val entries=date?.let {index?.days?.get(it)}.orEmpty();val tasks=date?.let {index?.tasks?.get(it)}.orEmpty()
                        val photos=entries.any {it.photos.isNotEmpty()};val thoughts=entries.any {it.photos.isEmpty()}
                        val chosen=date==selected
                        Surface(modifier=Modifier.weight(1f).padding(2.dp).heightIn(min=60.dp).then(if(date!=null) Modifier.clickable(role=androidx.compose.ui.semantics.Role.Button) {onSelect(date)}.semantics {contentDescription="${date.format(diaryDateFormat)}, ${entries.size} ricordi, ${tasks.size} impegni${if(chosen) ", selezionato" else ""}"} else Modifier),
                            shape=MaterialTheme.shapes.small,color=when {chosen->MaterialTheme.colorScheme.primaryContainer;date==today->MaterialTheme.colorScheme.secondaryContainer;else->MaterialTheme.colorScheme.surface}) {
                            Column(Modifier.padding(vertical=8.dp),horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.spacedBy(6.dp)) {
                                Text(date?.dayOfMonth?.toString().orEmpty(),style=MaterialTheme.typography.bodyMedium)
                                Row(horizontalArrangement=Arrangement.spacedBy(3.dp)) {
                                    if(photos) Box(Modifier.size(6.dp).background(MaterialTheme.colorScheme.primary,CircleShape))
                                    if(thoughts) Box(Modifier.size(6.dp).background(MaterialTheme.colorScheme.secondary,CircleShape))
                                    if(tasks.isNotEmpty()) Box(Modifier.size(6.dp).background(MaterialTheme.colorScheme.tertiary,CircleShape))
                                }
                            }
                        }
                    }
                }}
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DiaryEntryCard(entry:DiaryEntry,onOpen:(String)->Unit) {
    OutlinedCard(onClick={onOpen(entry.note.id)},modifier=Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
            entry.photos.firstOrNull()?.let {DiaryPhoto(it)}
            Text(entry.date.format(diaryDateFormat),style=MaterialTheme.typography.labelMedium)
            Text(entry.note.title.ifBlank {"Un ricordo"},style=MaterialTheme.typography.titleLarge)
            val preview=entry.note.body.take(600).replace(Regex("\\[[^\\]]*]\\(notes-asset://[^)]*\\)"),"").trim().take(180)
            if(preview.isNotBlank())Text(preview,maxLines=3)
            if(entry.photos.isNotEmpty())Text("${entry.photos.size} foto · Apri la pagina",style=MaterialTheme.typography.labelMedium)
        }
    }
}

@Composable
private fun DiaryPhoto(ref:AttachmentRef) {
    val app=LocalContext.current.applicationContext as NotesApplication
    val sync by app.githubSync.status.collectAsStateWithLifecycle()
    val bitmap by produceState<Bitmap?>(null,ref.key,sync.busy) {
        value=try {withContext(Dispatchers.IO){decodeAttachmentImage(app.attachments.verifiedFile(ref.key),640)}}
        catch(e:CancellationException){throw e}catch(_:Exception){null}
    }
    val image=bitmap
    if(image!=null) Image(image.asImageBitmap(),ref.name,Modifier.fillMaxWidth().height(180.dp),contentScale=ContentScale.Crop)
    else Surface(Modifier.fillMaxWidth().height(100.dp),color=MaterialTheme.colorScheme.surfaceContainer) {
        Box(contentAlignment=Alignment.Center){Text("Foto da caricare · apri Allegati")}
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun DiaryHomeCard(notes:List<Note>,onOpen:()->Unit) {
    var today by remember {mutableStateOf(LocalDate.now())}
    LaunchedEffect(Unit){while(true){today=LocalDate.now();delay(60000)}}
    val count=remember(notes,today){notes.count {Diary.noteDate(it)==today}}
    OutlinedCard(onClick=onOpen,modifier=Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp),verticalArrangement=Arrangement.spacedBy(4.dp)) {
            Text("La tua giornata",style=MaterialTheme.typography.titleLarge)
            Text(if(count==0) "Conserva un pensiero o una foto di oggi." else "$count ricordi di oggi · Apri il Diario")
        }
    }
}

@Composable
internal fun DiaryDateEditor(model:EditorViewModel) {
    var open by rememberSaveable {mutableStateOf(false)}
    val date=Diary.date(model.tags)
    val enabled=model.available && !model.saving && !model.mediaBusy && !model.checklistWorking
    TextButton(enabled=enabled,onClick={open=true}) {Text(date?.let {"Giorno · ${it.format(diaryDateFormat)}"} ?: "Giorno")}
    if(open) DiaryDateDialog(date,onDismiss={open=false},externalError=model.error,onDate={if(model.assignDiaryDate(it))open=false})
}

@Composable
private fun DiaryDateDialog(date:LocalDate?,onDismiss:()->Unit,allowRemove:Boolean=true,externalError:String?=null,onDate:(LocalDate?)->Unit) {
    var value by rememberSaveable {mutableStateOf((date ?: LocalDate.now()).toString())}
    var error by remember {mutableStateOf<String?>(null)}
    AlertDialog(onDismissRequest=onDismiss,title={Text("Scegli il giorno")},text={Column(Modifier.verticalScroll(rememberScrollState())) {
        Text("La data del ricordo è indipendente da quando hai creato la nota.")
        OutlinedTextField(value,{value=it},singleLine=true,label={Text("AAAA-MM-GG")})
        TextButton(onClick={value=LocalDate.now().toString()}){Text("Oggi")}
        if(allowRemove)TextButton(onClick={onDate(null)}){Text("Rimuovi dal calendario")}
        (error ?: externalError)?.let {Text(it,color=MaterialTheme.colorScheme.error)}
    }},confirmButton={TextButton(onClick={try {onDate(Diary.validDate(value.trim()))}catch(e:Exception){error=e.message ?: "Data non valida."}}){Text("Conferma")}},dismissButton={TextButton(onClick=onDismiss){Text("Annulla")}})
}

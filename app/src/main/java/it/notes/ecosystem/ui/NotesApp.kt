package it.notes.ecosystem.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextDecoration
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.horizontalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.createSavedStateHandle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import androidx.navigation.NavType
import androidx.navigation.compose.*
import androidx.navigation.navArgument
import it.notes.ecosystem.BuildConfig
import it.notes.ecosystem.domain.*
import it.notes.ecosystem.domain.Collection
import java.util.UUID

private fun noteRoute(note: Note): String =
    when (note.sketch?.kind) {
        VisualDocumentKind.SKETCH -> "sketch/${note.id}"
        VisualDocumentKind.WHITEBOARD -> "whiteboard/${note.id}"
        null -> "editor/${note.id}?new=false"
    }

@Composable
fun NotesApp(model: NotesViewModel, repository: NotesRepository, reminderTaskId:String?=null) {
    val nav = rememberNavController()
    val collections by model.collections.collectAsStateWithLifecycle()
    val allNotes by model.notes.collectAsStateWithLifecycle()
    var reminderOpened by rememberSaveable {mutableStateOf(false)}
    LaunchedEffect(reminderTaskId) {if(reminderTaskId!=null && !reminderOpened){reminderOpened=true;nav.navigate("reminder/${android.net.Uri.encode(reminderTaskId)}")}}
    NavHost(navController = nav, startDestination = "library") {
        composable("reminder/{id}",arguments=listOf(navArgument("id"){type=NavType.StringType})) {entry ->
            PlannerScreen(repository,allNotes,onOpenNote={target->allNotes.firstOrNull { it.id==target }?.let { nav.navigate(noteRoute(it)) }},
                onBack={nav.popBackStack()},onChecklist={nav.popBackStack()},initialScope=PlannerScope.ALL,
                onSection={nav.popBackStack()},initialTaskId=entry.arguments?.getString("id"))
        }
        composable("library") {
            LibraryScreen(model, repository, onOpen = { id -> allNotes.firstOrNull { it.id==id }?.let { nav.navigate(noteRoute(it)) } },
                onCreate = { nav.navigate("editor/${UUID.randomUUID()}?new=true") },
                onCreateSketch = { nav.navigate("sketch/${UUID.randomUUID()}") },
                onCreateWhiteboard = { mind -> nav.navigate("whiteboard/${UUID.randomUUID()}?mind=$mind") },
                onDiaryCreate = { date,book,photo -> nav.navigate("editor/${UUID.randomUUID()}?new=true&diary=$date&book=${android.net.Uri.encode(book.orEmpty())}&media=$photo") },
                onOpenTask = { nav.navigate("reminder/$it") },
                onTemplate = { key, reset -> nav.navigate("editor/${UUID.randomUUID()}?new=true&template=${android.net.Uri.encode(key)}&reset=$reset") },
                onDaily = { val day=java.time.LocalDate.now(); nav.navigate("editor/${PageTemplates.dailyId(day)}?new=true&day=$day") })
        }
        composable("sketch/{id}?linked={linked}", arguments=listOf(
            navArgument("id"){type=NavType.StringType},navArgument("linked"){type=NavType.StringType;nullable=true;defaultValue=null}
        )) {
            val sketch:SketchViewModel=viewModel(factory=viewModelFactory {initializer {SketchViewModel(repository,createSavedStateHandle())}})
            SketchScreen(sketch,allNotes,onBack={nav.popBackStack()},onOpenNote={target->allNotes.firstOrNull { it.id==target }?.let { nav.navigate(noteRoute(it)) }},
                onCopy={id->nav.popBackStack();nav.navigate("sketch/$id")})
        }
        composable(
            "whiteboard/{id}?linked={linked}&mind={mind}",
            arguments = listOf(
                navArgument("id") { type = NavType.StringType },
                navArgument("linked") { type = NavType.StringType; nullable = true; defaultValue = null },
                navArgument("mind") { type = NavType.BoolType; defaultValue = false },
            ),
        ) {
            val board: WhiteboardViewModel = viewModel(
                factory = viewModelFactory {
                    initializer { WhiteboardViewModel(repository, createSavedStateHandle()) }
                }
            )
            WhiteboardScreen(
                model = board,
                notes = allNotes,
                onBack = { nav.popBackStack() },
                onOpenNote = { target ->
                    allNotes.firstOrNull { it.id == target }?.let { nav.navigate(noteRoute(it)) }
                },
                onCopy = { id -> nav.popBackStack(); nav.navigate("whiteboard/$id") },
            )
        }
        composable("editor/{id}?new={new}&template={template}&day={day}&reset={reset}&diary={diary}&book={book}&media={media}", arguments = listOf(
            navArgument("id") { type = NavType.StringType },
            navArgument("new") { type = NavType.BoolType; defaultValue = false },
            navArgument("template") { type=NavType.StringType; defaultValue="" },
            navArgument("day") { type=NavType.StringType; defaultValue="" },
            navArgument("reset") { type=NavType.BoolType; defaultValue=true },
            navArgument("diary") { type=NavType.StringType; defaultValue="" },
            navArgument("book") { type=NavType.StringType; defaultValue="" },
            navArgument("media") { type=NavType.BoolType; defaultValue=false },
        )) { entry ->
            val editorApp = androidx.compose.ui.platform.LocalContext.current.applicationContext as it.notes.ecosystem.NotesApplication
            val editor: EditorViewModel = viewModel(factory = viewModelFactory {
                initializer {
                    EditorViewModel(
                        repository = repository,
                        state = createSavedStateHandle(),
                        blockStore = editorApp.contentBlocks,
                    )
                }
            })
            val id=entry.arguments?.getString("id")
            EditorScreen(editor, collections, initialAttachments = entry.arguments?.getBoolean("media") == true, allNotes = allNotes, onOpenNote = { target -> nav.popBackStack(); allNotes.firstOrNull { it.id==target }?.let { nav.navigate(noteRoute(it)) } },
                onSketchCreate = if (allNotes.any { it.id == id }) ({ blockId ->
                    val sketchId = UUID.randomUUID().toString()
                    if (blockId != null) editor.attachSketchToBlock(blockId, sketchId, "Disegno")
                    nav.navigate("sketch/$sketchId?linked=${android.net.Uri.encode(id.orEmpty())}")
                }) else null,
                linkedSketches = allNotes.filter { it.sketch?.kind == VisualDocumentKind.SKETCH && it.sketch.linkedNoteId == id && it.deletedAt == null },
                onOpenSketch = { nav.navigate("sketch/$it") },
                onWhiteboardCreate = if (allNotes.any { it.id == id }) ({ blockId ->
                    val boardId = UUID.randomUUID().toString()
                    if (blockId != null) editor.attachWhiteboardToBlock(blockId, boardId, "Lavagna")
                    nav.navigate("whiteboard/$boardId?linked=${android.net.Uri.encode(id.orEmpty())}")
                }) else null,
                linkedWhiteboards = allNotes.filter { it.sketch?.kind == VisualDocumentKind.WHITEBOARD && it.sketch.linkedNoteId == id && it.deletedAt == null },
                onOpenWhiteboard = { nav.navigate("whiteboard/$it") },
                onBack = { nav.popBackStack() })
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun LibraryScreen(model: NotesViewModel, repository: NotesRepository, onOpen: (String) -> Unit, onCreate: () -> Unit, onCreateSketch: () -> Unit, onCreateWhiteboard: (mindMap: Boolean) -> Unit, onDiaryCreate: (String,String?,Boolean)->Unit, onOpenTask: (String)->Unit, onTemplate: (String, Boolean)->Unit, onDaily: ()->Unit) {
    val notes by model.notes.collectAsStateWithLifecycle()
    val github = (androidx.compose.ui.platform.LocalContext.current.applicationContext as it.notes.ecosystem.NotesApplication).githubSync
    val syncStates by github.noteStates.collectAsStateWithLifecycle()
    val collections by model.collections.collectAsStateWithLifecycle()
    val drafts by model.drafts.collectAsStateWithLifecycle()
    val taskWrites by model.taskWrites.collectAsStateWithLifecycle()
    val tasks by model.tasks.collectAsStateWithLifecycle()
    val bulkBusy by model.bulkBusy.collectAsStateWithLifecycle()
    val savedSearches by model.savedSearches.collectAsStateWithLifecycle()
    val noteOrder by model.noteOrder.collectAsStateWithLifecycle()
    val organizationBusy by model.organizationBusy.collectAsStateWithLifecycle()
    var savedPanel by rememberSaveable { mutableStateOf(false) }
    var collectionPanel by rememberSaveable { mutableStateOf(false) }

    val suggestedTags by produceState<List<String>>(emptyList(), notes) {
        value = withContext(Dispatchers.Default) { notes.filter { it.deletedAt == null }.flatMap { Diary.userTags(it.tags) }.distinct().sorted() }
    }
    val collectionNames = remember(collections) { collections.associate { it.id to it.name } }
    val ordinaryDrafts = remember(drafts, notes) {
        val hidden = notes.filter { it.archived || it.deletedAt != null }.map { it.id }.toSet()
        drafts.filter { it.id !in hidden }
    }
    val draftIds = remember(drafts) { drafts.map { it.id }.toSet() }
    var taskFilter by rememberSaveable { mutableStateOf("Da fare") }
    val exporting by model.exporting.collectAsStateWithLifecycle()
    val importing by model.importing.collectAsStateWithLifecycle()
    val importPreview by model.importPreview.collectAsStateWithLifecycle()
    val importAssets by model.importAssets.collectAsStateWithLifecycle()
    val mediaProgress by model.mediaProgress.collectAsStateWithLifecycle()
    val mediaUsage by model.mediaUsage.collectAsStateWithLifecycle()
    var confirmMediaCleanup by rememberSaveable {mutableStateOf(false)}
    LaunchedEffect(Unit){model.refreshMediaUsage()}

    val resolver = androidx.compose.ui.platform.LocalContext.current.applicationContext.contentResolver
    val importJson = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.OpenDocument()
    ) { uri -> if (uri != null) model.previewImport(resolver, uri) }
    val mediaImport = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.OpenDocument()
    ) {uri->if(uri!=null)model.previewMediaImport(resolver,uri)}
    val jsonExport = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.CreateDocument("application/json")
    ) { uri -> if (uri != null) model.export(resolver, uri, false) }
    val markdownExport = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.CreateDocument("application/zip")
    ) { uri -> if (uri != null) model.export(resolver, uri, true) }
    val dark by model.darkMode.collectAsStateWithLifecycle()
    val error by model.error.collectAsStateWithLifecycle()
    var plannerScope by rememberSaveable { mutableStateOf(PlannerScope.TODAY.name) }
    var legacyTasks by rememberSaveable { mutableStateOf(false) }
    var section by rememberSaveable { mutableStateOf("Home") }
    var query by rememberSaveable { mutableStateOf("") }
    var filterName by rememberSaveable { mutableStateOf(NoteFilter.ALL.name) }
    var selectedCollection by rememberSaveable { mutableStateOf<String?>(null) }
    var filterTags by rememberSaveable { mutableStateOf(listOf<String>()) }
    var matchAllTags by rememberSaveable { mutableStateOf(true) }
    var onlyFavorites by rememberSaveable { mutableStateOf(false) }
    var onlyPinned by rememberSaveable { mutableStateOf(false) }
    var taskPresence by rememberSaveable { mutableStateOf(TaskPresence.ANY.name) }
    var grid by rememberSaveable { mutableStateOf(false) }
    var libraryKind by rememberSaveable { mutableStateOf("Tutte") }
    var committedQuery by rememberSaveable { mutableStateOf("") }
    LaunchedEffect(query) {
        if (query.isBlank()) {
            committedQuery = ""
        } else {
            delay(90)
            committedQuery = query
        }
    }
    val options = if (section == "Cerca") SearchOptions(filterTags, matchAllTags, onlyFavorites, onlyPinned, TaskPresence.valueOf(taskPresence)) else SearchOptions()
    val selectionScope = listOf(section, committedQuery, filterName, selectedCollection, options, libraryKind, noteOrder)
    var selecting by remember(selectionScope) { mutableStateOf(false) }
    var selected by remember(selectionScope) { mutableStateOf<Map<String, Note>>(emptyMap()) }
    BackHandler(enabled = selecting) { if (!bulkBusy) { selected = emptyMap(); selecting = false } }
    var createMenu by remember { mutableStateOf(false) }
    var templateGallery by rememberSaveable { mutableStateOf(false) }
    if (templateGallery) TemplateGallery(notes, onClose={templateGallery=false}, onUse={key,reset->templateGallery=false;onTemplate(key,reset)}, onEdit={id->templateGallery=false;onOpen(id)})
    var newCollection by rememberSaveable { mutableStateOf(false) }
    var collectionName by rememberSaveable { mutableStateOf("") }
    if (section == "Diario") {
        DiaryScreen(notes, collections, repository, onOpen=onOpen, onCreate=onDiaryCreate, onOpenTask=onOpenTask,
            onSection={section=it}, onManageCollections={section="Raccolte";selectedCollection=null})
        return
    }
    if (section == "Attività" && !legacyTasks) {
        PlannerScreen(repository, notes, onOpen, onBack = { section = "Home" }, onChecklist = { legacyTasks = true },
            initialScope = PlannerScope.valueOf(plannerScope), onSection = { label ->
                section = label; legacyTasks = false; filterName = NoteFilter.ALL.name
            })
        return
    }
    val snackbar = remember { SnackbarHostState() }
    LaunchedEffect(error) { error?.let { snackbar.showSnackbar(it); model.clearError() } }
    val filter = if (section == "Inbox") NoteFilter.INBOX else NoteFilter.valueOf(filterName)
    val effectiveQuery = if (section == "Cerca") committedQuery else ""
    val effectiveCollection = if (section == "Raccolte" || section == "Cerca") selectedCollection else null
    // Publish only the latest background search. During typing retain the previous committed
    // list only when data and every non-text filter are unchanged; label it as updating.
    val resultKey: List<Any?> = listOf(notes, filter, effectiveQuery, effectiveCollection, options, libraryKind, noteOrder)
    val result by produceState<Pair<List<Any?>, List<Note>>?>(null, resultKey) {
        val found = withContext(Dispatchers.Default) {
            orderNotes(searchNotes(notes, filter, effectiveQuery, effectiveCollection, options).filter { n ->
                when(libraryKind) {
                    "Disegni" -> n.sketch?.kind == VisualDocumentKind.SKETCH
                    "Lavagne" -> n.sketch?.kind == VisualDocumentKind.WHITEBOARD
                    "Checklist" -> n.sketch==null && Checklist.hasMarker(n.body)
                    "Testo" -> n.sketch==null && !Checklist.hasMarker(n.body)
                    else -> true
                }
            }, noteOrder)
        }
        value = resultKey to found
    }
    val sameSearchContext = section == "Cerca" && result?.first?.filterIndexed { index, _ -> index != 2 } ==
        resultKey.filterIndexed { index, _ -> index != 2 }
    val visible = if (result?.first == resultKey || sameSearchContext) result?.second.orEmpty() else emptyList()
    val searching = result?.first != resultKey || (section == "Cerca" && query != committedQuery)
    val filteredTasks = remember(tasks, taskFilter) { tasks.filter { when (taskFilter) {
        "Da fare" -> !it.item.completed
        "Completate" -> it.item.completed
        else -> true
    } } }
    val activeCount = remember(notes) { notes.count { it.deletedAt == null && !it.archived && it.task == null } }
    val pendingCount = remember(notes) { notes.count { it.task != null && it.task.completedAt == null && it.deletedAt == null && !it.archived } }

    Scaffold(
        topBar = { TopAppBar(colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            title = { EditorialAppTitle(if (section == "Home") "Il tuo spazio" else section) },
            actions = { IconButton(enabled = !bulkBusy, onClick = { section = "Impostazioni" }) {
                Icon(Icons.Default.Settings, contentDescription = "Impostazioni")
            } }) },
        snackbarHost = { SnackbarHost(snackbar) },
        floatingActionButton = {
            if (section != "Impostazioni" && !selecting && !bulkBusy) Box { ExtendedFloatingActionButton(onClick = {createMenu=true},
                containerColor = MaterialTheme.colorScheme.primary, contentColor = MaterialTheme.colorScheme.onPrimary,
                icon = { Icon(Icons.Default.Add, contentDescription = null) }, text = { Text("Crea") })
                DropdownMenu(createMenu,{createMenu=false}) {
                    DropdownMenuItem(text={Text("Nuova nota")},onClick={createMenu=false;onCreate()})
                    DropdownMenuItem(text={Text("Diario di oggi")},onClick={createMenu=false;onDaily()})
                    DropdownMenuItem(text={Text("Modelli")},onClick={createMenu=false;templateGallery=true})
                    DropdownMenuItem(text={Text("Nuovo disegno")},onClick={createMenu=false;onCreateSketch()})
                    DropdownMenuItem(text={Text("Nuova lavagna")},onClick={createMenu=false;onCreateWhiteboard(false)})
                    DropdownMenuItem(text={Text("Nuova mind map")},onClick={createMenu=false;onCreateWhiteboard(true)})
                }
            }
        },
        bottomBar = {
            EcosystemNavigation(section, enabled = !bulkBusy) { label ->
                section = label; legacyTasks = false; plannerScope = PlannerScope.TODAY.name; filterName = NoteFilter.ALL.name
            }
        },
    ) { padding ->
        LazyColumn(Modifier.fillMaxSize().padding(padding), contentPadding = PaddingValues(20.dp, 12.dp, 20.dp, 104.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (section == "Impostazioni") {
                item { EditorialSection("Fallo tuo.", "Aspetto, acquisizione rapida e dati personali.") }
                item { ListItem(headlineContent = { Text("Tema scuro") }, trailingContent = {
                    Switch(checked = dark, onCheckedChange = model::setDarkMode)
                }) }
                item { Text("Notes resta local-first: l'account è facoltativo. Puoi attivare Notes Cloud esplicitamente oppure continuare a usare solo il dispositivo e i backup locali/GitHub.") }
                item { QuickCaptureSettings() }
                item { GitHubSettings((androidx.compose.ui.platform.LocalContext.current.applicationContext as it.notes.ecosystem.NotesApplication).githubSync) }
                item { Text("Notes · versione ${BuildConfig.VERSION_NAME}", style = MaterialTheme.typography.labelLarge) }
                item { OutlinedButton(enabled = !importing && !exporting, onClick = {
                    importJson.launch(arrayOf("application/json", "text/plain", "application/octet-stream"))
                }) { Text("Importa backup JSON") } }
                item { Text("Importazione come copie: nessuna nota esistente viene sovrascritta. Se hai un export ZIP, estrai prima backup.json. Limite JSON: 5 MB. Per foto, audio e documenti usa il backup completo ZIP.") }
                item { Button(enabled = !exporting && !importing, onClick = { jsonExport.launch("notes-backup-${System.currentTimeMillis()}.json") }) { Text("Esporta dati JSON") } }
                item { OutlinedButton(enabled = !exporting && !importing, onClick = { markdownExport.launch("notes-markdown-${System.currentTimeMillis()}.zip") }) { Text("Backup completo ZIP · con allegati") } }
                item {OutlinedButton(enabled=!importing && !exporting,onClick={mediaImport.launch(arrayOf("application/zip","application/octet-stream"))}) {Text("Importa backup completo ZIP")}}
                item {Text("Foto, audio e documenti sono inclusi solo nel backup completo ZIP: il JSON conserva i collegamenti. Limiti: 8 MiB per file, 64 MiB di allegati nel backup e per passaggio GitHub.",style=MaterialTheme.typography.bodySmall)}
                item {Text(mediaUsage?.let {"Allegati sul dispositivo: ${it.first} file · ${it.second/1024/1024} MiB su 256 MiB"} ?: "Lettura spazio allegati…")}
                item {TextButton(enabled=!organizationBusy && !importing && !exporting,onClick={confirmMediaCleanup=true}) {Text("Libera allegati inutilizzati")}}
                if(mediaProgress.isNotBlank())item {Text(mediaProgress)}
                if (exporting || importing) item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
                item { Text("Gli export includono note, disegni modificabili, attività, ricorrenze, Focus registrato, cestino, raccolte e bozze. Le ricerche salvate e l’ordinamento sono preferenze locali, escluse da backup e GitHub. Sono file non cifrati: scegli dove conservarli. Puoi importare un backup JSON qui sotto.") }
            } else if (section == "Attività") {
                item { TextButton(onClick = { legacyTasks = false }) { Text("Oggi e attività autonome") }; Text("Le checklist delle note salvate, tutte qui.") }
                item {
                    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        listOf("Da fare", "Completate", "Tutte").forEach { label ->
                            FilterChip(selected = taskFilter == label, onClick = { taskFilter = label }, label = { Text(label) })
                        }
                    }
                }
                if (filteredTasks.isEmpty()) item { EmptyState("Un passo alla volta.", "Le attività delle tue note appariranno qui. Per iniziare, apri una nota e scegli Checklist.") }
                items(filteredTasks, key = { "task-" + it.noteId + "-" + it.item.lineIndex }) { task ->
                    Card(Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(12.dp)) {
                            Row {
                                Checkbox(checked = task.item.completed, modifier = Modifier.semantics { contentDescription = task.item.label },
                                    enabled = task.noteId !in draftIds && task.noteId !in taskWrites,
                                    onCheckedChange = { model.completeTask(task, it) })
                                Text(task.item.label, Modifier.weight(1f).padding(top = 12.dp),
                                    textDecoration = if (task.item.completed) TextDecoration.LineThrough else TextDecoration.None)
                            }
                            TextButton(onClick = { onOpen(task.noteId) }) {
                                Text((if (task.noteId in draftIds) "Apri bozza · " else "Apri nota · ") + task.noteTitle.ifBlank { "Senza titolo" })
                            }
                            if (task.noteId in draftIds) Text("Completa la modifica nella bozza.", style = MaterialTheme.typography.labelSmall)
                        }
                    }
                }
            } else {
                if (section == "Home") {
                    item { DiaryHomeCard(notes, onOpen={section="Diario"}) }
                    item {
                        HomeOverview(notes, collections, activeCount, pendingCount, onCreate,
                            onNotes = { section = "Note"; filterName = NoteFilter.ALL.name },
                            onAgenda = { plannerScope = PlannerScope.TODAY.name; legacyTasks = false; section = "Attività" },
                            onAllTasks = { plannerScope = PlannerScope.ALL.name; legacyTasks = false; section = "Attività" },
                            onCollection = { selectedCollection = it; section = "Raccolte"; filterName = NoteFilter.ALL.name }, onSketch = onCreateSketch)
                    }
                    item { EditorialSection("Tra le tue pagine", "Note, idee e progetti da ritrovare.") }
                }
                if ((section == "Home" || section == "Note") && ordinaryDrafts.isNotEmpty() && filter != NoteFilter.ARCHIVE && filter != NoteFilter.TRASH) {
                    item { EditorialSection("Da dove eri rimasto", "Le tue bozze sono qui.") }
                    items(ordinaryDrafts, key = { "draft-" + it.id }) { draft ->
                        OutlinedButton(onClick = { onOpen(draft.id) }, modifier = Modifier.fillMaxWidth()) {
                            Text(draft.title.ifBlank { draft.body.take(60).ifBlank { "Bozza senza titolo" } }, maxLines = 2)
                        }
                    }
                }
                if (section in listOf("Note", "Raccolte", "Cerca", "Inbox")) item {
                    LibraryOrganizationBar(noteOrder, model::setNoteOrder,
                        savedCount=if(section=="Cerca") savedSearches.size else null, onSaved={savedPanel=true})
                }
                if (section == "Cerca") {
                                        item { OutlinedTextField(value = query, onValueChange = { query = it },
                        modifier = Modifier.fillMaxWidth(), label = { Text("Cerca nel titolo, nel testo e nei tag") },
                        singleLine = true, leadingIcon = { Icon(Icons.Default.Search, null) },
                        trailingIcon = { if(query.isNotEmpty()) IconButton(onClick={query=""}) {Icon(Icons.Default.Close,"Cancella ricerca")} }) }
                    item { SearchControls(options, onChange = { value ->
                        filterTags = value.tags; matchAllTags = value.allTags; onlyFavorites = value.favoritesOnly
                        onlyPinned = value.pinnedOnly; taskPresence = value.tasks.name
                    }, collections = collections, collectionId = selectedCollection, onCollection = { selectedCollection = it },
                        suggestedTags = suggestedTags, filter = filter, onFilter = {filterName=it.name},
                        kind=libraryKind, onKind={libraryKind=it}, grid=grid, onGrid={grid=!grid}, onReset = {
                            filterTags = emptyList(); matchAllTags = true; onlyFavorites = false; onlyPinned = false
                            taskPresence = TaskPresence.ANY.name; selectedCollection = null; filterName = NoteFilter.ALL.name; libraryKind="Tutte"
                        }) }

                }
                if (section == "Note" || section == "Raccolte") item {
                    Row(horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                        FilterChip(section=="Note",{section="Note";selectedCollection=null},label={Text("Tutte le note")})
                        FilterChip(section=="Raccolte",{section="Raccolte"},label={Text("Raccolte")})
                    }
                }
                if (section == "Raccolte") {
                    item { EditorialSection("Ogni progetto, il suo posto.", "Raggruppa le note senza perdere il filo.")
                        Row(horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                            OutlinedButton(onClick = { newCollection = true }) { Text("Crea raccolta") }
                            TextButton(enabled=collections.isNotEmpty(),onClick={collectionPanel=true}) {Text("Gestisci")}
                        }
                    }
                    item { Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        FilterChip(selected = selectedCollection == null, onClick = { selectedCollection = null }, label = { Text("Tutte") })
                        collections.forEach { collection ->
                            FilterChip(selected = selectedCollection == collection.id,
                                onClick = { selectedCollection = collection.id }, label = { Text(collection.name) })
                        }
                    } }
                    if (collections.isEmpty()) item { Text("Crea una raccolta, poi assegnala dall’editor della nota.") }
                }
                if (section != "Inbox" && section != "Cerca") {
                    item { Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        listOf(NoteFilter.ALL to "Tutte", NoteFilter.INBOX to "Inbox", NoteFilter.FAVORITES to "Preferiti", NoteFilter.ARCHIVE to "Archivio", NoteFilter.TRASH to "Cestino").forEach { (value, label) ->
                            FilterChip(selected = filter == value, onClick = { filterName = value.name }, label = { Text(label) })
                        }
                    } }
                }
                if(section != "Cerca") item { Row(Modifier.horizontalScroll(rememberScrollState()),horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                    listOf("Tutte","Testo","Checklist","Disegni","Lavagne").forEach { kind ->FilterChip(libraryKind==kind,{libraryKind=kind},label={Text(kind)}) }
                    FilterChip(grid,{grid=!grid},label={Text(if(grid)"Griglia" else "Elenco")})
                } }
                if(section != "Cerca" || visible.isNotEmpty() || selecting) item { BulkActions(visible, selected, selecting, bulkBusy || searching, collections,
                    onMode = { selecting = it }, onSelection = { selected = it }, onApply = { snapshot, change ->
                        model.bulkEdit(snapshot, change) { selected = emptyMap(); selecting = false }
                    }) }
                if (section == "Cerca") item(key="search-status") {
                    Row(Modifier.fillMaxWidth().heightIn(min=28.dp),verticalAlignment=Alignment.CenterVertically,
                        horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                        Text(if(searching) "Aggiornamento risultati…" else "${visible.size} risultati",style=MaterialTheme.typography.labelMedium)
                        if(searching) CircularProgressIndicator(Modifier.size(14.dp),strokeWidth=2.dp)
                    }
                }
                if (searching && section != "Cerca") item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
                if (!searching && visible.isEmpty()) item {
                    EmptyState(if (section == "Cerca") "Nessun risultato." else if (filter == NoteFilter.TRASH)
                        "Il cestino è vuoto." else if (filter == NoteFilter.ARCHIVE) "L’archivio è vuoto." else "La prossima idea è tua.",
                        if (section == "Cerca") "Prova un’altra parola oppure azzera i filtri."
                        else if (filter == NoteFilter.TRASH) "Le note eliminate si possono ripristinare da qui."
                        else if (filter == NoteFilter.ARCHIVE) "Archivia le note concluse dal menu della scheda. Potrai ritrovarle qui."
                        else "Un pensiero, una lista, un progetto. Inizia con Nuova nota.")
                }
                val rows=if(grid && !selecting)visible.chunked(2) else visible.map {listOf(it)}
                items(rows,key={it.first().id},contentType={"note-row"}) { row ->
                    Row(Modifier.fillMaxWidth().then(if(section=="Cerca") Modifier.animateItem(
                        fadeInSpec=tween(160),placementSpec=tween(200),fadeOutSpec=tween(120)
                    ) else Modifier),horizontalArrangement=Arrangement.spacedBy(12.dp)) {
                        row.forEach { note -> Box(Modifier.weight(1f)) {
                    NoteCard(note, collectionNames[note.collectionId], syncStates[note.id],
                        compact = grid && !selecting, selecting = selecting, selected = note.id in selected, selectionEnabled = !bulkBusy && !searching && (note.id in selected || selected.size < 500),
                        onSelect = { selected = if (note.id in selected) selected - note.id else selected + (note.id to note) },
                        onPin = { model.pin(note.id, !note.pinned) }, onArchive = { model.archive(note.id, !note.archived) },
                        onOpen = { onOpen(note.id) }, onFavorite = { model.favorite(note.id) },
                        onTrash = { model.trash(note.id) }, onRestore = { model.restore(note.id) })
                        } }
                        if(grid && !selecting && row.size==1)Spacer(Modifier.weight(1f))
                    }
                }
            }
        }
    }
    importPreview?.let { data ->
        AlertDialog(onDismissRequest = { model.cancelImport() },
            title = { Text("Anteprima importazione") },
            text = { Text("${data.notes.count { it.deletedAt == null && !it.archived && it.task == null }} pagine attive (note e disegni), ${data.notes.count { it.task != null && it.deletedAt == null }} attività, ${data.notes.count { it.archived && it.deletedAt == null }} archiviate, ${data.notes.count { it.pinned }} fissate, ${data.notes.count { it.deletedAt != null }} nel cestino, ${data.collections.size} raccolte e ${data.drafts.size} bozze.\n${importAssets?.let {"$it allegati verificati inclusi."} ?: "Il JSON non include i file degli allegati."}\n\nSaranno aggiunte come copie. Reimportare lo stesso file crea altre copie." + if(data.notes.any(Reminders::active)) "\n\nI promemoria importati saranno attivati anche su questo dispositivo; quelli già scaduti possono notificare subito." else "") },
            confirmButton = { TextButton(enabled = !importing, onClick = model::confirmImport) {
                Text(if (importing) "Importazione…" else "Importa copie")
            } },
            dismissButton = { TextButton(enabled = !importing, onClick = model::cancelImport) { Text("Annulla") } })
    }
    if(confirmMediaCleanup) AlertDialog(onDismissRequest={if(!organizationBusy)confirmMediaCleanup=false},title={Text("Libera file inutilizzati?")},
        text={Text("Rimuove solo file locali non collegati a note, bozze o revisioni e conservati da più di 7 giorni. Non cancella file da GitHub. L’operazione non si può annullare.")},
        confirmButton={TextButton(enabled=!organizationBusy,onClick={model.cleanMedia();confirmMediaCleanup=false}){Text("Libera spazio")}},
        dismissButton={TextButton(onClick={confirmMediaCleanup=false}){Text("Annulla")}})
    if(savedPanel) SavedSearchPanel(savedSearches,collections,
        SavedSearch("current","Ricerca",query,filter,selectedCollection,
            SearchOptions(filterTags,matchAllTags,onlyFavorites,onlyPinned,TaskPresence.valueOf(taskPresence)),libraryKind,noteOrder),
        organizationBusy,error,onApply={ value ->
            query=value.query; filterName=value.filter.name; selectedCollection=value.collectionId
            filterTags=value.options.tags; matchAllTags=value.options.allTags
            onlyFavorites=value.options.favoritesOnly; onlyPinned=value.options.pinnedOnly
            taskPresence=value.options.tasks.name; libraryKind=value.kind
            model.setNoteOrder(value.order); section="Cerca"
        },onSave=model::saveSearch,onRename=model::renameSearch,onDelete=model::deleteSearch,onDismiss={savedPanel=false})
    if(collectionPanel) CollectionManager(collections,notes,drafts,organizationBusy,error,
        onOpen={selectedCollection=it;filterName=NoteFilter.ALL.name},onRename=model::renameCollection,
        onDelete={ value,done -> model.deleteEmptyCollection(value) {
            if(selectedCollection==value.id) selectedCollection=null
            done()
        } },onDismiss={collectionPanel=false})
    if (newCollection) AlertDialog(
        onDismissRequest = { if(!organizationBusy) newCollection = false },
        title = { Text("Nuova raccolta") },
        text = { Column { OutlinedTextField(collectionName, { if(it.length<=120) collectionName = it }, label = { Text("Nome") }, singleLine = true, enabled=!organizationBusy); error?.let {Text(it,color=MaterialTheme.colorScheme.error)} } },
        confirmButton = { TextButton(enabled = !organizationBusy && collectionName.isNotBlank(), onClick = {
            model.addCollection(collectionName) { collectionName = ""; newCollection = false }
        }) { Text("Crea") } },
        dismissButton = { TextButton(enabled=!organizationBusy,onClick = { newCollection = false }) { Text("Annulla") } },
    )
}

@Composable
private fun EmptyState(title: String, message: String) {
    Column(Modifier.fillMaxWidth().padding(vertical = 28.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Icon(Icons.Default.Description, null, Modifier.size(32.dp), tint = MaterialTheme.colorScheme.primary)
        Text(title, style = MaterialTheme.typography.headlineMedium)
        Text(message, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun NoteCard(note: Note, collection: String?, syncState: String?, compact: Boolean = false, selecting: Boolean, selected: Boolean, selectionEnabled: Boolean, onSelect: () -> Unit, onPin: () -> Unit, onArchive: () -> Unit, onOpen: () -> Unit, onFavorite: () -> Unit, onTrash: () -> Unit, onRestore: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    // A bounded excerpt avoids laying out the entire body of a long note in each card.
    val preview = remember(note.body,note.sketch) {
        if(note.sketch!=null) "" else note.body.take(1200)
            .replace(Regex("\\[((?:\\\\.|[^\\]])*)]\\(notes-asset://[a-f0-9]{64}\\.[a-z0-9]{2,4}\\)"),"Allegato · $1")
            .replace(Regex("notes-asset://[a-z0-9.]*"),"allegato").take(360).trim()
    }
    val checklistType =
        remember(note.body, note.sketch) {
            note.sketch == null &&
                Checklist.hasMarker(note.body)
        }
    val updatedLabel = remember(note.updatedAt) { editorialDate(note.updatedAt) }
    val selectionColor by animateColorAsState(
        targetValue = if (selected) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surface,
        animationSpec = tween(180), label = "note-selection")
    Card(onClick = { if (selecting) { if (selectionEnabled) onSelect() } else if (note.deletedAt == null) onOpen() }, modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = selectionColor),
        border = BorderStroke(if (selected) 2.dp else 1.dp, if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant),
        shape = RoundedCornerShape(24.dp)) {
        Row(Modifier.fillMaxWidth()) {
            if (selecting) Checkbox(selected, onCheckedChange = { onSelect() }, enabled = selectionEnabled,
                modifier = Modifier.semantics { contentDescription = "Seleziona " + note.title.ifBlank { "nota senza titolo" } })
            Box(Modifier.padding(top = 22.dp).width(4.dp).height(32.dp).background(
                if (note.favorite || note.pinned) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant))
            Column(Modifier.weight(1f).padding(start = 18.dp, top = 8.dp, end = 12.dp, bottom = 16.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(collection ?: "Inbox", Modifier.weight(1f), style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.primary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    if (note.pinned) Icon(Icons.Default.PushPin, "Fissata in alto", Modifier.size(16.dp), tint = MaterialTheme.colorScheme.primary)
                    if (note.archived) Icon(Icons.Default.Archive, "Archiviata", Modifier.size(16.dp))
                    if (note.favorite) Icon(Icons.Default.Star, "Preferita", Modifier.size(16.dp), tint = MaterialTheme.colorScheme.primary)
                    if (!selecting && note.deletedAt == null) Box {
                        IconButton(onClick = { menu = true }) { Icon(Icons.Default.MoreVert, "Azioni nota") }
                        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                            DropdownMenuItem(text = { Text(if (note.favorite) "Rimuovi dai preferiti" else "Aggiungi ai preferiti") },
                                onClick = { menu = false; onFavorite() })
                            DropdownMenuItem(text = { Text(if (note.pinned) "Non fissare più" else "Fissa in alto") }, onClick = { menu = false; onPin() })
                            DropdownMenuItem(text = { Text(if (note.archived) "Riporta nelle note" else "Archivia") }, onClick = { menu = false; onArchive() })
                            DropdownMenuItem(text = { Text("Sposta nel cestino") }, onClick = { menu = false; onTrash() })
                        }
                    } else if (!selecting) TextButton(onClick = onRestore) { Text("Ripristina") }
                }
                Text(note.title.ifBlank { "Senza titolo" }, style = MaterialTheme.typography.titleLarge,
                    fontFamily = FontFamily.Serif, maxLines = 2, overflow = TextOverflow.Ellipsis)
                if (checklistType) EditorialBadge("Checklist")
                when (note.sketch?.kind) {
                    VisualDocumentKind.SKETCH -> {
                        EditorialBadge("Disegno")
                        SketchPreview(note.body, Modifier.fillMaxWidth())
                    }
                    VisualDocumentKind.WHITEBOARD -> {
                        EditorialBadge("Lavagna")
                        WhiteboardPreview(note.body, Modifier.fillMaxWidth())
                    }
                    null -> Unit
                }
                if (note.tags.isNotEmpty()) Text(note.tags.joinToString(" ") { "#$it" }, style = MaterialTheme.typography.labelMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)

                if (preview.isNotBlank()) Text(preview, style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = if(compact)2 else 3, overflow = TextOverflow.Ellipsis)
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant, modifier = Modifier.padding(top = 6.dp))
                Text("Modificata · $updatedLabel", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                syncState?.let { Text(it, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun EditorScreen(model: EditorViewModel, collections: List<Collection>, initialChecklist: Boolean = false, initialAttachments: Boolean = false, onSketchCreate: ((blockId: String?) -> Unit)? = null, linkedSketches: List<Note> = emptyList(), onOpenSketch: (String)->Unit = {}, onWhiteboardCreate: ((blockId: String?) -> Unit)? = null, linkedWhiteboards: List<Note> = emptyList(), onOpenWhiteboard: (String)->Unit = {}, allNotes: List<Note> = emptyList(), onOpenNote: (String)->Unit = {}, onBack: () -> Unit) {
    var pendingDrawingBlockId by rememberSaveable { mutableStateOf<String?>(null) }
    var pendingNote by rememberSaveable {mutableStateOf<String?>(null)}
    var linkMessage by remember {mutableStateOf<String?>(null)}
    val openLinked: (String)->Unit = { target ->
        if(target==model.noteId) linkMessage="Sei già in questa nota."
        else if(allNotes.none {it.id==target && it.deletedAt==null && it.task==null && it.sketch==null}) linkMessage="Nota non disponibile: potrebbe essere nel cestino o non ancora sincronizzata."
        else if(model.dirty) pendingNote=target else onOpenNote(target)
    }
    val mediaApp=androidx.compose.ui.platform.LocalContext.current.applicationContext as it.notes.ecosystem.NotesApplication
    val media:AttachmentViewModel=viewModel(key="attachments-${model.noteId}",factory=viewModelFactory {initializer {AttachmentViewModel(mediaApp,model)}})
    var attachmentsOpen by rememberSaveable {mutableStateOf(initialAttachments)}
    var smartCaptureOpen by rememberSaveable { mutableStateOf(false) }
    var writingOnly by rememberSaveable {mutableStateOf(false)}
    var showHistory by rememberSaveable { mutableStateOf(false) }
    var confirmClose by rememberSaveable { mutableStateOf(false) }
    var chooseCollection by rememberSaveable { mutableStateOf(false) }
    var previewMode by rememberSaveable { mutableStateOf(false) }
    var checklistMode by rememberSaveable { mutableStateOf(initialChecklist) }
    var taskText by rememberSaveable { mutableStateOf("") }
    val currentBody = model.body
    val parsed by produceState<Pair<String, List<ChecklistItem>>?>(null, currentBody, checklistMode) {
        value = if (checklistMode) withContext(Dispatchers.Default) { currentBody to Checklist.parse(currentBody) } else null
    }
    val checklist = if (parsed?.first == currentBody) parsed?.second.orEmpty() else emptyList()
    val parsing = checklistMode && parsed?.first != currentBody
    val close = { if (model.dirty) confirmClose = true else onBack() }
    BackHandler { if (!model.loading && !model.saving && !model.mediaBusy && !model.checklistWorking) close() }
    Scaffold(
        topBar = { TopAppBar(colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            title = { EditorialAppTitle("La tua pagina", "IL TUO TACCUINO") }, navigationIcon = {
            IconButton(enabled = !model.loading && !model.saving && !model.mediaBusy && !model.checklistWorking, onClick = close) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Indietro") }
        }, actions = { Button(enabled = model.available && !model.loading && !model.saving && !model.mediaBusy && !model.checklistWorking, onClick = { model.save(onBack) }) {
            Text(if (model.saving) "Salvataggio…" else "Salva")
        } }) },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).imePadding().padding(horizontal = 24.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (model.loading || model.mediaBusy) LinearProgressIndicator(Modifier.fillMaxWidth())
            if(model.mediaBusy && !attachmentsOpen)Text(if(media.recording) "Registrazione in corso: apri Allegati per terminarla." else "Preparazione allegati…",style=MaterialTheme.typography.bodySmall)
            if(!attachmentsOpen)media.error?.let {Text(it,color=MaterialTheme.colorScheme.error)}
            model.error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            Row { TextButton(onClick={writingOnly=!writingOnly}){Text(if(writingOnly)"Mostra strumenti" else "Solo pagina")} }
            if(!writingOnly) {
            Text(model.draftStatus,
                style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            TextField(model.title, model::editTitle, modifier = Modifier.fillMaxWidth(),
                placeholder = { Text("Dai un titolo", style = MaterialTheme.typography.headlineLarge) },
                textStyle = MaterialTheme.typography.headlineLarge, colors = pageFieldColors(),
                enabled = model.available && !model.saving && !model.mediaBusy, singleLine = true)
            Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(enabled = model.available && !model.saving && !model.mediaBusy, onClick = { chooseCollection = true }) {
                Text(collections.firstOrNull { it.id == model.collectionId }?.name ?: "Inbox · da organizzare")
            }
            TextButton(enabled=model.available && !model.saving && !model.mediaBusy && !model.checklistWorking,onClick=model::saveAsTemplate) {Text("Crea modello")}
            TextButton(enabled=model.available && !model.saving,onClick={attachmentsOpen=true}) {Text(if(media.recording)"Registrazione…" else "Allegati")}
            TextButton(
                enabled = model.available && !model.saving && !model.mediaBusy,
                onClick = { smartCaptureOpen = true },
            ) {
                Text("Acquisisci")
            }
            DiaryDateEditor(model)
            TagsEditor(model)
            NoteConnections(model.noteId,model.body,allNotes,model.available && !model.saving && !model.mediaBusy && !model.checklistWorking,openLinked)
            if(onSketchCreate!=null)TextButton(enabled=model.available && !model.dirty && !model.saving && !model.mediaBusy,onClick={onSketchCreate(null)}){Text("Disegna")}
            linkedSketches.forEach { sketch -> TextButton(onClick={if(!model.dirty)onOpenSketch(sketch.id)},enabled=!model.dirty){Text("Disegno · ${sketch.title}")} }
            if(onWhiteboardCreate!=null)TextButton(enabled=model.available && !model.dirty && !model.saving && !model.mediaBusy,onClick={onWhiteboardCreate(null)}){Text("Lavagna")}
            linkedWhiteboards.forEach { board -> TextButton(onClick={if(!model.dirty)onOpenWhiteboard(board.id)},enabled=!model.dirty){Text("Lavagna · ${board.title}")} }
            }
            Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(
                    selected = !checklistMode && !previewMode && !model.blockMode,
                    onClick = {
                        model.disableBlockMode()
                        checklistMode = false
                        previewMode = false
                    },
                    label = { Text("Scrivi") },
                )
                FilterChip(
                    selected = model.blockMode,
                    enabled = model.available && !model.saving && !model.mediaBusy && !model.checklistWorking,
                    onClick = {
                        checklistMode = false
                        previewMode = false
                        model.enableBlockMode()
                    },
                    label = { Text("Blocchi") },
                )
                FilterChip(
                    selected = checklistMode,
                    onClick = {
                        model.disableBlockMode()
                        checklistMode = true
                        previewMode = false
                    },
                    label = { Text("Checklist") },
                )
                FilterChip(
                    selected = previewMode,
                    onClick = {
                        model.disableBlockMode()
                        previewMode = true
                        checklistMode = false
                    },
                    label = { Text("Anteprima") },
                )
                TextButton(
                    enabled = model.available && !model.saving && !model.mediaBusy,
                    onClick = { model.loadHistory(); showHistory = true },
                ) { Text("Cronologia") }
            }
            }
            if(writingOnly) Text(model.title.ifBlank {"La tua pagina"},style=MaterialTheme.typography.headlineMedium)
            if (previewMode) {
                MarkdownPreview(
                    model.body,
                    Modifier.fillMaxWidth().weight(1f),
                    onOpenNote = { if (!model.saving && !model.mediaBusy && !model.checklistWorking) openLinked(it) },
                    onOpenAttachment = { attachmentsOpen = true },
                )
            } else if (model.blockMode) {
                UniversalBlockEditor(
                    model = model,
                    modifier = Modifier.fillMaxWidth().weight(1f),
                    showControls = !writingOnly,
                    onCreateDrawing = { blockId ->
                        if (!model.saving && !model.mediaBusy && !model.checklistWorking) {
                            onSketchCreate?.invoke(blockId)
                        }
                    },
                    onOpenDrawing = { sketchId ->
                        if (!model.saving && !model.mediaBusy && !model.checklistWorking && !model.dirty) {
                            onOpenSketch(sketchId)
                        }
                    },
                    onWhiteboardCreate = { blockId ->
                        if (!model.saving && !model.mediaBusy && !model.checklistWorking) {
                            onWhiteboardCreate?.invoke(blockId)
                        }
                    },
                    onOpenWhiteboard = { boardId ->
                        if (!model.saving && !model.mediaBusy && !model.checklistWorking && !model.dirty) {
                            onOpenWhiteboard(boardId)
                        }
                    },
                )
            } else if (!checklistMode) {
                MarkdownEditor(
                    model,
                    Modifier.fillMaxWidth().weight(1f).background(MaterialTheme.colorScheme.surface, MaterialTheme.shapes.medium),
                    showToolbar = !writingOnly,
                    notes = allNotes.filter { it.id != model.noteId },
                )
            } else {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(taskText, { taskText = it }, Modifier.weight(1f), singleLine = true,
                        label = { Text("Nuova attività") }, enabled = model.available && !model.saving && !model.mediaBusy && !model.checklistWorking)
                    IconButton(enabled = taskText.isNotBlank() && model.available && !model.saving && !model.mediaBusy,
                        onClick = { if (model.addTask(taskText)) taskText = "" }) { Icon(Icons.Default.Add, "Aggiungi attività") }
                }
                ChecklistEditor(model, currentBody, checklist, parsing, Modifier.fillMaxWidth().weight(1f))
            }
        }
    }
    linkMessage?.let { message -> AlertDialog(onDismissRequest={linkMessage=null},title={Text("Collegamento")},text={Text(message)},confirmButton={TextButton(onClick={linkMessage=null}){Text("Chiudi")}}) }
    pendingNote?.let { target -> AlertDialog(onDismissRequest={pendingNote=null},title={Text("Aprire la nota collegata?")},text={Text("Prima salva o scarta le modifiche di questa pagina.")},
        confirmButton={TextButton(enabled=!model.saving && !model.mediaBusy,onClick={model.save {pendingNote=null;onOpenNote(target)}}){Text("Salva e apri")}},
        dismissButton={Row {TextButton(onClick={pendingNote=null}){Text("Resta")};TextButton(enabled=!model.saving && !model.mediaBusy,onClick={model.discard {pendingNote=null;onOpenNote(target)}}){Text("Scarta e apri")}}}) }
    if (showHistory) RevisionHistory(model, collections) { showHistory = false }
    if (confirmClose) AlertDialog(onDismissRequest = { confirmClose = false },
        title = { Text("Salvare le modifiche?") },
        text = { Text("Puoi salvare l’appunto oppure uscire senza conservare le ultime modifiche.") },
        confirmButton = { TextButton(onClick = { confirmClose = false; model.save(onBack) }) { Text("Salva") } },
        dismissButton = { Row {
            TextButton(onClick = { confirmClose = false }) { Text("Resta") }
            TextButton(onClick = { confirmClose = false; model.discard(onBack) }) { Text("Scarta") }
        } })
    if (chooseCollection) AlertDialog(onDismissRequest = { chooseCollection = false },
        title = { Text("Scegli raccolta") },
        text = { LazyColumn {
            item { TextButton(onClick = { model.assignCollection(null); chooseCollection = false }) { Text("Inbox") } }
            items(collections, key = { it.id }) { collection ->
                TextButton(onClick = { model.assignCollection(collection.id); chooseCollection = false }) { Text(collection.name) }
            }
        } },
        confirmButton = { TextButton(onClick = { chooseCollection = false }) { Text("Chiudi") } })
    AttachmentPanel(model,media,attachmentsOpen){attachmentsOpen=false}
    SmartCaptureSheet(
        editor = model,
        visible = smartCaptureOpen,
        onDismiss = { smartCaptureOpen = false },
    )
}

@Composable
internal fun pageFieldColors() = TextFieldDefaults.colors(
    focusedContainerColor = Color.Transparent, unfocusedContainerColor = Color.Transparent,
    disabledContainerColor = Color.Transparent,
    focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent,
    disabledIndicatorColor = Color.Transparent,
)

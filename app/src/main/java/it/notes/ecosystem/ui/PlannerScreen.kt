package it.notes.ecosystem.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import it.notes.ecosystem.domain.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.util.UUID

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun PlannerScreen(
    repository: NotesRepository,
    allNotes: List<Note>,
    onOpenNote: (String) -> Unit,
    onBack: () -> Unit,
    onChecklist: () -> Unit,
    initialScope: PlannerScope = PlannerScope.TODAY,
    onSection: (String) -> Unit = {},
    initialTaskId: String? = null
) {
    val scope = rememberCoroutineScope()
    var currentScope by rememberSaveable { mutableStateOf(initialScope.name) }
    var plannerViewName by rememberSaveable {
        mutableStateOf(PlannerView.AGENDA.name)
    }
    var selectedDateString by rememberSaveable {
        mutableStateOf(LocalDate.now().toString())
    }
    var planningTaskId by rememberSaveable {
        mutableStateOf<String?>(null)
    }

    val plannerView = try { PlannerView.valueOf(plannerViewName) } catch (_: Exception) { PlannerView.AGENDA }
    val selectedDate = try { LocalDate.parse(selectedDateString) } catch (_: Exception) { LocalDate.now() }
    val plannerIndex by produceState<PlannerIndex?>(null, allNotes) {
        value = withContext(Dispatchers.Default) {
            PlannerPro.plannerIndex(allNotes)
        }
    }
    val effectiveIndex = remember(plannerIndex, allNotes) {
        plannerIndex ?: PlannerPro.plannerIndex(allNotes)
    }
    val plannedForSelected = remember(effectiveIndex, selectedDate) {
        PlannerPro.dayNotes(effectiveIndex, selectedDate)
    }
    val dueForSelected = remember(effectiveIndex, selectedDate) {
        PlannerPro.dueOn(effectiveIndex, selectedDate)
    }

    var editing by rememberSaveable { mutableStateOf<String?>(initialTaskId) }
    var creating by rememberSaveable { mutableStateOf(false) }
    var focusedTask by rememberSaveable { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val plannerScope = try { PlannerScope.valueOf(currentScope) } catch (_: Exception) { PlannerScope.TODAY }
    val today = remember { LocalDate.now() }
    val plannerResult by produceState<Pair<Pair<List<Note>, PlannerScope>, List<Note>>?>(null, allNotes, plannerScope) {
        value = (allNotes to plannerScope) to withContext(Dispatchers.Default) {
            plannerNotes(allNotes, plannerScope, today)
        }
    }
    val tasks = if (plannerResult?.first == (allNotes to plannerScope)) plannerResult?.second.orEmpty() else emptyList()
    val calculating = plannerResult?.first != (allNotes to plannerScope)

    BackHandler { if (!busy) onBack() }
    fun action(block: suspend () -> Unit) {
        if (busy) return
        busy = true
        error = null
        scope.launch {
            try { block() }
            catch (e: CancellationException) { throw e }
            catch (e: Exception) { error = e.message ?: "Operazione non riuscita." }
            finally { busy = false }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { EditorialAppTitle("Attività", "PLANNER PRO E FOCUS") },
                navigationIcon = {
                    IconButton(enabled = !busy, onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "Indietro")
                    }
                },
                actions = {
                    TextButton(enabled = !busy, onClick = onChecklist) { Text("Da note") }
                }
            )
        },
        bottomBar = { EcosystemNavigation("Attività", enabled = !busy, onSelect = onSection) },
        floatingActionButton = {
            if (!busy) {
                FloatingActionButton(onClick = { creating = true }, containerColor = MaterialTheme.colorScheme.primary) {
                    Icon(Icons.Default.Add, "Nuova attività")
                }
            }
        }
    ) { padding ->
        LazyColumn(
            Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = PaddingValues(20.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item {
                PlannerViewSelector(
                    current = plannerView,
                    onView = { plannerViewName = it.name },
                    enabled = !busy,
                )
            }

            item {
                PlannerDateNavigator(
                    view = plannerView,
                    selected = selectedDate,
                    enabled = !busy,
                    onDate = { selectedDateString = it.toString() },
                )
            }

            if (error != null) item { Text(error.orEmpty(), color = MaterialTheme.colorScheme.error) }
            if (calculating || busy) item { LinearProgressIndicator(Modifier.fillMaxWidth()) }

            when (plannerView) {
                PlannerView.AGENDA -> {
                    item {
                        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            listOf(
                                PlannerScope.TODAY to "Oggi",
                                PlannerScope.UPCOMING to "Prossime",
                                PlannerScope.ALL to "Tutte",
                                PlannerScope.COMPLETED to "Completate"
                            ).forEach { (itemScope, label) ->
                                FilterChip(
                                    selected = plannerScope == itemScope,
                                    enabled = !busy,
                                    onClick = { currentScope = itemScope.name },
                                    label = { Text(label) }
                                )
                            }
                        }
                    }

                    if (!calculating && tasks.isEmpty()) {
                        item {
                            Text(
                                when (plannerScope) {
                                    PlannerScope.TODAY -> "Nessuna attività prevista per oggi. Un momento per te."
                                    PlannerScope.UPCOMING -> "Nessuna attività programmata per i prossimi giorni."
                                    PlannerScope.COMPLETED -> "Nessuna attività completata."
                                    PlannerScope.TRASH -> "Nessuna attività nel cestino."
                                    else -> "Nessuna attività creata. Tocca + per iniziare."
                                },
                                style = MaterialTheme.typography.bodyLarge
                            )
                        }
                    }

                    items(tasks, key = { it.id }) { task ->
                        val details = checkNotNull(task.task)
                        val completed = details.completedAt != null
                        Card(
                            onClick = { if (!busy) editing = task.id },
                            modifier = Modifier.fillMaxWidth(),
                            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                            border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant)
                        ) {
                            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Row {
                                    Checkbox(
                                        checked = completed,
                                        enabled = !busy,
                                        modifier = Modifier.semantics { contentDescription = task.title.ifBlank { "Attività" } },
                                        onCheckedChange = { check ->
                                            action {
                                                val updated = completePlannedTask(details, check, System.currentTimeMillis(), LocalDate.now())
                                                repository.updatePlannedTask(task, updated)
                                            }
                                        }
                                    )
                                    Column(Modifier.weight(1f).padding(start = 8.dp)) {
                                        Text(
                                            task.title.ifBlank { "Attività senza titolo" },
                                            fontFamily = FontFamily.Serif,
                                            style = MaterialTheme.typography.titleMedium,
                                            textDecoration = if (completed) TextDecoration.LineThrough else null
                                        )
                                        details.due?.let {
                                            Text("Scadenza: ${editorialDue(it)}", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
                                        }
                                        details.plannedDate?.let { day ->
                                            val timing =
                                                details.plannedTime?.let {
                                                    "$day · $it · ${details.plannedMinutes} min"
                                                } ?: day

                                            Text(
                                                "Pianificata: $timing",
                                                style = MaterialTheme.typography.labelSmall,
                                                color = MaterialTheme.colorScheme.tertiary,
                                            )
                                        }
                                        details.reminderAt?.let {
                                            Text("Promemoria: ${editorialDate(it)}", style = MaterialTheme.typography.labelSmall)
                                        }
                                    }
                                    IconButton(enabled = !busy, onClick = { focusedTask = task.id }) {
                                        Icon(Icons.Default.Timer, "Avvia focus")
                                    }
                                }
                                if (task.body.isNotBlank()) {
                                    Text(task.body, maxLines = 2, style = MaterialTheme.typography.bodyMedium)
                                }
                                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                    if (details.priority > 0) {
                                        EditorialBadge(
                                            when (details.priority) {
                                                3 -> "Alta"
                                                2 -> "Media"
                                                1 -> "Bassa"
                                                else -> "Priorità ${details.priority}"
                                            }
                                        )
                                    }
                                    if (details.repeat != RepeatRule.NONE) {
                                        EditorialBadge(
                                            when (details.repeat) {
                                                RepeatRule.DAILY -> "Ogni giorno"
                                                RepeatRule.WEEKLY -> "Ogni settimana"
                                                RepeatRule.MONTHLY -> "Ogni mese"
                                                else -> ""
                                            }
                                        )
                                    }
                                    if (details.focusSeconds > 0) {
                                        EditorialBadge("${details.focusSeconds / 60}m focus")
                                    }
                                }
                                Row(
                                    Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween
                                ) {
                                    details.linkedNoteId?.let { link ->
                                        TextButton(enabled = !busy, onClick = { onOpenNote(link) }) {
                                            Text("Apri nota collegata")
                                        }
                                    } ?: Spacer(Modifier.width(1.dp))

                                    TextButton(
                                        enabled = !busy && !completed,
                                        onClick = { planningTaskId = task.id },
                                    ) {
                                        Text(
                                            if (details.plannedDate == null) "Pianifica"
                                            else "Sposta"
                                        )
                                    }
                                }
                            }
                        }
                    }
                }

                PlannerView.DAY -> {
                    item {
                        DayTimeBlocks(
                            index = effectiveIndex,
                            selected = selectedDate,
                            enabled = !busy,
                            onEdit = { editing = it.id },
                            onFocus = { focusedTask = it.id },
                            onQuickPlan = { planningTaskId = it.id },
                        )
                    }
                }

                PlannerView.WEEK -> {
                    item {
                        WeekPlanner(
                            index = effectiveIndex,
                            selected = selectedDate,
                            enabled = !busy,
                            onDate = { selectedDateString = it.toString() },
                        )
                    }
                    item {
                        HorizontalDivider(Modifier.padding(vertical = 8.dp))
                        Text(
                            "Dettaglio ${PlannerPro.dayLabel(selectedDate)}",
                            style = MaterialTheme.typography.titleMedium,
                        )
                    }
                    item {
                        DayTimeBlocks(
                            index = effectiveIndex,
                            selected = selectedDate,
                            enabled = !busy,
                            onEdit = { editing = it.id },
                            onFocus = { focusedTask = it.id },
                            onQuickPlan = { planningTaskId = it.id },
                        )
                    }
                }

                PlannerView.MONTH -> {
                    item {
                        MonthPlanner(
                            index = effectiveIndex,
                            selected = selectedDate,
                            enabled = !busy,
                            onDate = { selectedDateString = it.toString() },
                        )
                    }
                    item {
                        HorizontalDivider(Modifier.padding(vertical = 8.dp))
                        Text(
                            "Attività per ${PlannerPro.dayLabel(selectedDate)}",
                            style = MaterialTheme.typography.titleMedium,
                        )
                    }

                    if (plannedForSelected.isEmpty() && dueForSelected.isEmpty()) {
                        item {
                            Text(
                                "Nessuna attività pianificata o in scadenza per questo giorno.",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    } else {
                        if (plannedForSelected.isNotEmpty()) {
                            item {
                                Text("Pianificate (${plannedForSelected.size}):", style = MaterialTheme.typography.labelLarge)
                            }
                            items(plannedForSelected, key = { "planned-${it.id}" }) { note ->
                                OutlinedCard(
                                    modifier = Modifier.fillMaxWidth(),
                                    onClick = { editing = note.id },
                                    enabled = !busy,
                                ) {
                                    Row(
                                        Modifier.padding(12.dp),
                                        horizontalArrangement = Arrangement.SpaceBetween,
                                    ) {
                                        Column(Modifier.weight(1f)) {
                                            Text(note.title.ifBlank { "Attività" }, style = MaterialTheme.typography.titleSmall)
                                            note.task?.plannedTime?.let {
                                                Text("$it · ${note.task.plannedMinutes} min", style = MaterialTheme.typography.labelSmall)
                                            }
                                        }
                                        IconButton(enabled = !busy, onClick = { focusedTask = note.id }) {
                                            Icon(Icons.Default.Timer, "Avvia focus")
                                        }
                                    }
                                }
                            }
                        }

                        if (dueForSelected.isNotEmpty()) {
                            item {
                                Text("In scadenza (${dueForSelected.size}):", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.error)
                            }
                            items(dueForSelected, key = { "due-${it.id}" }) { note ->
                                OutlinedCard(
                                    modifier = Modifier.fillMaxWidth(),
                                    onClick = { editing = note.id },
                                    enabled = !busy,
                                ) {
                                    Row(
                                        Modifier.padding(12.dp),
                                        horizontalArrangement = Arrangement.SpaceBetween,
                                    ) {
                                        Column(Modifier.weight(1f)) {
                                            Text(note.title.ifBlank { "Attività" }, style = MaterialTheme.typography.titleSmall)
                                            Text("Scadenza: ${note.task?.due}", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.error)
                                        }
                                        TextButton(enabled = !busy, onClick = { planningTaskId = note.id }) {
                                            Text("Pianifica")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    planningTaskId?.let { taskId ->
        val note = allNotes.firstOrNull {
            it.id == taskId && it.task != null && it.deletedAt == null
        }

        if (note == null) {
            planningTaskId = null
        } else {
            TimeBlockDialog(
                note = note,
                initialDate = selectedDate,
                enabled = !busy,
                onDismiss = { planningTaskId = null },
                onSave = { details ->
                    action {
                        repository.updatePlannedTask(note, details)
                        planningTaskId = null
                    }
                },
            )
        }
    }

    val editingTask = tasks.firstOrNull { it.id == editing } ?: allNotes.firstOrNull { it.id == editing }
    if (editing != null && editingTask != null) {
        TaskEditorDialog(
            editingTask.id, editingTask, allNotes, busy, error,
            onDismiss = { if (!busy) editing = null },
            onDelete = {
                action {
                    repository.updatePlannedTask(editingTask, editingTask.task!!, deleted = true)
                    editing = null
                }
            },
            onSave = { title, body, details, _ ->
                action {
                    repository.savePlannedTask(
                        expected = editingTask,
                        id = editingTask.id,
                        title = title,
                        body = body,
                        details = details,
                    )
                    editing = null
                }
            }
        )
    }

    if (creating) {
        val newId = remember { UUID.randomUUID().toString() }
        TaskEditorDialog(
            newId, null, allNotes, busy, error,
            onDismiss = { if (!busy) creating = false },
            onSave = { title, body, details, _ ->
                action {
                    repository.savePlannedTask(null, newId, title, body, details)
                    creating = false
                }
            }
        )
    }

    focusedTask?.let { taskId ->
        val target = allNotes.firstOrNull { it.id == taskId }
        if (target?.task != null) {
            val suggested =
                target.task
                    .plannedMinutes
                    .takeIf { target.task.plannedDate != null }

            FocusTimerDialog(
                task = target,
                onDismiss = { focusedTask = null },
                onSave = { session ->
                    action {
                        repository.addFocusSession(taskId, session)
                        focusedTask = null
                    }
                },
                suggestedMinutes = suggested,
            )
        }
    }
}

@Composable
internal fun TaskEditorDialog(
    id: String,
    initial: Note?,
    notes: List<Note>,
    busy: Boolean,
    externalError: String?,
    onDismiss: () -> Unit,
    onDelete: (() -> Unit)? = null,
    onSave: (String, String, TaskDetails, Boolean) -> Unit,
    initialDue: String? = null
) {
    val details = initial?.task
    var title by rememberSaveable { mutableStateOf(initial?.title.orEmpty()) }
    var body by rememberSaveable { mutableStateOf(initial?.body.orEmpty()) }
    var due by rememberSaveable { mutableStateOf(details?.due ?: initialDue ?: "") }
    var priority by rememberSaveable { mutableIntStateOf(details?.priority ?: 0) }
    var repeatRule by rememberSaveable { mutableStateOf(details?.repeat?.name ?: RepeatRule.NONE.name) }
    var reminderEpoch by rememberSaveable { mutableStateOf(details?.reminderAt) }
    var linkedNote by rememberSaveable { mutableStateOf(details?.linkedNoteId.orEmpty()) }
    var error by remember { mutableStateOf<String?>(null) }
    var complete by rememberSaveable { mutableStateOf(details?.completedAt != null) }

    var plannedDate by rememberSaveable {
        mutableStateOf(details?.plannedDate.orEmpty())
    }
    var plannedTime by rememberSaveable {
        mutableStateOf(details?.plannedTime.orEmpty())
    }
    var plannedMinutes by rememberSaveable {
        mutableIntStateOf(
            details?.plannedMinutes ?: PlannerPro.DEFAULT_BLOCK_MINUTES
        )
    }

    Dialog(onDismissRequest = onDismiss) {
        Surface(
            shape = MaterialTheme.shapes.extraLarge,
            color = MaterialTheme.colorScheme.surface,
            modifier = Modifier.fillMaxWidth()
        ) {
            Column(
                Modifier.padding(20.dp).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Text(if (initial == null) "Nuova attività" else "Modifica attività", style = MaterialTheme.typography.titleLarge)
                OutlinedTextField(title, { title = it }, label = { Text("Titolo") }, singleLine = true, enabled = !busy)
                OutlinedTextField(body, { body = it }, label = { Text("Note o descrizione") }, enabled = !busy)
                OutlinedTextField(due, { due = it }, label = { Text("Scadenza (AAAA-MM-GG)") }, singleLine = true, enabled = !busy)

                Text("Priorità:", style = MaterialTheme.typography.labelMedium)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf(0 to "Nessuna", 3 to "Alta", 2 to "Media", 1 to "Bassa").forEach { (p, label) ->
                        FilterChip(
                            selected = priority == p,
                            enabled = !busy,
                            onClick = { priority = p },
                            label = { Text(label) }
                        )
                    }
                }

                Text("Ricorrenza:", style = MaterialTheme.typography.labelMedium)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf(
                        RepeatRule.NONE to "Nessuna",
                        RepeatRule.DAILY to "Ogni giorno",
                        RepeatRule.WEEKLY to "Ogni settimana",
                        RepeatRule.MONTHLY to "Ogni mese"
                    ).forEach { (r, label) ->
                        FilterChip(
                            selected = repeatRule == r.name,
                            enabled = !busy,
                            onClick = { repeatRule = r.name },
                            label = { Text(label) }
                        )
                    }
                }

                TextButton(enabled = !busy, onClick = {
                    val candidate = System.currentTimeMillis() + 60 * 60 * 1000
                    reminderEpoch = candidate
                }) {
                    Text(if (reminderEpoch == null) "Aggiungi promemoria (+1h)" else "Promemoria impostato (${editorialDate(reminderEpoch!!)})")
                }
                if (reminderEpoch != null) {
                    TextButton(enabled = !busy, onClick = { reminderEpoch = null }) {
                        Text("Rimuovi promemoria")
                    }
                }

                HorizontalDivider()
                Text(
                    "Pianificazione",
                    style = MaterialTheme.typography.titleSmall,
                )
                Text(
                    "La pianificazione indica quando vuoi lavorarci; la scadenza indica entro quando va completata.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )

                OutlinedTextField(
                    value = plannedDate,
                    onValueChange = { plannedDate = it.take(10) },
                    label = { Text("Giorno pianificato (AAAA-MM-GG)") },
                    singleLine = true,
                    enabled = !busy,
                )

                OutlinedTextField(
                    value = plannedTime,
                    onValueChange = { plannedTime = it.take(5) },
                    label = { Text("Ora opzionale (HH:MM)") },
                    singleLine = true,
                    enabled = !busy && plannedDate.isNotBlank(),
                )

                Row(
                    Modifier.horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    listOf(15, 25, 30, 45, 60, 90).forEach { value ->
                        FilterChip(
                            selected = plannedMinutes == value,
                            enabled = !busy,
                            onClick = { plannedMinutes = value },
                            label = { Text("${value}m") },
                        )
                    }
                }

                if (notes.isNotEmpty()) {
                    Text("Collega a una pagina:", style = MaterialTheme.typography.labelMedium)
                    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        FilterChip(selected = linkedNote.isEmpty(), enabled = !busy, onClick = { linkedNote = "" }, label = { Text("Nessuna") })
                        notes.filter { it.deletedAt == null && it.task == null }.take(10).forEach { candidate ->
                            FilterChip(
                                selected = linkedNote == candidate.id,
                                enabled = !busy,
                                onClick = { linkedNote = candidate.id },
                                label = { Text(candidate.title.ifBlank { "Senza titolo" }) }
                            )
                        }
                    }
                }

                (error ?: externalError)?.let { Text(it, color = MaterialTheme.colorScheme.error) }

                Row(horizontalArrangement = Arrangement.End, modifier = Modifier.fillMaxWidth()) {
                    if (onDelete != null) {
                        TextButton(enabled = !busy, onClick = onDelete) {
                            Text("Elimina", color = MaterialTheme.colorScheme.error)
                        }
                    }
                    Spacer(Modifier.weight(1f))
                    TextButton(enabled = !busy, onClick = onDismiss) { Text("Annulla") }
                    Button(
                        enabled = !busy && title.isNotBlank(),
                        onClick = {
                            try {
                                val parsedDue = due.trim().takeIf { it.isNotEmpty() }?.also {
                                    val d = LocalDate.parse(it)
                                    require(d.year in 2000..2200) { "Data tra 2000 e 2200 richiesta." }
                                }
                                val selectedRepeat = RepeatRule.valueOf(repeatRule)
                                require(selectedRepeat == RepeatRule.NONE || parsedDue != null) { "La ricorrenza richiede una data di scadenza." }

                                val parsedPlannedDate =
                                    plannedDate.trim()
                                        .takeIf { it.isNotBlank() }
                                        ?.also { LocalDate.parse(it) }

                                val parsedPlannedTime =
                                    plannedTime.trim()
                                        .takeIf { it.isNotBlank() }
                                        ?.also { LocalTime.parse(it) }

                                val newDetails = validateTask(
                                    TaskDetails(
                                        due = parsedDue,
                                        priority = priority,
                                        repeat = selectedRepeat,
                                        completedAt = if (complete) (details?.completedAt ?: System.currentTimeMillis()) else null,
                                        linkedNoteId = linkedNote.takeIf { it.isNotEmpty() },
                                        focusSeconds = details?.focusSeconds ?: 0,
                                        focusReceipts = details?.focusReceipts.orEmpty(),
                                        completedCycles = details?.completedCycles ?: 0,
                                        stage = details?.stage ?: TaskStage.TODO,
                                        reminderAt = reminderEpoch,
                                        reminderZone = if (reminderEpoch != null) ZoneId.systemDefault().id else null,
                                        focusHistory = details?.focusHistory.orEmpty(),
                                        reminderTime = details?.reminderTime,
                                        plannedDate = parsedPlannedDate,
                                        plannedTime = parsedPlannedTime,
                                        plannedMinutes = plannedMinutes,
                                    )
                                )
                                onSave(title.trim(), body, newDetails, complete)
                            } catch (e: Exception) {
                                error = e.message ?: "Verifica i campi inseriti."
                            }
                        }
                    ) {
                        Text("Salva")
                    }
                }
            }
        }
    }
}

@Composable
internal fun FocusTimerDialog(
    task: Note,
    onDismiss: () -> Unit,
    onSave: (FocusSession) -> Unit,
    suggestedMinutes: Int? = null,
) {
    var running by rememberSaveable { mutableStateOf(false) }

    val initialSeconds =
        (suggestedMinutes ?: 25)
            .coerceIn(1, 120)
            .toLong() * 60L

    var seconds by rememberSaveable(task.id, suggestedMinutes) {
        mutableLongStateOf(initialSeconds)
    }
    var elapsed by rememberSaveable { mutableLongStateOf(0L) }

    LaunchedEffect(running) {
        while (running && seconds > 0) {
            kotlinx.coroutines.delay(1000)
            seconds--
            elapsed++
        }
    }

    Dialog(onDismissRequest = onDismiss) {
        Surface(shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surface, modifier = Modifier.padding(16.dp)) {
            Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                EditorialAppTitle("Sessione di focus", task.title.ifBlank { "Attività" })
                Text(
                    "${seconds / 60}:${(seconds % 60).toString().padStart(2, '0')}",
                    style = MaterialTheme.typography.displayMedium
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = { running = !running }) { Text(if (running) "Pausa" else "Avvia") }
                    OutlinedButton(onClick = { seconds = initialSeconds; running = false }) { Text("Ripristina") }
                }
                TextButton(
                    enabled = elapsed > 0,
                    onClick = {
                        val sessionSeconds = elapsed.coerceAtLeast(1L).coerceAtMost(7200L)
                        onSave(FocusSession(id = UUID.randomUUID().toString(), seconds = sessionSeconds, endedAt = System.currentTimeMillis()))
                    }
                ) {
                    Text("Salva minuti (${elapsed / 60}m) ed esci")
                }
                TextButton(onClick = onDismiss) { Text("Chiudi senza salvare") }
            }
        }
    }
}

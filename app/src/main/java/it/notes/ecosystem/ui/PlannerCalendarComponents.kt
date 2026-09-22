package it.notes.ecosystem.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.Event
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import it.notes.ecosystem.domain.*
import java.time.*
import java.time.format.DateTimeFormatter
import java.util.Locale

@Composable
internal fun PlannerViewSelector(
    current: PlannerView,
    onView: (PlannerView) -> Unit,
    enabled: Boolean,
) {
    Row(
        Modifier.horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        listOf(
            PlannerView.AGENDA to "Agenda",
            PlannerView.DAY to "Giorno",
            PlannerView.WEEK to "Settimana",
            PlannerView.MONTH to "Mese",
        ).forEach { (view, label) ->
            FilterChip(
                selected = current == view,
                enabled = enabled,
                onClick = { onView(view) },
                label = { Text(label) },
            )
        }
    }
}

@Composable
internal fun PlannerDateNavigator(
    view: PlannerView,
    selected: LocalDate,
    enabled: Boolean,
    onDate: (LocalDate) -> Unit,
) {
    val title =
        when (view) {
            PlannerView.MONTH ->
                PlannerPro.monthLabel(YearMonth.from(selected))
            PlannerView.WEEK -> {
                val days = PlannerPro.weekDays(selected)
                "${days.first().dayOfMonth} – ${days.last().dayOfMonth} ${
                    PlannerPro.monthLabel(YearMonth.from(days.last()))
                }"
            }
            else ->
                selected.format(
                    DateTimeFormatter.ofPattern(
                        "EEEE d MMMM yyyy",
                        Locale.getDefault()
                    )
                ).replaceFirstChar {
                    if (it.isLowerCase()) it.titlecase(Locale.getDefault())
                    else it.toString()
                }
        }

    Row(
        Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        IconButton(
            enabled = enabled,
            onClick = {
                onDate(
                    when (view) {
                        PlannerView.MONTH -> selected.minusMonths(1)
                        PlannerView.WEEK -> selected.minusWeeks(1)
                        else -> selected.minusDays(1)
                    }
                )
            },
        ) {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, "Periodo precedente")
        }

        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
            )
            TextButton(
                enabled = enabled && selected != LocalDate.now(),
                onClick = { onDate(LocalDate.now()) },
            ) {
                Text("Oggi")
            }
        }

        IconButton(
            enabled = enabled,
            onClick = {
                onDate(
                    when (view) {
                        PlannerView.MONTH -> selected.plusMonths(1)
                        PlannerView.WEEK -> selected.plusWeeks(1)
                        else -> selected.plusDays(1)
                    }
                )
            },
        ) {
            Icon(Icons.AutoMirrored.Filled.ArrowForward, "Periodo successivo")
        }
    }
}

@Composable
internal fun MonthPlanner(
    notes: List<Note> = emptyList(),
    index: PlannerIndex? = null,
    selected: LocalDate,
    enabled: Boolean,
    onDate: (LocalDate) -> Unit,
) {
    val month = YearMonth.from(selected)
    val days = remember(month) {
        PlannerPro.monthGrid(month)
    }

    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(Modifier.fillMaxWidth()) {
            listOf("L", "M", "M", "G", "V", "S", "D").forEach {
                Text(
                    it,
                    modifier = Modifier.weight(1f),
                    style = MaterialTheme.typography.labelSmall,
                )
            }
        }

        days.chunked(7).forEach { week ->
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                week.forEach { date ->
                    val planned = if (index != null) PlannerPro.monthCount(index, date) else PlannerPro.monthCount(notes, date)
                    val due = if (index != null) PlannerPro.dueCount(index, date) else PlannerPro.dueCount(notes, date)
                    val inMonth = YearMonth.from(date) == month
                    val chosen = date == selected

                    Surface(
                        modifier = Modifier
                            .weight(1f)
                            .heightIn(min = 64.dp)
                            .clickable(enabled = enabled) {
                                onDate(date)
                            },
                        shape = MaterialTheme.shapes.medium,
                        color =
                            if (chosen) {
                                MaterialTheme.colorScheme.primaryContainer
                            } else {
                                MaterialTheme.colorScheme.surface
                            },
                        border = BorderStroke(
                            1.dp,
                            MaterialTheme.colorScheme.outlineVariant,
                        ),
                    ) {
                        Column(
                            Modifier.padding(6.dp),
                            verticalArrangement = Arrangement.spacedBy(2.dp),
                        ) {
                            Text(
                                date.dayOfMonth.toString(),
                                color =
                                    if (inMonth) {
                                        MaterialTheme.colorScheme.onSurface
                                    } else {
                                        MaterialTheme.colorScheme.onSurfaceVariant
                                    },
                                style = MaterialTheme.typography.labelMedium,
                            )

                            if (planned > 0) {
                                Text(
                                    "$planned pian.",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.primary,
                                )
                            }

                            if (due > 0) {
                                Text(
                                    "$due scad.",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.error,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
internal fun WeekPlanner(
    notes: List<Note> = emptyList(),
    index: PlannerIndex? = null,
    selected: LocalDate,
    enabled: Boolean,
    onDate: (LocalDate) -> Unit,
) {
    val days = remember(selected) {
        PlannerPro.weekDays(selected)
    }

    Row(
        Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        days.forEach { date ->
            val planned = if (index != null) PlannerPro.dayNotes(index, date) else PlannerPro.dayNotes(notes, date)
            val due = if (index != null) PlannerPro.dueOn(index, date) else PlannerPro.dueOn(notes, date)

            ElevatedCard(
                onClick = { onDate(date) },
                enabled = enabled,
                modifier = Modifier.width(132.dp),
                colors = CardDefaults.elevatedCardColors(
                    containerColor =
                        if (date == selected) {
                            MaterialTheme.colorScheme.primaryContainer
                        } else {
                            MaterialTheme.colorScheme.surface
                        },
                ),
            ) {
                Column(
                    Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text(
                        PlannerPro.dayLabel(date),
                        style = MaterialTheme.typography.titleSmall,
                    )
                    Text(
                        "${planned.size} pianificate",
                        style = MaterialTheme.typography.bodySmall,
                    )
                    if (due.isNotEmpty()) {
                        Text(
                            "${due.size} in scadenza",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.error,
                        )
                    }

                    planned.take(3).forEach { note ->
                        val time = note.task?.plannedTime ?: "—"
                        Text(
                            "$time · ${note.title.ifBlank { "Attività" }}",
                            maxLines = 1,
                            style = MaterialTheme.typography.labelSmall,
                        )
                    }

                    if (planned.size > 3) {
                        Text(
                            "+${planned.size - 3}",
                            style = MaterialTheme.typography.labelSmall,
                        )
                    }
                }
            }
        }
    }
}

@Composable
internal fun DayTimeBlocks(
    notes: List<Note> = emptyList(),
    index: PlannerIndex? = null,
    selected: LocalDate,
    enabled: Boolean,
    onEdit: (Note) -> Unit,
    onFocus: (Note) -> Unit,
    onQuickPlan: (Note) -> Unit,
) {
    val planned = remember(notes, index, selected) {
        if (index != null) PlannerPro.timeBlocks(index, selected)
        else PlannerPro.timeBlocks(notes, selected)
    }

    val collisions = remember(planned) {
        PlannerPro.collisions(planned)
    }

    val collisionIds = remember(collisions) {
        collisions.flatMap {
            listOf(it.firstTaskId, it.secondTaskId)
        }.toSet()
    }

    val allDay = planned.filter { it.start == null }
    val timed = planned.filter { it.start != null }

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (collisionIds.isNotEmpty()) {
            AssistChip(
                onClick = {},
                label = {
                    Text(
                        "Ci sono ${collisions.size} sovrapposizioni nel piano."
                    )
                },
                leadingIcon = {
                    Icon(Icons.Default.Schedule, null)
                },
            )
        }

        if (allDay.isNotEmpty()) {
            Text(
                "Nel giorno",
                style = MaterialTheme.typography.titleMedium,
            )

            allDay.forEach { block ->
                TimeBlockCard(
                    block = block,
                    overlap = false,
                    enabled = enabled,
                    onEdit = { onEdit(block.note) },
                    onFocus = { onFocus(block.note) },
                )
            }
        }

        Text(
            "Timeline",
            style = MaterialTheme.typography.titleMedium,
        )

        if (timed.isEmpty()) {
            Text(
                "Nessun blocco orario. Pianifica un'attività per costruire la giornata.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        } else {
            timed.forEach { block ->
                TimeBlockCard(
                    block = block,
                    overlap = block.note.id in collisionIds,
                    enabled = enabled,
                    onEdit = { onEdit(block.note) },
                    onFocus = { onFocus(block.note) },
                )
            }
        }

        val unplanned = PlannerPro.unplanned(notes)
        if (unplanned.isNotEmpty()) {
            HorizontalDivider()
            Text(
                "Da pianificare",
                style = MaterialTheme.typography.titleMedium,
            )

            unplanned.take(12).forEach { note ->
                OutlinedCard(
                    modifier = Modifier.fillMaxWidth(),
                    onClick = { onQuickPlan(note) },
                    enabled = enabled,
                ) {
                    Row(
                        Modifier.padding(12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text(note.title.ifBlank { "Attività" })
                            note.task?.due?.let {
                                Text(
                                    "Scadenza: $it",
                                    style = MaterialTheme.typography.labelSmall,
                                )
                            }
                        }
                        Icon(Icons.Default.Event, "Pianifica")
                    }
                }
            }
        }
    }
}

@Composable
private fun TimeBlockCard(
    block: TimeBlock,
    overlap: Boolean,
    enabled: Boolean,
    onEdit: () -> Unit,
    onFocus: () -> Unit,
) {
    val task = checkNotNull(block.note.task)

    OutlinedCard(
        modifier = Modifier.fillMaxWidth(),
        onClick = onEdit,
        enabled = enabled,
        border = BorderStroke(
            if (overlap) 2.dp else 1.dp,
            if (overlap) {
                MaterialTheme.colorScheme.error
            } else {
                MaterialTheme.colorScheme.outlineVariant
            },
        ),
    ) {
        Row(
            Modifier.padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                Text(
                    if (block.start == null) {
                        "Senza orario"
                    } else {
                        "${PlannerPro.formatTime(block.start)} – ${
                            PlannerPro.formatTime(checkNotNull(block.end))
                        }"
                    },
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.primary,
                )
                Text(
                    block.note.title.ifBlank { "Attività" },
                    style = MaterialTheme.typography.titleMedium,
                )
                if (task.due != null) {
                    Text(
                        "Scadenza ${task.due}",
                        style = MaterialTheme.typography.labelSmall,
                    )
                }
            }

            IconButton(
                enabled = enabled,
                onClick = onFocus,
            ) {
                Icon(Icons.Default.Schedule, "Avvia focus")
            }
        }
    }
}

@Composable
internal fun TimeBlockDialog(
    note: Note,
    initialDate: LocalDate,
    enabled: Boolean,
    onDismiss: () -> Unit,
    onSave: (TaskDetails) -> Unit,
) {
    val task = checkNotNull(note.task)

    var date by rememberSaveable {
        mutableStateOf(task.plannedDate ?: initialDate.toString())
    }
    var time by rememberSaveable {
        mutableStateOf(task.plannedTime.orEmpty())
    }
    var minutes by rememberSaveable {
        mutableIntStateOf(task.plannedMinutes)
    }
    var error by remember {
        mutableStateOf<String?>(null)
    }

    Dialog(onDismissRequest = onDismiss) {
        Surface(
            shape = MaterialTheme.shapes.extraLarge,
            color = MaterialTheme.colorScheme.surface,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Column(
                Modifier
                    .padding(20.dp)
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text(
                    "Pianifica attività",
                    style = MaterialTheme.typography.titleLarge,
                )
                Text(
                    note.title.ifBlank { "Attività" },
                    style = MaterialTheme.typography.bodyLarge,
                )

                OutlinedTextField(
                    value = date,
                    onValueChange = { date = it.take(10) },
                    label = { Text("Giorno (AAAA-MM-GG)") },
                    singleLine = true,
                    enabled = enabled,
                )

                OutlinedTextField(
                    value = time,
                    onValueChange = { time = it.take(5) },
                    label = { Text("Ora opzionale (HH:MM)") },
                    singleLine = true,
                    enabled = enabled,
                )

                Text("Durata", style = MaterialTheme.typography.labelMedium)

                Row(
                    Modifier.horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    listOf(15, 25, 30, 45, 60, 90).forEach { option ->
                        FilterChip(
                            selected = minutes == option,
                            enabled = enabled,
                            onClick = { minutes = option },
                            label = { Text("${option}m") },
                        )
                    }
                }

                OutlinedTextField(
                    value = minutes.toString(),
                    onValueChange = {
                        it.toIntOrNull()?.let { parsed ->
                            minutes = parsed.coerceIn(
                                PlannerPro.MIN_BLOCK_MINUTES,
                                PlannerPro.MAX_BLOCK_MINUTES,
                            )
                        }
                    },
                    label = { Text("Minuti") },
                    singleLine = true,
                    enabled = enabled,
                )

                error?.let {
                    Text(
                        it,
                        color = MaterialTheme.colorScheme.error,
                    )
                }

                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.End,
                ) {
                    if (task.plannedDate != null) {
                        TextButton(
                            enabled = enabled,
                            onClick = {
                                onSave(PlannerPro.unschedule(task))
                            },
                        ) {
                            Text("Rimuovi piano")
                        }
                    }

                    Spacer(Modifier.weight(1f))

                    TextButton(
                        enabled = enabled,
                        onClick = onDismiss,
                    ) {
                        Text("Annulla")
                    }

                    Button(
                        enabled = enabled,
                        onClick = {
                            try {
                                val parsedDate = LocalDate.parse(date.trim())
                                val parsedTime =
                                    time.trim()
                                        .takeIf { it.isNotBlank() }
                                        ?.let(LocalTime::parse)

                                onSave(
                                    PlannerPro.schedule(
                                        task = task,
                                        date = parsedDate,
                                        time = parsedTime,
                                        minutes = minutes,
                                    )
                                )
                            } catch (e: Exception) {
                                error = e.message ?: "Dati di pianificazione non validi."
                            }
                        },
                    ) {
                        Text("Pianifica")
                    }
                }
            }
        }
    }
}

package it.notes.ecosystem.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import it.notes.ecosystem.data.FocusStore
import it.notes.ecosystem.domain.*
import it.notes.ecosystem.domain.Collection
import kotlinx.coroutines.*
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

@Composable
internal fun HomeOverview(notes: List<Note>, collections: List<Collection>, noteCount: Int, pendingCount: Int,
    onCreate: () -> Unit, onNotes: () -> Unit, onAgenda: () -> Unit, onAllTasks: () -> Unit,
    onCollection: (String) -> Unit, onSketch: () -> Unit) {
    var today by remember { mutableStateOf(LocalDate.now()) }
    LaunchedEffect(Unit) { while (true) { today = LocalDate.now(); delay(60000) } }
    val agendaKey = notes to today
    val agendaResult by produceState<Pair<Pair<List<Note>, LocalDate>, List<Note>>?>(null, agendaKey) {
        value = agendaKey to withContext(Dispatchers.Default) { plannerNotes(notes, PlannerScope.TODAY, today) }
    }
    val agenda = if (agendaResult?.first == agendaKey) agendaResult!!.second else emptyList()
    val context = LocalContext.current
    val store = remember { FocusStore(context) }
    var focus by remember { mutableStateOf<FocusClock?>(null) }
    val owner = LocalLifecycleOwner.current
    val scope = rememberCoroutineScope()
    DisposableEffect(owner, store) {
        fun refresh() { scope.launch {
            try { focus = store.load() } catch (e: CancellationException) { throw e } catch (_: Exception) { focus = null }
        } }
        refresh()
        val observer = LifecycleEventObserver { _, event -> if (event == Lifecycle.Event.ON_RESUME) refresh() }
        owner.lifecycle.addObserver(observer)
        onDispose { owner.lifecycle.removeObserver(observer) }
    }
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        EditorialEyebrow(today.format(DateTimeFormatter.ofPattern("EEEE d MMMM", Locale.ITALIAN)).uppercase(Locale.ITALIAN))
        Text("Oggi, nel tuo spazio.", style=MaterialTheme.typography.headlineLarge)
        Surface(shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.surface,
            border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant)) {
            Column(Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                EditorialEyebrow("LA TUA AGENDA")
                Text("Un passo alla volta.", style = MaterialTheme.typography.headlineSmall)
                if (agendaResult?.first != agendaKey) LinearProgressIndicator(Modifier.fillMaxWidth())
                else if (agenda.isEmpty()) Text("Oggi hai spazio. Nessuna attività prevista o scaduta.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
                else agenda.take(3).forEach { n ->
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Icon(Icons.Default.RadioButtonUnchecked, null, Modifier.size(20.dp), tint = MaterialTheme.colorScheme.primary)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            Text(n.title, maxLines = 2, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.titleMedium)
                            Text(if (LocalDate.parse(n.task!!.due).isBefore(today)) "Da riprendere · ${editorialDue(n.task.due!!)}" else "Oggi",
                                style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
                TextButton(onClick = onAgenda) { Text(if (agenda.size > 3) "Apri agenda · ${agenda.size} attività" else "Apri agenda") }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            HomeMetric(noteCount, "Pagine salvate", Modifier.weight(1f), onNotes)
            HomeMetric(pendingCount, "Attività da fare", Modifier.weight(1f), onAllTasks)
        }
        Surface(shape=MaterialTheme.shapes.extraLarge,color=MaterialTheme.colorScheme.primary,contentColor=MaterialTheme.colorScheme.onPrimary) {
            Column(Modifier.fillMaxWidth().padding(24.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
                EditorialEyebrow("IL TUO TACCUINO")
                Text("Scrivi. Disegna.\nDai forma alle idee.",style=MaterialTheme.typography.headlineMedium)
                Row(Modifier.horizontalScroll(rememberScrollState()),horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                    FilledTonalButton(onClick=onCreate){Text("Nuova nota")}
                    FilledTonalButton(onClick=onSketch){Text("Sketchbook")}
                }
            }
        }
        Surface(onClick = onAllTasks, shape = MaterialTheme.shapes.large, color = MaterialTheme.colorScheme.secondaryContainer,
            contentColor = MaterialTheme.colorScheme.onSecondaryContainer) {
            Row(Modifier.fillMaxWidth().padding(20.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                Icon(Icons.Default.Timer, null, Modifier.size(28.dp))
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                    EditorialEyebrow("FOCUS")
                    Text(if (focus != null) "Riprendi il tuo momento." else "Una cosa, fatta bene.", style = MaterialTheme.typography.headlineSmall)
                    Text(if (focus != null) "Apri Attività per ritrovare la sessione e registrarne il tempo." else "Scegli un’attività e dedicagli il tuo tempo.",
                        style = MaterialTheme.typography.bodyMedium)
                }
            }
        }
        if (collections.isNotEmpty()) {
            EditorialSection("Le tue raccolte")
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                collections.forEach { c -> SuggestionChip(onClick = { onCollection(c.id) }, label = { Text(c.name) },
                    icon = { Icon(Icons.Default.Folder, null, Modifier.size(18.dp)) }) }
            }
        }
    }
}
@Composable
private fun HomeMetric(count: Int, label: String, modifier: Modifier, onClick: () -> Unit) {
    Surface(onClick = onClick, modifier = modifier, shape = MaterialTheme.shapes.medium,
        color = MaterialTheme.colorScheme.surface, border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant)) {
        Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(count.toString(), style = MaterialTheme.typography.headlineLarge, color = MaterialTheme.colorScheme.primary)
            Text(label, style = MaterialTheme.typography.labelLarge)
        }
    }
}

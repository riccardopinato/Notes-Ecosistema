package it.notes.ecosystem.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import it.notes.ecosystem.domain.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.time.*

@Composable
fun KanbanBoard(notes:List<Note>,busy:Boolean,onEdit:(Note)->Unit,onMove:(Note,TaskStatus)->Unit,onRestore:(Note)->Unit) {
    LazyRow(horizontalArrangement=Arrangement.spacedBy(12.dp)) {
        items(TaskStatus.entries.toList(),key={it.name}) {status ->
            val group=notes.filter {it.task!!.status()==status}
            Surface(Modifier.width(280.dp),shape=MaterialTheme.shapes.large,color=MaterialTheme.colorScheme.surfaceContainerLow) {
                Column(Modifier.padding(12.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
                    Text("${statusLabel(status)} · ${group.size}",style=MaterialTheme.typography.titleMedium)
                    LazyColumn(Modifier.height(380.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
                        if(group.isEmpty()) item {Text("Nessuna attività",style=MaterialTheme.typography.bodySmall)}
                        items(group,key={it.id}) {note ->
                            var menu by remember {mutableStateOf(false)}
                            Card(Modifier.fillMaxWidth()) {Column(Modifier.padding(12.dp)) {
                                Text(note.title,style=MaterialTheme.typography.titleMedium)
                                note.task!!.due?.let {Text(editorialDue(it),style=MaterialTheme.typography.bodySmall)}
                                if(note.task.priority>0) Text("Priorità ${note.task.priority}",style=MaterialTheme.typography.labelSmall)
                                if(note.deletedAt==null) TextButton(enabled=!busy,onClick={onEdit(note)}){Text("Apri attività")}
                                else TextButton(enabled=!busy,onClick={onRestore(note)}){Text("Ripristina")}
                                if(note.deletedAt==null) Box {
                                    TextButton(enabled=!busy,onClick={menu=true}){Text("Sposta in…")}
                                    DropdownMenu(menu,{menu=false}) {TaskStatus.entries.filter {it!=status}.forEach {target ->
                                        DropdownMenuItem(text={Text(statusLabel(target))},onClick={menu=false;onMove(note,target)},enabled=!busy)
                                    }}
                                }
                            }}
                        }
                    }
                }
            }
        }
    }
}
private data class FocusReport(val key:List<Any>,val days:List<Pair<LocalDate,Long>>,val history:List<FocusHistoryRow>)
@Composable
fun FocusInsights(notes:List<Note>,today:LocalDate) {
    var show by rememberSaveable {mutableStateOf(false)}
    var expanded by rememberSaveable {mutableStateOf(false)}
    val zone=ZoneId.systemDefault();val key=listOf(notes,today,zone.id)
    val report by produceState<FocusReport?>(null,key) {value=withContext(Dispatchers.Default){FocusReport(key,weeklyFocus(notes,today,zone),focusHistory(notes))}}
    val current=report?.takeIf {it.key==key}
    OutlinedButton(onClick={expanded=!expanded}) {
        Text(if(expanded) "Chiudi riepilogo Focus" else current?.let {"Focus · ${it.days.sumOf {day->day.second}/60} min negli ultimi 7 giorni"} ?: "Riepilogo Focus")
    }
    if(expanded) Surface(shape=MaterialTheme.shapes.large,color=MaterialTheme.colorScheme.surfaceContainerLow) {
        Column(Modifier.fillMaxWidth().padding(16.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
            Text("Il tempo che ti sei dedicato",style=MaterialTheme.typography.titleLarge)
            if(current==null) LinearProgressIndicator(Modifier.fillMaxWidth()) else {
                Text("${current.days.sumOf {it.second}/60} minuti negli ultimi 7 giorni",style=MaterialTheme.typography.headlineSmall)
                val max=current.days.maxOf {it.second}.coerceAtLeast(1)
                Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(6.dp)) {
                    current.days.forEach {(date,seconds)->Column(Modifier.weight(1f)) {
                        LinearProgressIndicator(progress={seconds.toFloat()/max},modifier=Modifier.fillMaxWidth())
                        Text("${date.dayOfMonth}/${date.monthValue}",style=MaterialTheme.typography.labelSmall)
                        Text("${seconds/60}m",style=MaterialTheme.typography.labelSmall)
                    }}
                }
                TextButton(onClick={show=true}){Text("Storico · ${current.history.size} sessioni")}
            }
            Text("Solo sessioni registrate con data dalla v0.15. I totali precedenti restano nelle attività.",style=MaterialTheme.typography.bodySmall)
        }
    }
    if(show) AlertDialog(onDismissRequest={show=false},title={Text("Sessioni Focus")},text={
        LazyColumn(Modifier.heightIn(max=360.dp)) {
            val rows=current?.history.orEmpty()
            if(rows.isEmpty()) item {Text("Nessuna sessione datata registrata.")}
            items(rows,key={it.session.id}) {row ->
                ListItem(headlineContent={Text(row.title)},supportingContent={Text(Reminders.display(row.session.endedAt,zone.id))},trailingContent={Text("${row.session.seconds/60}m ${row.session.seconds%60}s")})
            }
        }
    },confirmButton={TextButton(onClick={show=false}){Text("Chiudi")}})
}

package it.notes.ecosystem.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.unit.dp
import it.notes.ecosystem.domain.*
import it.notes.ecosystem.domain.Collection

/** One entry point for search filters; the query remains the only text field. */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun SearchControls(options: SearchOptions, onChange: (SearchOptions) -> Unit,
    collections: List<Collection>, collectionId: String?, onCollection: (String?) -> Unit,
    suggestedTags: List<String>, onReset: () -> Unit,
    filter: NoteFilter, onFilter: (NoteFilter) -> Unit,
    kind: String, onKind: (String) -> Unit, grid: Boolean, onGrid: () -> Unit) {
    val panelHeight = LocalConfiguration.current.screenHeightDp.dp * 0.65f
    var expanded by rememberSaveable { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val favorites = options.favoritesOnly || filter == NoteFilter.FAVORITES
    val scope = if(filter == NoteFilter.FAVORITES) NoteFilter.ALL else filter
    val scopeLabels = listOf(NoteFilter.ALL to "Note attive", NoteFilter.INBOX to "Inbox",
        NoteFilter.ARCHIVE to "Archivio", NoteFilter.TRASH to "Cestino")
    val taskLabels = listOf(TaskPresence.ANY to "Qualsiasi", TaskPresence.HAS_TASKS to "Con attività",
        TaskPresence.OPEN_TASKS to "Da completare", TaskPresence.NO_TASKS to "Senza attività")
    val active = buildList {
        if(scope != NoteFilter.ALL) add(scopeLabels.firstOrNull {it.first==scope}?.second ?: scope.name)
        if(kind != "Tutte") add(kind)
        if(favorites) add("Preferiti")
        if(options.pinnedOnly) add("Fissate")
        collectionId?.let { id -> add(collections.firstOrNull {it.id==id}?.name ?: "Raccolta non disponibile") }
        if(options.tasks != TaskPresence.ANY) add(taskLabels.first {it.first==options.tasks}.second)
        if(options.tags.isNotEmpty()) add((if(options.allTags) "Tag: " else "Uno dei tag: ")+options.tags.joinToString {"#$it"})
    }
    Column(verticalArrangement=Arrangement.spacedBy(4.dp)) {
        Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick={expanded=true}) {
                Icon(Icons.Default.Tune,contentDescription=null,modifier=Modifier.size(18.dp))
                Spacer(Modifier.width(6.dp))
                Text(if(active.isEmpty()) "Filtri" else "Filtri · ${active.size}")
            }
            if(active.isNotEmpty()) TextButton(onClick={error=null;onReset()}) {Text("Azzera")}
            Spacer(Modifier.weight(1f))
            IconButton(onClick=onGrid) {
                Icon(if(grid) Icons.Default.ViewList else Icons.Default.GridView,
                    contentDescription=if(grid) "Mostra elenco" else "Mostra griglia")
            }
        }
        if(active.isNotEmpty()) Text(active.joinToString(" · "),style=MaterialTheme.typography.bodySmall,
            color=MaterialTheme.colorScheme.onSurfaceVariant)
    }
    if(expanded) ModalBottomSheet(onDismissRequest={expanded=false},sheetState=rememberModalBottomSheetState(skipPartiallyExpanded=true)) {
        Column(Modifier.fillMaxWidth().heightIn(max=panelHeight).verticalScroll(rememberScrollState()).padding(horizontal=24.dp),
            verticalArrangement=Arrangement.spacedBy(8.dp)) {
            Text("Affina la ricerca",style=MaterialTheme.typography.headlineSmall)
            Text("I filtri si combinano. Chiudi il pannello per vedere i risultati.",style=MaterialTheme.typography.bodySmall)
            Text("Dove cercare",style=MaterialTheme.typography.titleSmall)
            FlowRow(horizontalArrangement=Arrangement.spacedBy(6.dp)) {
                scopeLabels.forEach { (value,label) -> FilterChip(scope==value,{
                    if(filter==NoteFilter.FAVORITES) onChange(options.copy(favoritesOnly=true))
                    onFilter(value)
                },label={Text(label)}) }
            }
            Text("Tipo di contenuto",style=MaterialTheme.typography.titleSmall)
            FlowRow(horizontalArrangement=Arrangement.spacedBy(6.dp)) {
                listOf("Tutte","Testo","Checklist","Disegni").forEach {value ->
                    FilterChip(kind==value,{onKind(value)},label={Text(if(value=="Tutte") "Qualsiasi tipo" else value)})
                }
            }
            FlowRow(horizontalArrangement=Arrangement.spacedBy(6.dp)) {
                FilterChip(favorites,{
                    if(filter==NoteFilter.FAVORITES) onFilter(NoteFilter.ALL)
                    onChange(options.copy(favoritesOnly=!favorites))
                },label={Text("Solo preferiti")})
                FilterChip(options.pinnedOnly,{onChange(options.copy(pinnedOnly=!options.pinnedOnly))},label={Text("Solo fissate")})
            }
            Text("Raccolta",style=MaterialTheme.typography.titleSmall)
            FlowRow(horizontalArrangement=Arrangement.spacedBy(6.dp)) {
                FilterChip(collectionId==null,{onCollection(null)},label={Text("Qualsiasi raccolta")})
                collections.forEach {c -> FilterChip(collectionId==c.id,{onCollection(c.id)},label={Text(c.name)})}
            }
            Text("Checklist nella nota",style=MaterialTheme.typography.titleSmall)
            FlowRow(horizontalArrangement=Arrangement.spacedBy(6.dp)) {
                taskLabels.forEach {(value,label)->FilterChip(options.tasks==value,{onChange(options.copy(tasks=value))},label={Text(label)})}
            }
            Text("Tag",style=MaterialTheme.typography.titleSmall)
            val tags = (options.tags + suggestedTags).distinct().sorted()
            if(tags.isEmpty()) Text("Nessun tag disponibile. Puoi cercare liberamente nel campo principale.",style=MaterialTheme.typography.bodySmall)
            FlowRow(horizontalArrangement=Arrangement.spacedBy(6.dp)) {
                tags.forEach {tag -> FilterChip(tag in options.tags,{
                    runCatching {if(tag in options.tags) options.tags-tag else Tags.add(options.tags,tag)}
                        .onSuccess {onChange(options.copy(tags=it));error=null}.onFailure {error=it.message}
                },label={Text("#$tag")})}
            }
            if(options.tags.size>1) FlowRow(horizontalArrangement=Arrangement.spacedBy(6.dp)) {
                FilterChip(options.allTags,{onChange(options.copy(allTags=true))},label={Text("Tutti i tag scelti")})
                FilterChip(!options.allTags,{onChange(options.copy(allTags=false))},label={Text("Almeno uno")})
            }
            error?.let {Text(it,color=MaterialTheme.colorScheme.error)}
            Spacer(Modifier.height(12.dp))
        }
        Row(Modifier.fillMaxWidth().padding(horizontal=24.dp,vertical=12.dp),horizontalArrangement=Arrangement.spacedBy(12.dp)) {
            TextButton(onClick={error=null;onReset()}) {Text("Azzera filtri")}
            Button(onClick={expanded=false},modifier=Modifier.weight(1f)) {Text("Mostra risultati")}
        }
    }
}

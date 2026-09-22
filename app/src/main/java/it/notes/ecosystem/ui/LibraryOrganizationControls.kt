package it.notes.ecosystem.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import it.notes.ecosystem.domain.*
import it.notes.ecosystem.domain.Collection
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun LibraryOrganizationBar(order: NoteOrder, onOrder: (NoteOrder)->Unit,
    savedCount: Int? = null, onSaved: ()->Unit = {}) {
    var menu by remember { mutableStateOf(false) }
    FlowRow(horizontalArrangement=Arrangement.spacedBy(8.dp)) {
        Box {
            TextButton(onClick={menu=true}) {
                Icon(Icons.Default.Sort, null, Modifier.size(18.dp)); Spacer(Modifier.width(6.dp))
                Text(order.label)
            }
            DropdownMenu(expanded=menu,onDismissRequest={menu=false}) {
                NoteOrder.entries.forEach { value ->
                    DropdownMenuItem(text={Text((if(order==value) "✓ " else "")+value.label)},onClick={onOrder(value);menu=false})
                }
            }
        }
        if(savedCount != null) TextButton(onClick=onSaved) {
            Icon(Icons.Default.Bookmarks,null,Modifier.size(18.dp)); Spacer(Modifier.width(6.dp))
            Text("Ricerche salvate" + if(savedCount>0) " · $savedCount" else "")
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SavedSearchPanel(values: List<SavedSearch>, collections: List<Collection>, current: SavedSearch,
    busy: Boolean, error: String?, onApply: (SavedSearch)->Unit,
    onSave: (SavedSearch, ()->Unit)->Unit, onRename: (SavedSearch,String,()->Unit)->Unit,
    onDelete: (SavedSearch,()->Unit)->Unit, onDismiss: ()->Unit) {
    var adding by rememberSaveable { mutableStateOf(false) }
    var editing by remember { mutableStateOf<SavedSearch?>(null) }
    var deleting by remember { mutableStateOf<SavedSearch?>(null) }
    var name by rememberSaveable { mutableStateOf("") }
    val height = LocalConfiguration.current.screenHeightDp.dp * 0.65f
    ModalBottomSheet(onDismissRequest={if(!busy) onDismiss()},sheetState=rememberModalBottomSheetState(skipPartiallyExpanded=true)) {
        Column(Modifier.fillMaxWidth().heightIn(max=height).padding(horizontal=24.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
            Text("Ritrova il tuo percorso",style=MaterialTheme.typography.headlineSmall)
            Text("Salva parole, filtri e ordinamento. Le scorciatoie restano su questo dispositivo.",style=MaterialTheme.typography.bodySmall)
            OutlinedButton(enabled=!busy && values.size<30,onClick={adding=true;editing=null;name=""}) {Text("Salva la ricerca attuale")}
            if(values.isEmpty()) Text("Le ricerche che usi spesso saranno qui.")
            LazyColumn(Modifier.fillMaxWidth().weight(1f,fill=false),verticalArrangement=Arrangement.spacedBy(6.dp)) {
                items(values,key={it.id}) { value ->
                    val missing = value.collectionId != null && collections.none {it.id==value.collectionId}
                    OutlinedCard(Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(12.dp)) {
                            TextButton(enabled=!busy && !missing,onClick={onApply(value);onDismiss()}) {Text(value.name)}
                            Text(if(missing) "Raccolta non più disponibile: ricrea la ricerca con un’altra raccolta."
                                else value.query.ifBlank {"Tutte le parole"}+" · "+value.order.label,
                                style=MaterialTheme.typography.bodySmall,maxLines=2,overflow=TextOverflow.Ellipsis)
                            Row {
                                TextButton(enabled=!busy,onClick={editing=value;adding=false;name=value.name}) {Text("Rinomina")}
                                TextButton(enabled=!busy,onClick={deleting=value}) {Text("Elimina")}
                            }
                        }
                    }
                }
            }
            Spacer(Modifier.height(20.dp))
        }
    }
    if(adding || editing!=null) AlertDialog(onDismissRequest={if(!busy){adding=false;editing=null}},
        title={Text(if(adding) "Salva ricerca" else "Rinomina ricerca")},
        text={Column {
            OutlinedTextField(name,{if(it.length<=80)name=it},label={Text("Nome")},singleLine=true,enabled=!busy)
            error?.let {Text(it,color=MaterialTheme.colorScheme.error)}
        }},
        confirmButton={TextButton(enabled=!busy && name.isNotBlank(),onClick={
            val close={adding=false;editing=null}
            val value=editing
            if(value!=null) onRename(value,name,close) else onSave(current.copy(id=UUID.randomUUID().toString(),name=name),close)
        }) {Text(if(busy) "Salvataggio…" else "Salva")}},
        dismissButton={TextButton(enabled=!busy,onClick={adding=false;editing=null}) {Text("Annulla")}})
    deleting?.let { value -> AlertDialog(onDismissRequest={if(!busy)deleting=null},title={Text("Elimina ricerca?")},
        text={Column {Text("Rimuovere “${value.name}”? Le note rimangono al loro posto.");error?.let {Text(it,color=MaterialTheme.colorScheme.error)}}},
        confirmButton={TextButton(enabled=!busy,onClick={onDelete(value){deleting=null}}) {Text("Elimina")}},
        dismissButton={TextButton(enabled=!busy,onClick={deleting=null}) {Text("Annulla")}}) }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CollectionManager(collections: List<Collection>, notes: List<Note>, drafts: List<Draft>,
    busy: Boolean, error: String?, onOpen: (String)->Unit,
    onRename: (Collection,String,()->Unit)->Unit, onDelete: (Collection,()->Unit)->Unit, onDismiss: ()->Unit) {
    var editing by remember { mutableStateOf<Collection?>(null) }
    var deleting by remember { mutableStateOf<Collection?>(null) }
    var name by rememberSaveable { mutableStateOf("") }
    val height = LocalConfiguration.current.screenHeightDp.dp * 0.65f
    val summaryKey = listOf(notes,drafts)
    val summaryResult by produceState<Pair<List<Any>,Map<String,CollectionOverview>>?>(null,summaryKey) {
        value=summaryKey to withContext(Dispatchers.Default) { collectionOverviews(notes,drafts) }
    }
    val summaries = summaryResult?.takeIf {it.first==summaryKey}?.second
    ModalBottomSheet(onDismissRequest={if(!busy)onDismiss()},sheetState=rememberModalBottomSheetState(skipPartiallyExpanded=true)) {
        Column(Modifier.fillMaxWidth().heightIn(max=height).padding(horizontal=24.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
            Text("Le tue raccolte",style=MaterialTheme.typography.headlineSmall)
            Text("Rinomina senza spostare le note. Puoi eliminare solo raccolte vuote, non usate dalla cronologia.",style=MaterialTheme.typography.bodySmall)
            LazyColumn(Modifier.fillMaxWidth().weight(1f,fill=false),verticalArrangement=Arrangement.spacedBy(8.dp)) {
                items(collections,key={it.id}) { collection ->
                    val summary=summaries?.let {it[collection.id] ?: CollectionOverview(0,0,0,0)}
                    OutlinedCard(Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(12.dp)) {
                            TextButton(enabled=!busy,onClick={onOpen(collection.id);onDismiss()}) {Text(collection.name)}
                            Text(if(summary==null) "Calcolo…" else "${summary.active} attivi · ${summary.archived} archiviati · ${summary.trash} nel cestino · ${summary.drafts} bozze",style=MaterialTheme.typography.bodySmall)
                            Row {
                                TextButton(enabled=!busy,onClick={editing=collection;name=collection.name}) {Text("Rinomina")}
                                TextButton(enabled=!busy && summary?.empty==true,onClick={deleting=collection}) {Text("Elimina vuota")}
                            }
                        }
                    }
                }
            }
            Spacer(Modifier.height(20.dp))
        }
    }
    editing?.let { collection -> AlertDialog(onDismissRequest={if(!busy)editing=null},title={Text("Rinomina raccolta")},
        text={Column {
            OutlinedTextField(name,{if(it.length<=120)name=it},label={Text("Nome")},singleLine=true,enabled=!busy)
            Text("Il nuovo nome sarà usato anche nei backup e per le note sincronizzate.",style=MaterialTheme.typography.bodySmall)
            error?.let {Text(it,color=MaterialTheme.colorScheme.error)}
        }},confirmButton={TextButton(enabled=!busy && name.isNotBlank(),onClick={onRename(collection,name){editing=null}}) {Text("Salva")}},
        dismissButton={TextButton(enabled=!busy,onClick={editing=null}) {Text("Annulla")}}) }
    deleting?.let { collection -> AlertDialog(onDismissRequest={if(!busy)deleting=null},title={Text("Elimina raccolta vuota?")},
        text={Column {Text("Rimuovere “${collection.name}” da questo dispositivo? Le raccolte vuote non vengono sincronizzate.");error?.let {Text(it,color=MaterialTheme.colorScheme.error)}}},
        confirmButton={TextButton(enabled=!busy,onClick={onDelete(collection){deleting=null}}) {Text("Elimina")}},
        dismissButton={TextButton(enabled=!busy,onClick={deleting=null}) {Text("Annulla")}}) }
}

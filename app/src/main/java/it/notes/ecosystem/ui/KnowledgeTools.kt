package it.notes.ecosystem.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import it.notes.ecosystem.domain.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

@Composable
fun KnowledgeTools(field: TextFieldValue, enabled: Boolean, notes: List<Note>, onEdit: (MarkdownEdit) -> Unit) {
    var tool by rememberSaveable { mutableStateOf("") }
    var query by rememberSaveable { mutableStateOf("") }
    var replacement by rememberSaveable { mutableStateOf("") }
    var caseSensitive by rememberSaveable { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var undo by remember { mutableStateOf<Pair<String, String>?>(null) }
    var confirmation by remember { mutableStateOf<Pair<String, MarkdownEdit>?>(null) }
    val headings by produceState<Pair<String,List<NoteHeading>>?>(null,field.text,tool) {
        value = if(tool=="Indice") withContext(Dispatchers.Default) {field.text to Knowledge.headings(field.text)} else null
    }
    val resultKey = Triple(field.text, query, caseSensitive)
    val matches by produceState<Pair<Triple<String,String,Boolean>,List<IntRange>>?>(null,resultKey,tool) {
        value = if(tool=="Trova") withContext(Dispatchers.Default) {resultKey to LiteralSearch.ranges(field.text,query,!caseSensitive)} else null
    }
    val ranges = matches?.takeIf {it.first==resultKey}?.second.orEmpty()
    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState())) {
        listOf("Collega", "Indice", "Trova").forEach { name ->
            TextButton(enabled=enabled,onClick={tool=name;if(name=="Collega")query="";error=null}) {Text(name)}
        }
        undo?.takeIf {it.second==field.text}?.let { previous ->
            TextButton(enabled=enabled,onClick={onEdit(MarkdownEdit(previous.first,0,0));undo=null}) {Text("Annulla sostituzione")}
        }
    }
    if(tool.isNotEmpty()) AlertDialog(onDismissRequest={tool=""},title={Text(when(tool){"Collega"->"Collega una nota";"Indice"->"Indice dei titoli";else->"Trova e sostituisci"})},text={
        Column(verticalArrangement=Arrangement.spacedBy(8.dp)) {
            if(tool!="Indice") OutlinedTextField(query,{query=it},singleLine=true,label={Text(if(tool=="Collega")"Cerca titolo" else "Testo da cercare")})
            when(tool) {
                "Collega" -> LazyColumn(Modifier.heightIn(max=280.dp)) {
                    val found=notes.filter {it.task==null && it.sketch==null && it.deletedAt==null && it.title.contains(query,true)}
                    if(found.isEmpty()) item {Text("Nessuna nota salvata corrispondente.")}
                    items(found,key={it.id}) { note -> TextButton(enabled=enabled,onClick={
                        runCatching {Knowledge.insert(field.text,field.selection.start,field.selection.end,note.id,note.title)}
                            .onSuccess {onEdit(it);tool=""}.onFailure {error=it.message}
                    }) {Text(note.title.ifBlank {"Senza titolo"})} }
                }
                "Indice" -> LazyColumn(Modifier.heightIn(max=300.dp)) {
                    val current=headings?.takeIf {it.first==field.text}?.second.orEmpty()
                    if(current.isEmpty()) item {Text("Aggiungi titoli Markdown con #, ## o ###. I blocchi di codice sono esclusi.")}
                    items(current,key={it.offset}) { heading -> TextButton(enabled=enabled,onClick={onEdit(MarkdownEdit(field.text,heading.offset,heading.offset));tool=""}) {
                        Text("${"  ".repeat(heading.level-1)}${heading.title.ifBlank {"Titolo"}}")
                    } }
                }
                else -> {
                    Row { Checkbox(caseSensitive,{caseSensitive=it}); Text("Distingui maiuscole",Modifier.padding(top=12.dp)) }
                    Text(if(matches?.first!=resultKey) "Ricerca…" else "${ranges.size} occorrenze · ricerca letterale")
                    OutlinedTextField(replacement,{replacement=it},label={Text("Sostituisci con")})
                    TextButton(enabled=enabled && ranges.isNotEmpty(),onClick={
                        val next=ranges.firstOrNull {it.first>=field.selection.max}?:ranges.first()
                        onEdit(MarkdownEdit(field.text,next.first,next.last+1));tool=""
                    }) {Text("Seleziona successiva")}
                    TextButton(enabled=enabled && ranges.isNotEmpty(),onClick={
                        runCatching {LiteralSearch.replaceAll(field.text,query,replacement,!caseSensitive)}
                            .onSuccess {confirmation=field.text to it}.onFailure {error=it.message}
                    }) {Text("Sostituisci tutte (${ranges.size})")}
                    Text("La sostituzione include anche link e codice. Verifica il testo prima di salvare.",style=MaterialTheme.typography.bodySmall)
                }
            }
            error?.let {Text(it,color=MaterialTheme.colorScheme.error)}
        }
    },confirmButton={TextButton(onClick={tool=""}){Text("Chiudi")}})
    confirmation?.let { pending -> AlertDialog(onDismissRequest={confirmation=null},title={Text("Applicare la sostituzione?")},
        text={Text("Verranno sostituite tutte le occorrenze trovate. Puoi annullare dalla barra strumenti finché il testo non cambia.")},
        confirmButton={TextButton(enabled=enabled && field.text==pending.first,onClick={
            undo=pending.first to pending.second.text;onEdit(pending.second);confirmation=null;tool=""
        }){Text("Sostituisci")}},dismissButton={TextButton(onClick={confirmation=null}){Text("Annulla")}}) }
}

private data class ConnectionResult(val body:String,val notes:List<Note>,val outgoing:List<NoteLink>,val incoming:List<Note>)
@Composable
fun NoteConnections(id:String,body:String,notes:List<Note>,enabled:Boolean,onOpen:(String)->Unit) {
    var show by rememberSaveable {mutableStateOf(false)}
    val result by produceState<ConnectionResult?>(null,id,body,notes,show) {
        value=if(show) withContext(Dispatchers.Default) {
            ConnectionResult(body,notes,Knowledge.links(body).distinctBy {it.id},notes.filter {
                it.id!=id && it.deletedAt==null && it.task==null && it.sketch==null && Knowledge.links(it.body).any {ref->ref.id==id}
            })
        } else null
    }
    TextButton(enabled=enabled,onClick={show=true}) {Text("Collegamenti e backlink")}
    if(show) AlertDialog(onDismissRequest={show=false},title={Text("Le pagine collegate")},text={
        LazyColumn(Modifier.heightIn(max=350.dp)) {
            val current=result?.takeIf {it.body==body && it.notes==notes}
            if(current==null) item {Text("Ricerca collegamenti…")}
            else {
                item {Text("Da questa nota",style=MaterialTheme.typography.titleSmall)}
                if(current.outgoing.isEmpty()) item {Text("Nessun collegamento. Usa Collega nella barra dell’editor.")}
                items(current.outgoing,key={it.id}) {ref ->
                    val target=notes.firstOrNull {it.id==ref.id && it.task==null && it.sketch==null && it.deletedAt==null}
                    TextButton(enabled=enabled && target!=null,onClick={show=false;onOpen(ref.id)}) {
                        Text(target?.title?:"${ref.label} · non disponibile")
                    }
                }
                item {Text("Note che rimandano qui",style=MaterialTheme.typography.titleSmall)}
                if(current.incoming.isEmpty()) item {Text("Nessun backlink salvato.")}
                items(current.incoming,key={it.id}) {note -> TextButton(enabled=enabled,onClick={show=false;onOpen(note.id)}){Text(note.title)} }
            }
        }
    },confirmButton={TextButton(onClick={show=false}){Text("Chiudi")}})
}

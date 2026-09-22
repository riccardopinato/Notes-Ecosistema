package it.notes.ecosystem.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import it.notes.ecosystem.domain.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TemplateGallery(notes: List<Note>, onClose: ()->Unit, onUse: (String,Boolean)->Unit, onEdit: (String)->Unit) {
    var query by rememberSaveable { mutableStateOf("") }
    var selected by rememberSaveable { mutableStateOf<String?>(null) }
    var reset by rememberSaveable { mutableStateOf(true) }
    val personal by produceState<List<Note>>(emptyList(),notes,query) {
        value=withContext(Dispatchers.Default) {PersonalTemplates.catalog(notes,query)}
    }
    val builtin=remember(query) {PageTemplates.all.filter {it.name.contains(query.trim(),true)}}
    ModalBottomSheet(onDismissRequest=onClose) {
        LazyColumn(Modifier.fillMaxWidth().imePadding().heightIn(max=640.dp),contentPadding=PaddingValues(20.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
            item {
                Text("Una pagina da cui partire",style=MaterialTheme.typography.headlineSmall)
                Text("I modelli personali sono note con il tag modello. Aprili per rinominarli o modificarli; rimuovi il tag per toglierli dalla galleria.")
            }
            item {OutlinedTextField(query,{query=it},singleLine=true,label={Text("Cerca un modello")},modifier=Modifier.fillMaxWidth())}
            item {Row {Checkbox(reset,{reset=it});Text("Riparti con tutte le spunte da completare",modifier=Modifier.padding(top=12.dp))}}
            item {Text("Inserisci {{data}}, {{ora}} o {{giorno}} nel modello: saranno compilati nella nuova nota. La nuova nota nasce in Inbox, senza il tag modello.",style=MaterialTheme.typography.bodySmall)}
            if(builtin.isNotEmpty()) item {Text("Pronti all’uso",style=MaterialTheme.typography.titleMedium)}
            items(builtin,key={"built:${it.key}"}) {template ->
                TemplateCard(template.name,template.body,selected==template.key,{selected=if(selected==template.key)null else template.key},
                    onUse={onUse(template.key,reset)},onEdit=null)
            }
            item {Text("I tuoi modelli · ${personal.size}",style=MaterialTheme.typography.titleMedium)}
            if(personal.isEmpty()) item {Text("Apri una nota e tocca Crea modello. Viene salvata una copia in Archivio, senza modificare l’originale né aggiungere attività da fare.")}
            items(personal,key={"personal:${it.id}"}) {note ->
                val key="personal:${note.id}"
                TemplateCard(note.title.ifBlank {"Senza titolo"},note.body,selected==key,{selected=if(selected==key)null else key},
                    onUse={onUse(key,reset)},onEdit={onEdit(note.id)})
            }
            item {Text("Si usa la versione salvata del modello. Allegati e collegamenti restano condivisi; le bozze non salvate non vengono copiate. I modelli archiviati sono disponibili, quelli nel cestino no.",style=MaterialTheme.typography.bodySmall)}
            item {TextButton(onClick=onClose){Text("Chiudi")}}
        }
    }
}

@Composable
private fun TemplateCard(title:String,body:String,expanded:Boolean,onPreview:()->Unit,onUse:()->Unit,onEdit:(()->Unit)?) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
            Text(title,style=MaterialTheme.typography.titleLarge)
            if(expanded) Text(body.take(2000).let {if(body.length>2000) "$it\n…" else it},style=MaterialTheme.typography.bodyMedium)
            TextButton(onClick=onPreview) {Text(if(expanded)"Nascondi anteprima" else "Anteprima")}
            Button(onClick=onUse,modifier=Modifier.fillMaxWidth()){Text("Usa modello")}
            if(onEdit!=null) TextButton(onClick=onEdit){Text("Modifica modello")}
        }
    }
}

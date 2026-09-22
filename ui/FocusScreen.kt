package it.notes.ecosystem.ui
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import it.notes.ecosystem.domain.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun FocusScreen(clock:FocusClock,title:String,now:Long,busy:Boolean,error:String?,onBack:()->Unit,
    onNext:()->Unit,onPause:()->Unit,onStop:()->Unit,onDiscard:()->Unit) {
    BackHandler {if(!busy)onBack()}
    Scaffold(topBar={TopAppBar(title={EditorialAppTitle(if(clock.phase==FocusPhase.WORK)"Il tuo momento" else "Prenditi una pausa")},
        navigationIcon={TextButton(enabled=!busy,onClick=onBack){Text("Attività")}})},
        containerColor=MaterialTheme.colorScheme.primary,contentColor=MaterialTheme.colorScheme.onPrimary) {padding->
        Column(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(28.dp),
            horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.spacedBy(20.dp)) {
            Text(if(clock.phase==FocusPhase.WORK) "FOCUS · BLOCCO ${clock.completedBlocks+1}" else "PAUSA · ${clock.completedBlocks} BLOCCHI REGISTRATI",style=MaterialTheme.typography.labelLarge)
            Text(title,style=MaterialTheme.typography.headlineMedium)
            val remaining=clock.remaining(now)
            CircularProgressIndicator(progress={1f-remaining.toFloat()/clock.durationSeconds},modifier=Modifier.size(160.dp),
                color=MaterialTheme.colorScheme.onPrimary,trackColor=MaterialTheme.colorScheme.onPrimary.copy(alpha=0.2f),strokeWidth=8.dp)
            Text("${remaining/60}:${(remaining%60).toString().padStart(2,'0')}",style=MaterialTheme.typography.displayMedium)
            Text(when {clock.pausedMillis!=null->"Timer in pausa. Il tempo non aumenta.";clock.finished(now)->"Intervallo concluso. Scegli come continuare.";else->"Il conteggio continua anche uscendo. Nessun suono automatico a fine intervallo."})
            error?.let {Text(it)}
            if(!clock.finished(now)) FilledTonalButton(enabled=!busy,onClick=onPause){Text(if(clock.pausedMillis==null)"Metti in pausa" else "Riprendi")}
            if(clock.finished(now)) FilledTonalButton(enabled=!busy,onClick=onNext){Text(if(clock.phase==FocusPhase.WORK)"Registra e inizia pausa" else "Inizia prossimo Focus")}
            if(clock.phase==FocusPhase.WORK) FilledTonalButton(enabled=!busy && clock.durationSeconds-remaining>0,onClick=onStop){Text("Termina e registra")}
            OutlinedButton(enabled=!busy,onClick=onBack,colors=ButtonDefaults.outlinedButtonColors(contentColor=MaterialTheme.colorScheme.onPrimary)){Text("Torna alle attività")}
            TextButton(enabled=!busy,onClick=onDiscard,colors=ButtonDefaults.textButtonColors(contentColor=MaterialTheme.colorScheme.onPrimary)){Text(if(clock.phase==FocusPhase.WORK)"Scarta intervallo" else "Termina pausa")}
        }
    }
}

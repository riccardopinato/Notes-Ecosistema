package it.notes.ecosystem.ui
import android.Manifest
import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import it.notes.ecosystem.NotesApplication

@Composable
fun ReminderPermission() {
    val context=LocalContext.current
    val manager=(context.applicationContext as NotesApplication).reminders
    val schedulingError by manager.error.collectAsState()
    schedulingError?.let { Text(it,color=MaterialTheme.colorScheme.error) }
    var allowed by remember {mutableStateOf(manager.allowed())}
    val lifecycle=LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle) {
        val observer=LifecycleEventObserver {_,event->if(event==Lifecycle.Event.ON_RESUME){allowed=manager.allowed();manager.refresh()}}
        lifecycle.addObserver(observer);onDispose {lifecycle.removeObserver(observer)}
    }
    val request=rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {allowed=manager.allowed();manager.refresh()}
    if(!allowed) {
        Text("Le notifiche sono disattivate: i promemoria restano salvati, ma non vengono mostrati.",style=MaterialTheme.typography.bodySmall)
        TextButton(onClick={if(Build.VERSION.SDK_INT>=33)request.launch(Manifest.permission.POST_NOTIFICATIONS)
            else context.startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE,context.packageName))}) {Text("Abilita notifiche")}
        TextButton(onClick={context.startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE,context.packageName))}) {Text("Impostazioni notifiche")}
    }
}

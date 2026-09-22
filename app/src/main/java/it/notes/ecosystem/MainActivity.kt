package it.notes.ecosystem

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.material3.*
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import it.notes.ecosystem.ui.*

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        it.notes.ecosystem.capture.CaptureShortcuts.install(this)
        val app = application as NotesApplication
        setContent {
            val model: NotesViewModel = viewModel(factory = viewModelFactory {
                initializer { NotesViewModel(app.repository, app.preferences, app.attachments, java.io.File(app.cacheDir,"media_imports")) }
            })
            val dark by model.darkMode.collectAsStateWithLifecycle()
            NotesTheme(dark) {
                NotesApp(model, app.repository, intent.getStringExtra(it.notes.ecosystem.reminders.TaskReminders.TASK_EXTRA)?.takeIf {it.length in 1..200})
            }
        }
    }
}

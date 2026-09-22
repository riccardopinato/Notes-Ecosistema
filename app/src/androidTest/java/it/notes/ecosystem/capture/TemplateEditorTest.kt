package it.notes.ecosystem.capture

import android.content.Context
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.ViewModelStore
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import it.notes.ecosystem.data.LocalNotesRepository
import it.notes.ecosystem.data.NotesDatabase
import it.notes.ecosystem.domain.CaptureSeed
import it.notes.ecosystem.ui.EditorViewModel
import kotlinx.coroutines.runBlocking
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class TemplateEditorTest {
    private lateinit var db: NotesDatabase
    private lateinit var repo: LocalNotesRepository
    private var store = ViewModelStore()
    private val instrument get() = InstrumentationRegistry.getInstrumentation()
    @Before fun setup() {
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(), NotesDatabase::class.java).build()
        repo = LocalNotesRepository(db)
    }
    @After fun cleanup() { instrument.runOnMainSync { store.clear() }; db.close() }
    private fun open(key: String="meeting"): EditorViewModel {
        lateinit var model: EditorViewModel
        instrument.runOnMainSync {
            model = ViewModelProvider(store, object : ViewModelProvider.Factory {
                @Suppress("UNCHECKED_CAST")
                override fun <T : ViewModel> create(modelClass: Class<T>): T =
                    EditorViewModel(repo, SavedStateHandle(mapOf("id" to "capture-test", "new" to true, "template" to key))) as T
            })[EditorViewModel::class.java]
        }
        waitUntil { !model.loading }
        instrument.runOnMainSync { assertTrue(model.available) }
        return model
    }
    private fun waitUntil(condition: () -> Boolean) {
        repeat(200) {
            var ready = false
            instrument.runOnMainSync { ready = condition() }
            if (ready) return
            Thread.sleep(25)
        }
        fail("Editor operation timed out")
    }
    @Test fun templateStartsAsDraftAndSavesNormally() = runBlocking {
        val model=open()
        assertTrue(repo.snapshot().notes.isEmpty())
        val expected=it.notes.ecosystem.domain.PageTemplates.all.first().body
        assertEquals(expected,repo.getDraft("capture-test")?.body)
        var saved=false
        instrument.runOnMainSync {model.save {saved=true}}
        waitUntil {saved}
        assertEquals(expected,repo.get("capture-test")?.body)
    }
    @Test fun restoredDraftWinsOverAnotherTemplate() = runBlocking {
        val model=open()
        instrument.runOnMainSync {model.editBody("Il mio testo")}
        assertEquals("Il mio testo",repo.getDraft("capture-test")?.body)
        instrument.runOnMainSync {store.clear();store=ViewModelStore()}
        val restored=open("study")
        instrument.runOnMainSync {assertEquals("Il mio testo",restored.body)}
    }
    @Test fun existingNoteWinsOverTemplateSeed() = runBlocking {
        repo.save("capture-test","Esistente","Da conservare",null)
        val model=open()
        instrument.runOnMainSync {assertEquals("Da conservare",model.body);assertFalse(model.dirty)}
    }
}

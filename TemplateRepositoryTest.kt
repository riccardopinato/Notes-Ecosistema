package it.notes.ecosystem.data

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import it.notes.ecosystem.domain.*
import kotlinx.coroutines.test.runTest
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class TemplateRepositoryTest {
    private lateinit var db:NotesDatabase
    private lateinit var repo:LocalNotesRepository
    @Before fun setup(){db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),NotesDatabase::class.java).build();repo=LocalNotesRepository(db)}
    @After fun close(){db.close()}
    @Test fun createsArchivedCopyWithoutPollutingActiveTasks()=runTest {
        val id=repo.createTemplate(TemplateContent("T","- [ ] Fare",emptyList()));val note=repo.get(id)!!
        assertTrue(note.archived);assertTrue(PersonalTemplates.eligible(note));assertTrue(collectTasks(listOf(note)).isEmpty());assertNull(note.collectionId)
    }
    @Test fun originalAndDraftUntouched()=runTest {
        repo.save("original","T","Salvato",null);repo.queueDraft(Draft("original","T","Bozza",null,1)).await()
        repo.createTemplate(TemplateContent("T","Bozza",emptyList()))
        assertEquals("Salvato",repo.get("original")!!.body);assertEquals("Bozza",repo.getDraft("original")!!.body)
    }
    @Test fun repeatedCreatesUseDifferentIds()=runTest {
        val content=TemplateContent("T","B",emptyList());assertNotEquals(repo.createTemplate(content),repo.createTemplate(content))
    }
    @Test fun exportedImportedTemplateKeepsIdentityAsModel()=runTest {
        repo.createTemplate(TemplateContent("T","{{data}}",emptyList()));repo.importCopies(repo.snapshot())
        val notes=repo.snapshot().notes;assertEquals(2,notes.size);assertTrue(notes.all {it.archived && PersonalTemplates.eligible(it)})
    }
}

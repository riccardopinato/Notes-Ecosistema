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
class KnowledgeRepositoryTest {
    private lateinit var db:NotesDatabase
    private lateinit var repo:LocalNotesRepository
    private val a="11111111-1111-4111-8111-111111111111"
    private val b="22222222-2222-4222-8222-222222222222"
    @Before fun setup(){db=Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext<Context>(),NotesDatabase::class.java).build();repo=LocalNotesRepository(db)}
    @After fun cleanup(){db.close()}
    @Test fun importedLinksAndDraftsPointToCopies()=runTest {
        repo.save(a,"Origine",Knowledge.insert("",0,0,b,"Destinazione").text,null)
        repo.save(b,"Destinazione","Testo",null)
        repo.queueDraft(Draft(a,"Bozza",Knowledge.insert("",0,0,b,"Destinazione").text,null,3)).await()
        repo.importCopies(repo.snapshot())
        val result=repo.snapshot()
        val target=result.notes.single {it.id!=b && it.title=="Destinazione"}
        val source=result.notes.single {it.id!=a && it.title=="Origine"}
        assertEquals(target.id,Knowledge.links(source.body).single().id)
        assertEquals(target.id,Knowledge.links(result.drafts.single {it.id==source.id}.body).single().id)
        assertEquals(b,Knowledge.links(repo.get(a)!!.body).single().id)
    }
}

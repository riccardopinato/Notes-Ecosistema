package it.notes.ecosystem.data

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import it.notes.ecosystem.domain.*
import it.notes.ecosystem.media.*
import kotlinx.coroutines.test.runTest
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import java.io.File
import java.io.ByteArrayOutputStream
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class MediaRepositoryTest {
    private lateinit var db:NotesDatabase
    private lateinit var repo:LocalNotesRepository
    private lateinit var files:AttachmentFiles
    private lateinit var root:File
    private val content="documento prova".toByteArray()
    private val key=Attachments.key(content,AttachmentType.TEXT)
    private val body=Attachments.append("Nota",key,"Documento")
    @Before fun setup(){val context=ApplicationProvider.getApplicationContext<Context>();db=Room.inMemoryDatabaseBuilder(context,NotesDatabase::class.java).build();repo=LocalNotesRepository(db);root=File(context.cacheDir,"media-test-${UUID.randomUUID()}").apply{mkdirs()};files=AttachmentFiles(root);files.put(key,content);files.file(key).setLastModified(1)}
    @After fun close(){db.close();root.listFiles().orEmpty().forEach {it.delete()};root.delete()}
    @Test fun noteReferencesProtectOldFileFromCleanup()=runTest {repo.save("n","Nota",body,null);assertEquals(0,repo.cleanupAttachments {files.cleanup(it)});assertTrue(files.contains(key))}
    @Test fun draftReferencesProtectOldFileFromCleanup()=runTest {repo.queueDraft(Draft("n","Bozza",body,null,1)).await();assertEquals(0,repo.cleanupAttachments {files.cleanup(it)})}
    @Test fun revisionReferencesProtectRemovedAttachment()=runTest {repo.save("n","Nota",body,null);repo.save("n","Nota","Solo testo",null);assertEquals(0,repo.cleanupAttachments {files.cleanup(it)});assertTrue(repo.history("n").first().body.contains(key))}
    @Test fun unreferencedOldFileCanBeRemoved()=runTest {assertEquals(1,repo.cleanupAttachments {files.cleanup(it)});assertFalse(files.contains(key))}
    @Test fun importCopiesKeepsContentAddressedReferences()=runTest {repo.save("n","Nota",body,null);repo.importCopies(repo.snapshot());assertEquals(2,repo.snapshot().notes.size);assertEquals(setOf(key),Attachments.keys(repo.snapshot()));assertEquals(1,files.usage().first)}
    @Test fun completeBackupImportsAllBinaryFilesBeforeCopies()=runTest {
        repo.save("n","Nota",body,null);val output=ByteArrayOutputStream();MediaBundle.write(repo.snapshot(),files,output)
        val staging=File(root,"staging").apply{mkdirs()}
        MediaBundle.read(output.toByteArray().inputStream(),staging).use {preview->preview.install(files);repo.importCopies(preview.snapshot)}
        staging.delete();assertEquals(2,repo.snapshot().notes.size);assertArrayEquals(content,files.read(key))
    }
    @Test fun staleRemoteBodyCannotEraseNewAttachment()=runTest {
        repo.save("n","Nota","Prima",null);val old=repo.syncDocument("n")!!;repo.save("n","Nota",body,null)
        assertFalse(repo.applySync("n",old,old.copy(body="Remoto")));assertEquals(body,repo.get("n")!!.body)
    }
    @Test fun cleanupScansEveryPageOfRevisionHistory()=runTest {
        val expected=mutableSetOf<String>()
        repeat(35) {i->val k=Attachments.key("file $i".toByteArray(),AttachmentType.TEXT);expected+=k;repo.save("note-$i","Nota",Attachments.append("",k,"File"),null);repo.save("note-$i","Nota","Senza file",null)}
        var observed=emptySet<String>();repo.cleanupAttachments {observed=it;0};assertEquals(expected,observed)
    }
}

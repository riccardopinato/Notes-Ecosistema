package it.notes.ecosystem.sync

import it.notes.ecosystem.domain.*
import it.notes.ecosystem.media.*
import org.junit.Test
import org.junit.Rule
import org.junit.Assert.*
import org.junit.rules.TemporaryFolder
import java.io.IOException

class AttachmentSyncTest {
    @get:Rule val temp=TemporaryFolder()
    private val bytes="audio".toByteArray()
    private val key=Attachments.key(bytes,AttachmentType.M4A)
    private fun doc()=SyncDocument.from(Note("n","N",Attachments.append("",key,"Voce"),createdAt=1,updatedAt=1),null)
    private class Remote(var document:SyncDocument):GitHubTransport,AttachmentRemote {
        val files=mutableMapOf<String,ByteArray>();var noteWrites=0;var uploads=0;var downloads=0;var failUpload=false
        override fun head()="head"
        override fun list(head:String)=listOf(RemoteFile("n","sha"))
        override fun read(file:RemoteFile,head:String)=document
        override fun write(document:SyncDocument,expectedSha:String?):String {this.document=document;noteWrites++;return "written"}
        override fun downloadAttachment(key:String,head:String):ByteArray {downloads++;return files[key] ?: throw IOException("missing")}
        override fun uploadAttachment(key:String,bytes:ByteArray) {if(failUpload)throw IOException("offline");uploads++;files[key]=bytes}
    }
    @Test fun attachmentUploadedBeforeNoteIsPublished(){val remote=Remote(doc());val store=AttachmentFiles(temp.newFolder());store.put(key,bytes);AttachmentSync(remote,remote,store).write(doc(),null);assertArrayEquals(bytes,remote.files[key]);assertEquals(1,remote.noteWrites)}
    @Test fun failedAttachmentPreventsPublishingNote(){val remote=Remote(doc()).apply{failUpload=true};val store=AttachmentFiles(temp.newFolder());store.put(key,bytes);try{AttachmentSync(remote,remote,store).write(doc(),null);fail()}catch(_:IOException){};assertEquals(0,remote.noteWrites)}
    @Test fun downloadInstallsVerifiedContent(){val remote=Remote(doc()).apply{files[key]=bytes};val store=AttachmentFiles(temp.newFolder());AttachmentSync(remote,remote,store).read(RemoteFile("n","sha"),"head");assertArrayEquals(bytes,store.read(key))}
    @Test fun sharedFileTransferredOncePerRun(){val remote=Remote(doc());val store=AttachmentFiles(temp.newFolder());store.put(key,bytes);val transport=AttachmentSync(remote,remote,store);transport.write(doc(),null);transport.write(doc().copy(id="copy"),null);assertEquals(1,remote.uploads);assertEquals(2,remote.noteWrites)}
    @Test fun corruptedRemoteFileIsRejected(){val remote=Remote(doc()).apply{files[key]="bad".toByteArray()};val store=AttachmentFiles(temp.newFolder());try{AttachmentSync(remote,remote,store).read(RemoteFile("n","sha"),"head");fail()}catch(_:IllegalArgumentException){};assertFalse(store.contains(key))}
    @Test fun cachedNoteCanFetchItsMissingFile(){val remote=Remote(doc()).apply{files[key]=bytes};val store=AttachmentFiles(temp.newFolder());AttachmentSync(remote,remote,store).download(doc(),"head");assertTrue(store.contains(key))}
    @Test fun missingLocalFileCanBeRecoveredBeforeUpload(){val remote=Remote(doc()).apply{files[key]=bytes};val store=AttachmentFiles(temp.newFolder());AttachmentSync(remote,remote,store).write(doc(),null);assertArrayEquals(bytes,store.read(key));assertEquals(1,remote.noteWrites)}
    @Test fun verifiedLocalFileAvoidsRedownload(){val remote=Remote(doc());val store=AttachmentFiles(temp.newFolder());store.put(key,bytes);AttachmentSync(remote,remote,store).download(doc(),"head");assertEquals(0,remote.downloads)}
    @Test fun unchangedNoteRepairsMissingRemoteBinaryWithoutNoteRewrite(){val remote=Remote(doc());val store=AttachmentFiles(temp.newFolder());store.put(key,bytes);AttachmentSync(remote,remote,store).ensurePublished(doc());assertArrayEquals(bytes,remote.files[key]);assertEquals(0,remote.noteWrites)}
    @Test fun completedFileIsReusedAfterANewSyncPass(){val remote=Remote(doc());val store=AttachmentFiles(temp.newFolder());store.put(key,bytes);AttachmentSync(remote,remote,store).write(doc(),null);val next=AttachmentSync(remote,remote,store);next.download(doc(),"head");assertEquals(0,remote.downloads);assertArrayEquals(bytes,store.read(key))}
}

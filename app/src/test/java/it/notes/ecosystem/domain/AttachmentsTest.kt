package it.notes.ecosystem.domain

import it.notes.ecosystem.media.*
import it.notes.ecosystem.data.*
import org.junit.Test
import org.junit.Rule
import org.junit.Assert.*
import org.junit.rules.TemporaryFolder
import java.io.*
import java.util.zip.*

class AttachmentsTest {
    @get:Rule val temp=TemporaryFolder()
    private val bytes="documento".toByteArray()
    private val key=Attachments.key(bytes,AttachmentType.TEXT)
    private fun store()=AttachmentFiles(temp.newFolder())
    private fun snapshot(body:String=Attachments.append("Appunto",key,"documento.txt"))=BackupSnapshot(listOf(Note("n","Nota",body,createdAt=1,updatedAt=1)),emptyList(),emptyList())
    private fun zip(vararg entries:Pair<String,ByteArray>):ByteArray {val output=ByteArrayOutputStream();ZipOutputStream(output).use {z->entries.forEach {(name,data)->z.putNextEntry(ZipEntry(name));z.write(data);z.closeEntry()}};return output.toByteArray()}
    @Test fun digestIsContentAddressedAndStable(){assertEquals(key,Attachments.key(bytes.copyOf(),AttachmentType.TEXT));assertNotEquals(key,Attachments.key("altro".toByteArray(),AttachmentType.TEXT))}
    @Test fun gitBlobShaMatchesKnownGitObject(){assertEquals("ce013625030ba8dba906f756967f9e9ca394464a","hello\n".toByteArray().let(Attachments::gitSha))}
    @Test fun keyRejectsTraversalAndUnsupportedExtensions(){assertFalse(Attachments.validKey("../$key"));assertFalse(Attachments.validKey("a".repeat(64)+".exe"));assertNull(Attachments.target("https://$key"))}
    @Test(expected=IllegalArgumentException::class)fun emptyFileRejected(){Attachments.key(byteArrayOf(),AttachmentType.TEXT)}
    @Test(expected=IllegalArgumentException::class)fun overLimitFileRejected(){Attachments.key(ByteArray(Attachments.FILE_LIMIT+1),AttachmentType.TEXT)}
    @Test(expected=IllegalArgumentException::class)fun contentMismatchRejected(){Attachments.verify(key,"modified".toByteArray())}
    @Test fun labelsWithBracketsUnicodeAndBackslashesRoundTrip(){val text=Attachments.append("",key,"Caffè [Anna] \\ foto");assertEquals("Caffè [Anna] \\ foto",Attachments.refs(text).single().name)}
    @Test fun codeAndEscapedLinksAreIgnored(){val link="[d](notes-asset://$key)";assertTrue(Attachments.refs("`$link`\n```\n$link\n```\n    $link\n\\$link").isEmpty())}
    @Test fun imageMarkdownIsNotMisidentifiedAsAttachmentLink(){assertTrue(Attachments.refs("![x](notes-asset://$key)").isEmpty())}
    @Test(expected=IllegalArgumentException::class)fun openFenceBlocksAppend(){Attachments.append("```kotlin\ncode",key,"File")}
    @Test fun removeKeepsCodeAndOtherText(){val link="[d](notes-asset://$key)";val text="$link\n$link\n`$link`";assertEquals("\n\n`$link`",Attachments.remove(text,key))}
    @Test fun portableMarkdownUsesRelativeFiles(){assertTrue(Attachments.portable(Attachments.append("",key,"d")).contains("../assets/$key"))}
    @Test fun normalLinksAndPlainTextArePreserved(){val text="[Web](https://example.com) notes-asset://$key";assertEquals(text,Attachments.portable(text));assertTrue(Attachments.refs(text).isEmpty())}
    @Test fun copyingNoteKeepsAttachmentIdentity(){val data=snapshot();assertEquals(setOf(key),Attachments.keys(data.copy(notes=data.notes+data.notes.first().copy(id="copy"))))}
    @Test fun draftsAndTrashAreIncludedInBackupReferences(){val n=snapshot().notes.first().copy(deletedAt=5);assertEquals(setOf(key),Attachments.keys(BackupSnapshot(listOf(n),emptyList(),listOf(Draft("d","",n.body,null,1)))))}
    @Test fun reimportSameBytesCreatesOneFile(){val files=store();files.put(key,bytes);files.put(key,bytes);assertEquals(1,files.usage().first);assertArrayEquals(bytes,files.read(key))}
    @Test(expected=IllegalArgumentException::class)fun corruptedStoredFileIsNotRead(){val files=store();files.put(key,bytes);files.file(key).writeText("changed");files.read(key)}
    @Test fun verifiedDownloadRepairsCorruptLocalFile(){val files=store();files.put(key,bytes);files.file(key).writeText("changed");files.put(key,bytes);assertArrayEquals(bytes,files.read(key))}
    @Test fun cleanupKeepsReferencedFilesAndRecentImports(){val files=store();files.put(key,bytes);assertEquals(0,files.cleanup(emptySet()));files.file(key).setLastModified(1);assertEquals(0,files.cleanup(setOf(key)));assertEquals(1,files.cleanup(emptySet()))}
    @Test fun bundleRoundTripIncludesActualBytes(){val files=store();files.put(key,bytes);val out=ByteArrayOutputStream();MediaBundle.write(snapshot(),files,out);MediaBundle.read(out.toByteArray().inputStream(),temp.newFolder()).use {preview->assertEquals(snapshot(),preview.snapshot);val target=store();preview.install(target);assertArrayEquals(bytes,target.read(key))}}
    @Test fun completeBundleIncludesReferencedTrashAndDraftFiles(){val files=store();files.put(key,bytes);val original=snapshot().notes.single();val data=BackupSnapshot(listOf(original.copy(deletedAt=10)),emptyList(),listOf(Draft("draft","D",original.body,null,3)));val out=ByteArrayOutputStream();MediaBundle.write(data,files,out);MediaBundle.read(out.toByteArray().inputStream(),temp.newFolder()).use{assertEquals(data,it.snapshot);assertEquals(setOf(key),it.keys)}}
    @Test(expected=IllegalStateException::class)fun exportCannotClaimCompleteWhenAssetMissing(){MediaBundle.write(snapshot(),store(),ByteArrayOutputStream())}
    @Test(expected=IllegalArgumentException::class)fun archiveTraversalRejected(){MediaBundle.read(zip("../escape" to bytes).inputStream(),temp.newFolder())}
    @Test(expected=IllegalArgumentException::class)fun archiveAssetChecksumMismatchRejected(){MediaBundle.read(zip("assets/$key" to "other".toByteArray()).inputStream(),temp.newFolder())}
    @Test(expected=IllegalArgumentException::class)fun missingBinaryInBundleRejected(){val manifest="{\"format\":\"notes-ecosystem-media\",\"version\":1,\"assets\":[\"$key\"]}";MediaBundle.read(zip("bundle.json" to manifest.toByteArray(),"backup.json" to BackupWriter.json(snapshot()).toByteArray()).inputStream(),temp.newFolder())}
    @Test fun plainBackupPreservesLinksButNotBinary(){val data=snapshot();assertEquals(data,BackupReader.parse(BackupWriter.json(data)))}
    @Test(expected=IllegalArgumentException::class)fun twentyUniqueAttachmentsLimitEnforced(){var body="";repeat(21){body=Attachments.append(body,Attachments.key(byteArrayOf(it.toByte()),AttachmentType.TEXT),"$it")}}
    @Test fun repeatedReferenceDoesNotConsumeDistinctFileLimit(){var body="";repeat(25){body=Attachments.append(body,key,"File")};assertEquals(1,Attachments.refs(body).map{it.key}.distinct().size)}
    @Test(expected=IllegalArgumentException::class)fun inflatedAssetBeyondPerFileLimitIsRejected(){MediaBundle.read(zip("assets/$key" to ByteArray(Attachments.FILE_LIMIT+1)).inputStream(),temp.newFolder())}
    @Test fun failedArchiveLeavesNoStagedFiles(){val dir=temp.newFolder();try{MediaBundle.read(zip("bad/path" to bytes).inputStream(),dir);fail()}catch(_:IllegalArgumentException){};assertTrue(dir.listFiles().orEmpty().isEmpty())}
    @Test fun cancelledPreviewDoesNotInstallIntoAssetStore(){val original=store();original.put(key,bytes);val out=ByteArrayOutputStream();MediaBundle.write(snapshot(),original,out);val stageRoot=temp.newFolder();val target=store();val preview=MediaBundle.read(out.toByteArray().inputStream(),stageRoot);preview.close();assertFalse(target.contains(key));assertTrue(stageRoot.listFiles().orEmpty().isEmpty())}
    @Test fun temporaryCleanupOnlyDeletesOwnOldFiles(){val cache=temp.newFolder();val capture=File(cache,"media_capture").apply{mkdirs()};val old=File(capture,"voice-123.m4a").apply{writeBytes(bytes);setLastModified(1)};val recent=File(capture,"photo-123.jpg").apply{writeBytes(bytes)};val other=File(capture,"other.txt").apply{writeBytes(bytes);setLastModified(1)};cleanupMediaTemporaryFiles(cache);assertFalse(old.exists());assertTrue(recent.exists());assertTrue(other.exists())}
}

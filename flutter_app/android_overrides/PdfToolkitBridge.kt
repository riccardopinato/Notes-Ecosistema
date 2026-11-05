package it.notes.ecosystem.notes_ecosistema

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDPage
import com.tom_roush.pdfbox.multipdf.PDFMergerUtility
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/**
 * Offline PDFBox operations on new document objects only. No original CAS
 * path is opened for writing; no raw bytes, paths or document text are logged.
 */
class PdfToolkitBridge(context: Context) {
    companion object {
        private const val MAX_INPUT = 16 * 1024 * 1024
        private const val MAX_OUTPUT = 32 * 1024 * 1024
        private const val MAX_PAGES = 200
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    init {
        PDFBoxResourceLoader.init(context.applicationContext)
    }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "notes.ecosystem/pdf_toolbox")
            .setMethodCallHandler { call, reply ->
                if (call.method != "transform") {
                    reply.notImplemented()
                    return@setMethodCallHandler
                }
                Thread {
                    try {
                        val source = call.argument<ByteArray>("source")
                            ?: throw IllegalArgumentException("SOURCE_REQUIRED")
                        val action = call.argument<String>("action")
                            ?: throw IllegalArgumentException("ACTION_REQUIRED")
                        val result = transform(
                            source,
                            call.argument<ByteArray>("secondary"),
                            action,
                            call.argument<Int>("first"),
                            call.argument<Int>("last"),
                            call.argument<Int>("degrees"),
                            call.argument<List<Int>>("order")
                        )
                        mainHandler.post { reply.success(result) }
                    } catch (_: Exception) {
                        // Fail closed. Never surface original document contents.
                        mainHandler.post {
                            reply.error(
                                "PDF_TOOLBOX_UNSUPPORTED",
                                "PDF non valido, protetto o non elaborabile.",
                                null
                            )
                        }
                    }
                }.start()
            }
    }

    private fun validHeader(bytes: ByteArray) =
        bytes.size >= 5 &&
        bytes[0] == 37.toByte() && bytes[1] == 80.toByte() &&
        bytes[2] == 68.toByte() && bytes[3] == 70.toByte() &&
        bytes[4] == 45.toByte()

    private fun importWithResources(source: PDPage, target: PDDocument) {
        val imported = target.importPage(source)
        if (source.resources != null) {
            imported.resources = source.resources
        }
    }

    private fun outputBytes(document: PDDocument): ByteArray {
        val output = ByteArrayOutputStream()
        document.save(output)
        val bytes = output.toByteArray()
        if (bytes.size > MAX_OUTPUT || !validHeader(bytes)) {
            throw IllegalArgumentException("INVALID_OUTPUT")
        }
        return bytes
    }

    private fun transform(
        source: ByteArray,
        secondary: ByteArray?,
        operation: String,
        first: Int?,
        last: Int?,
        degrees: Int?,
        order: List<Int>?
    ): ByteArray {
        if (source.size > MAX_INPUT || !validHeader(source)) {
            throw IllegalArgumentException("INVALID_PDF")
        }
        PDDocument.load(source).use { initial ->
            if (initial.isEncrypted || initial.numberOfPages !in 1..MAX_PAGES) {
                throw IllegalArgumentException("UNSUPPORTED_PDF")
            }
            val outputDoc = when (operation) {
                "extractRange" -> {
                    if (first == null || last == null || first < 1 ||
                        last < first || last > initial.numberOfPages) {
                        throw IllegalArgumentException("INVALID_RANGE")
                    }
                    PDDocument().also { output ->
                        for (number in first..last) {
                            importWithResources(initial.getPage(number - 1), output)
                        }
                    }
                }
                "merge" -> {
                    if (secondary == null || secondary.size > MAX_INPUT ||
                        !validHeader(secondary)) {
                        throw IllegalArgumentException("INVALID_SECONDARY")
                    }
                    PDDocument.load(secondary).use { second ->
                        if (second.isEncrypted ||
                            second.numberOfPages !in 1..MAX_PAGES ||
                            initial.numberOfPages + second.numberOfPages > MAX_PAGES) {
                            throw IllegalArgumentException("PAGE_LIMIT")
                        }
                        PDDocument().use { output ->
                            val merger = PDFMergerUtility()
                            // Clones cross-document resources while both sources are open.
                            merger.appendDocument(output, initial)
                            merger.appendDocument(output, second)
                            return outputBytes(output)
                        }
                    }
                }
                "rotate" -> {
                    if (degrees != 90 && degrees != 180 && degrees != 270) {
                        throw IllegalArgumentException("INVALID_ROTATION")
                    }
                    for (page in initial.pages) {
                        page.rotation = (page.rotation + degrees) % 360
                    }
                    initial
                }
                "reorder" -> {
                    if (order == null || order.size != initial.numberOfPages ||
                        order.toSet() != (1..initial.numberOfPages).toSet()) {
                        throw IllegalArgumentException("INVALID_ORDER")
                    }
                    PDDocument().also { output ->
                        for (number in order) {
                            importWithResources(initial.getPage(number - 1), output)
                        }
                    }
                }
                else -> throw IllegalArgumentException("INVALID_ACTION")
            }
            return if (outputDoc === initial) {
                outputBytes(initial)
            } else {
                outputDoc.use { outputBytes(it) }
            }
        }
    }
}

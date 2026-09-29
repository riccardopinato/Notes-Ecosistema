package it.notes.ecosystem.notes_ecosistema

import android.app.ActivityManager
import android.content.Context
import android.os.Handler
import android.os.Looper
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.Conversation
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.LogSeverity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class LocalLlmBridge(private val activity: MainActivity) {
    companion object {
        private const val RUNTIME = "LiteRT-LM 0.17.1"
    }

    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile private var engine: Engine? = null
    @Volatile private var conversation: Conversation? = null
    @Volatile private var modelPath: String? = null

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        when (call.method) {
            "status" -> {
                result.success(status(args?.get("modelPath")?.toString()))
            }
            "load" -> runAsync(result) {
                val path = args?.get("modelPath")?.toString()
                load(path)
                status(path)
            }
            "generate" -> runAsync(result) {
                generate(args)
            }
            "cancel" -> {
                runCatching { conversation?.cancelProcess() }
                result.success(null)
            }
            "unload" -> runAsync(result) {
                unload()
                null
            }
            else -> result.notImplemented()
        }
    }

    fun destroy() {
        runCatching { conversation?.cancelProcess() }
        executor.execute { runCatching { unload() } }
        executor.shutdown()
    }

    private fun runAsync(
        result: MethodChannel.Result,
        block: () -> Any?,
    ) {
        executor.execute {
            runCatching(block)
                .onSuccess { value ->
                    mainHandler.post { result.success(value) }
                }
                .onFailure { error ->
                    mainHandler.post {
                        result.error(
                            "LOCAL_LLM",
                            error.message ?: "Inferenza locale non riuscita.",
                            null,
                        )
                    }
                }
        }
    }

    private fun validateModel(path: String?): File {
        val raw = path?.trim().orEmpty()
        require(raw.isNotEmpty()) { "Percorso modello mancante." }
        val file = File(raw).canonicalFile
        val root = activity.filesDir.canonicalFile
        require(file.path.startsWith(root.path + File.separator)) {
            "Il modello deve essere nello storage privato dell’app."
        }
        require(file.isFile && file.extension.lowercase() == "litertlm") {
            "File .litertlm non valido."
        }
        require(file.length() in (32L * 1024 * 1024)..(2L * 1024 * 1024 * 1024)) {
            "Dimensione modello non valida."
        }
        return file
    }

    private fun status(path: String?): Map<String, Any?> {
        val file = runCatching {
            path?.let(::validateModel)
        }.getOrNull()
        val activityManager =
            activity.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        return mapOf(
            "supported" to true,
            "installed" to (file != null),
            "loaded" to (
                engine?.isInitialized() == true &&
                    modelPath == file?.absolutePath
            ),
            "runtime" to RUNTIME,
            "backend" to "CPU",
            "modelName" to file?.name,
            "modelBytes" to (file?.length() ?: 0L),
            "memoryClassMb" to activityManager.memoryClass,
            "processors" to Runtime.getRuntime().availableProcessors(),
            "error" to null,
        )
    }

    private fun load(path: String?) {
        val file = validateModel(path)
        if (
            engine?.isInitialized() == true &&
            modelPath == file.absolutePath
        ) {
            return
        }

        unload()
        Engine.setNativeMinLogSeverity(LogSeverity.ERROR)
        val threads = (
            Runtime.getRuntime().availableProcessors() - 1
        ).coerceIn(1, 4)
        val runtimeCache =
            File(activity.cacheDir, "litert_lm").apply { mkdirs() }
        val next = Engine(
            EngineConfig(
                modelPath = file.absolutePath,
                backend = Backend.CPU(threadCount = threads),
                maxNumTokens = 3072,
                cacheDir = runtimeCache.absolutePath,
            )
        )
        next.initialize()
        engine = next
        modelPath = file.absolutePath
    }

    private fun generate(args: Map<*, *>?): Map<String, Any?> {
        val path = args?.get("modelPath")?.toString()
        load(path)
        val prompt = args?.get("prompt")?.toString()?.trim().orEmpty()
        require(prompt.isNotEmpty() && prompt.length <= 26000) {
            "Prompt locale vuoto o troppo lungo."
        }
        val systemInstruction =
            args?.get("systemInstruction")?.toString()?.trim().orEmpty()
                .take(5000)
        val maxOutputTokens = (
            args?.get("maxOutputTokens") as? Number
        )?.toInt()?.coerceIn(64, 768) ?: 384
        val activeEngine = engine
            ?: error("Runtime locale non inizializzato.")

        val started = System.nanoTime()
        val activeConversation = activeEngine.createConversation(
            ConversationConfig(
                systemInstruction = if (systemInstruction.isBlank()) {
                    null
                } else {
                    Contents.of(systemInstruction)
                },
                automaticToolCalling = false,
                channels = emptyList(),
                maxOutputToken = maxOutputTokens,
            )
        )
        conversation = activeConversation
        try {
            val response =
                activeConversation.sendMessage(prompt).toString().trim()
            require(response.isNotEmpty()) {
                "Il modello locale non ha restituito testo."
            }
            return mapOf(
                "text" to response,
                "elapsedMs" to (
                    (System.nanoTime() - started) / 1_000_000L
                ),
                "modelName" to File(modelPath.orEmpty()).name,
                "backend" to "CPU",
            )
        } finally {
            conversation = null
            runCatching { activeConversation.close() }
        }
    }

    private fun unload() {
        conversation?.let { activeConversation ->
            runCatching { activeConversation.cancelProcess() }
            runCatching { activeConversation.close() }
        }
        conversation = null
        engine?.let { activeEngine ->
            if (activeEngine.isInitialized()) {
                runCatching { activeEngine.close() }
            }
        }
        engine = null
        modelPath = null
    }
}

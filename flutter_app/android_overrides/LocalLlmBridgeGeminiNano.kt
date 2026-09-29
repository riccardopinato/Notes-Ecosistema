package it.notes.ecosystem.notes_ecosistema

import com.google.mlkit.genai.common.DownloadCallback
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.common.GenAiException
import com.google.mlkit.genai.prompt.GenerateContentResponse
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.java.GenerativeModelFutures
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.Future

class LocalLlmBridge(private val activity: MainActivity) {
    companion object {
        private const val RUNTIME = "ML Kit Prompt API 1.0.0-beta4"
        private const val MODEL = "Gemini Nano"
    }

    private val executor = Executors.newSingleThreadExecutor()
    private val generativeModel = Generation.getClient()
    private val futures = GenerativeModelFutures.from(generativeModel)

    @Volatile
    private var activeGeneration: Future<GenerateContentResponse>? = null

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> runAsync(result) {
                statusMap(futures.checkStatus().get())
            }
            "download" -> runAsync(result) {
                val status = futures.checkStatus().get()
                if (status == FeatureStatus.DOWNLOADABLE) {
                    futures.download(
                        object : DownloadCallback {
                            override fun onDownloadStarted(bytesToDownload: Long) = Unit

                            override fun onDownloadProgress(
                                totalBytesDownloaded: Long,
                            ) = Unit

                            override fun onDownloadCompleted() = Unit

                            override fun onDownloadFailed(e: GenAiException) = Unit
                        },
                    ).get()
                }
                statusMap(futures.checkStatus().get())
            }
            "generate" -> {
                val args = call.arguments as? Map<*, *>
                runAsync(result) { generate(args) }
            }
            "cancel" -> {
                activeGeneration?.cancel(true)
                activeGeneration = null
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    fun destroy() {
        activeGeneration?.cancel(true)
        activeGeneration = null
        runCatching { generativeModel.close() }
        executor.shutdownNow()
    }

    private fun runAsync(
        result: MethodChannel.Result,
        block: () -> Any?,
    ) {
        executor.execute {
            runCatching(block)
                .onSuccess { value ->
                    activity.runOnUiThread { result.success(value) }
                }
                .onFailure { error ->
                    activity.runOnUiThread {
                        result.error(
                            "LOCAL_AI",
                            error.message ?: "AI locale non disponibile.",
                            null,
                        )
                    }
                }
        }
    }

    private fun statusMap(status: Int): Map<String, Any?> {
        val supported = status != FeatureStatus.UNAVAILABLE
        return mapOf(
            "supported" to supported,
            "available" to (status == FeatureStatus.AVAILABLE),
            "downloadable" to (status == FeatureStatus.DOWNLOADABLE),
            "downloading" to (status == FeatureStatus.DOWNLOADING),
            "runtime" to RUNTIME,
            "backend" to "Android AICore",
            "modelName" to MODEL,
            "systemManaged" to true,
            "provider" to if (supported) "geminiNano" else "semantic",
            "error" to if (supported) {
                null
            } else {
                "Gemini Nano non è supportato o AICore non è ancora pronto su questo dispositivo."
            },
        )
    }

    private fun generate(args: Map<*, *>?): Map<String, Any?> {
        val status = futures.checkStatus().get()
        require(status == FeatureStatus.AVAILABLE) {
            when (status) {
                FeatureStatus.DOWNLOADABLE ->
                    "Gemini Nano è supportato ma deve essere preparato da Android."
                FeatureStatus.DOWNLOADING ->
                    "Android sta preparando Gemini Nano."
                else ->
                    "Gemini Nano non è disponibile su questo dispositivo."
            }
        }

        val prompt = args?.get("prompt")?.toString()?.trim().orEmpty()
        require(prompt.isNotEmpty() && prompt.length <= 18000) {
            "Prompt locale vuoto o troppo lungo."
        }
        val systemInstruction =
            args?.get("systemInstruction")?.toString()?.trim().orEmpty()
                .take(3000)
        val combinedPrompt = buildString {
            if (systemInstruction.isNotBlank()) {
                append(systemInstruction)
                append("\n\n")
            }
            append(prompt)
        }

        val started = System.nanoTime()
        val pending = futures.generateContent(combinedPrompt)
        activeGeneration = pending
        try {
            val response = pending.get()
            val text = response.candidates
                .firstOrNull()
                ?.text
                ?.trim()
                .orEmpty()
            require(text.isNotEmpty()) {
                "Gemini Nano non ha restituito testo."
            }
            return mapOf(
                "text" to text,
                "elapsedMs" to ((System.nanoTime() - started) / 1_000_000L),
                "modelName" to MODEL,
                "backend" to "Android AICore",
                "provider" to "geminiNano",
            )
        } finally {
            activeGeneration = null
        }
    }
}

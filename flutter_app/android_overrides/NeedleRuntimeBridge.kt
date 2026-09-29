package it.notes.ecosystem.notes_ecosistema

import android.os.Build
import android.os.Debug
import android.os.SystemClock
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

object NeedleNative {
    private var libraryLoaded = false

    init {
        libraryLoaded = runCatching {
            System.loadLibrary("notes_needle_jni")
            true
        }.getOrDefault(false)
    }

    fun supported(): Boolean =
        libraryLoaded &&
            Build.SUPPORTED_ABIS.any { it.equals("arm64-v8a", ignoreCase = true) } &&
            runCatching { nativeSupported() }.getOrDefault(false)

    external fun nativeSupported(): Boolean
    external fun nativeLoad(
        modelPath: String,
        systemPrompt: String,
        toolsJson: String,
    ): Int
    external fun nativeComplete(input: String, maxNewTokens: Int): String
    external fun nativeReset()
    external fun nativeLastError(): String
}

class NeedleRuntimeBridge(
    private val activity: MainActivity,
    private val modelPath: () -> String?,
) {
    companion object {
        private const val MODEL_NAME = "Needle 3 20L"
        private const val BACKEND = "Needle native ARM64"
        private const val MAX_PROMPT_CHARS = 14_000
        private const val MAX_OUTPUT_TOKENS = 512

        private const val SYSTEM_PROMPT =
            "Sei il motore locale di structured intelligence di Notes Ecosistema. " +
                "Scegli solo azioni esplicitamente supportate dal testo. " +
                "Non inventare valori e non proporre azioni distruttive o esterne."

        private val TOOLS_JSON = """
            [
              {
                "name":"create_task",
                "description":"Crea una attività solo quando la nota contiene una azione da svolgere.",
                "parameters":{
                  "type":"object",
                  "properties":{
                    "title":{"type":"string","description":"Titolo breve dell'attività"},
                    "dueText":{"type":"string","description":"Scadenza solo se esplicita nel testo"}
                  },
                  "required":["title"]
                }
              },
              {
                "name":"add_tags",
                "description":"Suggerisce tag centrali esplicitamente supportati dalla nota.",
                "parameters":{
                  "type":"object",
                  "properties":{
                    "tags":{
                      "type":"array",
                      "items":{"type":"string"},
                      "minItems":1,
                      "maxItems":12
                    }
                  },
                  "required":["tags"]
                }
              },
              {
                "name":"set_priority",
                "description":"Imposta una priorità solo quando è esplicita.",
                "parameters":{
                  "type":"object",
                  "properties":{
                    "priority":{
                      "type":"string",
                      "enum":["low","medium","high"]
                    }
                  },
                  "required":["priority"]
                }
              },
              {
                "name":"checklist_item",
                "description":"Crea una voce checklist da un elemento esplicito della nota.",
                "parameters":{
                  "type":"object",
                  "properties":{
                    "title":{"type":"string","description":"Testo breve della voce checklist"}
                  },
                  "required":["title"]
                }
              }
            ]
        """.trimIndent()
    }

    private val executor = Executors.newSingleThreadExecutor()
    @Volatile
    private var initializedPath: String? = null
    @Volatile
    private var prefixTokens: Int? = null

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> status(result)
            "analyze" -> analyze(call, result)
            "reset" -> reset(result)
            else -> result.notImplemented()
        }
    }

    fun destroy() {
        executor.shutdownNow()
    }

    private fun status(result: MethodChannel.Result) {
        val path = modelPath()
        val supported = NeedleNative.supported()
        result.success(
            mapOf(
                "supported" to supported,
                "modelInstalled" to (path != null),
                "ready" to (supported && path != null),
                "initialized" to (supported && path != null && initializedPath == path),
                "modelName" to MODEL_NAME,
                "backend" to BACKEND,
                "abi" to Build.SUPPORTED_ABIS.firstOrNull(),
                "prefixTokens" to prefixTokens,
                "error" to when {
                    !supported -> "Needle 3 locale richiede un dispositivo Android ARM64."
                    path == null -> "Pacchetto Needle 3 20L non installato."
                    else -> null
                },
            )
        )
    }

    private fun analyze(call: MethodCall, result: MethodChannel.Result) {
        val raw = call.arguments as? Map<*, *>
        val prompt = raw?.get("prompt")?.toString()?.trim().orEmpty()
        val requestedTokens = (raw?.get("maxOutputTokens") as? Number)
            ?.toInt()
            ?.coerceIn(32, MAX_OUTPUT_TOKENS)
            ?: 384

        if (prompt.isBlank()) {
            result.error("NEEDLE_INPUT", "Prompt Needle vuoto.", null)
            return
        }
        if (prompt.length > MAX_PROMPT_CHARS) {
            result.error("NEEDLE_INPUT", "Prompt Needle oltre il limite locale.", null)
            return
        }

        val path = modelPath()
        if (path == null || !File(path).isFile) {
            result.error(
                "NEEDLE_MODEL",
                "Pacchetto Needle 3 20L non installato.",
                null,
            )
            return
        }
        if (!NeedleNative.supported()) {
            result.error(
                "NEEDLE_UNSUPPORTED",
                "Needle 3 locale richiede Android ARM64.",
                null,
            )
            return
        }

        executor.execute {
            val startPss = currentPssKb()
            val started = SystemClock.elapsedRealtime()
            try {
                val loadStarted = SystemClock.elapsedRealtime()
                val prefix = NeedleNative.nativeLoad(
                    path,
                    SYSTEM_PROMPT,
                    TOOLS_JSON,
                )
                val loadMs = SystemClock.elapsedRealtime() - loadStarted
                initializedPath = path
                prefixTokens = prefix

                NeedleNative.nativeReset()
                val inferenceStarted = SystemClock.elapsedRealtime()
                val text = NeedleNative.nativeComplete(prompt, requestedTokens)
                val inferenceMs =
                    SystemClock.elapsedRealtime() - inferenceStarted
                val elapsedMs = SystemClock.elapsedRealtime() - started
                val endPss = currentPssKb()

                activity.runOnUiThread {
                    result.success(
                        mapOf(
                            "text" to text,
                            "elapsedMs" to elapsedMs,
                            "loadMs" to loadMs,
                            "inferenceMs" to inferenceMs,
                            "pssBeforeKb" to startPss,
                            "pssAfterKb" to endPss,
                            "modelName" to MODEL_NAME,
                            "backend" to BACKEND,
                            "prefixTokens" to prefix,
                            "provider" to "needle",
                        )
                    )
                }
            } catch (error: Throwable) {
                initializedPath = null
                prefixTokens = null
                val message = error.message
                    ?.takeIf { it.isNotBlank() }
                    ?: runCatching { NeedleNative.nativeLastError() }
                        .getOrNull()
                        ?.takeIf { it.isNotBlank() }
                    ?: "Inferenza Needle non riuscita."
                activity.runOnUiThread {
                    result.error("NEEDLE_RUNTIME", message, null)
                }
            }
        }
    }

    private fun reset(result: MethodChannel.Result) {
        executor.execute {
            runCatching {
                if (NeedleNative.supported()) NeedleNative.nativeReset()
            }.onSuccess {
                activity.runOnUiThread { result.success(null) }
            }.onFailure { error ->
                activity.runOnUiThread {
                    result.error(
                        "NEEDLE_RESET",
                        error.message ?: "Reset Needle non riuscito.",
                        null,
                    )
                }
            }
        }
    }

    private fun currentPssKb(): Int {
        val info = Debug.MemoryInfo()
        Debug.getMemoryInfo(info)
        return info.totalPss
    }
}

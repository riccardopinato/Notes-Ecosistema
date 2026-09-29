package it.notes.ecosystem.notes_ecosistema

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class LocalLlmBridge(private val activity: MainActivity) {
    companion object {
        private const val RUNTIME = "LiteRT-LM 0.17.1"
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        val modelPath = args?.get("modelPath")?.toString()
        when (call.method) {
            "status" -> result.success(status(modelPath))
            "cancel", "unload" -> result.success(null)
            "load", "generate" -> result.error(
                "LOCAL_LLM_EDITION",
                "Il runtime LLM è disponibile nell’APK Local AI.",
                null,
            )
            else -> result.notImplemented()
        }
    }

    fun destroy() = Unit

    private fun status(modelPath: String?): Map<String, Any?> {
        val file = modelPath
            ?.takeIf { it.isNotBlank() }
            ?.let(::File)
            ?.takeIf { it.isFile && it.extension.lowercase() == "litertlm" }
        return mapOf(
            "supported" to false,
            "installed" to (file != null),
            "loaded" to false,
            "runtime" to RUNTIME,
            "backend" to "CPU",
            "modelName" to file?.name,
            "modelBytes" to (file?.length() ?: 0L),
            "memoryClassMb" to 0,
            "processors" to Runtime.getRuntime().availableProcessors(),
            "error" to "Installa l’APK Notes Local AI per abilitare il runtime generativo.",
        )
    }
}

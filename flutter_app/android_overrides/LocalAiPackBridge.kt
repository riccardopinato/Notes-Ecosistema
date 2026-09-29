package it.notes.ecosystem.notes_ecosistema

import com.google.android.play.core.aipacks.AiPackManager
import com.google.android.play.core.aipacks.AiPackManagerFactory
import com.google.android.play.core.aipacks.AiPackState
import com.google.android.play.core.aipacks.model.AiPackStatus
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class LocalAiPackBridge(private val activity: MainActivity) {
    companion object {
        private const val PACK = "notes_needle3_20l"
        private const val MODEL = "needle3.cact"
    }

    private val manager: AiPackManager by lazy {
        AiPackManagerFactory.getInstance(activity.applicationContext)
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> status(result)
            "download" -> download(result)
            "remove" -> remove(result)
            "cancel" -> cancel(result)
            else -> result.notImplemented()
        }
    }

    private fun status(result: MethodChannel.Result) {
        runCatching {
            installedMap()?.let {
                result.success(it)
                return
            }

            manager.getPackStates(listOf(PACK))
                .addOnSuccessListener { states ->
                    result.success(
                        states.packStates()[PACK]?.let(::stateMap)
                            ?: notInstalledMap()
                    )
                }
                .addOnFailureListener { error ->
                    result.success(unavailableMap(error.message))
                }
        }.onFailure { error ->
            result.success(unavailableMap(error.message))
        }
    }

    private fun download(result: MethodChannel.Result) {
        runCatching {
            installedMap()?.let {
                result.success(it)
                return
            }

            manager.fetch(listOf(PACK))
                .addOnSuccessListener { states ->
                    result.success(
                        states.packStates()[PACK]?.let(::stateMap)
                            ?: notInstalledMap()
                    )
                }
                .addOnFailureListener { error ->
                    result.error(
                        "AI_PACK_DOWNLOAD",
                        error.message ?: "Download del pacchetto AI non riuscito.",
                        null,
                    )
                }
        }.onFailure { error ->
            result.error(
                "AI_PACK_DOWNLOAD",
                error.message ?: "Play AI Delivery non disponibile.",
                null,
            )
        }
    }

    private fun remove(result: MethodChannel.Result) {
        runCatching {
            manager.removePack(PACK)
                .addOnSuccessListener {
                    result.success(notInstalledMap())
                }
                .addOnFailureListener { error ->
                    result.error(
                        "AI_PACK_REMOVE",
                        error.message ?: "Rimozione del pacchetto AI non riuscita.",
                        null,
                    )
                }
        }.onFailure { error ->
            result.error(
                "AI_PACK_REMOVE",
                error.message ?: "Play AI Delivery non disponibile.",
                null,
            )
        }
    }

    private fun cancel(result: MethodChannel.Result) {
        runCatching {
            val states = manager.cancel(listOf(PACK))
            result.success(
                states.packStates()[PACK]?.let(::stateMap)
                    ?: notInstalledMap()
            )
        }.onFailure { error ->
            result.error(
                "AI_PACK_CANCEL",
                error.message ?: "Impossibile annullare il download.",
                null,
            )
        }
    }

    fun installedModelPath(): String? {
        val playLocation = manager.getPackLocation(PACK)
        if (playLocation != null) {
            val playModel = File(playLocation.assetsPath(), MODEL)
            if (playModel.isFile) return playModel.absolutePath
        }
        return bundledQaModelPath()
    }

    private fun installedMap(): Map<String, Any?>? {
        val path = installedModelPath() ?: return null
        val model = File(path)
        return mapOf(
            "supported" to true,
            "phase" to "installed",
            "bytesDownloaded" to model.length(),
            "totalBytes" to model.length(),
            "modelPath" to model.absolutePath,
            "bundledQa" to path.contains("needle_qa"),
            "error" to null,
        )
    }

    private fun bundledQaModelPath(): String? = runCatching {
        val targetDir = File(activity.filesDir, "needle_qa")
        val target = File(targetDir, MODEL)
        val expectedBytes = 35335380L

        if (target.isFile && target.length() == expectedBytes) {
            return@runCatching target.absolutePath
        }

        activity.assets.open(MODEL).use { input ->
            targetDir.mkdirs()
            val temporary = File(targetDir, "$MODEL.tmp")
            temporary.outputStream().use { output ->
                input.copyTo(output)
            }
            if (temporary.length() != expectedBytes) {
                temporary.delete()
                error("Modello Needle QA non valido.")
            }
            if (target.exists()) target.delete()
            if (!temporary.renameTo(target)) {
                temporary.copyTo(target, overwrite = true)
                temporary.delete()
            }
        }

        target.takeIf { it.isFile && it.length() == expectedBytes }?.absolutePath
    }.getOrNull()

    private fun stateMap(state: AiPackState): Map<String, Any?> {
        val phase = when (state.status()) {
            AiPackStatus.NOT_INSTALLED -> "notInstalled"
            AiPackStatus.PENDING -> "pending"
            AiPackStatus.DOWNLOADING -> "downloading"
            AiPackStatus.TRANSFERRING -> "transferring"
            AiPackStatus.COMPLETED -> "installed"
            AiPackStatus.WAITING_FOR_WIFI -> "waitingForWifi"
            AiPackStatus.REQUIRES_USER_CONFIRMATION -> "requiresConfirmation"
            AiPackStatus.FAILED -> "failed"
            AiPackStatus.CANCELED -> "canceled"
            else -> "unavailable"
        }

        val installed = if (state.status() == AiPackStatus.COMPLETED) {
            installedMap()
        } else {
            null
        }
        if (installed != null) return installed

        return mapOf(
            "supported" to true,
            "phase" to phase,
            "bytesDownloaded" to state.bytesDownloaded(),
            "totalBytes" to state.totalBytesToDownload(),
            "modelPath" to null,
            "error" to if (state.status() == AiPackStatus.FAILED) {
                "Play AI Delivery error ${state.errorCode()}."
            } else {
                null
            },
        )
    }

    private fun notInstalledMap(): Map<String, Any?> = mapOf(
        "supported" to true,
        "phase" to "notInstalled",
        "bytesDownloaded" to 0L,
        "totalBytes" to 0L,
        "modelPath" to null,
        "error" to null,
    )

    private fun unavailableMap(message: String?): Map<String, Any?> = mapOf(
        "supported" to false,
        "phase" to "unavailable",
        "bytesDownloaded" to 0L,
        "totalBytes" to 0L,
        "modelPath" to null,
        "error" to (
            message
                ?: "Play AI Delivery non disponibile in questa installazione."
            ),
    )
}

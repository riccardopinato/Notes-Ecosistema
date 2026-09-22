package it.notes.ecosystem.capture

import android.content.Context
import android.content.Intent
import it.notes.ecosystem.domain.CaptureSeed
import it.notes.ecosystem.domain.QuickCapture

object CaptureIntents {
    const val NEW_NOTE = "it.notes.ecosystem.NEW_NOTE"
    const val NEW_CHECKLIST = "it.notes.ecosystem.NEW_CHECKLIST"

    fun create(context: Context, checklist: Boolean = false) =
        Intent(context, CaptureActivity::class.java)
            .setAction(if (checklist) NEW_CHECKLIST else NEW_NOTE)

    /**
     * Compatibilità 0.8-0.21: questo metodo continua a interpretare SOLO
     * quick-capture testuale. Il nuovo CaptureActivity usa readExternal().
     */
    fun read(intent: Intent): CaptureSeed = when (intent.action) {
        NEW_NOTE -> CaptureSeed()
        NEW_CHECKLIST -> CaptureSeed(checklist = true)
        Intent.ACTION_SEND -> {
            require(intent.type == "text/plain") {
                "Questo parser legacy accetta solo testo."
            }
            require(!intent.hasExtra(Intent.EXTRA_STREAM)) {
                "Usa readExternal() per acquisire allegati."
            }
            QuickCapture.shared(
                intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString(),
                intent.getCharSequenceExtra(Intent.EXTRA_SUBJECT)?.toString(),
            )
        }
        else -> error("Azione non supportata.")
    }

    fun readExternal(intent: Intent): ExternalCapture =
        ExternalCaptureIntents.read(intent)
}

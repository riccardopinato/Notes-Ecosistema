package it.notes.ecosystem.capture

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import it.notes.ecosystem.MainActivity
import it.notes.ecosystem.R

object CaptureShortcuts {
    private fun note(context: Context, checklist: Boolean = false) = ShortcutInfo.Builder(context, if (checklist) "capture-checklist" else "capture-note")
        .setShortLabel(context.getString(if (checklist) R.string.capture_checklist else R.string.capture_note))
        .setLongLabel(context.getString(if (checklist) R.string.capture_new_checklist else R.string.capture_new_note))
        .setIcon(Icon.createWithResource(context, if (checklist) R.drawable.ic_capture_checklist else R.drawable.ic_capture_note))
        .setActivity(ComponentName(context, MainActivity::class.java))
        .setIntent(CaptureIntents.create(context, checklist)).build()
    fun install(context: Context) {
        // Launcher failures must not stop the app from opening.
        runCatching { context.getSystemService(ShortcutManager::class.java)?.addDynamicShortcuts(listOf(note(context), note(context, true))) }
    }
    fun pinNote(context: Context): Boolean {
        val manager = context.getSystemService(ShortcutManager::class.java) ?: return false
        return manager.isRequestPinShortcutSupported && manager.requestPinShortcut(note(context), null)
    }
    fun pinWidget(context: Context): Boolean {
        val manager = AppWidgetManager.getInstance(context)
        return manager.isRequestPinAppWidgetSupported && manager.requestPinAppWidget(ComponentName(context, QuickCaptureWidget::class.java), null, null)
    }
}

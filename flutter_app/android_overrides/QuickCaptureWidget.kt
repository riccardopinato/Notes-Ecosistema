package it.notes.ecosystem.notes_ecosistema

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class QuickCaptureWidget : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        manager: AppWidgetManager,
        ids: IntArray,
    ) {
        ids.forEach { id ->
            val views = RemoteViews(
                context.packageName,
                R.layout.quick_capture_widget,
            )
            fun action(
                requestCode: Int,
                action: String,
            ): PendingIntent = PendingIntent.getActivity(
                context,
                requestCode,
                Intent(context, MainActivity::class.java)
                    .setAction(action),
                PendingIntent.FLAG_UPDATE_CURRENT or
                    PendingIntent.FLAG_IMMUTABLE,
            )

            views.setOnClickPendingIntent(
                R.id.capture_note,
                action(1, "it.notes.ecosystem.NEW_NOTE"),
            )
            views.setOnClickPendingIntent(
                R.id.capture_checklist,
                action(2, "it.notes.ecosystem.NEW_CHECKLIST"),
            )
            manager.updateAppWidget(id, views)
        }
    }
}

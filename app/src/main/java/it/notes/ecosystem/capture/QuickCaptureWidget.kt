package it.notes.ecosystem.capture

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews
import it.notes.ecosystem.R

class QuickCaptureWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.quick_capture_widget)
            fun action(checklist: Boolean): PendingIntent = PendingIntent.getActivity(context, if (checklist) 2 else 1,
                CaptureIntents.create(context, checklist), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            views.setOnClickPendingIntent(R.id.capture_note, action(false))
            views.setOnClickPendingIntent(R.id.capture_checklist, action(true))
            manager.updateAppWidget(id, views)
        }
    }
}

package com.planerka.mobile

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class PlannerWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val snapshot = runCatching {
            JSONObject(widgetData.getString("planner_widget_snapshot", "{}") ?: "{}")
        }.getOrDefault(JSONObject())
        val tasks = snapshot.optJSONArray("tasks")
        val goalTitle = snapshot.optString("goalTitle", "Добавь цель")
        val goalPercent = snapshot.optInt("goalPercent", 0).coerceIn(0, 100)
        val shift = snapshot.optJSONObject("nextShift")
        val shiftText = shift?.let {
            val start = parseWidgetDate(it.optString("start"))
            val end = parseWidgetDate(it.optString("end"))
            val format = SimpleDateFormat("EEE HH:mm", Locale("ru"))
            "${it.optString("name")} · ${format.format(start)}–${format.format(end)}"
        } ?: "Ближайшая смена не выбрана"

        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.planner_widget).apply {
                setTextViewText(R.id.widget_goal_title, goalTitle.take(48))
                setTextViewText(R.id.widget_goal_percent, "$goalPercent%")
                setProgressBar(R.id.widget_goal_progress, 100, goalPercent, false)
                setTextViewText(R.id.widget_shift, shiftText.take(80))
                setTextViewText(R.id.widget_task_count, "Сегодня")

                val openIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("planerka://open"),
                )
                setOnClickPendingIntent(R.id.widget_container, openIntent)

                for (index in 0 until 3) {
                    val rowId = listOf(R.id.widget_task_1, R.id.widget_task_2, R.id.widget_task_3)[index]
                    val item = tasks?.optJSONObject(index)
                    if (item == null) {
                        setViewVisibility(rowId, View.GONE)
                    } else {
                        setViewVisibility(rowId, View.VISIBLE)
                        val title = item.optString("title", "Задача")
                        val overdue = item.optBoolean("isOverdue", false)
                        setTextViewText(rowId, (if (overdue) "!  " else "•  ") + title.take(56))
                        val taskId = item.optString("id")
                        val taskIntent = HomeWidgetLaunchIntent.getActivity(
                            context,
                            MainActivity::class.java,
                            Uri.Builder()
                                .scheme("planerka")
                                .authority("complete")
                                .appendQueryParameter("taskId", taskId)
                                .build(),
                        )
                        setOnClickPendingIntent(rowId, taskIntent)
                    }
                }
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}

private fun parseWidgetDate(value: String): Date =
    runCatching { Date.from(java.time.Instant.parse(value)) }.getOrDefault(Date())

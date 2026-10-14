package me.iweek.CalendarDiary

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * 闹钟排程逻辑（原生侧唯一入口）。
 *
 * 抽出成独立对象是为了让 [BootReceiver] 在开机后能复用同一套逻辑——
 * Dart 侧此时还没启动，Flutter 引擎不可用，重排必须完全在原生完成。
 */
object AlarmScheduler {

    private const val WINDOW_MILLIS = 5 * 60 * 1000L

    private fun pendingIntent(context: Context, id: Int, title: String, body: String): PendingIntent {
        val intent = Intent(context, TaskAlarmReceiver::class.java).apply {
            putExtra(TaskAlarmReceiver.EXTRA_ID, id)
            putExtra(TaskAlarmReceiver.EXTRA_TITLE, title)
            putExtra(TaskAlarmReceiver.EXTRA_BODY, body)
        }
        return PendingIntent.getBroadcast(
            context, id, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    /** 返回 true = 精确闹钟；false = 无精确权限，已降级为近似闹钟。 */
    fun schedule(context: Context, id: Int, epoch: Long, title: String, body: String): Boolean {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = pendingIntent(context, id, title, body)
        if (epoch <= System.currentTimeMillis()) {
            am.cancel(pi)
            return false
        }
        val canExact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            am.canScheduleExactAlarms()
        if (canExact) {
            am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, epoch, pi)
        } else {
            am.setWindow(AlarmManager.RTC_WAKEUP, epoch, WINDOW_MILLIS, pi)
        }
        return canExact
    }

    fun cancel(context: Context, id: Int) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.cancel(pendingIntent(context, id, "", ""))
    }
}
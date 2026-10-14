package me.iweek.CalendarDiary

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.provider.Settings

/**
 * 事项闹钟接收器。
 *
 * 为什么不直接用 flutter_local_notifications 自带的
 * `ScheduledNotificationReceiver`：那条链路要把整份通知详情用 Gson 从
 * Intent extras 反序列化后再重建通知，实测在部分国产 ROM 上会静默失败——
 * 闹钟被正常唤起，但通知从未进入投递流程（`numEnqueuedByApp` 不增长），
 * 用户表现为「到点完全没反应」，且没有任何报错可供定位。
 *
 * 这里改为：**调度时就把标题/正文写进 Intent extras**，收到广播后直接用
 * NotificationManager 发通知，不做反序列化，链路最短、行为可预期。
 */
class TaskAlarmReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra(EXTRA_ID, 0)
        if (id == null || id == 0) return
        val title = intent.getStringExtra(EXTRA_TITLE) ?: "事项提醒"
        val body = intent.getStringExtra(EXTRA_BODY) ?: ""

        // 该机型 logcat 全空，无法用 logcat 排查，改为写文件日志（run-as 可读）
        debug(context, "onReceive id=$id body=$body")

        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // 先删后建：已存在的渠道，其声音/振动等属性在这类国产 ROM 上会被
            // 「固化」，后续 createNotificationChannel 的更新不会生效。
            // 删掉重建才能确保用上我们想要的闹钟级配置。
            try {
                manager.deleteNotificationChannel(CHANNEL_ID)
            } catch (_: Exception) {
            }

            val alarmSound: Uri = Settings.System.DEFAULT_NOTIFICATION_URI
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)!!

            val channel =
                NotificationChannel(CHANNEL_ID, "事项提醒", NotificationManager.IMPORTANCE_HIGH)
                    .apply {
                        description = "日历事项闹钟提醒"
                        setSound(
                            alarmSound,
                            AudioAttributes.Builder()
                                .setUsage(AudioAttributes.USAGE_ALARM)
                                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                                .build()
                        )
                        // 按需求不震动：显式关闭渠道振动
                        enableVibration(false)
                        setShowBadge(true)
                        lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                    }
            manager.createNotificationChannel(channel)
            val cur = manager.getNotificationChannel(CHANNEL_ID)
            debug(
                context,
                "channel after create: importance=${cur?.importance} " +
                    "vibration=${cur?.vibrationPattern?.contentToString()} " +
                    "attrs=${cur?.audioAttributes?.usage}"
            )
        }

        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val contentIntent = PendingIntent.getActivity(
            context, id, launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            Notification.Builder(context)
        }
        builder.setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setWhen(System.currentTimeMillis())
            .setShowWhen(true)
            .setAutoCancel(true)
            .setContentIntent(contentIntent)
            // 锁屏也可见 + 归类为闹钟，提升优先级
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setCategory(Notification.CATEGORY_ALARM)
            .setPriority(Notification.PRIORITY_MAX)
            .setDefaults(Notification.DEFAULT_ALL)

        try {
            manager.notify(id, builder.build())
            debug(context, "notify ok id=$id")
        } catch (e: Exception) {
            debug(context, "notify FAILED id=$id err=$e")
            android.util.Log.e(TAG, "发送通知失败: $e")
        }

        // 后台直接播放在国产 ROM 上会被「后台音频」策略压制，必须走前台服务。
        startAlarmService(context, id, title, body)
    }

    /** 写文件日志：该机型 logcat 不可用，排查只能靠这个（adb exec-out run-as 读取）。 */
    private fun debug(context: Context, msg: String) {
        try {
            val f = java.io.File(context.filesDir, "alarm_debug.log")
            val time = java.text.SimpleDateFormat("HH:mm:ss.SSS", java.util.Locale.getDefault())
            f.appendText("${time.format(java.util.Date())} $msg\n")
        } catch (_: Exception) {
        }
    }

    /** 拉起前台服务响铃。后台播放被 ROM 压制时，这是唯一可靠的出声方式。 */
    private fun startAlarmService(context: Context, id: Int, title: String, body: String) {
        try {
            val intent = Intent(context, AlarmService::class.java).apply {
                putExtra(AlarmService.EXTRA_ID, id)
                putExtra(AlarmService.EXTRA_TITLE, title)
                putExtra(AlarmService.EXTRA_BODY, body)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            debug(context, "startAlarmService ok id=$id")
        } catch (e: Exception) {
            debug(context, "startAlarmService FAILED id=$id err=$e")
        }
    }

    companion object {
        const val TAG = "TaskAlarmReceiver"
        const val CHANNEL_ID = "task_reminder"
        const val EXTRA_ID = "task_id"
        const val EXTRA_TITLE = "task_title"
        const val EXTRA_BODY = "task_body"
    }
}
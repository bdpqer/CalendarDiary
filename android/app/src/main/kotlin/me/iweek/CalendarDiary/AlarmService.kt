package me.iweek.CalendarDiary

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings

/**
 * 提醒响铃前台服务。
 *
 * 为什么必须用前台服务：直接用 MediaPlayer 在广播接收器里播放，后台进程的
 * 音频会被这类国产 ROM 的「后台音频」策略压制——实测播放调用全部成功
 * （prepare/start 都执行了），但用户听不到任何声音。
 * 声明为 `foregroundServiceType="mediaPlayback"` 的前台服务后，系统会把它
 * 当作「正在播放媒体」，后台出声才稳定（闹钟/时钟类应用的标准做法）。
 *
 * 另外会申请**音频焦点**（闹钟级），让其他 app 暂时静音，确保提醒听得见。
 */
class AlarmService : Service() {

    private var player: MediaPlayer? = null
    private var focusRequest: AudioFocusRequest? = null
    private val stopTimer = Handler(Looper.getMainLooper())
    private val autoStop = Runnable { stopSelf() }

    /** 与 [TaskAlarmReceiver] 共用同一个调试日志文件（该机型 logcat 不可用）。 */
    private fun debug(msg: String) {
        try {
            val f = java.io.File(filesDir, "alarm_debug.log")
            val time = java.text.SimpleDateFormat("HH:mm:ss.SSS", java.util.Locale.getDefault())
            f.appendText("${time.format(java.util.Date())} [SVC] $msg\n")
        } catch (_: Exception) {
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "事项提醒"
        val body = intent?.getStringExtra(EXTRA_BODY) ?: ""

        // 必须在 5 秒内调用 startForeground
        startForeground(FGS_NOTIFICATION_ID, buildForegroundNotification(title, body))

        debug("service start title=$title body=$body")
        requestAudioFocus()
        startRinging()

        stopTimer.removeCallbacks(autoStop)
        stopTimer.postDelayed(autoStop, RING_TOTAL_MILLIS)
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        debug("service destroy")
        stopTimer.removeCallbacks(autoStop)
        stopRinging()
        abandonAudioFocus()
        super.onDestroy()
    }

    private fun buildForegroundNotification(title: String, body: String): Notification {
        val manager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // 前台服务专用渠道：只负责让服务存活，不重复发声
            manager.createNotificationChannel(
                NotificationChannel(
                    FGS_CHANNEL_ID, "提醒服务", NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "用于在后台播放提醒铃声"
                    setShowBadge(false)
                }
            )
        }
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val pi = PendingIntent.getActivity(
            this, 0, launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, FGS_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder.setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setOngoing(true)
            .setSound(null as android.net.Uri?)
            .setContentIntent(pi)
            .build()
    }

    private fun requestAudioFocus() {
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
            .setAudioAttributes(attrs)
            .setOnAudioFocusChangeListener { }
            .build()
        focusRequest = req
        val res = am.requestAudioFocus(req)
        debug("audioFocus result=$res")
    }

    private fun abandonAudioFocus() {
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        focusRequest?.let { am.abandonAudioFocusRequest(it) }
        focusRequest = null
    }

    private fun startRinging() {
        val uri = RingtoneManager.getActualDefaultRingtoneUri(
            this, RingtoneManager.TYPE_NOTIFICATION
        ) ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
        ?: Settings.System.DEFAULT_NOTIFICATION_URI ?: return
        try {
            player = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                setDataSource(this@AlarmService, uri)
                isLooping = true
                prepare()
                debug("player prepared uri=$uri")
                start()
                debug("player started isPlaying=${isPlaying}")
            }
        } catch (e: Exception) {
            debug("ring FAILED err=$e")
            player = null
        }
    }

    private fun stopRinging() {
        try {
            player?.apply {
                if (isPlaying) stop()
                release()
            }
        } catch (_: Exception) {
        }
        player = null
    }

    companion object {
        private const val FGS_CHANNEL_ID = "task_reminder_fgs"
        private const val FGS_NOTIFICATION_ID = 990001
        private const val RING_TOTAL_MILLIS = 20_000L
        const val EXTRA_ID = "task_id"
        const val EXTRA_TITLE = "task_title"
        const val EXTRA_BODY = "task_body"
    }
}
package me.iweek.CalendarDiary

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 事项闹钟调度入口（MethodChannel: me.iweek.CalendarDiary/alarm）。
 *
 * 自建而非依赖插件的原因同 [TaskAlarmReceiver]：插件的闹钟→通知链路在部分
 * 国产 ROM 上静默失败。这里直接用系统的 [AlarmManager] 排程，行为可控可验证。
 *
 * 除排程外，还承担两项「提醒可靠性」相关的只读查询与系统页跳转：
 * 1. 通知渠道实际重要性 —— 系统可能把渠道从 HIGH 静默降级为 DEFAULT，
 *    导致到点通知不显眼、用户以为没响；
 * 2. 电池优化白名单状态 —— 闹钟能否在后台稳定存活的关键前置条件。
 */
class MainActivity : FlutterFragmentActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "schedule" -> {
                        val id = call.argument<Int>("id") ?: 0
                        val epoch = call.argument<Number>("epoch")?.toLong() ?: 0L
                        val title = call.argument<String>("title") ?: "事项提醒"
                        val body = call.argument<String>("body") ?: ""
                        if (id == 0 || epoch <= 0L) {
                            result.success(false)
                        } else {
                            result.success(schedule(id, epoch, title, body))
                        }
                    }
                    "cancel" -> {
                        val id = call.argument<Int>("id") ?: 0
                        if (id != 0) cancel(id)
                        result.success(true)
                    }
                    "channelImportance" -> result.success(channelImportance())
                    "isIgnoringBatteryOptimizations" -> result.success(readBatteryOptimizationExempt())
                    "openNotificationSettings" -> {
                        result.success(openAppNotificationSettings())
                    }
                    "openBatteryOptimizationSettings" -> {
                        result.success(openBatteryOptimizationSettings())
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** 转发到 [AlarmScheduler]（与开机重排共用同一份排程逻辑）。 */
    private fun schedule(id: Int, epoch: Long, title: String, body: String): Boolean =
        AlarmScheduler.schedule(this, id, epoch, title, body)

    private fun cancel(id: Int) = AlarmScheduler.cancel(this, id)

    /**
     * 读取「事项提醒」渠道当前的**实际**重要性。
     *
     * 返回 -1 表示渠道尚未创建（App 刚装上还没发过通知）。
     * 渠道创建后 importance 会被系统或用户固化，改代码里的值无效 ——
     * 必须实测才能知道用户看到的提醒是不是被降级了。
     */
    private fun channelImportance(): Int {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        val channel = manager.getNotificationChannel(TaskAlarmReceiver.CHANNEL_ID)
        return channel?.importance ?: -1
    }

    /**
 * 是否已被加入「电池优化不受限制」名单（即后台可稳定存活）。
 *
 * 用 `PowerManager.isIgnoringBatteryOptimizations(包名)` 而非 `PackageManager` 的
 * 同名方法：后者在 AOSP 中是 @hide 的隐藏 API，SDK 工具链未暴露其签名，直接调用
 * 会编译报 `Unresolved reference`。`PowerManager` 这个是公开 API，等价且可用。
 * `PowerManager` 方法本身也需 API 23，故保留版本判断。
 */
    private fun readBatteryOptimizationExempt(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            pm.isIgnoringBatteryOptimizations(packageName)
        } else {
            true
        }
    }

    /** 跳转到本应用的「通知」设置页，供用户手动调回「重要」。 */
    private fun openAppNotificationSettings(): Boolean = startSettings(
        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
    )

    /**
     * 跳转到本应用的电池优化详情页。
     *
     * 优先用 `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`（该 ROM 支持时会直接
     * 弹确认框）；不支持则退回应用详情页，由用户自行在列表里查找。
     */
    private fun openBatteryOptimizationSettings(): Boolean {
        val direct = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
            .setData(Uri.parse("package:$packageName"))
        if (startSettings(direct)) return true
        return startSettings(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.parse("package:$packageName"))
        )
    }

    private fun startSettings(intent: Intent): Boolean = try {
        startActivity(intent)
        true
    } catch (_: Exception) {
        false
    }

    companion object {
        private const val CHANNEL = "me.iweek.CalendarDiary/alarm"
    }
}
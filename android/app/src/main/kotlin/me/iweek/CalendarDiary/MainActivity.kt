package me.iweek.CalendarDiary

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 事项闹钟调度入口（MethodChannel: me.iweek.CalendarDiary/alarm）。
 *
 * 自建而非依赖插件的原因同 [TaskAlarmReceiver]：插件的闹钟→通知链路在部分
 * 国产 ROM 上静默失败。这里直接用系统的 [AlarmManager] 排程，行为可控可验证。
 */
class MainActivity : FlutterActivity() {

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
                    else -> result.notImplemented()
                }
            }
    }

    /** 转发到 [AlarmScheduler]（与开机重排共用同一份排程逻辑）。 */
    private fun schedule(id: Int, epoch: Long, title: String, body: String): Boolean =
        AlarmScheduler.schedule(this, id, epoch, title, body)

    private fun cancel(id: Int) = AlarmScheduler.cancel(this, id)

    companion object {
        private const val CHANNEL = "me.iweek.CalendarDiary/alarm"
    }
}
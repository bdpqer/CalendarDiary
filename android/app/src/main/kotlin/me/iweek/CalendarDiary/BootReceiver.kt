package me.iweek.CalendarDiary

import android.database.sqlite.SQLiteDatabase
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * 开机 / 应用更新后重排所有未到期的提醒。
 *
 * 为什么必须有：闹钟是注册在系统 [android.app.AlarmManager] 里的，
 * **手机重启后会被系统清空**。而 Flutter 引擎此时还没启动，无法调用 Dart
 * 侧的 `rescheduleAll()`，所以必须有一个原生接收器，直接读数据库重排。
 *
 * 只做「到点那一刻」的一次性唤醒登记，登记完就退出，不常驻、不耗电。
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_LOCKED_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            return
        }
        val pending = goAsync()
        Thread {
            var count = 0
            try {
                val now = System.currentTimeMillis()
                // 只读打开 sqflite 建好的库，取出未到期的提醒
                val dbFile = context.getDatabasePath(DB_NAME)
                SQLiteDatabase.openDatabase(
                    dbFile.path, null, SQLiteDatabase.OPEN_READONLY
                ).use { db ->
                    db.rawQuery(
                        "SELECT id, content, reminder FROM tasks " +
                            "WHERE reminder IS NOT NULL AND reminder > ?",
                        arrayOf(now.toString())
                    ).use { c ->
                        while (c.moveToNext()) {
                            val id = c.getInt(0)
                            val content = c.getString(1) ?: ""
                            val reminder = c.getLong(2)
                            AlarmScheduler.schedule(context, id, reminder, "事项提醒", content)
                            count++
                        }
                    }
                }
                Log.i(TAG, "重排 $count 条提醒")
            } catch (e: Exception) {
                Log.e(TAG, "重排失败: $e")
            } finally {
                pending.finish()
            }
        }.start()
    }

    companion object {
        private const val TAG = "BootReceiver"
        private const val DB_NAME = "calendardiary.db"
    }
}
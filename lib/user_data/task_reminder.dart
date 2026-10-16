import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'diary_database.dart';

/// 事项闹钟提醒
///
/// 调度与通知下发走**自建链路**（见 `MainActivity` 的 MethodChannel 与
/// `TaskAlarmReceiver`），插件只保留两件事：初始化 + 发测试通知。
///
/// 换掉插件闹钟链路的原因（实测于本机Android 16 设备）：
/// 插件的闹钟虽然能被系统正常唤起，但接收器内部要把整份通知详情用 Gson
/// 从 Intent extras 反序列化后再重建通知，这一步会静默失败——通知从未进入
/// 投递流程（`dumpsys notification` 的 `numEnqueuedByApp` 始终为 0），
/// 用户表现为「到点完全没反应」，且没有任何报错可查。
///
/// 另外两个必须处理的点：
/// 1. **精确闹钟权限**：Android 14（API 34）起，targetSdk ≥ 34 的应用
///    **默认不授予** `SCHEDULE_EXACT_ALARM`。原生侧检测不到权限时会自动降级为
///    `setWindow` 近似闹钟（仍会响，可能延迟几分钟），并回报给 Dart 提示用户。
/// 2. **通知渠道**：Android 8+ 向不存在的渠道发通知会被系统**静默丢弃**，
///    因此 [init] 与接收器都会确保渠道存在。
///
/// 应用启动时 [init] 会重排所有未到期的提醒。
class TaskReminderService {
  TaskReminderService._();

  static final TaskReminderService instance = TaskReminderService._();

  static const String _channelId = 'task_reminder';
  static const String _channelName = '事项提醒';

  /// 自建闹钟通道（MainActivity 里的 MethodChannel），直接用系统 AlarmManager 排程
  static const MethodChannel _alarm = MethodChannel('me.iweek.CalendarDiary/alarm');

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// 最近一次调度的结果说明：
  /// - `null`：精确调度成功
  /// - `'inexact'`：已降级为不精确提醒（无精确闹钟权限）
  /// - 其他字符串：失败原因（供 UI 展示）
  String? lastError;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    // 通知小图标必须是 drawable 类型：插件用
    // getIdentifier(name, "drawable", pkg) 解析，传 @mipmap/xxx 会返回 0，
    // 系统会以「无有效小图标」静默丢弃通知。图标见 res/drawable/ic_notification.xml
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_notification'),
    );
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onTap,
    );
    await _createChannel();
    // 启动后重排所有未到期提醒
    await rescheduleAll();
  }

  void _onTap(NotificationResponse response) {
    // 点击通知暂无需特殊跳转
  }

  /// 显式创建通知渠道（幂等；渠道已存在时保留用户已调整的设置）
  Future<void> _createChannel() async {
    if (!Platform.isAndroid) return;
    try {
      const channel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: '日历事项闹钟提醒',
        importance: Importance.max,
      );
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(channel);
    } catch (e) {
      debugPrint('[TaskReminder] 创建通知渠道失败: $e');
    }
  }

  /// 申请 Android 13+ 通知权限，返回是否被授予。
  Future<bool> ensurePermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final result = await android?.requestNotificationsPermission();
      return result ?? true;
    } catch (_) {
      return false;
    }
  }

  /// 是否拥有精确闹钟权限。
  ///
  /// Android 14+ 且 targetSdk ≥ 34 时**默认拒绝**，需用户在
  /// 「设置 → 应用 → 特殊应用权限 → 闹钟和提醒」中开启。
  Future<bool> canScheduleExact() async {
    if (!Platform.isAndroid) return true;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final can = await android?.canScheduleExactNotifications();
      return can ?? false;
    } catch (e) {
      debugPrint('[TaskReminder] 查询精确闹钟权限失败: $e');
      return false;
    }
  }

  /// 打开系统「精确闹钟」授权页，返回用户是否授予。
  Future<bool> openExactAlarmSettings() async {
    if (!Platform.isAndroid) return true;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestExactAlarmsPermission();
      return granted ?? false;
    } catch (e) {
      debugPrint('[TaskReminder] 请求精确闹钟权限失败: $e');
      return false;
    }
  }

  /// 为单个事项安排提醒（id = task.id）。时间过期或参数缺失则跳过。
  ///
  /// 走自建的 MethodChannel（MainActivity 用系统 AlarmManager 排程 + 自己的
  /// 广播接收器发通知）。返回 false 表示**没有**注册成功，原因见 [lastError]。
  Future<bool> schedule(TaskItem task) async {
    lastError = null;
    if (task.id == null || task.reminder == null) {
      lastError = '事项未保存或未设置提醒时间';
      return false;
    }
    if (task.reminder!.isBefore(DateTime.now())) {
      lastError = '提醒时间已过';
      return false;
    }
    try {
      final exact = await _alarm.invokeMethod<bool>('schedule', {
        'id': task.id,
        'epoch': task.reminder!.millisecondsSinceEpoch,
        'title': _channelName,
        'body': task.content,
      });
      if (exact == true) return true;
      // 无精确闹钟权限：原生侧已降级为近似闹钟，仍会响但可能延迟
      lastError = 'inexact';
      return true;
    } catch (e) {
      lastError = '调度失败: $e';
      debugPrint('[TaskReminder] $lastError');
      return false;
    }
  }

  /// 立即发一条测试通知（绕过闹钟，直接验证「通知链路」是否正常）。
  ///
  /// 返回 true = 系统接受了这次投递。用于排查「闹钟到点没反应」到底是
  /// 闹钟触发的问题还是通知本身发不出去的问题。
  Future<bool> showTestNotification() async {
    if (!Platform.isAndroid) return false;
    await _createChannel();
    try {
      await _plugin.show(
        999999,
        '事项提醒',
        '测试通知：如果你看到这条，说明通知链路正常',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: '日历事项闹钟提醒',
            importance: Importance.max,
            priority: Priority.high,
            icon: 'ic_notification',
          ),
        ),
      );
      return true;
    } catch (e) {
      debugPrint('[TaskReminder] 测试通知失败: $e');
      lastError = '测试通知失败: $e';
      return false;
    }
  }

  /// 取消某事项的提醒
  Future<void> cancel(int taskId) async {
    try {
      await _alarm.invokeMethod<bool>('cancel', {'id': taskId});
      // 同步清掉插件侧可能残留的旧调度（升级前排的）
      await _plugin.cancel(taskId);
    } catch (e) {
      debugPrint('[TaskReminder] 取消提醒失败: $e');
    }
  }

  /// 重排所有未到期提醒（冷启动 / 开机广播 / 切回前台时调用）
  Future<void> rescheduleAll() async {
    try {
      final list = await DiaryDatabase.instance.pendingReminders();
      var ok = 0;
      for (final t in list) {
        if (await schedule(t)) ok++;
      }
      if (lastError != null) {
        debugPrint('[TaskReminder] 重排完成 $ok/${list.length}，$lastError');
      }
    } catch (e) {
      // 重排失败不影响主流程
      debugPrint('[TaskReminder] 重排异常: $e');
    }
  }

  // ─────────────────────── 提醒可靠性：渠道重要性 ───────────────────────

  /// 「事项提醒」渠道当前的**实际**重要性；`null` 表示渠道尚未创建。
  ///
  /// 渠道一旦创建，importance 会被系统或用户固化 —— 改代码里的 `Importance.max`
  /// 是无效的。实测发现部分 ROM 会把HIGH 静默降级为 DEFAULT（`mUserLockedFields=0`
  /// 说明并非用户操作），表现为到点通知不弹横幅、锁屏不显内容，用户误以为没响。
  /// 因此必须在运行时读真实值，再引导用户手动调回「重要」。
  Future<int?> channelImportance() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _alarm.invokeMethod<int>('channelImportance');
    } catch (e) {
      debugPrint('[TaskReminder] 读取渠道重要性失败: $e');
      return null;
    }
  }

  /// 渠道重要性是否低于「高」（Android 5 及以上 [Importance.high] = 4）。
  ///
  /// `null`（渠道未创建）视为正常：此时尚未发过通知，用户无需处理。
  Future<bool> isChannelImportanceDowngraded() async {
    final v = await channelImportance();
    if (v == null || v < 0) return false;
    return v < 4;
  }

  /// 跳转到本应用的系统「通知」设置页，供用户把渠道重要度调回「重要」。
  Future<bool> openNotificationSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _alarm.invokeMethod<bool>('openNotificationSettings') ?? false;
    } catch (e) {
      debugPrint('[TaskReminder] 打开通知设置失败: $e');
      return false;
    }
  }

  // ─────────────────────── 提醒可靠性：后台存活 ───────────────────────

  /// 是否已加入「电池优化不受限制」名单。
  ///
  /// 闹钟要在后台稳定触发，系统不能随意休眠该进程，这是前置条件之一。
  /// 未加白名单时部分 ROM 会压制后台唤醒，闹钟可能大幅延迟甚至丢失。
  Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _alarm.invokeMethod<bool>('isIgnoringBatteryOptimizations') ?? false;
    } catch (e) {
      debugPrint('[TaskReminder] 读取电池优化状态失败: $e');
      return false;
    }
  }

  /// 跳转到系统的电池优化设置页，引导用户把本 App 加入白名单。
  Future<bool> openBatteryOptimizationSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _alarm.invokeMethod<bool>('openBatteryOptimizationSettings') ?? false;
    } catch (e) {
      debugPrint('[TaskReminder] 打开电池优化设置失败: $e');
      return false;
    }
  }
}

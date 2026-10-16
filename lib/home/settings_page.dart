import 'dart:async';

import 'package:flutter/material.dart';

import '../date_base/almanac.dart';
import '../date_base/holiday_data.dart';
import '../user_data/diary_database.dart';
import '../user_data/task_reminder.dart';
import '../theme/app_colors.dart';

/// 「关于」页展示的农历算法版本
///
/// 升级 pubspec.yaml 中 lunar 依赖时请同步更新此处
/// （运行时读取包版本需引入 package_info_plus，不值当）。
const _kLunarVersion = 'lunar 1.7.8';

/// 设置页（对应原 App 的「我的」Tab）
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _totalDiaries = 0;
  int _withMedia = 0;
  bool _loaded = false;

  /// 「事项提醒」渠道的实际重要性；null = 尚未创建 / 查询失败。
  ///
  /// 用于检测系统是否把渠道从「高」静默降级 —— 降级后通知仍会送达，
  /// 但不再弹出横幅、锁屏不显内容，用户极易误判为「闹钟没响」。
  int? _channelImportance;

  /// 是否已在「电池优化不受限制」名单中。
  bool _ignoringBatteryOptimizations = false;

  /// 订阅日记增删：任意入口写/删/清空日记后，统计数字即时刷新
  /// （首页是 IndexedStack，本页常驻不重建，不订阅就不会更新）
  StreamSubscription<void>? _diarySub;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadReminderHealth();
    _diarySub = DiaryDatabase.diaryChanged.stream.listen((_) => _loadStats());
  }

  /// 加载提醒可靠性相关的两项实测状态。
  ///
  /// 用户可能刚在系统设置里改过，回到本页时（`initState` 只跑一次，
  /// 因为本页常驻于 IndexedStack）需要能刷新，故同时挂在下拉刷新里。
  Future<void> _loadReminderHealth() async {
    final imp = await TaskReminderService.instance.channelImportance();
    final ignoring =
        await TaskReminderService.instance.isIgnoringBatteryOptimizations();
    if (!mounted) return;
    setState(() {
      _channelImportance = imp;
      _ignoringBatteryOptimizations = ignoring;
    });
  }

  /// 渠道实际重要性的中文描述（对齐 Android `NotificationManager` 常量）。
  String get _channelImportanceText {
    final v = _channelImportance;
    if (v == null || v < 0) return '尚未创建（发一次通知后生效）';
    return switch (v) {
      5 => '最高（紧急）',
      4 => '高（推荐）',
      3 => '默认 ⚠️ 建议调高',
      2 => '低 ⚠️ 建议调高',
      1 => '最低 ⚠️ 建议调高',
      0 => '已关闭 ⚠️ 提醒不会显示',
      _ => '未知（$v）',
    };
  }

  @override
  void dispose() {
    _diarySub?.cancel();
    super.dispose();
  }

  Future<void> _loadStats() async {
    try {
      final s = await DiaryDatabase.instance.stats().timeout(const Duration(seconds: 3));
      if (mounted) {
        setState(() {
          _totalDiaries = s.total;
          _withMedia = s.withMedia;
          _loaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _confirmClearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('清空所有日记？'),
        content: const Text('全部日记与媒体文件将被永久删除，无法恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('清空', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (ok == true) {
      // 先取消已注册的事项闹钟，再清库，避免残留“孤儿闹钟”
      final tasks = await DiaryDatabase.instance.allTasks();
      for (final t in tasks) {
        if (t.id != null) {
          await TaskReminderService.instance.cancel(t.id!);
        }
      }
      await DiaryDatabase.instance.clearAll();
      await _loadStats();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已清空全部日记')),
        );
      }
    }
  }

  /// 立即发一条测试通知，验证通知链路（不经过闹钟）
  Future<void> _sendTestNotification() async {
    final ok = await TaskReminderService.instance.showTestNotification();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? '已发送测试通知，请下拉通知栏查看'
            : '发送失败：${TaskReminderService.instance.lastError ?? '未知原因'}'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = AlmanacUtil.of(DateTime.now());

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
      children: [
        // 今日概览
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceWarm,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderWarm),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('日历日记',
                      style: TextStyle(
                          fontSize: 17,
                          color: AppColors.textStrong,
                          fontWeight: FontWeight.w500)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Text('v4.2.0',
                        style: TextStyle(fontSize: 11, color: AppColors.red)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${DateTime.now().month}月${DateTime.now().day}日 '
                '${AlmanacUtil.weekdayCn(DateTime.now())} · ${a.lunarText}',
                style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
              Text('${a.ganZhi} · 生肖${a.shengXiao}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
              if (a.isJieQi && a.jieQi.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('今日节气：${a.jieQi}',
                      style: const TextStyle(fontSize: 12, color: AppColors.red)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 日记统计
        _Section(title: '日记统计', children: [
          _StatRow(label: '日记总数', value: _loaded ? '$_totalDiaries 篇' : '…'),
          _StatRow(label: '含媒体', value: _loaded ? '$_withMedia 篇' : '…'),
          _ActionRow(
            label: '清空所有日记',
            danger: true,
            onTap: _confirmClearAll,
          ),
        ]),

        // 提醒通知
        _Section(title: '提醒通知', children: [
          _ActionRow(
            label: '发送测试通知',
            onTap: _sendTestNotification,
          ),
          _ActionRow(
            label: '开启精确闹钟权限',
            onTap: () async {
              final ok = await TaskReminderService.instance.openExactAlarmSettings();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(ok ? '精确闹钟已开启，提醒会准点响' : '未开启，提醒可能延迟几分钟')),
              );
            },
          ),
          const _InfoRow(
            label: '说明',
            value: '「闹钟提醒」依赖系统精确闹钟权限。Android 14及以上默认不授予，'
                '未开启时提醒会自动降级为「近似提醒」，可能延迟几分钟。',
          ),
        ]),

        // 提醒可靠性：实测评测 + 修复引导
        //
        // 下面两项都不是「开关」而是「体检报告」：提醒能否被感知、能否在后台
        // 存活，都取决于系统侧的真实配置，代码里改不动，只能实测出来并引导用户。
        _Section(title: '提醒可靠性', children: [
          _StatRow(
            label: '通知重要度',
            value: _channelImportanceText,
          ),
          _ActionRow(
            label: '去调整通知重要度',
            onTap: () async {
              final ok = await TaskReminderService.instance.openNotificationSettings();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(ok
                      ? '请在系统设置中找到「日历日记」，把「事项提醒」设为「重要」'
                      : '无法打开系统通知设置，请手动前往应用设置'),
                ),
              );
              // 用户跳走期间状态会变，回到本页时重新体检
              await _loadReminderHealth();
            },
          ),
          _StatRow(
            label: '后台运行',
            value: _ignoringBatteryOptimizations ? '不受限制（推荐）' : '受系统限制',
          ),
          _ActionRow(
            label: '设为电池优化不限制',
            onTap: () async {
              final ok =
                  await TaskReminderService.instance.openBatteryOptimizationSettings();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(ok
                      ? '请在系统设置中选择「允许后台活动/不受限制」'
                      : '无法打开系统设置，请手动前往应用管理开启后台运行'),
                ),
              );
              await _loadReminderHealth();
            },
          ),
          const _InfoRow(
            label: '为何重要',
            value: '通知重要度被降级时，通知仍会送达但不弹横幅、锁屏不显示内容，'
                '容易误以为「闹钟没响」；后台受限则可能导致闹钟被系统休眠压制甚至丢弃。',
          ),
          const _InfoRow(
            label: '提醒失效自查',
            value: '若闹钟没响，请依次确认：① 通知重要度为「重要」；② 电池优化不受限制；'
                '③ 未对应用执行「强制停止」—— 强制停止会清空该应用的全部系统闹钟登记，'
                '需重新打开一次本应用才会恢复。',
          ),
        ]),

        // 节假日数据
        _Section(title: '节假日数据', children: [
          _StatRow(
            label: '已内置年份',
            value: HolidayData.supportedYears.map((e) => '$e').join('、'),
          ),
          const _InfoRow(
            label: '说明',
            value: '「休」为法定假日，「班」为调休上班。'
                '数据依据国务院办公厅放假安排内置，离线可用。',
          ),
        ]),

        // 关于
        _Section(title: '关于', children: [
          const _StatRow(label: '应用包名', value: 'me.iweek.CalendarDiary'),
          const _StatRow(label: '技术栈', value: 'Flutter + SQLite'),
          const _StatRow(label: '日历算法', value: _kLunarVersion),
        ]),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Text(title,
                style: const TextStyle(fontSize: 13, color: AppColors.textFaint)),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Column(children: children),
          ),
          const SizedBox(height: 16),
        ],
      );
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Text(label, style: const TextStyle(fontSize: 14, color: AppColors.textBody)),
            const Spacer(),
            Flexible(
              child: Text(value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 13, color: AppColors.textFaint)),
            ),
          ],
        ),
      );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 14, color: AppColors.textBody)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 12, color: AppColors.textFaint, height: 1.5)),
          ],
        ),
      );
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: danger ? AppColors.red : AppColors.textBody,
                ),
              ),
              const Spacer(),
              Icon(Icons.chevron_right, size: 16, color: Colors.grey.shade400),
            ],
          ),
        ),
      );
}

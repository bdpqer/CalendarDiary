import 'package:flutter/material.dart';

import '../date_base/history_today.dart';
import '../date_base/holiday_data.dart';
import '../date_base/almanac.dart';
import '../date_base/date_fmt.dart';
import '../user_data/diary_database.dart';
import '../user_data/task_reminder.dart';
import 'diary_detail_page.dart';
import 'diary_editor_page.dart';
import '../widgets/section_title.dart';
import '../theme/app_colors.dart';

/// 今日详情：底部上滑页面（参照原 App 版式）
///
/// 版式（自上而下）：
///   拖动条
///   10月12日 星期一          [九月] 初三
///   第42周 第285天
///   当日事项(无)      +添加事项   ☆ 标记
///   黄历卡片：干支 + 历史上的今天
///   节假日提示
///   日记入口
class TodaySheet extends StatelessWidget {
  const TodaySheet({
    super.key,
    required this.date,
    this.scrollController,
    this.onRefresh,
    this.taskEpoch = 0,
  });

  final DateTime date;

  /// 底部上滑面板的内层滚动控制器（由 DraggableScrollableSheet 提供）
  final ScrollController? scrollController;

  /// 日记内容变化后回调（刷新日历日记标记）
  final VoidCallback? onRefresh;

  /// 事项变更代号（跨入口变更时自增，触发当日事项列表重载）
  final int taskEpoch;

  @override
  Widget build(BuildContext context) {
    final a = AlmanacUtil.of(date);
    final holiday = HolidayData.of(date);

    return Container(
        decoration: BoxDecoration(
          color: AppColors.surfacePanel,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            // 拖动条
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.dragHandle,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
                children: [
                  _DateHeader(
                    date: date,
                    almanac: a,
                    week: _weekOfYear(date),
                    dayOfYear: _dayOfYear(date),
                  ),
                  const SizedBox(height: 10),
                  _TodoCard(
                      date: date, onChanged: onRefresh ?? () {}, taskEpoch: taskEpoch),
                  const SizedBox(height: 10),
                  _DiaryEntryCard(date: date, onRefresh: onRefresh),
                  const SizedBox(height: 10),
                  _AlmanacCard(almanac: a, date: date),
                  if (holiday != null) ...[
                    const SizedBox(height: 10),
                    _HolidayTip(info: holiday),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
  }

  static int _dayOfYear(DateTime d) =>
      d.difference(DateTime(d.year, 1, 1)).inDays + 1;

  /// 第几周（周日起始）
  static int _weekOfYear(DateTime d) {
    final first = DateTime(d.year, 1, 1);
    final offset = (d.weekday + 6) % 7; // 1=周一 → 0
    final dayOfYear = d.difference(first).inDays;
    return ((dayOfYear - offset) ~/ 7) + 1;
  }
}

/// 日期头部
class _DateHeader extends StatelessWidget {
  const _DateHeader({
    required this.date,
    required this.almanac,
    required this.week,
    required this.dayOfYear,
  });

  final DateTime date;
  final DayAlmanac almanac;
  final int week;
  final int dayOfYear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${date.month}月${date.day}日 ${AlmanacUtil.weekdayCn(date)}',
                style: const TextStyle(
                  fontSize: 19,
                  color: AppColors.textStrong,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              // 农历月份标签
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surfaceTag,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  almanac.monthText,
                  style: const TextStyle(fontSize: 11, color: AppColors.primaryDeep),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                almanac.dayText,
                style: const TextStyle(
                  fontSize: 16,
                  color: AppColors.red,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '第$week周 第$dayOfYear天',
            style: const TextStyle(fontSize: 12, color: AppColors.textFaint),
          ),
        ],
      ),
    );
  }
}

/// 卡片外壳
class _CardBox extends StatelessWidget {
  const _CardBox({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.borderWarm, width: 0.8),
        ),
        child: child,
      );
}

/// 当日事项（任务）
///
/// 功能：添加 / 勾选完成（空白方框 → 方块中间打勾）/ 星标（联动日历实心星）/
/// 闹钟提醒（精确本地通知）/ 编辑内容 / 删除。事项数量无上限。
class _TodoCard extends StatefulWidget {
  const _TodoCard({
    required this.date,
    required this.onChanged,
    this.taskEpoch = 0,
  });

  final DateTime date;

  /// 事项变化（尤其是星标）后回调，用于刷新日历实心星
  final VoidCallback onChanged;

  /// 事项变更代号（跨入口变更时自增，触发列表重载）
  final int taskEpoch;

  @override
  State<_TodoCard> createState() => _TodoCardState();
}

class _TodoCardState extends State<_TodoCard> {
  List<TaskItem> _tasks = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _TodoCard old) {
    super.didUpdateWidget(old);
    if (old.date != widget.date || old.taskEpoch != widget.taskEpoch) {
      _load();
    }
  }

  Future<void> _load() async {
    final list = await DiaryDatabase.instance.tasksOfDate(widget.date);
    if (mounted) {
      setState(() {
        _tasks = list;
        _loading = false;
      });
    }
  }

  Future<void> _toggleDone(TaskItem t) async {
    t.done = !t.done;
    await DiaryDatabase.instance.updateTask(t);
    // 完成后取消提醒；重新未完成则恢复提醒
    if (t.done) {
      if (t.reminder != null) await TaskReminderService.instance.cancel(t.id!);
    } else {
      await TaskReminderService.instance.schedule(t);
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleStar(TaskItem t) async {
    t.starred = !t.starred;
    await DiaryDatabase.instance.updateTask(t);
    if (mounted) setState(() {});
    widget.onChanged();
  }

  Future<void> _delete(TaskItem t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除事项'),
        content: const Text('确定删除该事项？删除后其提醒也会取消。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await DiaryDatabase.instance.deleteTask(t.id!);
    await TaskReminderService.instance.cancel(t.id!);
    await _load();
    widget.onChanged();
  }

  /// 添加新事项
  Future<void> _add() async {
    final t = await showTaskEditorDialog(context, widget.date);
    if (t == null) return;
    if (!mounted) return;
    await saveNewTask(context, t);
    await _load();
    widget.onChanged();
  }

  /// 编辑已有事项（内容 + 提醒）
  Future<void> _editTask(TaskItem t) async {
    final updated = await showTaskEditorDialog(context, widget.date, t);
    if (updated == null) return;
    if (updated.reminder != null && t.reminder == null) {
      final granted = await TaskReminderService.instance.ensurePermission();
      if (!granted) updated.reminder = null;
    }
    final hadReminder = t.reminder != null;
    final willRemind = updated.reminder != null;
    t.content = updated.content;
    t.reminder = updated.reminder;
    await DiaryDatabase.instance.updateTask(t);
    if (willRemind) {
      if (hadReminder) await TaskReminderService.instance.cancel(t.id!);
      final ok = await TaskReminderService.instance.schedule(t);
      if (mounted) _showScheduleResult(context, ok);
    } else if (hadReminder) {
      await TaskReminderService.instance.cancel(t.id!);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return _CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('当日事项',
                  style:
                      TextStyle(fontSize: 14, color: AppColors.textStrong, fontWeight: FontWeight.w500)),
              Text('（${_tasks.length}）',
                  style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
              const Spacer(),
              GestureDetector(
                onTap: _add,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add, size: 18, color: AppColors.red),
                    const SizedBox(width: 2),
                    const Text('添加事项',
                        style: TextStyle(fontSize: 13, color: AppColors.red)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_loading)
            const Text('加载中…',
                style: TextStyle(fontSize: 13, color: AppColors.textPlaceholder))
          else if (_tasks.isEmpty)
            const Text('暂无事项',
                style: TextStyle(fontSize: 13, color: AppColors.textPlaceholder))
          else
            ..._tasks.map(_buildRow),
        ],
      ),
    );
  }

  Widget _buildRow(TaskItem t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 完成态：空白方框 → 方块中间打勾
            GestureDetector(
              onTap: () => _toggleDone(t),
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: t.done ? AppColors.primary : Colors.transparent,
                  border: Border.all(
                    color: t.done ? AppColors.primary : AppColors.borderNeutral,
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: t.done
                    ? const Icon(Icons.check, size: 15, color: Colors.white)
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            // 内容（完成态加删除线、变灰）
            Expanded(
              child: GestureDetector(
                onTap: () => _editTask(t),
                child: Text(
                  t.content,
                  style: TextStyle(
                    fontSize: 14,
                    color: t.done ? AppColors.textPlaceholder : AppColors.textStrong,
                    decoration: t.done ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
            ),
            // 提醒时钟
            GestureDetector(
              onTap: () => _editTask(t),
              child: t.reminder != null
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.alarm, size: 15, color: AppColors.primary),
                        const SizedBox(width: 2),
                        Text(DateFmt.remindText(t.reminder!),
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.primary)),
                      ],
                    )
                  : Icon(Icons.alarm_outlined,
                      size: 16, color: Colors.grey.shade400),
            ),
            const SizedBox(width: 8),
            // 星标：点击变实心，联动日历
            GestureDetector(
              onTap: () => _toggleStar(t),
              child: Icon(
                t.starred ? Icons.star : Icons.star_border,
                size: 20,
                color: t.starred
                    ? AppColors.star
                    : Colors.grey.shade400,
              ),
            ),
            const SizedBox(width: 6),
            // 删除
            GestureDetector(
              onTap: () => _delete(t),
              child: Icon(Icons.delete_outline,
                  size: 18, color: Colors.grey.shade400),
            ),
          ],
        ),
      );
}

/// 事项编辑弹窗（新增 / 修改共用）——顶层函数，供「当日事项」卡与
/// 日历长按日期等任意入口调用。
///
/// 返回 [TaskItem]（已填好 content 与 reminder，date 仅新增时设置），取消返回 null。
Future<TaskItem?> showTaskEditorDialog(BuildContext context, DateTime date,
    [TaskItem? existing]) async {
  final ctl = TextEditingController(text: existing?.content ?? '');
  DateTime? reminder = existing?.reminder;
  var remindOn = existing?.reminder != null;
  final result = await showDialog<TaskItem?>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setSt) => AlertDialog(
        title: Text(existing == null ? '添加事项' : '编辑事项'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctl,
              maxLines: 3,
              autofocus: existing == null,
              decoration: const InputDecoration(
                hintText: '输入事项内容',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('闹钟提醒', style: TextStyle(fontSize: 14)),
                const Spacer(),
                Switch(
                  value: remindOn,
                  activeThumbColor: AppColors.primary,
                  activeTrackColor: AppColors.primary.withValues(alpha: 0.4),
                  onChanged: (v) async {
                    if (v) {
                      final dt = await _pickReminderTime(c, reminder);
                      if (dt == null) return;
                      reminder = dt;
                    } else {
                      reminder = null;
                    }
                    setSt(() => remindOn = v);
                  },
                ),
              ],
            ),
            if (remindOn && reminder != null)
              Text(DateFmt.remindText(reminder!),
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.primary)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, null),
              child: const Text('取消')),
          TextButton(
            onPressed: () {
              final text = ctl.text.trim();
              if (text.isEmpty) {
                Navigator.pop(c, null);
                return;
              }
              // 新建事项默认加星标（日历上更醒目），可在事项列表里点星取消
              final t = existing ??
                  TaskItem(date: DateFmt.dayKey(date), content: text, starred: true);
              t.content = text;
              t.reminder = remindOn ? reminder : null;
              Navigator.pop(c, t);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
  return result;
}

/// 保存新事项：申请通知权限（未授权则仅保存不提醒）→ 落库 → 排提醒
Future<void> saveNewTask(BuildContext context, TaskItem t) async {
  if (t.reminder != null) {
    final granted = await TaskReminderService.instance.ensurePermission();
    if (!granted) {
      t.reminder = null; // 未授权则仅保存事项，不提醒
      if (context.mounted) {
        _showReminderHint(context, '未授予通知权限，事项已保存但不提醒');
      }
    }
  }
  final id = await DiaryDatabase.instance.insertTask(t);
  t.id = id;
  if (t.reminder != null) {
    final ok = await TaskReminderService.instance.schedule(t);
    if (context.mounted) _showScheduleResult(context, ok);
  }
}

/// 按调度结果给用户明确反馈：成功不打扰；降级/失败必须提示
void _showScheduleResult(BuildContext context, bool ok) {
  if (ok) {
    if (TaskReminderService.instance.lastError == 'inexact') {
      _showReminderHint(
        context,
        '未开启「精确闹钟」权限，提醒可能延迟几分钟',
        action: SnackBarAction(
          label: '去开启',
          onPressed: () =>
              TaskReminderService.instance.openExactAlarmSettings(),
        ),
      );
    }
    return;
  }
  final err = TaskReminderService.instance.lastError;
  if (err == null || err == '提醒时间已过') return; // 无需打扰用户
  _showReminderHint(context, '提醒设置失败：$err');
}

void _showReminderHint(BuildContext context, String text,
    {SnackBarAction? action}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), action: action),
  );
}

/// 选择提醒时间（日期 + 时间），仅允许未来；取消返回 null
Future<DateTime?> _pickReminderTime(
    BuildContext context, DateTime? initial) async {
  final now = DateTime.now();
  var picked = initial ?? now.add(const Duration(hours: 1));
  final date = await showDatePicker(
    context: context,
    initialDate: picked,
    firstDate: DateTime(now.year, now.month, now.day),
    lastDate: DateTime(now.year + 5, 12, 31),
  );
  if (date == null) return null;
  if (!context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(picked),
  );
  if (time == null) return null;
  final dt =
      DateTime(date.year, date.month, date.day, time.hour, time.minute);
  if (dt.isBefore(now)) return null;
  return dt;
}

/// 「历史上的今天」卡片（占据原「黄历」卡片位置，保留干支 / 冲煞）
class _AlmanacCard extends StatefulWidget {
  const _AlmanacCard({required this.almanac, required this.date});

  final DayAlmanac almanac;
  final DateTime date;

  @override
  State<_AlmanacCard> createState() => _AlmanacCardState();
}

class _AlmanacCardState extends State<_AlmanacCard> {
  List<String> _events = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _AlmanacCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.date != widget.date) _load();
  }

  Future<void> _load() async {
    await HistoryToday.instance.ensureLoaded();
    if (!mounted) return;
    setState(() => _events = HistoryToday.instance.eventsOf(widget.date));
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.almanac;
    return _CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SectionTitle(
                '历史上的今天',
                barHeight: 13,
                gap: 6,
                color: AppColors.primaryMuted,
                padding: EdgeInsets.zero,
              ),
              const Spacer(),
              Icon(Icons.chevron_right, size: 16, color: Colors.grey.shade400),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            a.ganZhi,
            style: const TextStyle(
              fontSize: 19,
              color: AppColors.textStrong,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          if (_events.isEmpty)
            const Text('暂无记录',
                style: TextStyle(fontSize: 13, color: AppColors.textPlaceholder))
          else
            ..._events.map(_buildEvent),
          const SizedBox(height: 4),
          const Divider(height: 16, thickness: 0.5, color: AppColors.dividerWarm),
          Text(
            '冲${a.chongSha} · 财神${a.caiShen} · 喜神${a.xiShen}',
            style: const TextStyle(fontSize: 11, color: AppColors.textPlaceholder),
          ),
        ],
      ),
    );
  }

  /// 单条历史事件：年份前缀（到第一个冒号）加粗着色，正文常规
  Widget _buildEvent(String text) {
    var idx = text.indexOf('：');
    if (idx < 0) idx = text.indexOf(':');
    final hasPrefix = idx > 0 && idx <= 12;

    const body =
        TextStyle(fontSize: 13, height: 1.6, color: AppColors.textSecondary);
    const head = TextStyle(
      fontSize: 13,
      height: 1.6,
      color: AppColors.primaryDeep,
      fontWeight: FontWeight.w600,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 7, right: 7),
            width: 4,
            height: 4,
            decoration: const BoxDecoration(
              color: AppColors.bulletDot,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: hasPrefix
                ? Text.rich(TextSpan(children: [
                    TextSpan(text: text.substring(0, idx + 1), style: head),
                    TextSpan(text: text.substring(idx + 1), style: body),
                  ]))
                : Text(text, style: body),
          ),
        ],
      ),
    );
  }
}

/// 节假日提示
class _HolidayTip extends StatelessWidget {
  const _HolidayTip({required this.info});

  final HolidayInfo info;

  @override
  Widget build(BuildContext context) {
    final isRest = info.isRest;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceNotice,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(isRest ? Icons.beach_access : Icons.work,
              size: 16, color: AppColors.red),
          const SizedBox(width: 8),
          Text(
            isRest ? '${info.label} 放假' : '调休上班（${info.label}）',
            style: const TextStyle(fontSize: 13, color: AppColors.primaryDeep),
          ),
        ],
      ),
    );
  }
}

/// 日记入口
class _DiaryEntryCard extends StatelessWidget {
  const _DiaryEntryCard({required this.date, this.onRefresh});

  final DateTime date;
  final VoidCallback? onRefresh;

  /// 点击卡片查看当天日记：有日记进详情页，没有则提示去写
  Future<void> _viewDiary(BuildContext context) async {
    final entry = await DiaryDatabase.instance.entryOfDate(date);
    if (!context.mounted) return;
    if (entry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这一天还没有日记，点右侧「写日记」记录一下吧')),
      );
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DiaryDetailPage(date: date)),
    );
    onRefresh?.call();
  }

  @override
  Widget build(BuildContext context) {
    return _CardBox(
      child: Row(
        children: [
          // 图标 + 标题：点击查看当天日记
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _viewDiary(context),
              child: Row(
                children: [
                  const Icon(Icons.menu_book_outlined,
                      size: 18, color: AppColors.red),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('这一天的日记',
                        style:
                            TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                  ),
                ],
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => DiaryEditorPage(date: date)),
              );
              onRefresh?.call();
            },
            style: TextButton.styleFrom(
              foregroundColor: AppColors.red,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('写日记'),
          ),
        ],
      ),
    );
  }
}

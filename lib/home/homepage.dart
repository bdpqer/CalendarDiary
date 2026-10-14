import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../user_data/diary_database.dart';
import '../user_data/diary_list_page.dart';
import 'calendar_list/calendar_view.dart';
import 'day_detail_widget.dart';
import 'settings_page.dart';
import '../theme/app_colors.dart';

/// 主界面（参照原 App 版式）
///
/// 三个 Tab：日历 / 日记 / 设置
/// 日历页为可上下滑动的多月份日历，点击日期从底部弹出今日详情。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final _db = DiaryDatabase.instance;

  /// 日历列表锚点：index 0 对应 1900-01，向上（未来）无限增长
  static const int _baseYear = 1900;

  /// 初始展示的当前月之后的额外月数，滚动接近底部时动态增加
  static const int _initialExtraMonths = 12;

  int _extraMonths = _initialExtraMonths;
  double _screenWidth = 0;
  bool _didInitialScroll = false;

  DateTime? _selectedDate;
  int _tab = 0;

  /// 有日记的日期：yyyy-MM-dd → 日
  final Map<String, Set<int>> _diaryDays = {};

  /// 有星标事项的日期：yyyy-MM-dd → 日
  final Map<String, Set<int>> _starredDays = {};

  /// 事项变更代号：跨入口（如日历长按添加）变更时自增，
  /// 驱动底部面板「当日事项」列表重载
  int _taskEpoch = 0;

  /// 订阅日记增删改，任意入口写/删日记后自动刷新日历红点与星标
  late final StreamSubscription<void> _diarySub;

  /// 底部上滑面板的 peek 高度占比
  static const double _sheetPeek = 0.12;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final n = DateTime.now();
    _selectedDate = DateTime(n.year, n.month, n.day);
    _loadDiaryDays();
    _loadStarredDays();
    _diarySub = DiaryDatabase.diaryChanged.stream.listen((_) => _onTaskChanged());
  }

  /// ScrollController 延迟到 didChangeDependencies 创建：
  /// 此时能通过 MediaQuery 拿到本视图的真实逻辑宽度，
  /// 精确算出「当前月」的滚动偏移 → 首帧即定位，无闪动也无累计误差
  late final ScrollController _scrollCtrl;
  bool _ctrlReady = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ctrlReady) return;
    _ctrlReady = true;
    final width = MediaQuery.sizeOf(context).width;
    final off = _offsetForIndex(_nowIndex, width: width);
    _logDebug('init width=$width nowIndex=$_nowIndex offset=$off');
    _scrollCtrl = ScrollController(initialScrollOffset: off);
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    if (_ctrlReady) {
      _scrollCtrl.removeListener(_onScroll);
      _scrollCtrl.dispose();
    }
    _diarySub.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadDiaryDays();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    // 滚近底部（未来方向）时扩展未来月份，实现无限上划
    if (_scrollCtrl.position.pixels >
        _scrollCtrl.position.maxScrollExtent - 800) {
      setState(() => _extraMonths += 60);
    }
  }

  /// 仅在 debug 构建输出的诊断日志
  ///
  /// 用 `assert` 包裹后，release 构建里整段调用会被 tree-shake 掉 ——
  /// 既保留排查能力，又不给正式包留日志噪声。
  void _logDebug(String message) {
    assert(() {
      debugPrint('[WND] $message');
      return true;
    }());
  }

  /// index → 月份
  DateTime _monthAt(int index) =>
      DateTime(_baseYear + index ~/ 12, index % 12 + 1);

  /// 当前月对应的 index
  int get _nowIndex {
    final n = DateTime.now();
    return (n.year - _baseYear) * 12 + (n.month - 1);
  }

  int get _totalMonths => _nowIndex + 1 + _extraMonths;

  /// 日期列表 → `yyyy-M` → 日集合（日记红点与星标共用同一聚合逻辑）
  static Map<String, Set<int>> _buildMonthMap(Iterable<DateTime> dates) {
    final map = <String, Set<int>>{};
    for (final d in dates) {
      map.putIfAbsent('${d.year}-${d.month}', () => <int>{}).add(d.day);
    }
    return map;
  }

  Future<void> _loadDiaryDays() async {
    try {
      final map = _buildMonthMap(await _db.datesWithDiary());
      if (mounted) setState(() => _diaryDays..clear()..addAll(map));
    } catch (_) {
      // 日记标记加载失败不影响日历展示
    }
  }

  Future<void> _loadStarredDays() async {
    try {
      final map = _buildMonthMap(await _db.starredTaskDates());
      if (mounted) setState(() => _starredDays..clear()..addAll(map));
    } catch (_) {
      // 星标加载失败不影响日历展示
    }
  }

  /// 事项变化后：同时刷新日记标记与星标
  void _onTaskChanged() {
    _taskEpoch++;
    _loadDiaryDays();
    _loadStarredDays();
  }

  /// 长按日历日期：选中该日并直接弹出「添加事项」弹窗
  Future<void> _onDayLongPress(DateTime date) async {
    final d = DateTime(date.year, date.month, date.day);
    setState(() => _selectedDate = d);
    final t = await showTaskEditorDialog(context, d);
    if (t == null) return;
    if (!mounted) return;
    await saveNewTask(context, t);
    _onTaskChanged();
  }

  Set<int> _daysOf(DateTime month) =>
      _diaryDays['${month.year}-${month.month}'] ?? const {};

  Set<int> _starredOf(DateTime month) =>
      _starredDays['${month.year}-${month.month}'] ?? const {};

  /// 单个月份卡片的高度（各月周数 4~6 不一，高度随月份变化）
  double _monthHeight(DateTime m, {double? width}) =>
      MonthCalendarCard.extentFor(width ?? _screenWidth, m);

  /// 「周数」前缀和：`_rowsPrefix[i]` = 前 i 个月的总周数
  ///
  /// 周数只取决于月份（`MonthCalendarCard.rowsFor` 与屏幕宽度无关），
  /// 因此这份缓存不会因宽度变化而失效；每个月的周数在整个应用生命周期内
  /// 只会被计算一次。
  final List<int> _rowsPrefix = <int>[0];

  int _rowsPrefixAt(int index) {
    while (_rowsPrefix.length <= index) {
      final i = _rowsPrefix.length - 1;
      _rowsPrefix.add(_rowsPrefix[i] + MonthCalendarCard.rowsFor(_monthAt(i)));
    }
    return _rowsPrefix[index];
  }

  /// 第 index 个月卡片顶部的累计滚动偏移
  ///
  /// 卡片高度 = `fixedHeight + 周数 × 格子高度`，其中只有「周数」随月份变化，
  /// 于是累计偏移可化为：
  ///   `index × fixedHeight + （前 index 个月总周数）× 格子高度`
  ///
  /// 原先是从 1900-01 起逐月累加（`_monthAt` + `extentFor` 各自新建 DateTime），
  /// 跳到 2050 年要循环约 1800 次、选择器上限 2100 年约 2400 次；
  /// 现在只与「前缀和补齐」的增量有关，重复调用为 O(1)。
  double _offsetForIndex(int index, {double? width}) {
    final w = width ?? _screenWidth;
    return index * MonthCalendarCard.fixedHeight +
        _rowsPrefixAt(index) * MonthCalendarCard.cellHeightFor(w);
  }

  /// 跳转：双轮年月选择器（参照原 App 样式）
  Future<void> _jumpToDate() async {
    final init = _selectedDate ?? DateTime.now();
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (c) => _MonthJumpDialog(initial: init),
    );
    if (picked == null) return;

    // 保留原日，超出目标月天数时收敛到月末
    final day = init.day.clamp(1, DateTime(picked.year, picked.month + 1, 0).day);
    final target = DateTime(picked.year, picked.month, day);

    // 目标月超出列表已生成的范围时先扩展未来月份，避免被 clamp 吞掉
    final index = (target.year - _baseYear) * 12 + (target.month - 1);
    final needed = index - _nowIndex + 1;
    setState(() {
      _selectedDate = target;
      if (needed > _extraMonths) _extraMonths = needed + 12;
    });
    // 等列表按新 itemCount 完成布局后再滚动
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToMonth(DateTime(picked.year, picked.month));
    });
  }

  /// 选中日期：更新底部今日面板
  void _selectDate(DateTime date) {
    setState(() => _selectedDate = DateTime(date.year, date.month, date.day));
  }

  /// 回今天：选中今天并滚动到当前月
  void _backToToday() {
    final n = DateTime.now();
    _selectDate(n);
    _scrollToMonth(DateTime(n.year, n.month));
  }

  /// 滚动到某月（定位到该月顶部）
  void _scrollToMonth(DateTime month) {
    if (!_scrollCtrl.hasClients) return;
    final index = (month.year - _baseYear) * 12 + (month.month - 1);
    // 兜底：目标月尚未生成时先扩展再重试一帧
    if (index >= _totalMonths) {
      setState(() => _extraMonths = index - _nowIndex + 12);
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _scrollToMonth(month));
      return;
    }
    final offset = _offsetForIndex(index);
    // SliverVariedExtentList 对未布局区域的高度是估算的，maxScrollExtent
    // 可能偏小；直接 clamp 会把定位压回去，所以这里不做 clamp
    //（SliverVariedExtentList 本身支持渲染任意滚动偏移）
    _logDebug('scrollTo $month idx=$index offset=$offset '
        'max=${_scrollCtrl.position.maxScrollExtent}');
    _scrollCtrl.jumpTo(offset);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        // IndexedStack：三个页面常驻，切 Tab 不销毁重建，
        // 日历的滚动位置因此不会在切回时丢失/重置
        child: IndexedStack(
          index: _tab,
          children: [
            Builder(builder: (context) => _buildCalendarPage()),
            const DiaryListPage(),
            const SettingsPage(),
          ],
        ),
      ),
      bottomNavigationBar: _BottomTabBar(
        index: _tab,
        onChanged: (i) => setState(() => _tab = i),
      ),
    );
  }

  Widget _buildCalendarPage() {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      if (width > 0 && width != _screenWidth) {
        _screenWidth = width;
      }

      // 拿到真实宽度后，首帧定位到当前月（替代 initState 里不可靠的宽度估算）
      if (!_didInitialScroll && width > 0) {
        _didInitialScroll = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final n = DateTime.now();
          _scrollToMonth(DateTime(n.year, n.month));
        });
      }

      final peekPx = constraints.maxHeight * _sheetPeek;

      return Stack(
        children: [
          // 日历列表（可无限上下划动；各月高度随周数 4~6 变化）
          Positioned.fill(
            child: CustomScrollView(
              controller: _scrollCtrl,
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.only(bottom: peekPx),
                  sliver: SliverVariedExtentList.builder(
                    itemCount: _totalMonths,
                    itemExtentBuilder: (index, _) =>
                        _monthHeight(_monthAt(index)),
                    itemBuilder: (context, index) {
                      final m = _monthAt(index);
                      return MonthCalendarCard(
                        key: ValueKey('${m.year}-${m.month}'),
                        month: m,
                        diaryDays: _daysOf(m),
                        starredDays: _starredOf(m),
                        selectedDate: _selectedDate,
                        onDayTap: _selectDate,
                        onDayLongPress: _onDayLongPress,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // 跳转日期悬浮按钮
          Positioned(
            left: 14,
            bottom: peekPx + 12,
            child: _FloatButton(
              icon: Icons.fast_forward,
              label: '跳转日期',
              onTap: _jumpToDate,
            ),
          ),

          // 回今天悬浮按钮
          Positioned(
            right: 14,
            bottom: peekPx + 12,
            child: _FloatButton(
              icon: Icons.my_location,
              label: '回今天',
              onTap: _backToToday,
            ),
          ),

          // 底部上滑「今日」副页面
          Positioned.fill(
            child: DraggableScrollableSheet(
              initialChildSize: _sheetPeek,
              minChildSize: _sheetPeek,
              maxChildSize: 0.92,
              snap: true,
              snapSizes: const [_sheetPeek, 0.92],
              builder: (context, sheetScroll) {
                return Container(
                  decoration: const BoxDecoration(
                    color: AppColors.surfacePanel,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                    boxShadow: [
                      BoxShadow(color: Color(0x22000000), blurRadius: 8),
                    ],
                  ),
                  child: TodaySheet(
                    date: _selectedDate ?? DateTime.now(),
                    scrollController: sheetScroll,
                    onRefresh: _onTaskChanged,
                    taskEpoch: _taskEpoch,
                  ),
                );
              },
            ),
          ),
        ],
      );
    });
  }
}

/// 年月双轮跳转选择器（参照原 App 弹窗样式）
class _MonthJumpDialog extends StatefulWidget {
  const _MonthJumpDialog({required this.initial});

  final DateTime initial;

  @override
  State<_MonthJumpDialog> createState() => _MonthJumpDialogState();
}

class _MonthJumpDialogState extends State<_MonthJumpDialog> {
  static const int _minYear = 1900;
  static const int _maxYear = 2100;

  late int _year = widget.initial.year.clamp(_minYear, _maxYear);
  late int _month = widget.initial.month;

  late final FixedExtentScrollController _yearCtrl =
      FixedExtentScrollController(initialItem: _year - _minYear);
  late final FixedExtentScrollController _monthCtrl =
      FixedExtentScrollController(initialItem: _month - 1);

  @override
  void dispose() {
    _yearCtrl.dispose();
    _monthCtrl.dispose();
    super.dispose();
  }

  /// 选中行的高亮底色（必须半透明：selectionOverlay 画在文字上方，
  /// 不透明底色会把选中项文字盖住）
  Widget _selOverlay() => IgnorePointer(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: AppColors.primaryBorder.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );

  Widget _wheel({
    required FixedExtentScrollController ctrl,
    required int count,
    required Text Function(int index) buildItem,
    required ValueChanged<int> onChanged,
  }) {
    return SizedBox(
      height: 190,
      child: CupertinoPicker(
        scrollController: ctrl,
        itemExtent: 38,
        selectionOverlay: _selOverlay(),
        onSelectedItemChanged: onChanged,
        children: List.generate(count, (i) => Center(child: buildItem(i))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: _wheel(
                    ctrl: _yearCtrl,
                    count: _maxYear - _minYear + 1,
                    buildItem: (i) => Text('${_minYear + i}年',
                        style: const TextStyle(
                            fontSize: 16, color: AppColors.textStrong)),
                    onChanged: (i) => setState(() => _year = _minYear + i),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _wheel(
                    ctrl: _monthCtrl,
                    count: 12,
                    buildItem: (i) => Text('${i + 1}月',
                        style: const TextStyle(
                            fontSize: 16, color: AppColors.textStrong)),
                    onChanged: (i) => setState(() => _month = i + 1),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => Navigator.pop(context, DateTime(_year, _month)),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 9),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: AppColors.primaryBorder, width: 1.4),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('跳转到选中月份',
                    style: TextStyle(
                        fontSize: 14,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 橙色描边悬浮按钮（跳转日期 / 回今天）
class _FloatButton extends StatelessWidget {
  const _FloatButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.primaryBorder, width: 1.2),
          borderRadius: BorderRadius.circular(6),
          boxShadow: const [
            BoxShadow(color: Color(0x14000000), blurRadius: 4),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: AppColors.red),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 13, color: AppColors.red)),
          ],
        ),
      ),
    );
  }
}

/// 底部 Tab 栏：日历 / 日记 / 设置
class _BottomTabBar extends StatelessWidget {
  const _BottomTabBar({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  static const _items = ['日历', '日记', '设置'];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.borderLight, width: 0.6)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: List.generate(_items.length, (i) {
              final active = i == index;
              return Expanded(
                child: InkWell(
                  onTap: () => onChanged(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 6),
                      Text(
                        _items[i],
                        style: TextStyle(
                          fontSize: 15,
                          color: active ? AppColors.red : AppColors.textBody,
                          fontWeight: active ? FontWeight.w500 : FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // 选中下划线
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: active ? 20 : 0,
                        height: 2.5,
                        decoration: BoxDecoration(
                          color: AppColors.red,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

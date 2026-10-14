import 'package:flutter/material.dart';

import '../../date_base/holiday_data.dart';
import '../../date_base/almanac.dart';
import '../../theme/app_colors.dart';

/// 单个日期格子（参照原 App 版式）
///
/// 布局（自上而下）：
///   休/班   ← 右上角小标记
///  国庆节   ← 节日名（红色小字）
///    1      ← 公历数字
///   廿二    ← 农历日 / 节气名
class DayCellNew extends StatelessWidget {
  const DayCellNew({
    super.key,
    required this.date,
    required this.onTap,
    this.onLongPress,
    this.hasDiary = false,
    this.starred = false,
    this.selected = false,
  });

  final DateTime date;
  final VoidCallback onTap;

  /// 长按日期（快捷添加事项）
  final VoidCallback? onLongPress;

  /// 该日是否有日记（有则显示底部小圆点）
  final bool hasDiary;

  /// 该日是否有星标事项（有则左上角显示实心星）
  final bool starred;

  /// 是否被选中（选中显示红色圆环）
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final a = AlmanacUtil.of(date);
    final holiday = HolidayData.of(date);

    final isRest = holiday?.isRest ?? false;
    final isWorkDay = holiday?.isWork ?? false;

    // 数字颜色：节日/周末/今天 → 红；其余 → 黑
    final Color numColor;
    if (a.isToday || a.hasFestival || isRest || a.isWeekend) {
      numColor = AppColors.red;
    } else {
      numColor = AppColors.textStrong;
    }

    // 节日名（显示在数字上方）
    String festivalName = '';
    if (a.festival.isNotEmpty) {
      festivalName = a.festival.first;
    } else if (a.otherFestival.isNotEmpty) {
      festivalName = a.otherFestival.first;
    }

    // 数字下方文字：节气 > 农历日
    final isJieQi = a.isJieQi;
    final subText = isJieQi ? a.jieQi : a.dayText;
    final subColor = isJieQi ? AppColors.textStrong : AppColors.lunarGrey;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 星标：约红圈大小、居中铺在日期数字下层（数字仍在最上层）；不透明黄色，醒目
          if (starred)
            Positioned.fill(
              child: Center(
                child: Icon(
                  Icons.star,
                  size: 24,
                  color: AppColors.star,
                ),
              ),
            ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 上部：节日名（完整显示）+ 休/班（右上角绝对定位）
              SizedBox(
                height: 13,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    if (festivalName.isNotEmpty)
                      // 节日名完整显示，允许超出格子宽度（用 OverflowBox）
                      OverflowBox(
                        maxWidth: 74,
                        alignment: Alignment.center,
                        child: Text(
                          festivalName,
                          maxLines: 1,
                          softWrap: false,
                          style: const TextStyle(
                            fontSize: 8.5,
                            height: 1.0,
                            color: AppColors.red,
                          ),
                        ),
                      ),
                    if (isRest)
                      Positioned(
                          top: -2,
                          right: 0,
                          child: _badge('休', AppColors.red))
                    else if (isWorkDay)
                      Positioned(
                          top: -2,
                          right: 0,
                          child: _badge('班', AppColors.workBadge)),
                  ],
                ),
              ),

              // 中部：公历数字（今天/选中日 → 红圈 + 红字）
              SizedBox(
                height: 28,
                child: Center(
                  child: Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: (selected || a.isToday)
                        ? BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: AppColors.red, width: 1.5),
                          )
                        : null,
                    child: Text(
                      '${date.day}',
                      style: TextStyle(
                        fontSize: 18,
                        height: 1.0,
                        color:
                            (selected || a.isToday) ? AppColors.red : numColor,
                        fontWeight: isJieQi || a.hasFestival || a.isToday
                            ? FontWeight.w500
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ),

              // 下部：农历日 / 节气
              SizedBox(
                height: 13,
                child: Center(
                  child: Text(
                    subText,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.0,
                      color: subColor,
                      fontWeight: isJieQi ? FontWeight.w500 : FontWeight.normal,
                    ),
                  ),
                ),
              ),

              // 日记小圆点
              SizedBox(
                height: 5,
                child: hasDiary
                    ? Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.red,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 休/班小标记
  Widget _badge(String text, Color color) => Text(
        text,
        style: TextStyle(fontSize: 9, height: 1.0, color: color),
      );
}

/// 单个月份卡片（可独立滚动）
class MonthCalendarCard extends StatelessWidget {
  const MonthCalendarCard({
    super.key,
    required this.month,
    required this.diaryDays,
    required this.starredDays,
    required this.selectedDate,
    required this.onDayTap,
    this.onDayLongPress,
  });

  /// 该月任意日期即可，格式 yyyy-MM
  final DateTime month;

  /// 有日记的日集合
  final Set<int> diaryDays;

  /// 有星标事项的日集合
  final Set<int> starredDays;

  /// 当前选中日期（用于高亮今日面板所展示的日期）
  final DateTime? selectedDate;

  final ValueChanged<DateTime> onDayTap;

  /// 长按某一天（快捷添加事项入口）
  final ValueChanged<DateTime>? onDayLongPress;

  static const _weekLabels = ['日', '一', '二', '三', '四', '五', '六'];

  /// 固定布局尺寸（与 extentFor 保持同步，保证滚动定位精确）
  static const double titleHeight = 48;
  static const double headerHeight = 22;
  static const double gapHeight = 4;
  static const double gridHInset = 8;
  static const double cellAspect = 0.82;

  /// 该月实际占用的周数（4~6），按需收缩，避免月末出现空行
  static int rowsFor(DateTime month) {
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = DateTime(month.year, month.month, 1).weekday % 7;
    return ((leading + daysInMonth) / 7).ceil();
  }

  /// 单个日期格子的高度
  static double _cellHeight(double width) =>
      ((width - gridHInset * 2) / 7) / cellAspect;

  /// 单个日期格子的高度（对外暴露，供首页计算滚动偏移时复用同一套尺寸）
  static double cellHeightFor(double width) => _cellHeight(width);

  /// 卡片中与「周数」无关的固定高度（月份标题 + 星期表头 + 间隔）
  ///
  /// 卡片高度可写成 `fixedHeight + rowsFor(month) * 格子高度`，
  /// 首页据此把「累计滚动偏移」化为 O(1) 计算，无需逐月累加。
  static const double fixedHeight = titleHeight + headerHeight + gapHeight;

  /// 月份卡片总高度（逻辑像素）
  static double extentFor(double width, DateTime month) =>
      fixedHeight + rowsFor(month) * _cellHeight(width);

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // 周日起始
    final leading = first.weekday % 7;
    final totalCells = rowsFor(month) * 7;

    final now = DateTime.now();
    final isThisMonth = month.year == now.year && month.month == now.month;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 月份标题（固定高度）
        SizedBox(
          height: titleHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Text(
                  '${month.year}年${month.month}月',
                  style: const TextStyle(
                    fontSize: 22,
                    color: AppColors.textStrong,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (isThisMonth) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Text('本月',
                        style: TextStyle(fontSize: 11, color: AppColors.red)),
                  ),
                ],
                const Spacer(),
                // 分享图标
                GestureDetector(
                  onTap: () {},
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.share_outlined,
                        size: 20, color: AppColors.red),
                  ),
                ),
              ],
            ),
          ),
        ),
        // 星期表头：周日与周六为红（固定高度）
        SizedBox(
          height: headerHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: List.generate(7, (i) {
                final isWeekend = i == 0 || i == 6;
                return Expanded(
                  child: Center(
                    child: Text(
                      '周${_weekLabels[i]}',
                      style: TextStyle(
                        fontSize: 13,
                        color: isWeekend ? AppColors.red : AppColors.textStrong,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: gapHeight),
        // 日期格子
        GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: gridHInset),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: cellAspect,
          ),
          itemCount: totalCells,
          itemBuilder: (context, index) {
            final dayOffset = index - leading + 1;
            final date = DateTime(month.year, month.month, dayOffset);
            final inMonth = dayOffset >= 1 && dayOffset <= daysInMonth;
            if (!inMonth) return const SizedBox.shrink();
            return DayCellNew(
              date: date,
              hasDiary: diaryDays.contains(date.day),
              starred: starredDays.contains(date.day),
              selected: selectedDate != null &&
                  selectedDate!.year == month.year &&
                  selectedDate!.month == month.month &&
                  selectedDate!.day == dayOffset,
              onTap: () => onDayTap(date),
              onLongPress:
                  onDayLongPress == null ? null : () => onDayLongPress!(date),
            );
          },
        ),
      ],
    );
  }
}

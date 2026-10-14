// 日历高度与滚动偏移的纯计算测试
//
// 首页的滚动定位完全依赖「卡片高度」与「累计偏移」两个公式，
// 一旦二者不同步，跳转日期就会定位到错误的月份。这里把这两点钉死。
import 'package:flutter_test/flutter_test.dart';
import 'package:calendardiary/home/calendar_list/calendar_view.dart';

/// 锚点：首页 `_baseYear = 1900`，index 0 → 1900-01
int indexToYear(int index) => 1900 + index ~/ 12;
int indexToMonth(int index) => index % 12 + 1;

void main() {
  group('MonthCalendarCard.rowsFor', () {
    test('行数恒在 4~6 之间（1900-01 ~ 2100-12 全量扫描）', () {
      for (var y = 1900; y <= 2100; y++) {
        for (var m = 1; m <= 12; m++) {
          expect(
            MonthCalendarCard.rowsFor(DateTime(y, m)),
            inInclusiveRange(4, 6),
            reason: '$y-${m.toString().padLeft(2, '0')}',
          );
        }
      }
    });

    test('已知月份的行数：2026-02 恰为 4 行、2024-02 为 5 行', () {
      // 2026-02-01 是周日、当月 28 天 → 正好 4 行（月末无空行）
      expect(MonthCalendarCard.rowsFor(DateTime(2026, 2)), 4);
      // 2024-02-01 是周四、闰年 29 天 → 5 行
      expect(MonthCalendarCard.rowsFor(DateTime(2024, 2)), 5);
    });

    test('与「前导空格 + 当月天数」向上取整的朴素算法一致', () {
      for (var y = 2020; y <= 2030; y++) {
        for (var m = 1; m <= 12; m++) {
          final daysInMonth = DateTime(y, m + 1, 0).day;
          final leading = DateTime(y, m, 1).weekday % 7;
          expect(
            MonthCalendarCard.rowsFor(DateTime(y, m)),
            ((leading + daysInMonth) / 7).ceil(),
          );
        }
      }
    });
  });

  group('高度公式', () {
    test('fixedHeight = 标题 + 星期表头 + 间隔', () {
      expect(
        MonthCalendarCard.fixedHeight,
        MonthCalendarCard.titleHeight +
            MonthCalendarCard.headerHeight +
            MonthCalendarCard.gapHeight,
      );
    });

    test('extentFor = fixedHeight + 行数 × 格子高度', () {
      const width = 390.0;
      for (final m in [
        DateTime(2026, 1),
        DateTime(2026, 2),
        DateTime(2026, 3),
        DateTime(2024, 2),
      ]) {
        expect(
          MonthCalendarCard.extentFor(width, m),
          MonthCalendarCard.fixedHeight +
              MonthCalendarCard.rowsFor(m) *
                  MonthCalendarCard.cellHeightFor(width),
          reason: '$m',
        );
      }
    });

    test('行数相同的月份高度相同，行数不同的月份高度不同', () {
      const width = 390.0;
      // 2026-02（4 行）与 2026-01（5 行）不同；2026-03 与 2026-04 同为 5 行
      expect(
        MonthCalendarCard.extentFor(width, DateTime(2026, 2)),
        lessThan(MonthCalendarCard.extentFor(width, DateTime(2026, 1))),
      );
      expect(
        MonthCalendarCard.extentFor(width, DateTime(2026, 3)),
        MonthCalendarCard.extentFor(width, DateTime(2026, 4)),
      );
    });
  });

  group('滚动偏移：前缀和公式与逐月累加等价', () {
    test('1900-01 ~ 2100-12 全量比对（首页已改用前者）', () {
      const width = 390.0;
      final fixed = MonthCalendarCard.fixedHeight;
      final cell = MonthCalendarCard.cellHeightFor(width);

      // 逐月累加（首页改造前的写法）
      var naive = 0.0;
      // 前缀和所需的总周数
      var rowsSum = 0;
      const lastIndex = 2412; // 2100-12 对应的 index

      for (var index = 0; index <= lastIndex; index++) {
        // 前缀和公式
        final fast = index * fixed + rowsSum * cell;
        expect(
          fast,
          closeTo(naive, 1e-6),
          reason: 'index=$index 处两套公式结果应一致',
        );

        if (index < lastIndex) {
          final m = DateTime(indexToYear(index), indexToMonth(index));
          naive += MonthCalendarCard.extentFor(width, m);
          rowsSum += MonthCalendarCard.rowsFor(m);
        }
      }
    });

    test('索引换算：index 0/9/1512 分别对应 1900-01/1900-10/2026-01', () {
      expect(indexToYear(0), 1900);
      expect(indexToMonth(0), 1);
      expect(indexToYear(9), 1900);
      expect(indexToMonth(9), 10);
      expect(indexToYear(1512), 2026);
      expect(indexToMonth(1512), 1);
    });
  });
}

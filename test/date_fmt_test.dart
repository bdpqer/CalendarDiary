// DateFmt 纯函数单元测试
//
// `lib/date_base/date_fmt.dart` 不依赖任何 Flutter 库，属于纯逻辑。
import 'package:flutter_test/flutter_test.dart';
import 'package:calendardiary/date_base/date_fmt.dart';

void main() {
  group('DateFmt.dayKey', () {
    test('补零为 yyyy-MM-dd', () {
      expect(DateFmt.dayKey(DateTime(2026, 1, 5)), '2026-01-05');
      expect(DateFmt.dayKey(DateTime(2026, 12, 31)), '2026-12-31');
    });

    test('个位数年份也补到 4 位', () {
      expect(DateFmt.dayKey(DateTime(999, 3, 4)), '0999-03-04');
    });
  });

  group('DateFmt.yearMonth', () {
    test('由年、月整数拼出 yyyy-MM', () {
      expect(DateFmt.yearMonth(2026, 1), '2026-01');
      expect(DateFmt.yearMonth(2026, 10), '2026-10');
      expect(DateFmt.yearMonth(999, 2), '0999-02');
    });

    test('结果可直接用于 substr(date,1,7) 前缀匹配', () {
      final key = DateFmt.dayKey(DateTime(2026, 10, 13));
      expect(key.substring(0, 7), DateFmt.yearMonth(2026, 10));
    });
  });

  group('DateFmt.monthDayKey', () {
    test('MM-DD 补零', () {
      expect(DateFmt.monthDayKey(DateTime(2026, 1, 5)), '01-05');
      expect(DateFmt.monthDayKey(DateTime(2026, 11, 25)), '11-25');
    });
  });

  group('DateFmt.remindText', () {
    test('月日不补零、时分补零', () {
      expect(DateFmt.remindText(DateTime(2026, 1, 5, 9, 7)), '1月5日 09:07');
      expect(DateFmt.remindText(DateTime(2026, 6, 1, 0, 0)), '6月1日 00:00');
    });

    test('两位月日与 23:59 边界', () {
      expect(DateFmt.remindText(DateTime(2026, 12, 31, 23, 59)), '12月31日 23:59');
    });
  });
}

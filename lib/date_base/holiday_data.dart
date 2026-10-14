/// 法定节假日与调休数据
///
/// 「休」= 法定假日放假，「班」= 调休上班（周末但要上班）。
/// 原小枣日历通过网络接口拉取，这里内置一份静态数据作为离线兜底。
library;

/// 某一天的休假状态
enum HolidayType {
  none,
  rest, // 休
  work, // 班
}

/// 节假日数据源
class HolidayData {
  const HolidayData._();

  /// 某年某月的安排：key 为 day，value 为休假信息
  /// 结构：{ 年: { 月: { 日: HolidayInfo } } }
  static final Map<int, Map<int, Map<int, HolidayInfo>>> _schedule = {
    // ===== 2026 年（国办发明电〔2025〕7号）=====
    2026: {
      // 元旦：1/1-1/3 休，1/4(周日) 班
      1: {
        1: const HolidayInfo(HolidayType.rest, '元旦'),
        2: const HolidayInfo(HolidayType.rest, '元旦'),
        3: const HolidayInfo(HolidayType.rest, '元旦'),
        4: const HolidayInfo(HolidayType.work, '调休'),
      },
      // 春节：2/15-2/23 休（共9天），2/14、2/28 班
      2: {
        14: const HolidayInfo(HolidayType.work, '调休'),
        15: const HolidayInfo(HolidayType.rest, '春节'),
        16: const HolidayInfo(HolidayType.rest, '春节'),
        17: const HolidayInfo(HolidayType.rest, '春节'),
        18: const HolidayInfo(HolidayType.rest, '春节'),
        19: const HolidayInfo(HolidayType.rest, '春节'),
        20: const HolidayInfo(HolidayType.rest, '春节'),
        21: const HolidayInfo(HolidayType.rest, '春节'),
        22: const HolidayInfo(HolidayType.rest, '春节'),
        23: const HolidayInfo(HolidayType.rest, '春节'),
        28: const HolidayInfo(HolidayType.work, '调休'),
      },
      // 清明：4/4-4/6 休
      4: {
        4: const HolidayInfo(HolidayType.rest, '清明'),
        5: const HolidayInfo(HolidayType.rest, '清明'),
        6: const HolidayInfo(HolidayType.rest, '清明'),
      },
      // 劳动节：5/1-5/5 休，5/9 班
      5: {
        1: const HolidayInfo(HolidayType.rest, '劳动节'),
        2: const HolidayInfo(HolidayType.rest, '劳动节'),
        3: const HolidayInfo(HolidayType.rest, '劳动节'),
        4: const HolidayInfo(HolidayType.rest, '劳动节'),
        5: const HolidayInfo(HolidayType.rest, '劳动节'),
        9: const HolidayInfo(HolidayType.work, '调休'),
      },
      // 端午：6/19-6/21 休
      6: {
        19: const HolidayInfo(HolidayType.rest, '端午'),
        20: const HolidayInfo(HolidayType.rest, '端午'),
        21: const HolidayInfo(HolidayType.rest, '端午'),
      },
      // 中秋：9/25-9/27 休；国庆调休 9/20 班
      9: {
        20: const HolidayInfo(HolidayType.work, '调休'),
        25: const HolidayInfo(HolidayType.rest, '中秋'),
        26: const HolidayInfo(HolidayType.rest, '中秋'),
        27: const HolidayInfo(HolidayType.rest, '中秋'),
      },
      // 国庆：10/1-10/7 休，10/10 班
      10: {
        1: const HolidayInfo(HolidayType.rest, '国庆节'),
        2: const HolidayInfo(HolidayType.rest, '国庆节'),
        3: const HolidayInfo(HolidayType.rest, '国庆节'),
        4: const HolidayInfo(HolidayType.rest, '国庆节'),
        5: const HolidayInfo(HolidayType.rest, '国庆节'),
        6: const HolidayInfo(HolidayType.rest, '国庆节'),
        7: const HolidayInfo(HolidayType.rest, '国庆节'),
        10: const HolidayInfo(HolidayType.work, '调休'),
      },
    },

    // ===== 2025 年（国办发明电〔2024〕12号）=====
    2025: {
      // 元旦：1/1 休（不调休）
      1: {
        1: const HolidayInfo(HolidayType.rest, '元旦'),
        // 春节调休：1/26 班
        26: const HolidayInfo(HolidayType.work, '调休'),
        // 春节：1/28-1/31 休
        28: const HolidayInfo(HolidayType.rest, '春节'),
        29: const HolidayInfo(HolidayType.rest, '春节'),
        30: const HolidayInfo(HolidayType.rest, '春节'),
        31: const HolidayInfo(HolidayType.rest, '春节'),
      },
      2: {
        // 春节续：2/1-2/4 休，2/8 班
        1: const HolidayInfo(HolidayType.rest, '春节'),
        2: const HolidayInfo(HolidayType.rest, '春节'),
        3: const HolidayInfo(HolidayType.rest, '春节'),
        4: const HolidayInfo(HolidayType.rest, '春节'),
        8: const HolidayInfo(HolidayType.work, '调休'),
      },
      4: {
        // 清明：4/4-4/6 休
        4: const HolidayInfo(HolidayType.rest, '清明'),
        5: const HolidayInfo(HolidayType.rest, '清明'),
        6: const HolidayInfo(HolidayType.rest, '清明'),
        // 劳动节调休：4/27 班
        27: const HolidayInfo(HolidayType.work, '调休'),
      },
      5: {
        // 劳动节：5/1-5/5 休
        1: const HolidayInfo(HolidayType.rest, '劳动节'),
        2: const HolidayInfo(HolidayType.rest, '劳动节'),
        3: const HolidayInfo(HolidayType.rest, '劳动节'),
        4: const HolidayInfo(HolidayType.rest, '劳动节'),
        5: const HolidayInfo(HolidayType.rest, '劳动节'),
        // 端午：5/31 休
        31: const HolidayInfo(HolidayType.rest, '端午'),
      },
      6: {
        // 端午续：6/1-6/2 休
        1: const HolidayInfo(HolidayType.rest, '端午'),
        2: const HolidayInfo(HolidayType.rest, '端午'),
      },
      9: {
        // 国庆调休：9/28 班
        28: const HolidayInfo(HolidayType.work, '调休'),
      },
      // 国庆+中秋：10/1-10/8 休，10/11 班
      10: {
        1: const HolidayInfo(HolidayType.rest, '国庆节'),
        2: const HolidayInfo(HolidayType.rest, '国庆节'),
        3: const HolidayInfo(HolidayType.rest, '国庆节'),
        4: const HolidayInfo(HolidayType.rest, '国庆节'),
        5: const HolidayInfo(HolidayType.rest, '国庆节'),
        6: const HolidayInfo(HolidayType.rest, '国庆节'),
        7: const HolidayInfo(HolidayType.rest, '国庆节'),
        8: const HolidayInfo(HolidayType.rest, '中秋节'),
        11: const HolidayInfo(HolidayType.work, '调休'),
      },
    },
  };

  /// 查询某天的休假信息，无则返回 null
  static HolidayInfo? of(DateTime date) {
    final year = _schedule[date.year];
    if (year == null) return null;
    final month = year[date.month];
    if (month == null) return null;
    return month[date.day];
  }

  /// 支持的年份列表
  static List<int> get supportedYears => _schedule.keys.toList()..sort();
}

/// 休假信息
class HolidayInfo {
  const HolidayInfo(this.type, this.label);

  final HolidayType type;

  /// 「休」或「班」之外的补充说明，如「国庆节」
  final String label;

  bool get isRest => type == HolidayType.rest;
  bool get isWork => type == HolidayType.work;
}

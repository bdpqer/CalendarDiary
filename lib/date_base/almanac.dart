/// 农历 / 干支 / 生肖 / 节气 算法封装
///
/// 基于 lunar 库，参照原小枣日历 date_base/nongli.dart 的接口设计。
/// 只暴露界面实际使用的日历能力（农历文本 / 干支 / 节气 / 节日 / 冲煞 / 喜神 / 财神）。
/// 需要更完整的黄历字段时，直接从 [DayAlmanac.lunar] 上按需取即可。
library;

import 'package:lunar/lunar.dart';

/// 一天的日历信息聚合对象
///
/// 原移植自小枣日历的一批接口（纳音 / 胎神 / 九星 / 值神 / 建除十二神 /
/// 彭祖百忌 / 宜忌 / 闰月 / 四柱干支 / 生肖文本等）在界面里从未被渲染过，
/// 已一并移除，避免「看着有能力其实是死代码」的认知负担。
class DayAlmanac {
  DayAlmanac({
    required this.date,
    required this.lunar,
    required this.lunarText,
    required this.ganZhi,
    required this.shengXiao,
    required this.jieQi,
    required this.isToday,
    required this.isWeekend,
    this.festival = const [],
    this.otherFestival = const [],
  });

  final DateTime date;

  /// 农历日期对象
  final Lunar lunar;

  /// 农历完整文本，如「乙巳年 六月廿一」
  final String lunarText;

  /// 干支纪年+月+日
  final String ganZhi;

  /// 生肖
  final String shengXiao;

  /// 节气（无节气返回空串）
  final String jieQi;

  final bool isToday;
  final bool isWeekend;

  /// 传统节日（春节、元旦…）
  final List<String> festival;

  /// 公历节日（劳动节、国庆节…）
  final List<String> otherFestival;

  /// 农历日中文，如「初一」
  String get dayText => lunar.getDayInChinese();

  /// 农历月中文
  String get monthText => lunar.getMonthInChinese();

  /// 是否节气日
  bool get isJieQi => jieQi.isNotEmpty;

  /// 当日所有节日文本（传统优先）
  List<String> get allFestivals => [...festival, ...otherFestival];

  /// 是否有节日
  bool get hasFestival => allFestivals.isNotEmpty;

  /// 冲煞
  String get chongSha => lunar.getDayChongDesc();

  /// 喜神方位
  String get xiShen => lunar.getDayPositionXiDesc();

  /// 财神方位
  String get caiShen => lunar.getDayPositionCaiDesc();
}

/// 日历工具类
class AlmanacUtil {
  const AlmanacUtil._();

  static final Map<String, DayAlmanac> _cache = {};

  /// 缓存上限
  ///
  /// 每个 value 都持有一个 `Lunar` 对象，而用户翻月是可无限延伸的
  /// （日历锚点定在 1900-01、向上无限增长）—— 不加限制的话缓存只增不减。
  static const int _maxCache = 512;

  /// 获取某天的日历信息（带缓存）
  static DayAlmanac of(DateTime date) {
    final key = _keyOf(date);
    final cached = _cache[key];
    if (cached != null) return cached;

    final d = DateTime(date.year, date.month, date.day);
    final lunar = Lunar.fromDate(d);
    final almanac = DayAlmanac(
      date: d,
      lunar: lunar,
      lunarText: '${lunar.getYearInChinese()}年 ${lunar.getMonthInChinese()}月${lunar.getDayInChinese()}',
      ganZhi: '${lunar.getYearInGanZhi()}年 ${lunar.getMonthInGanZhi()}月 ${lunar.getDayInGanZhi()}日',
      shengXiao: lunar.getYearShengXiao(),
      jieQi: lunar.getJieQi(),
      isToday: _isSameDay(d, DateTime.now()),
      isWeekend: d.weekday == DateTime.saturday || d.weekday == DateTime.sunday,
      festival: lunar.getFestivals(),
      otherFestival: Solar.fromDate(d).getFestivals(),
    );
    if (_cache.length >= _maxCache) {
      // Map 保持插入顺序：超限时丢弃最早的一半（FIFO），
      // 比「全部清空」温和，比手写 LRU 简单，够用。
      for (final k in _cache.keys.take(_maxCache ~/ 2).toList()) {
        _cache.remove(k);
      }
    }
    _cache[key] = almanac;
    return almanac;
  }

  /// 中文星期，如「星期一」
  static String weekdayCn(DateTime date) {
    const names = ['一', '二', '三', '四', '五', '六', '日'];
    return '星期${names[date.weekday - 1]}';
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _keyOf(DateTime d) => '${d.year}-${d.month}-${d.day}';
}

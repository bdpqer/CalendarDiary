import 'dart:convert';

import 'package:flutter/services.dart';

import '../date_base/date_fmt.dart';

/// 「历史上的今天」数据服务
///
/// 数据文件：`assets/history_in_today.json`
/// 结构：`{ "MM-DD": { "events": ["前4713年：…", …] } }`
///
/// 采用惰性加载 + 进程内缓存：整个文件仅解析一次，之后按日期 O(1) 命中。
class HistoryToday {
  HistoryToday._();

  static final HistoryToday instance = HistoryToday._();

  static const String _assetPath = 'assets/history_in_today.json';

  Map<String, List<String>>? _data;
  Future<void>? _loading;

  bool get isLoaded => _data != null;

  /// 保证数据已载入（并发调用只解析一次）。
  Future<void> ensureLoaded() {
    if (_data != null) return Future.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    final raw = await rootBundle.loadString(_assetPath);
    final decoded = json.decode(raw);
    final result = <String, List<String>>{};
    if (decoded is Map) {
      decoded.forEach((key, value) {
        final list = value is Map ? value['events'] : value;
        if (list is List) {
          result['$key'] =
              list.map((e) => '$e').toList(growable: false);
        }
      });
    }
    _data = result;
  }

  /// 取某日的历史事件（未加载时返回空列表，调用方应先 await [ensureLoaded]）。
  ///
  /// 数据键 `MM-DD` 由 [DateFmt.monthDayKey] 统一生成，不再在本类内重复拼装。
  List<String> eventsOf(DateTime date) =>
      _data?[DateFmt.monthDayKey(date)] ?? const [];
}

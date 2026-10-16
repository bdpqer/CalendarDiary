import 'dart:async';

import 'package:flutter/material.dart';

import '../date_base/almanac.dart';
import '../home/diary_detail_page.dart';
import '../home/diary_editor_page.dart';
import 'diary_database.dart';
import 'diary_repository.dart';
import '../widgets/empty_state.dart';
import '../theme/app_colors.dart';

/// 日记总览列表（按时间倒序）
class DiaryListPage extends StatefulWidget {
  const DiaryListPage({super.key, this.loader});

  /// 列表数据加载器。
  ///
  /// 默认走真实仓库（[DiaryRepository.loadAll]）；测试注入假数据，
  /// 使 widget 测试不必依赖 sqflite 文件库与 path_provider。
  final Future<List<DiaryEntryView>> Function({int limit})? loader;

  @override
  State<DiaryListPage> createState() => _DiaryListPageState();
}

class _DiaryListPageState extends State<DiaryListPage> {
  List<DiaryEntryView> _items = [];

  /// 未过滤的全量列表。
  ///
  /// 搜索必须在输入时即时过滤，而 `_reload()` 只在加载/刷新时才跑——
  /// 没有这份全量副本，`_onSearch` 就只能改关键词、改不了列表。
  List<DiaryEntryView> _all = [];
  bool _loading = true;
  String? _error;
  String _query = '';
  StreamSubscription<void>? _diarySub;

  @override
  void initState() {
    super.initState();
    _reload();
    // 全局订阅：从日历面板/详情页等任意入口增删日记后，列表即时刷新
    // （首页是 IndexedStack，本页常驻不重建，仅靠编辑器返回时的 _reload 覆盖不到跨 Tab 场景）
    _diarySub = DiaryDatabase.diaryChanged.stream.listen((_) => _reload());
  }

  @override
  void dispose() {
    _diarySub?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final all = await (widget.loader ?? DiaryRepository.loadAll)();
      if (!mounted) return;
      setState(() {
        _all = all;
        _items = _filter(_all);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  List<DiaryEntryView> _filter(List<DiaryEntryView> all) {
    if (_query.isEmpty) return all;
    final q = _query.toLowerCase();
    return all.where((e) {
      if (e.content.toLowerCase().contains(q)) return true;
      return _matchDate(e.date, q);
    }).toList();
  }

  /// 日期匹配（与内容匹配取并集），兼容常见书写形式：
  ///
  /// - 变体形式：`2026-10-15`、`2026/10/15`、`2026年10月15日`、`10-15`、`10.15`、
  ///   `10月15日`（补零/不补零均收录）。搜「10月」只命中 10 月，搜「15」命中 15 日。
  /// - 紧凑数字：查询去掉非数字字符后 ≥4 位时，与 `yyyyMMdd` 紧凑串比对，
  ///   覆盖 `20261015`、`1015` 这类无分隔输入。
  bool _matchDate(DateTime d, String q) {
    final variants = <String>[
      '${d.year}-${_two(d.month)}-${_two(d.day)}',
      '${d.year}/${d.month}/${d.day}',
      '${d.year}年${d.month}月${d.day}日',
      '${_two(d.month)}-${_two(d.day)}',
      '${d.month}-${d.day}',
      '${d.month}月${d.day}日',
      '${_two(d.month)}月${_two(d.day)}日',
      '${d.month}.${d.day}',
      '${_two(d.month)}.${_two(d.day)}',
    ];
    if (variants.join('\n').toLowerCase().contains(q)) return true;
    final digits = q.replaceAll(_nonDigit, '');
    if (digits.length >= 4) {
      return '${d.year}${_two(d.month)}${_two(d.day)}'.contains(digits);
    }
    return false;
  }

  static final RegExp _nonDigit = RegExp('[^0-9]');

  static String _two(int n) => n.toString().padLeft(2, '0');

  void _onSearch(String v) {
    final q = v.trim();
    if (q == _query) return;
    setState(() {
      _query = q;
      _items = _filter(_all);
    });
  }

  Future<void> _openWrite() async {
    final now = DateTime.now();
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => DiaryEditorPage(date: DateTime(now.year, now.month, now.day))),
    );
    if (ok == true) await _reload();
  }

  Future<void> _openDetail(DateTime d) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DiaryDetailPage(date: d)),
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 搜索 + 新建
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: _onSearch,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: '搜索日记内容或日期',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _openWrite,
                style: IconButton.styleFrom(backgroundColor: AppColors.primary),
                icon: const Icon(Icons.add, color: Colors.white),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _ErrorView(message: _error!, onRetry: _reload)
                  : _items.isEmpty
                      ? _Empty(query: _query, onWrite: _openWrite)
                      : RefreshIndicator(
                          onRefresh: _reload,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            itemCount: _items.length,
                            itemBuilder: (_, i) {
                              final e = _items[i];
                              final a = AlmanacUtil.of(e.date);
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Material(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: () => _openDetail(e.date),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // 日期块
                                          Container(
                                            width: 46,
                                            padding: const EdgeInsets.symmetric(vertical: 6),
                                            decoration: BoxDecoration(
                                              color: AppColors.surfaceWarm,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Column(
                                              children: [
                                                Text('${e.date.day}',
                                                    style: const TextStyle(
                                                        fontSize: 18,
                                                        color: AppColors.primary)),
                                                Text('${e.date.month}月',
                                                    style: const TextStyle(
                                                        fontSize: 10,
                                                        color: AppColors.textHint)),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Text(
                                                      a.lunarText,
                                                      style: const TextStyle(
                                                          fontSize: 11, color: AppColors.textHint),
                                                    ),
                                                    if (e.mood != null) ...[
                                                      const SizedBox(width: 6),
                                                      Text(e.mood!,
                                                          style: const TextStyle(fontSize: 13)),
                                                    ],
                                                    if (e.weather != null) ...[
                                                      const SizedBox(width: 6),
                                                      Text(e.weather!,
                                                          style: const TextStyle(fontSize: 13)),
                                                    ],
                                                    const Spacer(),
                                                    if (e.mediaLabel.isNotEmpty)
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(
                                                            horizontal: 5, vertical: 1),
                                                        decoration: BoxDecoration(
                                                          color: AppColors.surfaceNeutral,
                                                          borderRadius: BorderRadius.circular(3),
                                                        ),
                                                        child: Text(e.mediaLabel,
                                                            style: const TextStyle(
                                                                fontSize: 10,
                                                                color: AppColors.textSecondaryAlt)),
                                                      ),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  e.preview.isEmpty ? '（仅媒体内容）' : e.preview,
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                      fontSize: 13, height: 1.4, color: AppColors.textPrimary),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.textDisabled),
            const SizedBox(height: 12),
            const Text('日记加载失败',
                style: TextStyle(fontSize: 14, color: AppColors.textSecondaryAlt)),
            const SizedBox(height: 6),
            Text(message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: AppColors.textDisabled)),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重试'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.query, required this.onWrite});

  final String query;
  final VoidCallback onWrite;

  @override
  Widget build(BuildContext context) => EmptyState(
        // 搜索无结果时不显示「写第一篇」按钮（文案会误导），维持原有行为
        actionLabel: query.isEmpty ? '写第一篇' : null,
        onAction: query.isEmpty ? onWrite : null,
        children: [
          Text(
            query.isEmpty ? '还没有日记' : '没有匹配的日记',
            style: const TextStyle(fontSize: 14, color: AppColors.textHint),
          ),
          // 仅在「完全没有日记」时给出引导；搜索无结果时不啰嗦
          if (query.isEmpty) ...[
            const SizedBox(height: 6),
            const Text('记录每天的所见所感',
                style: TextStyle(fontSize: 12, color: AppColors.textDisabled)),
          ],
        ],
      );
}

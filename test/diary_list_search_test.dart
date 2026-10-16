// 日记列表页：加载与搜索（内容 + 日期）的 widget 测试
//
// 背景：曾经有一个真实 bug —— `_filter()` 只在 `_reload()` 内调用，
// 而 `_reload()` 不包含「用户输入」这个触发时机，导致搜索框打字时
// 列表毫无变化。纯函数单测防不住这类「接线断了」的问题，只有从
// TextField 灌文字、看渲染结果的 widget 测试能钉死这条链路。
//
// 数据通过 DiaryListPage 的可选 loader 参数注入，不碰 sqflite。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:calendardiary/user_data/diary_database.dart';
import 'package:calendardiary/user_data/diary_list_page.dart';
import 'package:calendardiary/user_data/diary_repository.dart';

/// 三篇假日记：跨两个月（10 月两篇、9 月一篇），内容含中英文与数字，
/// 用于同时验证内容搜索与日期搜索。
List<DiaryEntryView> _seed() => [
      DiaryEntryView(
        id: 1,
        date: DateTime(2026, 10, 15),
        content: '今天因为栏杆的诉讼去了漳浒寨街道办事处410\n\n'
            '天水项目声光电系统的中标通知书发了\n\n碧水源换芯',
      ),
      DiaryEntryView(
        id: 2,
        date: DateTime(2026, 10, 14),
        content: '今天什么事也没发生',
      ),
      DiaryEntryView(
        id: 3,
        date: DateTime(2026, 9, 13),
        content: '该APP正式生成',
      ),
    ];

Widget _harness(List<DiaryEntryView> data) => MaterialApp(
      home: Scaffold(
        body: DiaryListPage(loader: ({int limit = 1000}) async => data),
      ),
    );

// 三篇日记各自的定位器（按列表卡片上的 preview 文本）。
// 必须限定在 ListView 内——否则搜索框里输入的关键词本身也会被
// textContaining 匹配到（例如输入「天水」后字段文本也是「天水」）。
final _list = find.byType(ListView);
final _e1 = find.descendant(of: _list, matching: find.textContaining('天水')); // 10-15，长文
final _e2 = find.descendant(of: _list, matching: find.text('今天什么事也没发生')); // 10-14
final _e3 = find.descendant(of: _list, matching: find.text('该APP正式生成')); // 09-13

Future<void> _pumpList(WidgetTester tester) async {
  await tester.pumpWidget(_harness(_seed()));
  await tester.pumpAndSettle();
}

Future<void> _search(WidgetTester tester, String q) async {
  await tester.enterText(find.byType(TextField), q);
  await tester.pump();
}

void main() {
  group('DiaryListPage 加载', () {
    testWidgets('初始加载显示全部日记', (tester) async {
      await _pumpList(tester);
      expect(_e1, findsOneWidget);
      expect(_e2, findsOneWidget);
      expect(_e3, findsOneWidget);
    });
  });

  group('DiaryListPage 内容搜索', () {
    testWidgets('输入关键词后列表即时过滤（回归防护：打字必须触发过滤）',
        (tester) async {
      await _pumpList(tester);
      await _search(tester, '天水');
      expect(_e1, findsOneWidget);
      expect(_e2, findsNothing);
      expect(_e3, findsNothing);
    });

    testWidgets('大小写不敏感', (tester) async {
      await _pumpList(tester);
      await _search(tester, 'app');
      expect(_e3, findsOneWidget);
      expect(_e1, findsNothing);
      expect(_e2, findsNothing);
    });

    testWidgets('无匹配时显示空态且不显示「写第一篇」', (tester) async {
      await _pumpList(tester);
      await _search(tester, 'zzzz');
      expect(find.text('没有匹配的日记'), findsOneWidget);
      expect(find.text('写第一篇'), findsNothing);
    });

    testWidgets('清空关键词后恢复全量', (tester) async {
      await _pumpList(tester);
      await _search(tester, '天水');
      expect(_e2, findsNothing);
      await _search(tester, '');
      expect(_e1, findsOneWidget);
      expect(_e2, findsOneWidget);
      expect(_e3, findsOneWidget);
    });
  });

  group('DiaryListPage 日期搜索', () {
    testWidgets('10-15 形式命中 15 号那篇', (tester) async {
      await _pumpList(tester);
      await _search(tester, '10-15');
      expect(_e1, findsOneWidget);
      expect(_e2, findsNothing);
      expect(_e3, findsNothing);
    });

    testWidgets('2026-10-14 完整形式命中 14 号那篇', (tester) async {
      await _pumpList(tester);
      await _search(tester, '2026-10-14');
      expect(_e2, findsOneWidget);
      expect(_e1, findsNothing);
      expect(_e3, findsNothing);
    });

    testWidgets('9月13 中文形式命中 9 月 13 号那篇', (tester) async {
      await _pumpList(tester);
      await _search(tester, '9月13');
      expect(_e3, findsOneWidget);
      expect(_e1, findsNothing);
      expect(_e2, findsNothing);
    });

    testWidgets('10月13 不误命中（13 号在 9 月，10 月无 13 号）', (tester) async {
      await _pumpList(tester);
      await _search(tester, '10月13');
      expect(find.text('没有匹配的日记'), findsOneWidget);
    });

    testWidgets('「10月」按月命中两篇', (tester) async {
      await _pumpList(tester);
      await _search(tester, '10月');
      expect(_e1, findsOneWidget);
      expect(_e2, findsOneWidget);
      expect(_e3, findsNothing);
    });

    testWidgets('紧凑数字 1015 命中 15 号那篇', (tester) async {
      await _pumpList(tester);
      await _search(tester, '1015');
      expect(_e1, findsOneWidget);
      expect(_e2, findsNothing);
      expect(_e3, findsNothing);
    });

    testWidgets('紧凑数字 20260913 命中 9 月 13 号那篇', (tester) async {
      await _pumpList(tester);
      await _search(tester, '20260913');
      expect(_e3, findsOneWidget);
      expect(_e1, findsNothing);
      expect(_e2, findsNothing);
    });
  });

  group('DiaryListPage 搜索与刷新共存', () {
    testWidgets('过滤状态下数据刷新（diaryChanged）仍保持过滤',
        (tester) async {
      await _pumpList(tester);
      await _search(tester, '天水');
      expect(_e1, findsOneWidget);

      // 模拟别处新增/删除日记：走 stream 触发 _reload
      DiaryDatabase.diaryChanged.add(null);
      await tester.pumpAndSettle();

      expect(_e1, findsOneWidget);
      expect(_e2, findsNothing);
      expect(_e3, findsNothing);
    });
  });
}

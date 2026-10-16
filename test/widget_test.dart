// 冒烟测试：确保应用可正常构建并启动。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:calendardiary/main.dart';

void main() {
  testWidgets('App boots without throwing', (WidgetTester tester) async {
    // 用 runAsync 包裹：应用含周期性定时器（录音控制条等），该定时器在真实 async
    // 区创建，不会被 AutomatedTestWidgetsFlutterBinding 的 fakeAsync 定时器断言拦下。
    await tester.runAsync(() async {
      await tester.pumpWidget(const WannianDiaryApp());
      // AppLockGate 初始化（异步读 SharedPreferences）完成后才渲染主页，
      // 轮询等待 MaterialApp 出现。
      for (var i = 0; i < 100; i++) {
        await tester.pump();
        if (find.byType(MaterialApp).evaluate().isNotEmpty) break;
        await Future.delayed(const Duration(milliseconds: 10));
      }
      // 应用顶层为 MaterialApp，且能完成首帧构建
      expect(find.byType(MaterialApp), findsOneWidget);
      await tester.pump();
    });
  });
}

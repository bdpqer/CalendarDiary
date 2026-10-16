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
      // 应用顶层为 MaterialApp，且能完成首帧构建
      expect(find.byType(MaterialApp), findsOneWidget);
      await tester.pump();
    });
  });
}

// 冒烟测试：确保应用可正常构建并启动。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:calendardiary/main.dart';

void main() {
  testWidgets('App boots without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(const WannianDiaryApp());
    // 应用顶层为 MaterialApp，且能完成首帧构建
    expect(find.byType(MaterialApp), findsOneWidget);
    await tester.pumpAndSettle();
  });
}

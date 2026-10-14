import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 小节标题：主色竖条 + 文字
///
/// 原先在 `day_detail_widget.dart`（`_SectionLabel`）与 `diary_editor_page.dart`
/// （`_SectionTitle`）各写了一份，只有竖条高度（13/12）、间距（6/8）与文字颜色
/// 三处细微差异。统一到本组件，差异用参数保留 —— **两处渲染结果与原实现一致**。
class SectionTitle extends StatelessWidget {
  const SectionTitle(
    this.text, {
    super.key,
    this.barHeight = 12,
    this.gap = 8,
    this.color = AppColors.textSecondaryAlt,
    this.padding = const EdgeInsets.only(bottom: 10, top: 2),
  });

  final String text;

  /// 竖条高度
  final double barHeight;

  /// 竖条与文字的间距
  final double gap;

  /// 文字颜色
  final Color color;

  /// 外层内边距
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(
          children: [
            Container(
              width: 3,
              height: barHeight,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(width: gap),
            Text(
              text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      );
}

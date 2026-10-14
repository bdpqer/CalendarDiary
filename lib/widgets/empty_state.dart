import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 通用空状态占位：图标 + 自定义内容 + 可选的主行动按钮
///
/// 原先 `diary_list_page._Empty`（还没有日记 / 搜索无结果）与
/// `diary_detail_page._EmptyView`（某天还没有日记）各写了一份，外层结构
/// （居中 → 32 内边距 → 56 图标 → 24 间距 → 主色按钮）完全相同。
/// 中段内容由 [children] 传入。
///
/// [actionLabel] 与 [onAction] 同时非空时才渲染按钮 ——
/// 「搜索无结果」场景原本就不给「写第一篇」按钮（文案会误导），行为保持不变。
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    this.icon = Icons.menu_book_outlined,
    this.actionLabel,
    this.onAction,
    required this.children,
  });

  final IconData icon;

  /// 按钮文案（如「写第一篇」/「写一篇」）；为 null 则不渲染按钮
  final String? actionLabel;

  final VoidCallback? onAction;

  /// 图标与按钮之间的自定义内容
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final label = actionLabel;
    final action = onAction;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: AppColors.textDisabled),
            const SizedBox(height: 16),
            ...children,
            if (label != null && action != null) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: action,
                icon: const Icon(Icons.add, size: 18),
                label: Text(label),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

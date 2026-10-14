import 'package:flutter/material.dart';

/// 全局配色表
///
/// 统一收敛此前散落在各页面里的硬编码色值（`Color(0xFF...)`）。
/// 以后调整配色只需改这里一处。
///
/// 各字段均为 `static const`，因此可以直接用在 `const` 构造中，
/// 例如 `const TextStyle(color: AppColors.textStrong)`。
class AppColors {
  const AppColors._();

  // ---------------- 品牌主色 ----------------

  /// 主色：描边 / 按钮 / 强调
  static const primary = Color(0xFFC38D4B);

  /// 主色浅描边（悬浮按钮、跳转弹窗边框）
  static const primaryBorder = Color(0xFFE8B98A);

  /// 主色深（棕色系文字：农历月份标签、历史事件前缀、节假日提示）
  static const primaryDeep = Color(0xFFB5714A);

  /// 主色暗（小节标题文字）
  static const primaryMuted = Color(0xFF8A6A4A);

  // ---------------- 状态 / 强调色 ----------------

  /// 日历红：节日 / 周末 / 今天 / 危险操作
  static const red = Color(0xFFE23B2E);

  /// 危险红：删除确认
  static const danger = Color(0xFFC0392B);

  /// 星标黄
  static const star = Color(0xFFE2A53B);

  /// 绿：节气标记 / 次要强调
  static const green = Color(0xFF27AE60);

  /// 橙：节日强调
  static const orange = Color(0xFFD35400);

  /// 录音脉冲高亮
  static const recordPulse = Color(0xFFEC7063);

  // ---------------- 文字 ----------------

  /// 最深（标题 / 工作日数字）
  static const textStrong = Color(0xFF1A1A1A);
  static const textPrimary = Color(0xFF2C2C2A);
  static const textBody = Color(0xFF333333);
  static const textSecondary = Color(0xFF555555);
  static const textSecondaryAlt = Color(0xFF5F5E5A);
  static const textMuted = Color(0xFF666666);
  static const textHint = Color(0xFF888780);
  static const textFaint = Color(0xFF999999);
  static const textPlaceholder = Color(0xFFAAAAAA);
  static const textDisabled = Color(0xFFB4B2A9);

  // ---------------- 背景 / 面 ----------------

  /// 纯白（卡片、Tab 栏）
  static const white = Color(0xFFFFFFFF);

  /// 暖色卡片底（日期信息卡、今日概览）
  static const surfaceWarm = Color(0xFFFCF6F1);

  /// 中性浅底（图片占位、标签底）
  static const surfaceNeutral = Color(0xFFF1EFE8);

  /// 面板底（底部上滑面板 / 今日详情）
  static const surfacePanel = Color(0xFFF5F5F5);

  /// 提示底（节假日提示）
  static const surfaceNotice = Color(0xFFFFF6EC);

  /// 标签底（农历月份标签）
  static const surfaceTag = Color(0xFFF6E3D8);

  // ---------------- 描边 / 分隔 ----------------

  static const borderLight = Color(0xFFEEEEEE);
  static const borderWarm = Color(0xFFE8D5C4);
  static const borderWarmLight = Color(0xFFE3CEB4);
  static const borderNeutral = Color(0xFFBBBBBB);
  static const dividerWarm = Color(0xFFEFE6DC);
  static const dragHandle = Color(0xFFCCCCCC);
  static const bulletDot = Color(0xFFC9A88A);

  // ---------------- 日历专用 ----------------

  /// 农历日文字（灰）
  static const lunarGrey = Color(0xFF9A9A9A);

  /// 「班」调休标记
  static const workBadge = Color(0xFF8A8A8A);
}

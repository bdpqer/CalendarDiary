/// 日记与媒体的纯文本格式化
///
/// 本文件**刻意不导入任何 Flutter / 平台相关库**（无 `dart:ui`、无插件），
/// 因此这些函数可以脱离 UI 环境直接单元测试 —— 这是把它们从
/// `diary_database.dart`（依赖 sqflite / path_provider）里抽出来的原因。
library;

/// 列表页摘要文本：换行合并为空格，超过 60 字截断
///
/// `DiaryEntry`（详情数据）与 `DiaryEntryView`（列表轻量视图）共用此实现。
String diaryPreviewText(String content) {
  final text = content.trim().replaceAll('\n', ' ');
  if (text.isEmpty) return '';
  return text.length <= 60 ? text : '${text.substring(0, 60)}…';
}

/// 媒体摘要文本，如「3图 · 1视频」
///
/// 三类数量均为 0 时返回空串（调用方据此决定是否展示角标）。
String diaryMediaLabel({
  required int imageCount,
  required int videoCount,
  required int audioCount,
}) {
  final parts = <String>[];
  if (imageCount > 0) parts.add('$imageCount图');
  if (videoCount > 0) parts.add('$videoCount视频');
  if (audioCount > 0) parts.add('$audioCount语音');
  return parts.join(' · ');
}

/// 时长的友好文本，如「1分23秒」「7秒」
///
/// 非正值（未采集到时长）返回空串，调用方据此隐藏该字段。
/// 不足 1 秒会被截断为 0 秒，属于预期行为。
String mediaDurationText(int durationMs) {
  if (durationMs <= 0) return '';
  final s = durationMs ~/ 1000;
  final m = s ~/ 60;
  final rest = s % 60;
  if (m > 0) return '$m分$rest秒';
  return '$rest秒';
}

/// 体积的友好文本，如「980 B」「12 KB」「3.4 MB」
///
/// 非正值返回空串。KB 取整、MB 保留一位小数。
String mediaSizeText(int sizeBytes) {
  if (sizeBytes <= 0) return '';
  if (sizeBytes < 1024) return '$sizeBytes B';
  if (sizeBytes < 1024 * 1024) {
    return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
  }
  return '${(sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// mm:ss 计时文本，如 01:23（用于录音条与语音播放进度）
///
/// 不足 1 小时只显示分:秒；超过 1 小时分钟数会回绕（与原始实现一致，
/// 语音/录音场景时长有限，无需小时位）。
String formatClock(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

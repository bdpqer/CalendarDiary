import 'diary_database.dart';
import 'diary_text.dart';

/// 日记列表的轻量视图模型
class DiaryEntryView {
  DiaryEntryView({
    required this.id,
    required this.date,
    required this.content,
    this.mood,
    this.weather,
    this.imageCount = 0,
    this.videoCount = 0,
    this.audioCount = 0,
  });

  final int id;
  final DateTime date;
  final String content;
  final String? mood;
  final String? weather;
  final int imageCount;
  final int videoCount;
  final int audioCount;

  /// 摘要文本（基于纯函数 [diaryPreviewText]）
  String get preview => diaryPreviewText(content);

  /// 媒体摘要，如「3图 · 1视频」（基于纯函数 [diaryMediaLabel]）
  String get mediaLabel => diaryMediaLabel(
        imageCount: imageCount,
        videoCount: videoCount,
        audioCount: audioCount,
      );

  /// 由数据库「列表摘要」投影构造（只含列表所需字段与媒体计数）
  factory DiaryEntryView.fromSummary(DiarySummary s) => DiaryEntryView(
        id: s.id,
        date: s.date,
        content: s.content,
        mood: s.mood,
        weather: s.weather,
        imageCount: s.imageCount,
        videoCount: s.videoCount,
        audioCount: s.audioCount,
      );
}

/// 日记查询门面
class DiaryRepository {
  const DiaryRepository._();

  static final _db = DiaryDatabase.instance;

  /// 读取全部日记摘要（倒序）。只查日记主表 + 三列媒体计数子查询，
  /// 不加载附件行——列表项仅展示数量角标，无需完整附件对象。
  static Future<List<DiaryEntryView>> loadAll({int limit = 1000}) async {
    final summaries = await _db.diarySummaries(limit: limit);
    return summaries.map(DiaryEntryView.fromSummary).toList();
  }
}

/// 统一日期 / 时间格式化工具
///
/// 此前 `yyyy-MM-dd` 的拼装逻辑在 `diary_database`、`day_detail_widget` 中各写了一份，
/// `MM-DD` 在 `history_today` 里另写一份，`M月D日 HH:mm` 又在 `day_detail_widget` 里写一份。
/// 这里集中实现，避免各处 `padLeft` 补零规则出现分歧。
class DateFmt {
  DateFmt._();

  /// yyyy-MM-dd —— 任务归属日与数据库日期键
  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// yyyy-MM（由年、月两个整数拼接，供无 DateTime 对象的场景使用）
  static String yearMonth(int year, int month) =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';

  /// MM-DD —— 「历史上的今天」数据键
  static String monthDayKey(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 提醒时间友好文本：M月D日 HH:mm
  static String remindText(DateTime d) =>
      '${d.month}月${d.day}日 '
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}

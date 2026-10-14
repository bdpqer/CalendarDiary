// 日记纯文本格式化单元测试
//
// `lib/user_data/diary_text.dart` 刻意不导入 Flutter / 插件，属于纯逻辑，
// 因此这里的断言无需任何平台环境即可成立。
import 'package:flutter_test/flutter_test.dart';
import 'package:calendardiary/user_data/diary_text.dart';

void main() {
  group('diaryPreviewText', () {
    test('空内容与纯空白 → 空串', () {
      expect(diaryPreviewText(''), '');
      expect(diaryPreviewText('   \n  '), '');
    });

    test('换行合并为空格，并去掉首尾空白', () {
      expect(diaryPreviewText(' 第一行\n第二行 \n'), '第一行 第二行');
    });

    test('恰好 60 字不截断', () {
      final exactly60 = '字' * 60;
      expect(diaryPreviewText(exactly60), exactly60);
      expect(diaryPreviewText(exactly60).length, 60);
    });

    test('61 字截断为 60 字 + 省略号', () {
      expect(diaryPreviewText('字' * 61), '${'字' * 60}…');
    });
  });

  group('diaryMediaLabel', () {
    test('三类均为 0 → 空串', () {
      expect(
        diaryMediaLabel(imageCount: 0, videoCount: 0, audioCount: 0),
        '',
      );
    });

    test('单类型', () {
      expect(diaryMediaLabel(imageCount: 3, videoCount: 0, audioCount: 0), '3图');
      expect(diaryMediaLabel(imageCount: 0, videoCount: 1, audioCount: 0), '1视频');
      expect(diaryMediaLabel(imageCount: 0, videoCount: 0, audioCount: 2), '2语音');
    });

    test('多类型按 图 · 视频 · 语音 顺序连接', () {
      expect(
        diaryMediaLabel(imageCount: 3, videoCount: 1, audioCount: 2),
        '3图 · 1视频 · 2语音',
      );
    });

    test('跳过为 0 的类型', () {
      expect(
        diaryMediaLabel(imageCount: 2, videoCount: 0, audioCount: 1),
        '2图 · 1语音',
      );
    });
  });

  group('mediaDurationText', () {
    test('非正值 → 空串（未采集到时长时隐藏该字段）', () {
      expect(mediaDurationText(0), '');
      expect(mediaDurationText(-1), '');
    });

    test('不足 1 分钟只显示秒', () {
      expect(mediaDurationText(7000), '7秒');
      expect(mediaDurationText(59999), '59秒');
    });

    test('整分钟补 0 秒', () {
      expect(mediaDurationText(60000), '1分0秒');
    });

    test('分秒组合；超过 60 分不进位为小时', () {
      expect(mediaDurationText(83000), '1分23秒');
      expect(mediaDurationText(3661000), '61分1秒');
    });

    test('边界：999ms 因整除截断为 0 秒（当前实现的既有行为）', () {
      expect(mediaDurationText(999), '0秒');
    });
  });

  group('mediaSizeText', () {
    test('非正值 → 空串', () {
      expect(mediaSizeText(0), '');
      expect(mediaSizeText(-5), '');
    });

    test('小于 1KB 用 B', () {
      expect(mediaSizeText(1), '1 B');
      expect(mediaSizeText(1023), '1023 B');
    });

    test('KB 取整：1024B 即 1KB', () {
      expect(mediaSizeText(1024), '1 KB');
      expect(mediaSizeText(1024 * 12), '12 KB');
    });

    test('MB 保留一位小数', () {
      expect(mediaSizeText(1024 * 1024), '1.0 MB');
      expect(mediaSizeText((3.4 * 1024 * 1024).round()), '3.4 MB');
    });
  });
}

# 日历日记 CalendarDiary

一个保留完整日历功能、以多媒体日记为核心的 Flutter 应用：日历 / 日记 / 设置三个 Tab，支持农历黄历、图文音视频日记、星标事项与精确闹钟提醒，数据全部本地存储、离线可用。

## 功能特性

**日历**
- 可无限上下滑动的多月份日历（1900 年起，滚动近底部自动扩展）
- 农历 / 干支 / 生肖 / 节气 / 冲煞 / 喜神 / 财神（基于 [lunar](https://pub.dev/packages/lunar) 库封装）
- 国务院办公厅放假安排内置数据（法定假日 / 调休上班，离线可用）
- 「历史上的今天」按 MM-DD 索引
- 日期跳转（双轮年月选择器）、回今天、有日记日期红点标记

**日记**
- 图文 / 视频 / 语音多媒体日记，媒体文件导入应用私有目录
- 心情 / 天气标签，正文摘要自动截断
- 日记列表按媒体数量角标展示

**事项与提醒**
- 当日事项（完成 / 星标 / 删除）
- 事项提醒基于精确闹钟（`flutter_local_notifications` + 时区），Android 14+ 未授权时自动降级为近似提醒

## 技术栈

| 领域 | 选型 |
| --- | --- |
| 框架 | Flutter 3.47 / Dart 3.13 |
| 数据库 | sqflite（diary / attachment / task 三表） |
| 农历算法 | lunar |
| 媒体 | image_picker（图片）、record（录音）、video_player + audioplayers（播放） |
| 通知提醒 | flutter_local_notifications + timezone |
| 其他 | path_provider、permission_handler、intl、flutter_localizations |

## 目录结构

```
lib/
├── main.dart                    # 入口
├── home/                        # 主界面三 Tab
│   ├── homepage.dart            #   日历主页（无限滚动月份列表 + 底部今日面板）
│   ├── diary_list_page.dart     #   日记列表
│   ├── diary_editor_page.dart   #   日记编辑器
│   ├── diary_detail_page.dart   #   日记详情
│   ├── day_detail_widget.dart   #   当日事项 / 今日面板
│   ├── settings_page.dart       #   设置 / 统计 / 关于
│   ├── calendar_list/           #   月份日历组件
│   └── widgets/media_widgets.dart
├── user_data/                   # 数据层
│   ├── diary_database.dart      #   SQLite 建表 / 迁移 / 查询
│   ├── diary_repository.dart    #   查询门面 + DiaryEntryView
│   ├── diary_text.dart          #   纯函数：摘要 / 媒体角标 / 时长格式化
│   ├── media_capture_service.dart
│   └── task_reminder.dart       # 通知与闹钟调度
├── date_base/                   # 日期与静态数据
│   ├── almanac.dart             #   农历 / 干支 / 节气封装
│   ├── date_fmt.dart            #   日期格式化
│   ├── holiday_data.dart        #   节假日安排
│   └── history_today.dart       #   历史上的今天
├── theme/app_colors.dart
└── widgets/                     # SectionTitle / EmptyState 等共用组件
```

## 快速开始

```bash
flutter pub get
flutter run          # 连接设备后运行
flutter build apk    # 出品
```

包名 `me.iweek.CalendarDiary`，数据库 `calendardiary.db`（内置自旧版 `wanniandiary.db` 的一次性迁移）。

## 开发备注

- **本地补丁**：`patched_audioplayers_android/` 是对 `audioplayers_android 5.3.0` 的本地覆盖（`dependency_overrides`），用 `setCommunicationDevice`（API 31+）替换已废弃的 `AudioManager.isSpeakerphoneOn`，消除两条编译警告。上游修复后可移除覆盖并删除该目录。
- **工具链**：Gradle 8.14.1 / AGP 8.13.0 / Kotlin 2.2.20。
- **静态检查**：`flutter analyze` 零告警。
- **测试**：`flutter test`（日期格式、文本摘要、日历布局单测）。

## 数据与隐私

所有日记、媒体文件与提醒均存储于本机应用沙箱，不访问网络、无账号体系。

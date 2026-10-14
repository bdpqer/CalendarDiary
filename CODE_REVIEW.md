# 日历日记（wanniandiary）代码审查报告

> 审查范围：`lib/`（17 个 Dart 文件，5565 行）+ `android/app/src/main/`（5 个 Kotlin 文件）+ `pubspec.yaml`
> 审查日期：2026-10-13 · 版本：v4.2.0+1

## 一、总体评价

整体架构清晰、分层合理（`data_base` 静态数据 / `date_base` 算法 / `user_data` 数据层 / `home` 表现层），
注释质量高，SQLite 设计规范（有索引、有外键、有版本迁移），原生闹钟链路的降级处理（精确→近似、前台服务响铃）
体现了对国产 ROM 的实战经验。**代码可用性好，主要问题是「死代码残留 + 可抽象的重复逻辑 + 工程卫生」三类。**

问题总计 **23 项**：P0 级 0 项、P1 级 5 项、P2 级 9 项、P3 级 9 项。

---

## 二、P1：建议优先处理（真实缺陷 / 明确冗余）

### P1-1 ⚠️ `deleteFile` 在异步流程中被同步调用，可能漏删文件

**位置**：`lib/user_data/diary_database.dart:411-419`（`delete`）、`:566-577`（`clearAll`）

```dart
Future<void> delete(int id) async {
  final atts = await db.query('attachment', where: 'diary_id = ?', whereArgs: [id]);
  await db.delete('diary', where: 'id = ?', whereArgs: [id]);
  for (final a in atts) {
    deleteFile(a['path'] as String);   // ← 同步 IO，在 async 函数里裸调用
  }
}
```

`deleteFile` 内部用 `existsSync()` / `deleteSync()` 做同步磁盘 IO。在批量删除（清空全部日记）时，
若附件多达数百个，会阻塞 UI 线程造成卡顿掉帧。

**建议**：改为 `Future<void> deleteFileAsync(String path)`，用 `await f.exists()` + `await f.delete()`；
或至少在循环外包一层 `await Future(() { ... })` 让出事件循环。

---

### P1-2 ⚠️ 附件全量重建会产生「孤儿文件」——旧媒体不删除

**位置**：`lib/user_data/diary_database.dart:374-408`（`save`）

```dart
// 全量重建附件关联
await db.delete('attachment', where: 'diary_id = ?', whereArgs: [id]);
```

只删了数据库记录，**没有删除对应的物理文件**。用户在编辑器里删掉一张图片再保存，
该图片文件永久遗留在 `diary_media/<year>/` 下，且不再被任何记录引用 → 磁盘只增不减。

**建议**：删除附件记录前先查出 `path` 列表，保存成功后（或删除前）删除这些文件；
注意排除「本次仍保留」的路径（编辑器重新保存时会重新导入同一路径）。

---

### P1-3 `allEntries` 的子查询绕路，可简化为直接按 diary_id 查

**位置**：`lib/user_data/diary_database.dart:349-371`

```dart
final attRows = await db.rawQuery(
  'SELECT a.* FROM attachment a '
  'WHERE a.diary_id IN (SELECT id FROM diary ORDER BY date DESC LIMIT ?) '
  'ORDER BY a.sort_order ASC',
  [limit],
);
```

问题：① 子查询里重复了一次 `ORDER BY date DESC LIMIT ?` 全表排序；
② 若日记总数超过 `limit`，子查询语义与主查询一致（能对上），但**当主查询与子查询的排序在中途数据变化时会不一致**；
③ 更直接的问题——外层没有按 diary 分组，返回的是全部附件的大列表，然后 Dart 侧用 `putIfAbsent` 归组。

**建议**：既然已拿到 `list`（当页日记），直接 `IN` 这些 id 即可，语义更明确、少一次排序：

```dart
final ids = list.map((e) => e.id!).toList();
final placeholders = List.filled(ids.length, '?').join(',');
final attRows = await db.rawQuery(
  'SELECT * FROM attachment WHERE diary_id IN ($placeholders) ORDER BY sort_order ASC',
  ids,
);
```

（`ids.length` 在 `limit=1000` 时约 1000 个占位符，SQLite 默认上限是 999——
**因此当前写法其实是在规避参数上限**。若要改，需改用分批 IN（每批 500）或保留现方案并补注释说明。）

> 结论：这一项目前**功能正确**，属于「可读性优化」，不必强行改。列为 P1 仅因注释未说明「为何用子查询」。

---

### P1-4 `Timeline` 无关，但 `_offsetForIndex` 是 O(n) 累加，跳转远期年份时明显

**位置**：`lib/home/homepage.dart:177-183`

```dart
double _offsetForIndex(int index, {double? width}) {
  double sum = 0;
  for (int i = 0; i < index; i++) {
    sum += _monthHeight(_monthAt(i), width: width);
  }
  return sum;
}
```

锚点是 **1900-01**。跳转到 2050 年时 index ≈ 1800，即循环 1800 次；
跳转到 2100 年（选择器上限）时 index ≈ 2400，每次 `_monthAt` 都新建 `DateTime` 并调用
`MonthCalendarCard.extentFor`（内含天数计算）。

**建议**：① 绝大多数月份是 5 行或 6 行，高度只有 4~6 三种取值，可按「月份 → 行数」预计算一次前缀和缓存；
② 或把锚点从 1900 改为「当前年 - 20 年」，直接把 index 降到 ~240 以内，同时保持向上无限滚动不变。
（顺带：`_MonthJumpDialog` 的 `_minYear=1900` 与 `_baseYear=1900` 是硬编码耦合，改锚点需同步。）

---

### P1-5 pubspec 声明的 `shared_preferences` 完全未被使用

**位置**：`pubspec.yaml` 依赖 `shared_preferences: ^2.3.3`
**验证**：`grep -rn "SharedPreferences" lib/` → 无任何匹配。

同时「设置」页的两个开关 `_showFestival` / `_showDiaryDot`
（`lib/home/settings_page.dart:22-23`）**只存在于 State 中，没有持久化、也没有真正生效**：

- 切 Tab 后依赖 `IndexedStack` 保活才不丢失，杀进程即重置；
- `MonthCalendarCard` / `DayCellNew` 从未接收这两个开关，改开关**界面上没有任何变化**。

**建议**：二选一——
① 用 `shared_preferences` 真正落地开关并透传到日历组件（这才是该依赖被引入的原始意图）；
② 若决定不做，删除 `shared_preferences` 依赖与这两个无效开关，避免「看起来能用其实没用」的假功能。

---

## 三、P2：冗余与重复逻辑

### P2-1 日期 key 格式化在 4 处重复实现

| 位置 | 形式 | 用途 |
|---|---|---|
| `diary_database.dart:560-563` | `_dateKey` / `_pad4` / `_pad2` | 任务归属日 `yyyy-MM-dd` |
| `day_detail_widget.dart:586-589` | 顶层 `_dateKey` | 新建任务归属日 |
| `day_detail_widget.dart:592-594` | 顶层 `_timeText` | 提醒时间文案 |
| `history_today.dart:46-48` | `keyOf` | 历史数据 `MM-DD` |

`diary_database._dateKey` 与 `day_detail_widget._dateKey` **实现完全相同**，属于直接复制。

**建议**：抽到 `lib/date_base/` 下统一工具（如 `DateFmt.dayKey(DateTime)` / `DateFmt.timeHm(DateTime)`），
或直接改用已在依赖里的 `intl`：`DateFormat('yyyy-MM-dd')` / `DateFormat('M月d日 HH:mm')`。
（`intl` 已被 `diary_editor_page` / `diary_detail_page` 使用，不引入新依赖。）

### P2-2 `DiaryEntry.preview` / `mediaLabel` 与 `DiaryEntryView` 完全重复

**位置**：`diary_database.dart:128-142` vs `diary_repository.dart:25-39`

两个类的 `preview` 与 `mediaLabel` 逻辑逐字相同，只是数据源一个走 `attachments.where(...)`、
一个走已算好的 `imageCount` 等字段。此外 `DiaryEntryView.from` 里再次遍历 `attachments` 三次
（`images` / `videos` / `audios` 各筛一遍）。

**建议**：`DiaryEntry` 增加 `imageCount` / `videoCount` / `audioCount` 三个 int getter（一次遍历），
`DiaryEntryView.from` 直接复用；`preview` 提到一个 mixin 或顶层扩展函数上。

### P2-3 `_Checkbox`/`_EmptyView` 等空状态视图重复

`diary_list_page.dart` 的 `_Empty`（`:276`）与 `diary_detail_page.dart` 的 `_EmptyView`（`:313`）
结构高度相似（图标 + 日期 + 农历 + 按钮），可合并为一个参数化组件。

### P2-4 `_SectionLabel` 与 `_SectionTitle` 重复

`day_detail_widget.dart:712` 的 `_SectionLabel`（3×13 竖条 + 文字）与
`diary_editor_page.dart:489` 的 `_SectionTitle`（3×12 竖条 + 文字）是同一视觉组件的两份实现，
仅字号差 0 与高度差 1。建议抽到 `lib/home/widgets/` 共用。

### P2-5 颜色常量散落，未统一管理

`CalColors` 只覆盖了日历格子用色（6 个）。但实际代码中**硬编码**了大量hex色值：

```
0xFFC38D4B（主色）出现 20+ 次    0xFFE23B2E（红）出现 10+ 次
0xFFFCF6F1 / 0xFFE8D5C4 / 0xFFF1EFE8 / 0xFF2C2C2A / 0xFF5F5E5A
0xFF888780 / 0xFFB4B2A9 / 0xFF999999 / 0xFFAAAAAA ...
```

同一语义（如主色 `0xFFC38D4B`）在 7 个文件里各自出现，改配色需要全局搜索替换。

**建议**：扩展 `CalColors`（或新建 `AppColors`）补齐主色/正文/次要/占位/卡片底色/边框，
全部替换为常量引用。这也是**成本最低、收益最直接**的一项重构。

### P2-6 `mediaLabel`／`preview` 等纯字符串逻辑未做单元测试

`test/widget_test.dart` 只有 1 个冒烟测试（14 行），项目**没有任何针对业务逻辑的测试**。
`DiaryEntry.preview` 的截断、`durationText` / `sizeText` 的边界、`AlmanacUtil.weekdayCn`、
`HolidayData.of`、`_weekOfYear` / `_dayOfYear` 都是纯函数，测试成本极低、收益很高。
建议至少补齐纯函数测试。

### P2-7 `_AlmanacCard` 与 `_TodoCard` 各自 new 了 StatefulWidget 做数据加载

两个卡片都以「`didUpdateWidget` 判断 date 变化 → 重新查库」的模式加载，逻辑雷同。
可抽一个「按日期加载」的通用 StatefulWidget 包装，或引入简单的 `FutureBuilder` 以消除重复样板。

### P2-8 死代码：`lib/home/cards/today_card.dart` 整个文件 186 行无人引用

`grep -rn "today_card" lib/` → 无任何 import。该文件是旧版「当日信息卡」，
已被 `day_detail_widget.dart` 的 `TodaySheet` 完全取代。

### P2-9 `AlmanacUtil` 有 17 个 getter/方法从未被外部使用

`DayAlmanac` 里 `nineStar` / `fuShen` / `taiShen` / `naYin` / `pengZu` / `zhiXing` /
`tianShen` / `daySha` / `yiJiText` / `yearGanZhi` / `monthGanZhi` / `dayGanZhi` /
`isLeapMonth` / `shengXiaoText` / `day` / `month` / `year`，
以及 `AlmanacUtil.weekdayShort` / `solarText` / `daysInMonth` / `HolidayData.hasYear`
—— **全部无调用方**（仅 `TodayCard` 用了 `yi/ji/chongSha/caiShen/xiShen`，而它本身是死代码）。

其中 `chongSha` / `caiShen` / `xiShen` 在 `_AlmanacCard` 中有使用，属有效。
其余属「移植原小枣日历时的接口预留」。`lunar` 库的 getter 是惰性计算的，不调用不产生开销，
但**代码体积与认知负担**是实实在在的。

**建议**：保留确有规划的部分，其余删除；若希望「保留完整黄历能力」，至少在文件头注释说明是预留接口。

---

## 四、P3：工程卫生与细节

| 编号 | 问题 | 位置 | 建议 |
|---|---|---|---|
| P3-1 | 根目录堆积 **46 个 `.log` + 14 个 `_*.png` + 13 个 `_*.db`**，共约 4.5 MB 调试残留 | 项目根目录 | 清理；`.gitignore` 已忽略 `*.log`，但 `_*` 未忽略，建议补 `_*` 规则 |
| P3-2 | `build/` 已 **2.0 GB**、`.dart_tool/` 156 MB | 项目根 | `flutter clean` 可回收约 2.1 GB |
| P3-3 | `HomePage` 遗留 3 处 `debugPrint('[WND] ...')` | `homepage.dart:79,238` | 生产构建应移除或降级为 `assert` 包裹 |
| P3-4 | `DayCellNew` 内 `CalendarDiary` 的分享按钮 `onTap: () {}` 空实现 | `calendar_view.dart:316-317` | 未实现的功能应隐藏按钮，避免用户点击无反应 |
| P3-5 | `MainActivity.kt` 的 `WINDOW_MILLIS` 常量未被使用（实际用 `AlarmScheduler` 内的同名常量） | `MainActivity.kt:45` | 删除未使用常量 |
| P3-6 | `TaskAlarmReceiver.kt` 导入了 `MediaPlayer` / `MediaPlayer` 相关但响铃已挪到 `AlarmService` | `TaskAlarmReceiver.kt` | 清理未使用 import（`MediaPlayer`、`AlarmScheduler.WINDOW_MILLIS` 等） |
| P3-7 | `TaskAlarmReceiver.RING_MILLIS` 常量未被使用（实际时长在 `AlarmService.RING_TOTAL_MILLIS`） | `TaskAlarmReceiver.kt:底部 companion` | 删除 |
| P3-8 | `Manifest` 中 `foregroundServiceType="mediaPlayback"` 需确认已声明；`BootReceiver` 需 `RECEIVE_BOOT_COMPLETED` | `AndroidManifest.xml` | 复查（本次未展开 `values/` 目录，建议自行核对） |
| P3-9 | `media_capture_service.checkRecording()` 无调用方；`playVideos` 循环串行 pick，选第 2 个时若取消会 break 丢掉已选 | `media_capture_service.dart:75-84,134` | 移除死方法；视频多选建议改用 `pickMultiImage` 风格的批量 API（`image_picker` 无视频批量 API，属库限制，至少补注释说明） |

---

## 五、优先级建议路线图

**第一批（半天，低风险高收益）**
1. 清理根目录 73 个临时文件 + `flutter clean` 回收 2.1 GB（P3-1/2）
2. 扩充 `CalColors` 统一配色常量（P2-5）
3. 删除 `today_card.dart` 死文件 + `shared_preferences` 依赖（P2-8 / P1-5）
4. 清理 Kotlin 未使用 import 与常量（P3-5/6/7）

**第二批（涉及逻辑改动）** ✅ 已完成，见第八节

5. ✅ 修复附件重建的孤儿文件问题（P1-2）—— **唯一的真实数据/磁盘缺陷**（另追加修复「导入即落盘」的同类漏网路径）
6. ✅ `deleteFile` 改异步（P1-1，并顺带清空 `lib/` 全部同步文件 IO、新增目录归属校验防误删相册原图）
7. ✅ 抽取日期格式化工具，消除 4 处重复（P2-1）
8. ✅ 合并 `preview` / `mediaLabel` 重复实现（P2-2，并加入一次遍历的 `mediaCounts`）

**第三批** ✅ 已完成，见第十节

9. ✅ `_offsetForIndex` 改为 O(1) 前缀和（P1-4）；经评估**未采用「缩短锚点」方案**，理由见第十节
10. ✅ 决策结论：**保持移除**两个开关（不为其重新引入依赖，也不保留空实现）
11. ✅ 补齐纯函数单元测试（P2-6）—— 新增 `lib/user_data/diary_text.dart` + 3 个测试文件
12. ✅ 清理 `audioOutputPath()` 死代码 + 启动时孤儿文件清扫（经确认后实施，带三重安全约束）

**第四批** ✅ 已完成，见第十二节

13. ✅ 合并两组重复组件（P2-3 / P2-4）—— 抽出 `lib/widgets/section_title.dart` 与 `lib/widgets/empty_state.dart`
14. ⏭️ **未做**：`_AlmanacCard` / `_TodoCard` 抽通用「按日期加载」包装（P2-7）—— 理由见第十二节
15. ✅ 清理 `AlmanacUtil` 无调用方 getter（P2-9；实际 **22 个**，含同样早已无调用方的 `yi` / `ji`）
16. ⏸️ **保留待处理**：分享按钮（P3-4，按你的决定不动）；✅ `checkRecording` 死方法已删（P3-9）

**第四批追加：另一份分析报告中的 P0（复核后确认属实，一并修复）**

17. ✅ 编辑日记会把 `created_at` 重置为「现在」（数据丢失）
18. ✅ 删除日记遗留 `attachment` 僵尸行（外键从未启用，`ON DELETE CASCADE` 形同虚设）
19. ✅ 性能/健壮性三项：`stats()` 全表加载改 SQL 聚合、`AlmanacUtil._cache` 加容量上限、视频初始化补异常保护

---

## 六、值得肯定的部分

- 数据库设计规范：三张表均有索引，外键级联，`onUpgrade` 有版本迁移分支
- `DiaryDatabase._withDb` 的「失败清空缓存 + 重试」模式处理得当
- `StreamController.broadcast` 的事件驱动刷新，解决了 `IndexedStack` 常驻页面的跨 Tab 同步问题
- 原生闹钟链路对国产 ROM 的适配（前台服务响铃 + 音频焦点 + 渠道删建）注释详实，实战价值高
- `MonthCalendarCard.extentFor` 与 `SliverVariedExtentList` 的高度同步设计，解决了可变高度列表的精确定位问题
- 依赖修复 `dependency_overrides: record_linux` 的注释解释了上游约束不自洽的根因，非常专业

---

## 七、第一批执行记录（2026-10-13 已完成）

> 执行前已完整备份至 `D:/project/_wanniandiary_backup_20261013_2328/`（含 `lib/`、Kotlin 源码、`pubspec.yaml`、`test/`，以及抢救出的 debug APK）。

### 1. 工程卫生清理（P3-1 / P3-2）

| 项目 | 结果 |
|---|---|
| 根目录调试残留 | 删除 **76 个**（44 个 `flutter_XX.log`、`_analyze.log`、`_build.log`、13 个 `_db*.db`、14 张截图 png、若干脚本输出文本），约 4.5 MB |
| `build/` | 删除，回收 **2.0 GB**（删除前先救出 `app-debug.apk` 存入备份目录） |
| `.dart_tool/` | **保留**（156 MB，含 `package_config.json`，删除会破坏 IDE 索引，须重跑 `pub get` 才能恢复） |
| `.gitignore` | 补充 `/_*` 规则，防止调试残留再次入库 |

> D 盘此前已濒临写满（118G 中 117G 已用，仅剩 313 MB），本次回收的 2.0 GB 有实际意义。

### 2. 配色常量化（P2-5）

- 新增 `lib/theme/app_colors.dart`，定义 **35 个**语义化常量（品牌主色 / 状态色 / 文字 / 背景 / 描边 / 日历专用）。
- 替换 **129 处** `Color(0xFF...)` + **29 处** `CalColors.X`，涉及 9 个文件。
- 删除 `calendar_view.dart` 中的 `CalColors` 类（字段已全部并入 `AppColors`）。
- 所有字段均为 `static const`，故原先的 `const TextStyle(...)` / `const BoxDecoration(...)` 等 const 上下文**依然成立**，不会引入编译错误。

### 3. 死代码与无用依赖（P2-8 / P1-5）

- 删除 `lib/home/cards/today_card.dart`（186 行，全项目 0 引用）及遗留的空目录 `cards/`。
- 移除 `pubspec.yaml` 中的 `shared_preferences`（全项目 0 引用）。
- **同步修改 `GeneratedPluginRegistrant.java`**：移除其中的 `SharedPreferencesPlugin` 注册。该文件虽标注「自动生成」，但若保留对已删除插件的引用，Android 侧会**直接编译失败**。
- 移除设置页两个**空实现开关**（`_showFestival` / `_showDiaryDot`）及配套 `_SwitchRow` 组件。这两个开关既不持久化、也未透传给日历组件，拨动无任何视觉变化。

> ⚠️ **待决策**：若要保留「显示节日与节气 / 显示日记标记」开关，需做真正的实现（持久化 + 透传到 `MonthCalendarCard` → `DayCellNew`）。建议单独作为一个任务。

### 4. Kotlin 侧清理（P3-5 / P3-6 / P3-7）

| 文件 | 清理内容 |
|---|---|
| `MainActivity.kt` | 删除未使用常量 `WINDOW_MILLIS` |
| `TaskAlarmReceiver.kt` | 删除未使用 import `android.media.MediaPlayer`；删除未使用常量 `RING_MILLIS` |
| `AlarmService.kt` | 删除未使用常量 `TAG`（该类无 `Log` 调用，仅写文件日志） |

所有 `companion object` 结构复核无误，其余常量（`EXTRA_*`、`CHANNEL`、`FGS_*`、`RING_TOTAL_MILLIS`、`TAG`）均确认仍在使用。

### 5. 校验方式与结论（重要）

本机 **无法运行完整类型检查**：`flutter --version` 与 `dart analyze` 在派生子进程时均报
`CreateFile failed 231`（OS error 231 = `ERROR_PIPE_BUSY`，管道资源耗尽），带沙箱跳过亦无效，属环境限制。

因此改用以下组合校验：

| 校验项 | 方法 | 结果 |
|---|---|---|
| 语法正确性 | `dart format --output=none lib`（进程内解析，仅校验不写入） | 17 个文件全部解析通过，退出码 0 |
| 常量定义/使用一致性 | 提取全部 `AppColors.X` 与定义列表求差集 | 用到但未定义 = **0**；定义但未使用 = **0** |
| 硬编码色值残留 | `grep '0xFF[0-9A-Fa-f]{6}'`（排除配色表） | **0** |
| 旧引用残留 | `grep 'CalColors'` | **0** |
| import 完整性 | 逐个检查使用 `AppColors` 的文件 | **9/9** 均正确导入 |
| 逐文件 diff | 与备份逐一对比 | 变更均为预期内容，无意外改动 |

**尚未覆盖**：类型层面的错误。由于替换前后表达式类型完全一致（都是 `Color` 常量），此类风险极低。
**建议在能运行 `flutter analyze` 的环境跑一次确认。**

### 6. 一个值得记录的坑：行尾符

原项目**行尾符不统一**：`main.dart` 为 CRLF，其余 Dart 文件均为 LF。

批量替换脚本经 Python `read_text()` / `write_text()` 处理时，会把 LF 文件整体转成 CRLF ——
**内容完全正确，但 diff 会显示成整个文件被重写**，严重干扰复核（正是如此，本次一度出现 `-384 +371` 这种假象）。
已全部还原为各自原本的行尾符。

> 后续再做批量文本处理时，务必使用**二进制读写**（`read_bytes` / `write_bytes`），或显式指定 `newline=''`。

---

## 八、第二批执行记录（2026-10-13 已完成）

> 改动前已快照至 `D:/project/_wanniandiary_backup_batch2_20261013_2340/`（`lib/` + `pubspec.yaml`）。
> 涉及 5 个文件修改 + 1 个新文件。

### 1. 附件重建的孤儿文件（P1-2）—— 本轮唯一的真实数据/磁盘缺陷

**问题**：`save()` 全量重建附件关联时只删数据库记录，物理文件永久留在 `diary_media/` 且无人引用。

**修复**（`diary_database.dart` `save()`）：重建前先查出该日记的旧附件路径，与「本次仍保留」的路径集合求差；
重建完成、数据库已与新状态一致后，再删除差集对应的物理文件。

```dart
final kept = entry.attachments.map((a) => p.normalize(a.path)).toSet();
// … 旧路径中不在 kept 内的 → stalePaths …
await db.delete('attachment', where: 'diary_id = ?', whereArgs: [id]);
// … 重新插入本次附件 …
entry.id = id;
await _deleteFiles(stalePaths);   // 数据库已一致，此时再删盘
```

> 判断依据：编辑器加载已存媒体时**沿用原路径**，因此「路径字符串相同」即等价于「仍被引用」，无需额外匹配逻辑。

### 2. 追加修复：编辑期「导入即落盘」的孤儿文件（本轮新发现，同源且更早发生）

`save()` 只能清理**进过数据库**的文件。但编辑器在选图 / 拍照 / 录像 / 录音时就已经把文件写进应用私有目录 ——
若用户**移除后又保存**，或**直接放弃编辑**，这些文件**从未进过数据库**，原方案完全覆盖不到。

**修复**（`diary_editor_page.dart`）：新增 `_sessionImports` 集合跟踪本次会话新导入的路径。

| 时机 | 行为 |
|---|---|
| 导入成功（相册 / 拍照 / 录像 / 录音共 5 个入口） | 路径记入 `_sessionImports` |
| 用户点删除 | 若属本次新导入 → 立即删盘并从集合移除（老附件仍交由 `save()` 的统一清理） |
| 保存成功 | 清空集合（路径已入库，转由数据库管理） |
| 页面销毁（放弃编辑 / 异常退出） | 清理集合中所有未入库文件 |

### 3. `deleteFile` 异步化（P1-1）

| 项目 | 改动 |
|---|---|
| `deleteFile` | `existsSync/deleteSync` → `await exists()/await delete()`，返回 `Future<void>` |
| 调用点 | `delete()` / `clearAll()` 改为 `await _deleteFiles(...)` |
| 新增 `_deleteFiles` | 用 `Future.wait` 并发删除，避免数百附件时逐个串行等待 |
| 同文件 `mediaDir` / `importFile` | `existsSync` / `createSync` → `await dir.create(recursive: true)` / `await src.exists()` |
| `media_capture_service.dart` | `stopRecording` / `cancelRecording` / `_newVoicePath` / `_importOne` 四处同步 IO 一并异步化 |

结果：在 `lib/` 下检索 `existsSync()`、`deleteSync()`、`createSync(`、`lengthSync()`，**全部归零**。

### 4. ⚠️ 顺带修掉一个更危险的隐患：可能误删用户相册原图

`importFile` 在「跨分区复制失败」时会**回落返回原始相册路径**，而原 `deleteFile` 无条件删除 ——
一旦这种记录落库，删除该日记或「清空所有日记」就会**删掉用户相册里的原图**。

新 `deleteFile` 增加了归属校验，只处理 `diary_media/` 目录内的文件：

```dart
final root = await _mediaRootDir();      // <app docs>/diary_media，进程内缓存
if (!p.isWithin(root, target)) return;   // 目录外一律不动
```

### 5. 日期格式化去重（P2-1）

新增 `lib/date_base/date_fmt.dart`，4 个方法按需替换：

| 新方法 | 替换掉 |
|---|---|
| `DateFmt.dayKey` | `diary_database._dateKey`、`day_detail_widget._dateKey`（两份逐字完全相同） |
| `DateFmt.remindText` | `day_detail_widget._timeText` |
| `DateFmt.monthDayKey` | `history_today.keyOf` |
| `DateFmt.yearMonth` | `diary_database` 内的 `_pad4 / _pad2` 拼接 |

同时删除 `diary_database._dateKey / _pad4 / _pad2`、`day_detail_widget._dateKey / _timeText`、`history_today.keyOf`。

> `almanac.dart` 的私有 `_keyOf`（`'y-m-d'`，**不补零**）未动 —— 它只是内部缓存键，与对外日期键语义无关。

### 6. `preview` / `mediaLabel` 重复实现合并（P2-2）

- 抽出顶层函数 `diaryPreviewText(String)` 与 `diaryMediaLabel({imageCount, videoCount, audioCount})`
  （放在 `diary_database.dart`；`diary_repository.dart` 本就 import 该文件，无需新增依赖）。
- `DiaryEntry.preview` / `DiaryEntryView.preview` 均改为委托，`mediaLabel` 同理。
- `DiaryEntry` 新增 `mediaCounts` —— **一次遍历**得出三类数量；
  原先 `DiaryEntryView.from` 连续三次 `where(...).toList()`，每次都新建一个列表。
- `DiaryEntryView.from` 改用 `e.mediaCounts`。

---

## 九、第二批校验结论与遗留项

### 校验方式（本机仍无法运行完整类型检查，原因见第七节）

| 校验项 | 方法 | 结果 |
|---|---|---|
| 语法正确性 | `dart format --output=none lib` | 18 个文件全部解析通过，退出码 0 |
| 行尾符 | Python 二进制比对（吸取第一批教训） | 全部 LF，无一行被整体改写 |
| 旧符号残留 | `_dateKey` / `_pad4` / `_pad2` / `_timeText` / `keyOf` | **均为 0** |
| 同步 IO 残留 | `existsSync()` / `deleteSync()` / `createSync(` / `lengthSync()` | **0** |
| 新增符号一致性 | `DateFmt` 定义 vs 使用求差集 | 未定义 0 / 未使用 0 |
| 逐文件 diff | 与第二批前快照比对 | 改动均与预期一致，无意外行 |

**仍未覆盖**：类型层面错误。本次涉及泛型集合、**记录类型**（`({int image, int video, int audio})`）
与 `Future<void>` 的传播，类型风险高于第一批（第一批只是等价的 `Color` 常量替换）。
**建议在能运行 `flutter analyze` 的环境确认一次。**

### 本轮新增发现（建议纳入第三批）

1. **`audioOutputPath()` 是死代码**：`diary_database.dart:526`，全项目 0 调用；
   其功能与 `media_capture_service._newVoicePath()` 重复。属「重复实现 + 死代码」双重问题。
2. **进程被系统杀死时仍会漏清理**：`dispose()` 在进程被杀时不会执行，编辑中未保存的导入文件仍可能残留（概率低）。
   根治需在启动时做一次「孤儿文件清扫」：列出 `diary_media/` 下文件，与数据库路径集合求差，
   删除**未被引用且超过 24 小时**的文件（时间阈值用于避开正在编辑中的文件）。本次未实施。
3. **`DiaryEntry.preview` / `mediaLabel` 当前无调用方**（列表页走的是 `DiaryEntryView`）。
   已保留为模型 API 且不再重复实现；若追求精简可一并移除。

---

## 十、第三批执行记录（2026-10-13 已完成）

> 改动前快照：`D:/project/_wanniandiary_backup_batch3_20261013_2347/`（`lib/` + `test/` + `pubspec.yaml`）。
> 涉及 5 个文件修改 + 4 个新文件（1 个 lib、3 个 test）。

### 1. 滚动偏移 O(n) → O(1)（P1-4）

**思路**：把 `extentFor` 展开后会发现，只有「周数」是随月份的变量 ——

```
卡片高度 = fixedHeight（标题48 + 表头22 + 间隔4） + rowsFor(月份) × 格子高度(宽度)
```

于是第 index 个月的累计偏移可以直接写成：

```
offset(index) = index × fixedHeight + rowsPrefix(index) × cellHeight(width)
```

- `MonthCalendarCard` 新增 `fixedHeight` 常量与 `cellHeightFor(width)`，`extentFor` 改为复用二者（**代数完全等价**，见第十一节数值验证）。
- `HomePage` 新增 `_rowsPrefix`（int 前缀和）与 `_rowsPrefixAt(index)`。
  关键点：**周数只取决于月份、与屏幕宽度无关**，所以这份缓存不会因宽度变化而失效，
  且每个月的周数在整个应用生命周期内只计算一次。

| 场景 | 改造前 | 改造后 |
|---|---|---|
| 启动首帧定位（index≈1521） | O(1521) 逐月累加，每次新建 `DateTime` + 调 `extentFor` | 补齐前缀和后 **O(1)** |
| 「回今天」/「跳转日期」 | 每次 O(1800)（2050 年）/ O(2400)（2100 年） | **O(1)** |

> **未采纳「缩短锚点」方案**：`_MonthJumpDialog` 允许选到 1900 年，把锚点后移会让
> 1900~锚点年之间的跳转算出负偏移 → 定位到列表顶部（错误）。要正确支持就得让列表向下扩展，
> 改动面反而更大、风险更高。

### 2. 启动时孤儿文件清扫（P1-2 收尾，经确认后实施）

`dispose()` 在**进程被系统杀死**时不会执行 —— 用户录音/选图后未保存就清掉后台，文件会永久残留。
这是 `save()`（只清理进过数据库的）与 `dispose()`（进程被杀时不执行）都覆盖不到的**最后一处漏网路径**。

新增 `DiaryDatabase.purgeOrphanMedia({Duration minAge = 24h})`，在 `main()` 中 `unawaited(...)` 静默执行。
**三重安全约束，任一不满足都不删**：

1. 只遍历 `diary_media/` 目录本身（`root.list(recursive: true)` 只会产出它的后代，目录外文件不可能进入候选）；
2. `attachment` 表中**没有任何记录引用**该路径；
3. 文件 mtime 早于 `now - 24h` —— 避开「正在编辑、尚未保存」的文件。

另外加了扩展名白名单（`.jpg/.jpeg/.png/.mp4/.mov/.m4a/.aac`）与全程 try/catch：
任何异常都返回 0、绝不影响启动。

### 3. 死代码清理

| 位置 | 处理 |
|---|---|
| `diary_database.audioOutputPath()` | **删除**（全项目 0 调用，且与 `media_capture_service._newVoicePath()` 重复实现） |
| `homepage.dart` 两处 `debugPrint('[WND] ...')` | 改为 `_logDebug()`，用 `assert((){...}())` 包裹 —— release 构建会被 tree-shake 掉，不再给正式包留日志噪声 |

### 4. 纯函数抽取 + 单元测试（P2-6）

**新增 `lib/user_data/diary_text.dart`**：`diaryPreviewText` / `diaryMediaLabel` / `mediaDurationText` / `mediaSizeText`。

关键点是它**刻意不导入任何 Flutter / 插件库**。原来这些逻辑长在 `diary_database.dart` 里，
而那个文件依赖 sqflite / path_provider（进而牵连 `dart:ui`），导致纯逻辑**根本无法脱离 UI 环境测试**。
抽取之后：

- `DiaryAttachment.durationText / sizeText`、`DiaryEntry.preview / mediaLabel`、`DiaryEntryView.*` 全部改为委托 —— **实现只有一份**。
- 这些函数和 `date_fmt.dart` 一样，可用 `dart` 直接执行验证（见第十一节）。

**新增 3 个测试文件**：

| 文件 | 覆盖内容 |
|---|---|
| `test/date_fmt_test.dart` | 4 个格式化方法的补零规则与边界 |
| `test/diary_text_test.dart` | 摘要截断（60/61 字边界）、空/纯空白、媒体角标顺序、时长与体积的 B·KB·MB 分档 |
| `test/calendar_layout_test.dart` | `rowsFor` 恒在 4~6、已知月份行数、高度公式，以及**前缀和公式与逐月累加的 2413 点全量等价性** |

---

## 十一、第三批校验结论

### 本批争取到一项真正可执行的验证手段

前两批受限于 `flutter` / `dart analyze` 无法启动（管道资源耗尽，`CreateFile failed 231`），只能做静态推断。
本批验证出一个关键事实：**`dart.exe <script>` 可以进程内直接运行，且 `assert` 生效**。

于是把 `test/` 里的同款断言另写成临时脚本（`_pure_check.dart`，跑完即删），在真实 Dart VM 中执行了一遍：

```
rowsFor 分布: {5: 1874, 6: 516, 4: 22}
偏移公式最大误差: 4.6798959374427795e-8
✅ 全部通过：56 项断言            （退出码 0）
```

其中 `rowsFor` 的分布是**用另一套独立实现的 Python 版本先算一遍**再拿来比对的，两者完全一致 ——
这同时交叉验证了 Dart 与 Python 的日期语义（`DateTime.weekday % 7` 与 `isoweekday() % 7` 等价、
月末天数推导一致），覆盖 1900-01 ~ 2100-12 全部 2412 个月。

**因此：纯逻辑部分（`date_fmt` / `diary_text` / 日历高度与偏移公式）属于「已实际执行验证」，
而非静态推断。** 前缀和公式与逐月累加的最大绝对误差 `4.7e-8` 也印证了测试里 `closeTo(..., 1e-6)`
容差取值是安全的（放大了约 20 倍余量）。

| 校验项 | 方法 | 结果 |
|---|---|---|
| 纯逻辑断言 | 临时脚本在真实 Dart VM 中执行 | **56/56 通过** |
| 行数分布 | Python 独立实现 vs Dart 交叉核对 | 完全一致 |
| 语法正确性 | `dart format --output=none lib test` | 23 个文件全部解析通过，退出码 0 |
| 行尾符 | Python 二进制比对 | 全部保持原样（`main.dart` 仍为 CRLF，未被批量改写） |
| 废弃符号残留 | `audioOutputPath` / `debugPrint('[WND]` 等 | 0 |
| 逐文件 diff | 与第三批前快照比对 | 仅 5 个文件改动 + 4 个新文件，均符合预期 |

**仍未覆盖**：`flutter test` 与 `flutter analyze` 依然无法启动（同一环境限制）。
所以 `test/` 下这三个文件**没有经过测试框架实际执行** —— 但其中的断言已在真实 Dart VM 中逐条验证通过，
且用到的 `flutter_test` API（`group` / `test` / `expect` / `closeTo` / `inInclusiveRange` / `lessThan`）
均为标准用法，编译层面的风险较低。
**请你在能跑 `flutter test` 的环境执行一次确认。**

### 第三批之后仍可做的（第四批候选）

1. **P2-3 / P2-4 重复组件**：`diary_list_page._Empty` vs `diary_detail_page._EmptyView`；
   `day_detail_widget._SectionLabel` vs `diary_editor_page._SectionTitle`（仅差 1px 高度与 0 号字号）。
2. **P2-7 样板重复**：`_AlmanacCard` / `_TodoCard` 的「`didUpdateWidget` 判断日期变化 → 重新查库」可抽通用包装。
3. **P2-9 预留接口**：`AlmanacUtil` 仍有 17 个无调用方 getter（`naYin`/`pengZu`/`yiJiText`/`nineStar` …），
   属移植原小枣日历时的接口预留。建议删除，或至少在文件头注明「预留接口」，降低认知负担。
4. **P3-4 空实现按钮**：`MonthCalendarCard` 标题栏的分享图标 `onTap: () {}` —— 建议隐藏，避免点了没反应。
5. **P3-9**：`media_capture_service.checkRecording()` 无调用方（死方法）；
   `pickVideos` 逐个 `pickVideo`，用户选第 2 个时取消会丢掉已选（`image_picker` 无视频批量 API，
   属库限制，至少应补注释说明）。

---

## 十二、第四批执行记录（2026-10-14 已完成）

> 改动前快照：`D:/project/_wanniandiary_backup_batch4_20261013_2359/`（`lib/` + `test/`）。
> 涉及 10 个文件修改 + 2 个新文件。
>
> **本批的起因**：审查过程中发现项目根目录另有一份 `代码分析报告.md`（2026-10-13 11:42 生成，
> 标注「15 个文件 / 4,110 行」—— 是**本批改动之前**的版本）。其中标注了 3 个 P0。
> 我逐条复核：**1 条不成立、2 条属实**（见第十三节）。属实的两条是本轮最有价值的修复。
>
> ⚠️ 注意：该文件与本目录的 `README.md` 在本次会话进行期间（约 00:04）从项目根目录消失了。
> 经核对 Windows 回收站，当时被删除的只有我自建的临时脚本 `_batch4_check.dart`，
> 这两个文件**不是本会话删除的**。项目内另有 `.workbuddy/`（含真机验证截图与另一份会话记忆），
> 推测是并行的另一个会话或手动操作所致 —— 请自行确认。

### 1. P0：编辑日记会把创建时间重置为「现在」（数据丢失）

**位置**：`diary_database.dart` `save()` 的 update 分支

`DiaryEntry.toMap()` 里是 `'created_at': (createdAt ?? DateTime.now())`，而编辑器的
`DiaryEntry` **不携带原始创建时间** —— 整表覆盖写库后，创建时间被改成保存那一刻。

```dart
// 修复前
await db.update('diary', entry.toMap(), where: 'id = ?', whereArgs: [id]);

// 修复后：更新时剔除 created_at，保留库里的原值
await db.update('diary', entry.toMap()..remove('created_at'),
    where: 'id = ?', whereArgs: [id]);
```

**用户可见症状**：`diary_detail_page.dart:148` 的「编辑于 X月X日」是
`updatedAt` 与 `createdAt` 差值 > 1 分钟才显示；两者被写成同一时刻后，该行**编辑一次就永久消失**。

> 选择「在 `save()` 里剔除字段」而不是「让编辑器回传 createdAt」，是因为前者对所有调用方都成立，
> 不依赖调用方记得传值 —— 后者一旦有新入口忘了传就会复发。

### 2. P0：删除日记遗留 `attachment` 僵尸行（外键从未启用）

**位置**：`diary_database.dart` `delete()` / `_open()`

建表时写了 `FOREIGN KEY (diary_id) REFERENCES diary (id) ON DELETE CASCADE`，
但 **sqflite 默认不开启外键约束**，且 `_open()` 里没有 `PRAGMA foreign_keys = ON` ——
级联从未触发，`delete()` 也只删了 `diary` 行。结果每次删日记都在 `attachment` 表里
留下一批指向已删除日记的僵尸行（`clearAll()` 因为显式删了两张表才没暴露）。

**三处修复**：

| 位置 | 改动 |
|---|---|
| `_open()` | 新增 `onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON')` |
| `delete()` | 补 `db.delete('attachment', where: 'diary_id = ?')`，不再依赖级联 |
| 版本迁移 | `_dbVersion` 2 → 3；`onUpgrade` 里 `DELETE FROM attachment WHERE diary_id NOT IN (SELECT id FROM diary)` 清掉历史僵尸行 |

> 僵尸行的第二个危害容易被忽略：第三批加的启动清扫 `purgeOrphanMedia()` 会读全表 `attachment.path`
> 作为「仍被引用」的集合 —— 僵尸行会让对应文件**永远清不掉**。

### 3. 性能与健壮性三项

| 项 | 位置 | 改动 |
|---|---|---|
| 统计全表加载 | `DiaryRepository.stats()` | 原先 `allEntries(limit: 100000)` 把**全部日记 + 全部附件行**读进内存再装配对象（只为数两个数字）。改为 `COUNT(*)` / `EXISTS` 两条 SQL。设置页每次进入、每篇日记增删改后都会调用它 |
| 缓存无界 | `AlmanacUtil._cache` | 每个 value 持有一个 `Lunar`；日历向上无限延伸 → 缓存只增不减。加 `_maxCache = 512`，超限按 FIFO 丢弃最早一半（Map 保持插入顺序） |
| 视频崩溃 | `MediaPreviewTile._initVideo` | `await c.initialize()` 原来没有 try/catch：文件被外部删除或编码不支持会抛**未捕获的异步异常**，卡片永久停在「点击播放」占位。现降级为「无法播放」图标（`videocam_off_outlined`） |

### 4. 死代码清理（22 + 6 个符号）

按你的决定「删掉未使用部分」执行：

| 位置 | 删除内容 |
|---|---|
| `date_base/almanac.dart` | `DayAlmanac` 的 19 个 getter（`day`/`month`/`year`/`isLeapMonth`/`dayGanZhi`/`monthGanZhi`/`yearGanZhi`/`shengXiaoText`/`yi`/`ji`/`fuShen`/`taiShen`/`naYin`/`nineStar`/`tianShen`/`daySha`/`pengZu`/`zhiXing`/`yiJiText`）+ `AlmanacUtil` 的 3 个静态方法（`weekdayShort`/`solarText`/`daysInMonth`） |
| `data_base/holiday_data.dart` | `hasYear()` |
| `user_data/diary_database.dart` | `DiaryAttachment.fileName` / `sizeText` / `durationText`；`DiaryEntry.hasMedia`（被我自己的 `stats()` 改动孤立，一并删除） |
| `user_data/media_capture_service.dart` | `checkRecording()` |
| `home/widgets/media_widgets.dart` | `MediaPreviewTile.onTap` / `_AudioTile.onTap`（**无任何调用方传它**） |

> ⚠️ **一处需要你知道的取舍**：`DayAlmanac.yi` / `ji`（宜忌）也在删除之列 ——
> 它唯一的调用方是第一批已删掉的 `today_card.dart`，**现在确实无任何界面使用**。
> 若你想在「今日详情」里显示宜忌，恢复成本是 3 行：
> `List<String> get yi => lunar.getDayYi();` + `List<String> get ji => lunar.getDayJi();`，
> 再在黄历卡片里加一段渲染即可。

### 5. 重复组件合并（P2-3 / P2-4）

新增 `lib/widgets/`（跨层共用，因为 `user_data/diary_list_page.dart` 与 `home/` 都要用）：

| 新组件 | 取代 | 说明 |
|---|---|---|
| `SectionTitle` | `day_detail_widget._SectionLabel` + `diary_editor_page._SectionTitle` | 同一视觉组件两份实现，仅差竖条高度（13/12）、间距（6/8）、文字色。差异改为可选参数，**两处渲染结果不变** |
| `EmptyState` | `diary_list_page._Empty` + `diary_detail_page._EmptyView` | 外层结构（居中 → 32 内边距 → 56 图标 → 24 间距 → 主色按钮）完全相同，中段内容用 `children` 传入。按钮改为可选 —— 「搜索无结果」原本就不显示「写第一篇」，行为保持不变 |

### 6. 顺带：录音时长终于落了库

`record` 插件只返回文件路径、不返回时长，所以 `durationMs` 一直是 0，语音条只能退而显示**文件大小**。
现在 `startRecording` 记录起始时刻、`stopRecording` 算出真实时长。同时语音条的两条文案
改为复用 `diary_text.dart` 的 `mediaSizeText` / `mediaDurationText`（原先就地重写了一份格式化逻辑）。

> 显示变化：「语音 · 00:12」（大小）→「语音 · 12秒」（时长）。播放中的进度仍用 `mm:ss` 格式。

### 7. 明确跳过的两项

- **P2-7 `_AlmanacCard` / `_TodoCard` 抽通用包装**：`_TodoCard` 有交互状态（增删改、勾选、星标），
  不是「加载即可渲染」，通用「按日期加载」包装只能套住 `_AlmanacCard` 一个 —— 为一个使用者抽抽象不划算。
- **P3-4 分享按钮**：按你的决定保留待处理，未改动。

---

## 十三、第四批校验结论

### 1. 对另一份报告的逐条复核

`代码分析报告.md`（11:42，改动前版本）共列 3 个 P0、4 个 P1。复核结果：

| 报告结论 | 复核 | 说明 |
|---|---|---|
| P0-1 `test/widget_test.dart` 调 `MyApp()`，`flutter test` 必然失败 | ❌ **不成立** | 该文件用的是 `WannianDiaryApp`；连第一批的备份里也是它。报告可能基于更早的版本 |
| P0-2 编辑覆盖 `created_at` | ✅ **属实** | 已修，见第十二节 |
| P0-3 `delete()` 不删附件行 + 外键未启用 | ✅ **属实** | 已修，见第十二节 |
| P1-1 语音无法播放（无播放库） | ❌ **不成立** | `media_widgets.dart` 已有完整的 `VoicePlayer`（基于 `audioplayers`，`pubspec.yaml` 也已声明）。仅 `durationMs` 恒为 0 属实，本轮已修 |
| P1-2 设置开关空转 / 不持久化 | ⏭️ 已处理 | 第一批已随 `shared_preferences` 一起移除（你当时的决定是「保持移除」） |
| P1-3 编辑器删媒体 / 放弃编辑留孤儿文件 | ⏭️ 已处理 | 第二批已修（`save()` 差集删除 + 编辑器 `_sessionImports`） |
| P1-4 跳转日期越界静默落到列表末尾 | ❌ **不成立** | `_jumpToDate()` 已按需扩容 `_extraMonths`，`_scrollToMonth()` 还有兜底重试 |
| 4.2 `_TodoCard` 的「添加事项 / 标记」是空回调 | ❌ **不成立** | `onTap: _add` 已实现（弹窗 → 落库 → 排闹钟） |
| 4.2 分享图标空回调 | ✅ 属实 | 存在，但按你的决定保留待处理 |

**结论：报告基于旧版本，约六成结论已过期或不成立；但两个 P0 是真问题，已修复。**

### 2. 校验方式（本批争取到与第三批同等强度的验证）

| 校验项 | 方法 | 结果 |
|---|---|---|
| 纯逻辑 / 缓存裁剪 / 字段语义 | 临时脚本在**真实 Dart VM** 中执行（`almanac.dart` 不依赖 Flutter，可直接 import 项目包） | **97/97 项断言通过**，退出码 0 |
| 缓存裁剪正确性 | 连续取 700 天（跨过 512 上限）后**回访早期日期**，与 `Lunar.fromDate` 重新计算的结果逐字段比对 | 一致 |
| 语法正确性 | `dart format --output=none lib test` | 25 个文件全部解析通过，退出码 0 |
| 行尾符 | Python 二进制比对（逐文件 CRLF/LF 计数） | **21 个文件全部保持原状**（`main.dart` 仍 CRLF） |
| 已删符号残留 | 22 + 6 个符号全项目检索 | 全部 0（`daysInMonth` 的 4 处命中是 `calendar_view.dart` 内的**局部变量**，与被删的 `AlmanacUtil.daysInMonth` 无关） |
| 孤立 import | 逐个检查改动文件 | 无（`diary_list_page` 第 139 行仍在用 `AlmanacUtil.of`） |
| 逐文件 diff | 与第四批快照逐行比对 | 10 个改动文件全部符合预期，无意外行 |

### 3. 行数账（诚实说明）

| 项 | 变化 |
|---|---|
| 既有文件 | **−69 行** |
| 新增共享组件 | +124 行（`section_title.dart` 59 + `empty_state.dart` 65，含文档注释） |
| 净变化 | **+55 行** |

净行数是**增加的** —— 因为两个共享组件各自带了一段「为什么存在」的注释，
而删除的 28 个死符号多是单行 getter。真正的收益在**认知负担**与**行为正确性**，不在行数。

### 4. 仍未覆盖

`flutter analyze` / `flutter test` 在本机依然无法启动（`CreateFile failed 231`，管道资源耗尽）。
本批的类型风险点集中在：`onConfigure` 回调签名、`Sqflite.firstIntValue` 的返回类型、
记录类型 `({int total, int withMedia})` 的委托、以及 `EmptyState.children` 的 `List<Widget>` 展开。
**建议你在能跑分析器的环境确认一次。**

另外 `PRAGMA foreign_keys = ON` 是**运行时行为**，静态分析覆盖不到 ——
建议装一次新包后实测：写一篇带媒体的日记 → 删掉 → 用 DB 工具确认 `attachment` 表里没有残留行。

### 5. 第四批之后仍可做的

1. **P3-4 分享按钮**（你选择保留待处理）：目前 `onTap: () {}`。要么移除，要么实现为「复制当天日记文本」（Flutter 自带 `Clipboard`，无需新依赖）。
2. **`_AlmanacCard` 右侧的 `chevron_right`**（`:630`）：灰色箭头暗示可点，但整卡没有点击行为 —— 同类「假交互」，建议一并整理。
3. **`pickVideos` 多选限制**：逐个 `pickVideo`，用户选第 2 个时取消会丢掉已选。`image_picker` 无视频批量 API，属库限制，建议补注释说明。
4. **`importFile` 跨分区失败时回落原始相册路径**：第二批已加目录归属校验（不会再误删相册原图），但落库后该路径在 `diary_media/` 之外，孤儿清扫也管不到 —— 可考虑改为失败即返回 null 并提示用户。
5. **文档同步**：`README.md` 仍是 Flutter 模板原文；`项目说明.md` 的多处描述与代码不符（Tab 数量、周起始日、圆点颜色、媒体命名前缀等），见另一份报告第五节。





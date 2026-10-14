import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../date_base/date_fmt.dart';

/// 媒体附件类型
enum MediaType {
  image, // 图片（含拍照）
  video, // 视频
  audio, // 语音
}

/// 日记附件
class DiaryAttachment {
  DiaryAttachment({
    this.id,
    required this.diaryId,
    required this.type,
    required this.path,
    this.durationMs = 0,
    this.sizeBytes = 0,
    this.sortOrder = 0,
    this.createdAt,
  });

  final int? id;
  final int diaryId;
  final MediaType type;

  /// 应用私有目录下的绝对路径
  final String path;

  /// 音视频时长（毫秒）
  final int durationMs;

  /// 文件大小（字节）
  final int sizeBytes;

  /// 展示顺序
  int sortOrder;

  final DateTime? createdAt;

  Map<String, Object?> toMap(int diaryIdValue) => {
        'diary_id': diaryIdValue,
        'type': type.index,
        'path': path,
        'duration_ms': durationMs,
        'size_bytes': sizeBytes,
        'sort_order': sortOrder,
      };

  factory DiaryAttachment.fromMap(Map<String, Object?> m) => DiaryAttachment(
        id: m['id'] as int?,
        diaryId: m['diary_id'] as int,
        type: MediaType.values[(m['type'] as int)],
        path: m['path'] as String,
        durationMs: (m['duration_ms'] as int?) ?? 0,
        sizeBytes: (m['size_bytes'] as int?) ?? 0,
        sortOrder: (m['sort_order'] as int?) ?? 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch((m['created_at'] as int?) ?? 0),
      );
}

/// 一篇日记
class DiaryEntry {
  DiaryEntry({
    this.id,
    required this.date,
    required this.content,
    this.mood,
    this.weather,
    this.createdAt,
    this.updatedAt,
    List<DiaryAttachment>? attachments,
  }) : attachments = attachments ?? [];

  int? id;

  /// 日记归属日期（公历零点）
  DateTime date;

  /// 正文文本
  final String content;

  /// 心情标记
  final String? mood;

  /// 天气标记
  final String? weather;

  DateTime? createdAt;
  DateTime? updatedAt;

  List<DiaryAttachment> attachments;

  bool get isEmpty => content.trim().isEmpty && attachments.isEmpty;

  List<DiaryAttachment> get images => attachments.where((a) => a.type == MediaType.image).toList();
  List<DiaryAttachment> get videos => attachments.where((a) => a.type == MediaType.video).toList();
  List<DiaryAttachment> get audios => attachments.where((a) => a.type == MediaType.audio).toList();

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'date': date.millisecondsSinceEpoch,
        'content': content,
        'mood': mood,
        'weather': weather,
        'created_at': (createdAt ?? DateTime.now()).millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      };

  factory DiaryEntry.fromMap(Map<String, Object?> m) => DiaryEntry(
        id: m['id'] as int?,
        date: DateTime.fromMillisecondsSinceEpoch(m['date'] as int),
        content: (m['content'] as String?) ?? '',
        mood: m['mood'] as String?,
        weather: m['weather'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch((m['created_at'] as int?) ?? 0),
        updatedAt: DateTime.fromMillisecondsSinceEpoch((m['updated_at'] as int?) ?? 0),
      );
}

/// 列表所需的日记轻量投影：基础字段 + 三类媒体计数（由 [diarySummaries] 查询填充）。
///
/// 与 [DiaryEntry] 不同，它**不加载附件行**——列表只需数量角标，
/// 避免为计数把全部附件读进内存再丢弃。
class DiarySummary {
  DiarySummary({
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

  factory DiarySummary.fromMap(Map<String, Object?> m) => DiarySummary(
        id: m['id'] as int,
        date: DateTime.fromMillisecondsSinceEpoch(m['date'] as int),
        content: (m['content'] as String?) ?? '',
        mood: m['mood'] as String?,
        weather: m['weather'] as String?,
        imageCount: (m['c_img'] as int?) ?? 0,
        videoCount: (m['c_vid'] as int?) ?? 0,
        audioCount: (m['c_aud'] as int?) ?? 0,
      );
}

/// 当日事项 / 任务
///
/// 归属某个公历日（`date` 为 yyyy-MM-dd），可无上限添加；
/// `done` 完成态（空白方框 → 打勾方块），`starred` 星标（实心星联动日历）；
/// `reminder` 为可选的闹钟提醒时间（epoch 毫秒，null 表示不设提醒）。
class TaskItem {
  TaskItem({
    this.id,
    required this.date,
    required this.content,
    this.done = false,
    this.starred = false,
    this.reminder,
    this.createdAt,
  });

  int? id;

  /// 归属日期（公历零点，格式 yyyy-MM-dd）
  final String date;

  /// 事项内容
  String content;

  /// 是否完成
  bool done;

  /// 是否星标（实心星，日历当日展示）
  bool starred;

  /// 闹钟提醒时间；null = 不提醒
  DateTime? reminder;

  DateTime? createdAt;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'date': date,
        'content': content,
        'done': done ? 1 : 0,
        'starred': starred ? 1 : 0,
        'reminder': reminder?.millisecondsSinceEpoch,
        'created_at': (createdAt ?? DateTime.now()).millisecondsSinceEpoch,
      };

  factory TaskItem.fromMap(Map<String, Object?> m) => TaskItem(
        id: m['id'] as int?,
        date: (m['date'] as String?) ?? '',
        content: (m['content'] as String?) ?? '',
        done: (m['done'] as int?) == 1,
        starred: (m['starred'] as int?) == 1,
        reminder: m['reminder'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['reminder'] as int),
        createdAt:
            DateTime.fromMillisecondsSinceEpoch((m['created_at'] as int?) ?? 0),
      );
}

/// 日记数据库 + 媒体文件管理
class DiaryDatabase {
  DiaryDatabase._();

  static final DiaryDatabase instance = DiaryDatabase._();

  static const _dbName = 'calendardiary.db';

  /// 旧库文件名（v4.2.0 之前），用于应用升级时一次性迁移，迁移后不再使用。
  static const _legacyDbName = 'wanniandiary.db';

  /// 版本历史：
  /// - 1：diary + attachment
  /// - 2：tasks
  /// - 3：开启外键后，清理历史遗留的 attachment 僵尸行
  static const _dbVersion = 3;

  /// 日记增删改后广播，供首页等订阅者刷新（如日历红点、星标）
  static final StreamController<void> diaryChanged =
      StreamController<void>.broadcast();

  /// 缓存初始化 Future，避免并发调用时重复 openDatabase
  Future<Database>? _opening;

  /// 媒体根目录（`diary_media/`）缓存，供「文件是否由本应用管理」的归属校验复用
  String? _mediaRootPath;

  Future<Database> get database => _opening ??= _open();

  /// 打开失败时清空缓存，允许下次重试（例如首次创建表失败后可恢复）
  Future<T> _withDb<T>(Future<T> Function(Database db) action) async {
    try {
      final db = await database;
      return await action(db);
    } catch (e) {
      // 打开或查询失败 → 重置缓存，下次重新打开
      _opening = null;
      rethrow;
    }
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, _dbName);
    final file = File(path);
    if (!await file.exists()) {
      // 数据库改名迁移：把旧库 wanniandiary.db（及 WAL/SHM 辅助文件）整体复制为新库，
      // 保留用户全部日记数据。仅在「新库不存在、旧库存在」时触发，因此幂等、可重复调用。
      final legacyPath = p.join(dir, _legacyDbName);
      final legacyFile = File(legacyPath);
      if (await legacyFile.exists()) {
        await legacyFile.copy(path);
        for (final suffix in const ['-wal', '-shm']) {
          final aux = File('$legacyPath$suffix');
          if (await aux.exists()) {
            await aux.copy('$path$suffix');
          }
        }
      }
    }
    return openDatabase(
      path,
      version: _dbVersion,
      // sqflite 默认**不开启**外键约束，建表时写的 `ON DELETE CASCADE` 不会生效；
      // 必须在每次建立连接时显式打开，否则删除日记后 attachment 会留下僵尸行。
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE diary (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date INTEGER NOT NULL,
            content TEXT NOT NULL DEFAULT '',
            mood TEXT,
            weather TEXT,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute('CREATE INDEX idx_diary_date ON diary(date)');
        await db.execute('''
          CREATE TABLE attachment (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            diary_id INTEGER NOT NULL,
            type INTEGER NOT NULL,
            path TEXT NOT NULL,
            duration_ms INTEGER NOT NULL DEFAULT 0,
            size_bytes INTEGER NOT NULL DEFAULT 0,
            sort_order INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            FOREIGN KEY (diary_id) REFERENCES diary (id) ON DELETE CASCADE
          )
        ''');
        await db.execute('CREATE INDEX idx_att_diary ON attachment(diary_id)');
        await _createTasksTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createTasksTable(db);
        }
        if (oldVersion < 3) {
          // v2 及以前未开启外键，删除日记时 `ON DELETE CASCADE` 不会触发，
          // attachment 表里堆积了指向已删除日记的僵尸行。
          // 危害：① 表只增不减；② 僵尸行会让启动时的孤儿媒体清扫
          // 误判对应文件「仍被引用」，从而永远清不掉。
          await db.execute(
            'DELETE FROM attachment WHERE diary_id NOT IN (SELECT id FROM diary)',
          );
        }
      },
    );
  }

  /// 创建「事项」表（供首次建库与升级复用）
  static Future<void> _createTasksTable(Database db) async {
    await db.execute('''
      CREATE TABLE tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        content TEXT NOT NULL DEFAULT '',
        done INTEGER NOT NULL DEFAULT 0,
        starred INTEGER NOT NULL DEFAULT 0,
        reminder INTEGER,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_tasks_date ON tasks(date)');
  }

  // ---------------- 日记 CRUD ----------------

  /// 查询某天的日记；无则返回 null
  Future<DiaryEntry?> entryOfDate(DateTime date) => _withDb((db) async {
        final day =
            DateTime(date.year, date.month, date.day).millisecondsSinceEpoch;
        final rows = await db.query('diary',
            where: 'date = ?', whereArgs: [day], limit: 1);
        if (rows.isEmpty) return null;
        final entry = DiaryEntry.fromMap(rows.first);
        entry.attachments = await attachmentsOf(entry.id!);
        return entry;
      });

  /// 查询有日记的所有日期（按时间倒序）
  Future<List<DateTime>> datesWithDiary() async {
    final db = await database;
    final rows = await db.query('diary', columns: ['date'], orderBy: 'date DESC');
    return rows.map((r) => DateTime.fromMillisecondsSinceEpoch(r['date'] as int)).toList();
  }

  /// 查询全部日记的**列表摘要**（倒序），不加载附件行。
  ///
  /// 用三个关联子查询直接算出每篇日记的「图/视频/语音」数量，
  /// 列表只需展示数量角标，无需把附件行读进内存（此前 `allEntries`
  /// 会为每篇日记装配全部附件对象，纯属浪费）。
  Future<List<DiarySummary>> diarySummaries({int limit = 1000}) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT d.id AS id, d.date AS date, d.content AS content,
             d.mood AS mood, d.weather AS weather,
             (SELECT COUNT(*) FROM attachment a
                WHERE a.diary_id = d.id AND a.type = ${MediaType.image.index}) AS c_img,
             (SELECT COUNT(*) FROM attachment a
                WHERE a.diary_id = d.id AND a.type = ${MediaType.video.index}) AS c_vid,
             (SELECT COUNT(*) FROM attachment a
                WHERE a.diary_id = d.id AND a.type = ${MediaType.audio.index}) AS c_aud
      FROM diary d
      ORDER BY d.date DESC
      LIMIT ?
    ''', [limit]);
    return rows.map(DiarySummary.fromMap).toList();
  }

  /// 日记统计：（总数，含媒体数）
  ///
  /// 直接走 SQL 聚合（`COUNT(*)` / `EXISTS`）拿两个数字，
  /// 不读取任何日记或附件行。设置页每次进入、以及任意一篇日记增删改后都会调用它。
  Future<({int total, int withMedia})> stats() async {
    final db = await database;
    final total = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM diary'),
        ) ??
        0;
    final withMedia = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM diary d '
            'WHERE EXISTS (SELECT 1 FROM attachment a WHERE a.diary_id = d.id)',
          ),
        ) ??
        0;
    return (total: total, withMedia: withMedia);
  }

  /// 新建或更新某天的日记
  Future<int> save(DiaryEntry entry) async {
    final db = await database;
    final day = DateTime(entry.date.year, entry.date.month, entry.date.day);
    entry.date = day;

    if (entry.id == null) {
      // 同一天只允许一篇：先查后决定 insert/update
      final existing = await db.query('diary', where: 'date = ?', whereArgs: [day.millisecondsSinceEpoch], limit: 1);
      if (existing.isNotEmpty) {
        entry.id = existing.first['id'] as int;
      }
    }

    int id;
    // 全量重建附件关联时，本次不再被引用的旧媒体文件必须一并删除，
    // 否则会永久残留在 diary_media/ 下且无人引用（孤儿文件，磁盘只增不减）
    var stalePaths = const <String>[];
    if (entry.id == null) {
      id = await db.insert('diary', entry.toMap());
    } else {
      id = entry.id!;
      // 更新时**不写 created_at**：`toMap()` 用的是 `createdAt ?? DateTime.now()`，
      // 而编辑器的 `DiaryEntry` 并不携带原始创建时间，直接整表覆盖会把创建时间
      // 重置为「现在」→ 详情页「编辑于…」的差值判断随之失真（编辑一次就消失）。
      await db.update('diary', entry.toMap()..remove('created_at'),
          where: 'id = ?', whereArgs: [id]);
      // 重建前先记录旧路径，并排除「本次仍保留」的附件
      // （编辑器加载已存媒体时沿用原路径，故仍保留的附件路径与旧记录完全一致）
      final kept = entry.attachments.map((a) => p.normalize(a.path)).toSet();
      final oldRows = await db.query(
        'attachment',
        columns: ['path'],
        where: 'diary_id = ?',
        whereArgs: [id],
      );
      stalePaths = [
        for (final r in oldRows)
          if (((r['path'] as String?) ?? '').isNotEmpty &&
              !kept.contains(p.normalize(r['path'] as String)))
            r['path'] as String,
      ];
      await db.delete('attachment', where: 'diary_id = ?', whereArgs: [id]);
    }

    for (var i = 0; i < entry.attachments.length; i++) {
      final a = entry.attachments[i];
      a.sortOrder = i;
      await db.insert('attachment', {
        ...a.toMap(id),
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
    }
    entry.id = id;
    // 数据库已与新状态一致，此时再清理磁盘孤儿文件（异步 IO，不阻塞 UI）
    await _deleteFiles(stalePaths);
    if (!diaryChanged.isClosed) diaryChanged.add(null);
    return id;
  }

  /// 删除日记及其媒体文件
  ///
  /// 显式删除 attachment 行，不依赖建表时的 `ON DELETE CASCADE`：
  /// 虽然 `onConfigure` 已开启外键、级联本应生效，但显式删除语义更直白，
  /// 且无论外键是否生效都能得到正确结果（此前依赖级联 = 留下僵尸行）。
  Future<void> delete(int id) async {
    final db = await database;
    final atts = await db.query(
      'attachment',
      columns: ['path'],
      where: 'diary_id = ?',
      whereArgs: [id],
    );
    await db.delete('attachment', where: 'diary_id = ?', whereArgs: [id]);
    await db.delete('diary', where: 'id = ?', whereArgs: [id]);
    await _deleteFiles(atts.map((a) => (a['path'] as String?) ?? ''));
    if (!diaryChanged.isClosed) diaryChanged.add(null);
  }

  // ---------------- 附件 ----------------

  Future<List<DiaryAttachment>> attachmentsOf(int diaryId) async {
    final db = await database;
    final rows = await db.query(
      'attachment',
      where: 'diary_id = ?',
      whereArgs: [diaryId],
      orderBy: 'sort_order ASC',
    );
    return rows.map(DiaryAttachment.fromMap).toList();
  }

  // ---------------- 媒体文件存储 ----------------

  /// 媒体根目录：`<app>/diary_media/<year>/`
  Future<String> mediaDir(int year) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'diary_media', '$year'));
    // create(recursive: true) 幂等，已存在时不会报错；用异步版本避免导入流程中的同步 IO
    await dir.create(recursive: true);
    return dir.path;
  }

  /// 导入外部文件（如相册/相机产物）到应用私有目录
  Future<String> importFile(String srcPath, MediaType type, int year) async {
    final dir = await mediaDir(year);
    final ext = type == MediaType.audio
        ? '.m4a'
        : (type == MediaType.video ? '.mp4' : '.jpg');
    final name = 'a_${DateTime.now().millisecondsSinceEpoch}$ext';
    final dest = p.join(dir, name);

    final src = File(srcPath);
    if (!await src.exists()) return srcPath;
    // 跨分区需复制，失败则回落原路径
    try {
      await src.copy(dest);
      return dest;
    } catch (_) {
      return srcPath;
    }
  }

  /// 媒体根目录（`diary_media/`）绝对路径，带进程内缓存
  Future<String> _mediaRootDir() async {
    final cached = _mediaRootPath;
    if (cached != null) return cached;
    final base = await getApplicationDocumentsDirectory();
    final root = p.normalize(p.join(base.path, 'diary_media'));
    _mediaRootPath = root;
    return root;
  }

  /// 删除媒体文件（静默失败）
  ///
  /// 只删除 `diary_media/` 下由本应用管理的文件：
  /// [importFile] 在跨分区复制失败时会回落为原始相册路径，
  /// 若无条件删除，会误删用户相册里的原文件。
  ///
  /// 已改为异步 IO（`await exists/delete`）—— 此前用 `existsSync/deleteSync`，
  /// 在「清空全部日记」等批量场景下会阻塞 UI 线程造成掉帧。
  Future<void> deleteFile(String path) async {
    if (path.isEmpty) return;
    try {
      final target = p.normalize(path);
      final root = await _mediaRootDir();
      if (!p.isWithin(root, target)) return;
      final f = File(target);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // 文件可能已被用户删除或路径异常，忽略
    }
  }

  /// 批量删除媒体文件（并发执行，避免数百附件时逐个串行等待）
  Future<void> _deleteFiles(Iterable<String> paths) async {
    final list = paths.where((e) => e.isNotEmpty).toList(growable: false);
    if (list.isEmpty) return;
    await Future.wait(list.map(deleteFile));
  }

  /// 清扫媒体孤儿文件所需的扩展名白名单
  ///
  /// 只处理本应用会产生的媒体类型，避免误删 `diary_media/` 内其它意外文件。
  static const Set<String> _mediaExtensions = {
    '.jpg', '.jpeg', '.png', '.mp4', '.mov', '.m4a', '.aac',
  };

  /// 清扫 `diary_media/` 下的孤儿文件，返回删除数量
  ///
  /// 用于兜底 `save()` / `dispose()` 覆盖不到的场景：**录音或选图后未保存，
  /// 随后进程被系统杀死** —— 此时 `dispose()` 不会执行，文件会永久残留。
  ///
  /// 三重安全约束，任一不满足都不删：
  /// 1. 只遍历 `diary_media/` 目录本身 —— `root.list(recursive: true)` 只会
  ///    产出它的后代，目录外的文件不可能进入候选；
  /// 2. 数据库 `attachment` 表中**没有任何记录引用**该路径；
  /// 3. 文件最后修改时间早于 `now - [minAge]`（默认 24 小时）——
  ///    时间阈值用于避开「用户正在编辑、尚未保存」的文件。
  ///
  /// 全程静默失败：清扫属于后台卫生工作，任何异常都不应影响启动。
  Future<int> purgeOrphanMedia({
    Duration minAge = const Duration(hours: 24),
  }) async {
    try {
      final root = Directory(await _mediaRootDir());
      if (!await root.exists()) return 0;

      final db = await database;
      final rows = await db.query('attachment', columns: ['path']);
      final referenced = <String>{};
      for (final r in rows) {
        final path = (r['path'] as String?) ?? '';
        if (path.isNotEmpty) referenced.add(p.normalize(path));
      }

      final cutoff = DateTime.now().subtract(minAge);
      var removed = 0;
      await for (final entity in root.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final path = p.normalize(entity.path);
        if (referenced.contains(path)) continue;
        if (!_mediaExtensions.contains(p.extension(path).toLowerCase())) continue;
        if ((await entity.stat()).modified.isAfter(cutoff)) continue;
        try {
          await entity.delete();
          removed++;
        } catch (_) {
          // 单个文件删除失败不影响其余清扫
        }
      }
      return removed;
    } catch (_) {
      return 0;
    }
  }

  // ---------------- 事项 / 任务 ----------------

  /// 查询某天的全部事项（按创建时间正序）
  Future<List<TaskItem>> tasksOfDate(DateTime day) => _withDb((db) async {
        final key = DateFmt.dayKey(day);
        final rows = await db.query('tasks',
            where: 'date = ?', whereArgs: [key], orderBy: 'created_at ASC');
        return rows.map(TaskItem.fromMap).toList();
      });

  /// 查询全部事项（用于清空前批量取消已注册的闹钟）
  Future<List<TaskItem>> allTasks() => _withDb((db) async {
        final rows = await db.query('tasks', orderBy: 'id ASC');
        return rows.map(TaskItem.fromMap).toList();
      });

  /// 新增事项，返回自增 id
  Future<int> insertTask(TaskItem t) async {
    final db = await database;
    return db.insert('tasks', t.toMap());
  }

  /// 更新事项（done/starred/content/reminder 任一变化）
  Future<void> updateTask(TaskItem t) async {
    final db = await database;
    await db.update('tasks', t.toMap(), where: 'id = ?', whereArgs: [t.id]);
  }

  /// 删除事项
  Future<void> deleteTask(int id) async {
    final db = await database;
    await db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }

  /// 查询某月有星标事项的日期集合（日历实心星用）
  Future<Set<int>> starredDaysInMonth(int year, int month) async {
    final db = await database;
    final prefix = DateFmt.yearMonth(year, month);
    final rows = await db.query(
      'tasks',
      columns: ['date'],
      where: "substr(date,1,7) = ? AND starred = 1",
      whereArgs: [prefix],
    );
    final set = <int>{};
    for (final r in rows) {
      final d = DateTime.tryParse((r['date'] as String?) ?? '');
      if (d != null) set.add(d.day);
    }
    return set;
  }

  /// 查询所有星标事项的日期（按日），日历实心星联动用
  Future<List<DateTime>> starredTaskDates() async {
    final db = await database;
    final rows = await db.query('tasks', columns: ['date'], where: 'starred = 1');
    final list = <DateTime>[];
    for (final r in rows) {
      final d = DateTime.tryParse((r['date'] as String?) ?? '');
      if (d != null) list.add(d);
    }
    return list;
  }

  /// 查询所有「未完成的未来提醒」事项（用于开机/启动重排）
  Future<List<TaskItem>> pendingReminders() async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await db.query(
      'tasks',
      where: 'reminder IS NOT NULL AND done = 0 AND reminder > ?',
      whereArgs: [now],
      orderBy: 'reminder ASC',
    );
    return rows.map(TaskItem.fromMap).toList();
  }

  /// 清空全部数据（设置里的「清空所有日记」用）
  Future<void> clearAll() async {
    final db = await database;
    final atts = await db.query('attachment', columns: ['path']);
    await db.delete('diary');
    await db.delete('attachment');
    await db.delete('tasks');
    await _deleteFiles(atts.map((a) => (a['path'] as String?) ?? ''));
    // 广播变更：让首页日历标记与日记列表即时刷新（此前只靠手动刷新才消失）
    if (!diaryChanged.isClosed) diaryChanged.add(null);
  }
}

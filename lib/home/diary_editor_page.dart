import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../date_base/almanac.dart';
import '../user_data/diary_database.dart';
import '../user_data/media_capture_service.dart';
import 'widgets/media_widgets.dart';
import '../widgets/section_title.dart';
import '../theme/app_colors.dart';

/// 日记编辑器：文本 + 图片 + 照片 + 语音 + 视频
class DiaryEditorPage extends StatefulWidget {
  const DiaryEditorPage({super.key, required this.date});

  final DateTime date;

  @override
  State<DiaryEditorPage> createState() => _DiaryEditorPageState();
}

class _DiaryEditorPageState extends State<DiaryEditorPage> {
  final _textCtrl = TextEditingController();
  final _db = DiaryDatabase.instance;
  final _media = MediaCaptureService.instance;

  final List<CapturedMedia> _images = [];
  final List<CapturedMedia> _videos = [];
  final List<CapturedMedia> _audios = [];

  String? _mood;
  String? _weather;

  bool _loading = true;
  bool _saving = false;
  int? _existingId;

  /// 本次编辑会话内新导入（已落盘）的媒体路径
  ///
  /// 这些文件在选择/录制时即写入应用私有目录。若用户移除后保存、或直接放弃编辑，
  /// 它们不会进入数据库，必须在页面销毁前清理，否则会残留成孤儿文件。
  final Set<String> _sessionImports = {};

  static const _moods = ['😊', '😌', '😐', '😔', '😤', '🤒', '🥰', '🤔'];

  /// 天气图标（仅图标，无文字）：晴 / 多云 / 阴 / 雨 / 雷雨 / 雪 / 雾 / 阴雨
  static const _weathers = ['☀️', '⛅', '☁️', '🌧️', '⛈️', '❄️', '🌫️', '💧'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    // 放弃编辑或异常退出：清掉本次导入但未入库的媒体文件
    if (_sessionImports.isNotEmpty) {
      for (final path in _sessionImports) {
        unawaited(_db.deleteFile(path));
      }
      _sessionImports.clear();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      // 超时保护：数据库初始化异常时不卡住界面
      final entry = await _db
          .entryOfDate(widget.date)
          .timeout(const Duration(seconds: 3));
      if (entry != null) {
        _existingId = entry.id;
        _textCtrl.text = entry.content;
        _mood = entry.mood;
        _weather = entry.weather;
        for (final a in entry.attachments) {
          _bucket(a.type).add(a.toCapturedMedia());
        }
      }
    } catch (_) {
      // 读取失败按新日记处理
      _existingId = null;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<CapturedMedia> _bucket(MediaType t) {
    switch (t) {
      case MediaType.image:
        return _images;
      case MediaType.video:
        return _videos;
      case MediaType.audio:
        return _audios;
    }
  }

  /// 记录本次会话新导入的媒体，供放弃编辑 / 移除时清理磁盘文件
  void _trackImports(Iterable<CapturedMedia> items) {
    for (final m in items) {
      _sessionImports.add(m.path);
    }
  }

  // ---------------- 媒体操作 ----------------

  Future<void> _pickFromGallery() async {
    if (!await _media.ensureGallery()) {
      _toast('需要相册权限');
      return;
    }
    final r = await _media.pickImages();
    if (r.isNotEmpty) {
      _trackImports(r);
      setState(() => _images.addAll(r));
    }
  }

  Future<void> _takePhoto() async {
    if (!await _media.ensureCamera()) {
      _toast('需要相机权限');
      return;
    }
    final r = await _media.takePhoto();
    if (r != null) {
      _trackImports([r]);
      setState(() => _images.add(r));
    }
  }

  Future<void> _pickVideo() async {
    if (!await _media.ensureGallery()) {
      _toast('需要相册权限');
      return;
    }
    final r = await _media.pickVideos();
    if (r.isNotEmpty) {
      _trackImports(r);
      setState(() => _videos.addAll(r));
    }
  }

  Future<void> _recordByCamera() async {
    if (!await _media.ensureCamera()) {
      _toast('需要相机权限');
      return;
    }
    final r = await _media.recordVideoByCamera();
    if (r != null) {
      _trackImports([r]);
      setState(() => _videos.add(r));
    }
  }

  Future<void> _startVoice() async {
    if (!await _media.ensureMicrophone()) {
      _toast('需要麦克风权限');
      return;
    }
    final ok = await _media.startRecording();
    if (ok && mounted) {
      setState(() {});
      _showRecordingBar();
    }
  }

  Future<void> _showRecordingBar() async {
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => RecordingBar(
        onCancel: () async {
          await _media.cancelRecording();
          if (!mounted) return;
          setState(() {});
          Navigator.pop(context);
        },
        onStop: () async {
          final r = await _media.stopRecording();
          if (r != null) {
            _trackImports([r]);
            setState(() => _audios.add(r));
          }
          if (!mounted) return;
          setState(() {});
          Navigator.pop(context);
        },
      ),
    );
  }

  void _remove(MediaType t, int index) {
    final bucket = _bucket(t);
    final removed = bucket[index];
    setState(() => bucket.removeAt(index));
    // 本次新导入、尚未入库的文件：移除后立即删盘，避免残留
    if (_sessionImports.remove(removed.path)) {
      unawaited(_db.deleteFile(removed.path));
    }
  }

  void _toast(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s), duration: const Duration(seconds: 2)),
    );
  }

  // ---------------- 保存 ----------------

  /// 标记为「允许退出」，PopScope 的 canPop 只读，需配合内部标志使用
  bool _allowPop = false;

  Future<void> _save() async {
    if (_saving) return;
    final content = _textCtrl.text.trim();
    final all = [..._images, ..._videos, ..._audios];
    if (content.isEmpty && all.isEmpty) {
      _toast('写点什么再保存吧');
      return;
    }

    setState(() => _saving = true);
    try {
      final entry = DiaryEntry(
        id: _existingId,
        date: widget.date,
        content: content,
        mood: _mood,
        weather: _weather,
        attachments: all.map((m) => m.toAttachment(0)).toList(),
      );
      await _db.save(entry);
      // 已入库：这些路径归数据库管理，不再作为临时文件在 dispose 时清理
      _sessionImports.clear();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _toast('保存失败：$e');
      }
      return;
    }
    if (!mounted) return;
    // 保存成功：允许退出后再 pop
    _allowPop = true;
    Navigator.of(context).pop(true);
  }

  /// 关闭页面（含放弃确认）
  Future<void> _close() async {
    if (_saving) return;
    if (await _confirmExit() && mounted) {
      _allowPop = true;
      Navigator.of(context).pop();
    }
  }

  Future<bool> _confirmExit() async {
    if (_saving) return false;
    final dirty = _textCtrl.text.trim().isNotEmpty ||
        _images.isNotEmpty ||
        _videos.isNotEmpty ||
        _audios.isNotEmpty;
    if (!dirty) return true;

    final r = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('放弃编辑？'),
        content: const Text('当前内容尚未保存。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('继续编辑')),
          TextButton(
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('放弃', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    return r ?? false;
  }

  // ---------------- 构建 ----------------

  @override
  Widget build(BuildContext context) {
    final a = AlmanacUtil.of(widget.date);
    final dateStr = DateFormat('yyyy年M月d日').format(widget.date);

    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // 系统返回键：走统一关闭流程
        await _close();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('写日记'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: '关闭',
            onPressed: _close,
          ),
          actions: [
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('保存'),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                children: [
                  // 日期信息卡：保留日历的日期上下文
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceWarm,
                      border: Border.all(color: AppColors.borderWarmLight),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(dateStr,
                                style: const TextStyle(
                                    fontSize: 16, color: AppColors.primary)),
                            const SizedBox(width: 8),
                            Text(AlmanacUtil.weekdayCn(widget.date),
                                style: const TextStyle(
                                    fontSize: 13, color: AppColors.textHint)),
                            if (a.hasFestival) ...[
                              const SizedBox(width: 8),
                              Text(a.allFestivals.first,
                                  style: const TextStyle(
                                      fontSize: 13, color: AppColors.orange)),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('${a.lunarText} · ${a.ganZhi} · 生肖${a.shengXiao}',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textHint)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 心情
                  _ChipSelector(
                    options: _moods,
                    selected: _mood,
                    onChanged: (v) => setState(() => _mood = v),
                  ),
                  const SizedBox(height: 16),

                  // 天气（仅图标，无文字）
                  _ChipSelector(
                    options: _weathers,
                    selected: _weather,
                    onChanged: (v) => setState(() => _weather = v),
                  ),
                  const SizedBox(height: 16),

                  // 正文
                  TextField(
                    controller: _textCtrl,
                    maxLines: null,
                    minLines: 8,
                    keyboardType: TextInputType.multiline,
                    style: const TextStyle(fontSize: 15, height: 1.6),
                    decoration: const InputDecoration(
                      hintText: '记录今天发生的事…',
                      border: InputBorder.none,
                    ),
                  ),

                  const Divider(height: 32),

                  // 语音
                  if (_audios.isNotEmpty) ...[
                    SectionTitle('语音 ${_audios.length}'),
                    ..._audios.asMap().entries.map(
                          (e) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: SizedBox(
                              height: 56,
                              child: MediaPreviewTile(
                                media: e.value,
                                onDelete: () => _remove(MediaType.audio, e.key),
                              ),
                            ),
                          ),
                        ),
                    const SizedBox(height: 16),
                  ],

                  // 图片 / 照片
                  if (_images.isNotEmpty) ...[
                    SectionTitle('图片 ${_images.length}'),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: _images.length,
                      itemBuilder: (_, i) => MediaPreviewTile(
                        media: _images[i],
                        onDelete: () => _remove(MediaType.image, i),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // 视频
                  if (_videos.isNotEmpty) ...[
                    SectionTitle('视频 ${_videos.length}'),
                    ..._videos.asMap().entries.map(
                          (e) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: AspectRatio(
                              aspectRatio: 16 / 9,
                              child: MediaPreviewTile(
                                media: e.value,
                                onDelete: () => _remove(MediaType.video, e.key),
                              ),
                            ),
                          ),
                        ),
                  ],
                ],
              ),
        bottomNavigationBar: _loading
            ? null
            : Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                decoration: const BoxDecoration(
                  color: AppColors.white,
                  border: Border(top: BorderSide(color: Color(0x14000000))),
                ),
                child: SafeArea(
                  top: false,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _ToolBtn(icon: Icons.photo_library_outlined, label: '相册', onTap: _pickFromGallery),
                      _ToolBtn(icon: Icons.photo_camera_outlined, label: '拍照', onTap: _takePhoto),
                      _ToolBtn(icon: Icons.mic_none, label: '语音', onTap: _startVoice),
                      _ToolBtn(icon: Icons.videocam_outlined, label: '拍视频', onTap: _recordByCamera),
                      _ToolBtn(icon: Icons.video_library_outlined, label: '视频', onTap: _pickVideo),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _ToolBtn extends StatelessWidget {
  const _ToolBtn({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: AppColors.textPrimary),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondaryAlt)),
          ],
        ),
      ),
    );
  }
}

/// 横排 chip 选择器（心情 / 天气共用）
///
/// 再次点选已选项即取消（返回 null），与原本「选中态再点一下清空」行为一致。
class _ChipSelector extends StatelessWidget {
  const _ChipSelector({
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<String> options;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 36,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: options.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final v = options[i];
            final sel = selected == v;
            return GestureDetector(
              onTap: () => onChanged(sel ? null : v),
              child: Container(
                width: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: sel
                      ? AppColors.primary.withValues(alpha: 0.15)
                      : AppColors.surfaceNeutral,
                  borderRadius: BorderRadius.circular(8),
                  border: sel ? Border.all(color: AppColors.primary) : null,
                ),
                child: Text(v, style: const TextStyle(fontSize: 18)),
              ),
            );
          },
        ),
      );
}

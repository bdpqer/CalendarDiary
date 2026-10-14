import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../date_base/almanac.dart';
import '../user_data/diary_database.dart';
import '../user_data/media_capture_service.dart';
import 'diary_editor_page.dart';
import 'widgets/media_widgets.dart';
import '../widgets/empty_state.dart';
import '../theme/app_colors.dart';

/// 日记详情/阅读页
class DiaryDetailPage extends StatefulWidget {
  const DiaryDetailPage({super.key, required this.date});

  final DateTime date;

  @override
  State<DiaryDetailPage> createState() => _DiaryDetailPageState();
}

class _DiaryDetailPageState extends State<DiaryDetailPage> {
  final _db = DiaryDatabase.instance;
  DiaryEntry? _entry;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final e = await _db.entryOfDate(widget.date);
      if (mounted) {
        setState(() {
          _entry = e;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _entry = null;
          _loading = false;
        });
      }
    }
  }

  Future<void> _edit() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => DiaryEditorPage(date: widget.date)),
    );
    if (ok == true) {
      await _load();
      if (mounted) Navigator.pop(context, true);
    }
  }

  Future<void> _delete() async {
    final entry = _entry;
    if (entry?.id == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除这篇日记？'),
        content: const Text('正文和所有媒体文件都会被删除，无法恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('删除', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _db.delete(entry!.id!);
      if (mounted) Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('日记'),
        actions: [
          if (_entry != null && _loading == false) ...[
            IconButton(icon: const Icon(Icons.edit_outlined), onPressed: _edit),
            IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_entry == null || _entry!.isEmpty)
              ? _EmptyView(date: widget.date, onWrite: () async {
                  final ok = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(builder: (_) => DiaryEditorPage(date: widget.date)),
                  );
                  if (ok == true) {
                    await _load();
                  }
                })
              : _ContentView(entry: _entry!, onEdit: _edit),
    );
  }
}

class _ContentView extends StatelessWidget {
  const _ContentView({required this.entry, required this.onEdit});

  final DiaryEntry entry;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final a = AlmanacUtil.of(entry.date);
    final e = entry;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        // 日期头
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('yyyy年M月d日').format(e.date),
                    style: const TextStyle(fontSize: 20, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${AlmanacUtil.weekdayCn(e.date)} · ${a.lunarText}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textHint),
                  ),
                  if (e.updatedAt != null &&
                      e.updatedAt!.difference(e.createdAt ?? e.updatedAt!).inMinutes.abs() > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '编辑于 ${DateFormat('M月d日 HH:mm').format(e.updatedAt!)}',
                        style: const TextStyle(fontSize: 11, color: AppColors.textDisabled),
                      ),
                    ),
                ],
              ),
            ),
            if (e.mood != null)
              Text(e.mood!, style: const TextStyle(fontSize: 28)),
            if (e.weather != null)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text(e.weather!, style: const TextStyle(fontSize: 22)),
              ),
          ],
        ),
        const Divider(height: 28),

        // 正文
        if (e.content.isNotEmpty)
          SelectableText(
            e.content,
            style: const TextStyle(fontSize: 15, height: 1.7, color: AppColors.textPrimary),
          ),

        // 语音
        if (e.audios.isNotEmpty) ...[
          const SizedBox(height: 20),
          ...e.audios.map((au) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  height: 56,
                  child: MediaPreviewTile(media: au.toCapturedMedia()),
                ),
              )),
        ],

        // 图片
        if (e.images.isNotEmpty) ...[
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: e.images.length,
            itemBuilder: (_, i) => _ImageViewer(
              images: e.images.map((x) => x.path).toList(),
              index: i,
            ),
          ),
        ],

        // 视频
        if (e.videos.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...e.videos.map((v) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: MediaPreviewTile(media: v.toCapturedMedia()),
                ),
              )),
        ],

        const SizedBox(height: 32),
        Center(
          child: TextButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('编辑这篇日记'),
          ),
        ),
      ],
    );
  }
}

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.images, required this.index});

  final List<String> images;
  final int index;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _FullscreenGallery(images: images, initial: index),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(
          File(images[index]),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const ColoredBox(
            color: AppColors.surfaceNeutral,
            child: Icon(Icons.broken_image_outlined, color: AppColors.textDisabled),
          ),
        ),
      ),
    );
  }
}

class _FullscreenGallery extends StatefulWidget {
  const _FullscreenGallery({required this.images, required this.initial});

  final List<String> images;
  final int initial;

  @override
  State<_FullscreenGallery> createState() => _FullscreenGalleryState();
}

class _FullscreenGalleryState extends State<_FullscreenGallery> {
  late final PageController _ctrl = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1}/${widget.images.length}'),
      ),
      body: PageView.builder(
        controller: _ctrl,
        itemCount: widget.images.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) => InteractiveViewer(
          maxScale: 4,
          child: Center(
            child: Image.file(File(widget.images[i]), fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.date, required this.onWrite});

  final DateTime date;
  final VoidCallback onWrite;

  @override
  Widget build(BuildContext context) {
    final a = AlmanacUtil.of(date);
    return EmptyState(
      actionLabel: '写一篇',
      onAction: onWrite,
      children: [
        Text(
          DateFormat('yyyy年M月d日').format(date),
          style: const TextStyle(fontSize: 15, color: AppColors.textSecondaryAlt),
        ),
        const SizedBox(height: 4),
        Text(
          '${a.lunarText} · ${a.ganZhi}',
          style: const TextStyle(fontSize: 12, color: AppColors.textHint),
        ),
        const SizedBox(height: 8),
        const Text('这一天还没有日记',
            style: TextStyle(fontSize: 13, color: AppColors.textDisabled)),
      ],
    );
  }
}

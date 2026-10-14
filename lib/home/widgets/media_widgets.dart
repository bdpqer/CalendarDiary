import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../user_data/diary_text.dart';
import '../../user_data/media_capture_service.dart';
import '../../theme/app_colors.dart';

/// 全局语音播放器（同一时刻只播放一条语音）
class VoicePlayer extends ChangeNotifier {
  VoicePlayer._() {
    _player.onPlayerComplete.listen((_) {
      _playing = false;
      _position = _duration;
      notifyListeners();
    });
    _player.onDurationChanged.listen((d) {
      _duration = d;
      notifyListeners();
    });
    _player.onPositionChanged.listen((p) {
      _position = p;
      notifyListeners();
    });
  }

  static final VoicePlayer instance = VoicePlayer._();

  final AudioPlayer _player = AudioPlayer();
  String? _path;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  /// 当前正在播放（含暂停）的文件路径
  String? get path => _path;
  bool get playing => _playing;
  Duration get position => _position;
  Duration get duration => _duration;

  /// 点击切换：播放 / 暂停 / 换文件
  Future<void> toggle(String path) async {
    if (_path == path) {
      if (_playing) {
        await _player.pause();
        _playing = false;
      } else {
        await _player.resume();
        _playing = true;
      }
      notifyListeners();
      return;
    }
    // 切换到新文件
    await _player.play(DeviceFileSource(path));
    _path = path;
    _playing = true;
    _position = Duration.zero;
    _duration = Duration.zero;
    notifyListeners();
  }
}

/// 媒体预览播放器（图片 / 语音 / 视频）
class MediaPreviewTile extends StatefulWidget {
  const MediaPreviewTile({
    super.key,
    required this.media,
    this.onDelete,
  });

  final CapturedMedia media;
  final VoidCallback? onDelete;

  @override
  State<MediaPreviewTile> createState() => _MediaPreviewTileState();
}

class _MediaPreviewTileState extends State<MediaPreviewTile> {
  VideoPlayerController? _video;
  bool _videoReady = false;

  /// 初始化失败（文件被外部删除 / 编码不受支持）
  bool _videoFailed = false;

  @override
  void initState() {
    super.initState();
    if (widget.media.type == MediaType.video) {
      _initVideo();
    }
  }

  Future<void> _initVideo() async {
    final c = VideoPlayerController.file(File(widget.media.path));
    _video = c;
    try {
      await c.initialize();
      if (mounted) setState(() => _videoReady = true);
    } catch (_) {
      // 此前没有 try/catch：文件缺失或编码不支持时会抛出未捕获的异步异常
      // （原生侧打印 stack，卡片则永久停在「点击播放」占位，点了也没反应）。
      // 现在明确降级为「无法播放」占位。
      if (mounted) setState(() => _videoFailed = true);
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.media;
    Widget content;

    switch (m.type) {
      case MediaType.image:
        content = ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(
            File(m.path),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, __, ___) => const _Broken(),
          ),
        );
        break;

      case MediaType.video:
        content = ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: _videoReady && _video != null
              ? Stack(
                  alignment: Alignment.center,
                  children: [
                    FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: _video!.value.size.width,
                        height: _video!.value.size.height,
                        child: VideoPlayer(_video!),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() {
                        _video!.value.isPlaying ? _video!.pause() : _video!.play();
                      }),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _video!.value.isPlaying
                              ? Icons.pause
                              : Icons.play_arrow,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  ],
                )
              : _videoFailed
                  ? const ColoredBox(
                      color: AppColors.textPrimary,
                      child: Center(
                        child: Icon(Icons.videocam_off_outlined,
                            color: Colors.white38, size: 30),
                      ),
                    )
                  : const ColoredBox(
                      color: AppColors.textPrimary,
                      child: Center(
                        child: Icon(Icons.play_circle_outline,
                            color: Colors.white38, size: 30),
                      ),
                    ),
        );
        break;

      case MediaType.audio:
        content = _AudioTile(media: m);
        break;
    }

    return Stack(
      children: [
        Positioned.fill(child: content),
        if (widget.onDelete != null)
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: widget.onDelete,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }
}

/// 语音条目：点击播放 / 暂停，带进度
class _AudioTile extends StatefulWidget {
  const _AudioTile({required this.media});

  final CapturedMedia media;

  @override
  State<_AudioTile> createState() => _AudioTileState();
}

class _AudioTileState extends State<_AudioTile> {
  VoicePlayer get _vp => VoicePlayer.instance;

  @override
  void initState() {
    super.initState();
    _vp.addListener(_onPlayerChanged);
  }

  void _onPlayerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _vp.removeListener(_onPlayerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.media;
    final active = _vp.path == m.path;
    final playing = active && _vp.playing;
    final hasDur = active && _vp.duration.inMilliseconds > 0;
    final progress = hasDur
        ? (_vp.position.inMilliseconds / _vp.duration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;

    // 右侧信息：播放中显示进度，否则显示时长（未采集到时长则退回文件大小）
    // 两条文案都复用 `diary_text.dart` 里的纯函数，不再就地重写一份格式化逻辑。
    final String meta;
    if (hasDur) {
      meta = '${formatClock(_vp.position)} / ${formatClock(_vp.duration)}';
    } else {
      final duration = mediaDurationText(m.durationMs);
      final size = mediaSizeText(m.sizeBytes);
      meta = duration.isNotEmpty
          ? duration
          : (size.isNotEmpty ? size : '点击播放');
    }

    return GestureDetector(
      onTap: () => _vp.toggle(m.path),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? AppColors.primary.withValues(alpha: 0.10)
              : AppColors.surfaceNeutral,
          borderRadius: BorderRadius.circular(10),
          border: active
              ? Border.all(color: AppColors.primary.withValues(alpha: 0.45))
              : null,
        ),
        child: Row(
          children: [
            // 播放/暂停按钮
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(
                playing ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('语音 · $meta',
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textPrimary)),
                  const SizedBox(height: 5),
                  // 进度条
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: SizedBox(
                      height: 3,
                      child: LinearProgressIndicator(
                        value: playing || (active && progress > 0)
                            ? progress
                            : 0,
                        backgroundColor:
                            AppColors.primary.withValues(alpha: 0.18),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            AppColors.primary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Broken extends StatelessWidget {
  const _Broken();

  @override
  Widget build(BuildContext context) => const ColoredBox(
        color: AppColors.surfaceNeutral,
        child: Center(
          child: Icon(Icons.broken_image_outlined, color: AppColors.textDisabled),
        ),
      );
}

/// 录音悬浮控制条
class RecordingBar extends StatefulWidget {
  const RecordingBar({super.key, required this.onCancel, required this.onStop});

  final VoidCallback onCancel;
  final VoidCallback onStop;

  @override
  State<RecordingBar> createState() => _RecordingBarState();
}

class _RecordingBarState extends State<RecordingBar> {
  Timer? _timer;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = formatClock(Duration(seconds: _seconds));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: AppColors.textPrimary,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            const _PulseDot(),
            const SizedBox(width: 10),
            Text(text,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontFeatures: [FontFeature.tabularFigures()])),
            const Spacer(),
            GestureDetector(
              onTap: widget.onCancel,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('取消',
                    style: TextStyle(color: Colors.white, fontSize: 14)),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: widget.onStop,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('完成',
                    style: TextStyle(color: Colors.white, fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Color.lerp(
              AppColors.danger, AppColors.recordPulse, _c.value),
        ),
      ),
    );
  }
}

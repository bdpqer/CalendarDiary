import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import 'diary_database.dart';

export 'diary_database.dart' show MediaType;

/// 媒体采集结果
class CapturedMedia {
  CapturedMedia(
    this.path,
    this.type, {
    this.durationMs = 0,
    this.sizeBytes = 0,
  });

  final String path;
  final MediaType type;
  final int durationMs;
  final int sizeBytes;
}

/// `CapturedMedia` → 数据库附件行（保存时用）
extension CapturedMediaToAttachment on CapturedMedia {
  DiaryAttachment toAttachment(int diaryId) => DiaryAttachment(
        diaryId: diaryId,
        type: type,
        path: path,
        durationMs: durationMs,
        sizeBytes: sizeBytes,
      );
}

/// 数据库附件行 → `CapturedMedia`（详情/编辑器展示用）
extension DiaryAttachmentToCaptured on DiaryAttachment {
  CapturedMedia toCapturedMedia() =>
      CapturedMedia(path, type, durationMs: durationMs, sizeBytes: sizeBytes);
}

/// 统一封装相机、相册、录音、视频的采集入口
class MediaCaptureService {
  MediaCaptureService._();

  static final MediaCaptureService instance = MediaCaptureService._();

  final ImagePicker _picker = ImagePicker();
  final AudioRecorder _recorder = AudioRecorder();

  bool _recording = false;
  bool get isRecording => _recording;

  /// 本次录音的开始时刻，用于在停止时算出真实时长
  ///
  /// `record` 插件只返回文件路径、不返回时长，此前 `durationMs` 恒为 0，
  /// 导致语音条只能退而显示文件大小。
  DateTime? _recordingStartedAt;

  // ---------------- 权限 ----------------

  Future<bool> ensureCamera() async =>
      (await Permission.camera.request()).isGranted;

  Future<bool> ensureMicrophone() async =>
      (await Permission.microphone.request()).isGranted;

  /// Android 13+ 用 READ_MEDIA_IMAGES / VIDEO，旧版本用 READ_EXTERNAL_STORAGE
  Future<bool> ensureGallery() async {
    if (!Platform.isAndroid) return true;
    if ((await Permission.photos.request()).isGranted) return true;
    if ((await Permission.videos.request()).isGranted) return true;
    return (await Permission.storage.request()).isGranted;
  }

  // ---------------- 图片 ----------------

  /// 从相册选图
  Future<List<CapturedMedia>> pickImages({int limit = 9}) async {
    final picked = await _picker.pickMultiImage(limit: limit);
    if (picked.isEmpty) return const [];
    return _importMany(picked.map((x) => x.path).toList(), MediaType.image);
  }

  /// 拍照
  Future<CapturedMedia?> takePhoto() async {
    final x = await _picker.pickImage(source: ImageSource.camera, imageQuality: 88);
    if (x == null) return null;
    return _importOne(x.path, MediaType.image);
  }

  // ---------------- 视频 ----------------

  /// 从相册选视频
  Future<List<CapturedMedia>> pickVideos({int limit = 3}) async {
    final out = <CapturedMedia>[];
    for (var i = 0; i < limit; i++) {
      final x = await _picker.pickVideo(source: ImageSource.gallery);
      if (x == null) break;
      final m = await _importOne(x.path, MediaType.video);
      if (m != null) out.add(m);
    }
    return out;
  }

  /// 拍摄视频
  Future<CapturedMedia?> recordVideoByCamera() async {
    final x = await _picker.pickVideo(source: ImageSource.camera);
    if (x == null) return null;
    return _importOne(x.path, MediaType.video);
  }

  // ---------------- 语音 ----------------

  /// 开始录音，返回是否成功（权限不足返回 false）
  Future<bool> startRecording() async {
    if (_recording) return true;
    final path = await _newVoicePath();
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: path,
    );
    _recording = true;
    _recordingStartedAt = DateTime.now();
    return true;
  }

  /// 停止录音
  Future<CapturedMedia?> stopRecording() async {
    if (!_recording) return null;
    final path = await _recorder.stop();
    _recording = false;
    final startedAt = _recordingStartedAt;
    _recordingStartedAt = null;
    if (path == null) return null;
    final f = File(path);
    if (!await f.exists()) return null;
    return CapturedMedia(
      path,
      MediaType.audio,
      durationMs: startedAt == null
          ? 0
          : DateTime.now().difference(startedAt).inMilliseconds,
      sizeBytes: await f.length(),
    );
  }

  /// 放弃本次录音并删除文件
  Future<void> cancelRecording() async {
    if (!_recording) return;
    final path = await _recorder.stop();
    _recording = false;
    _recordingStartedAt = null;
    if (path != null) {
      final f = File(path);
      if (await f.exists()) await f.delete();
    }
  }

  // ---------------- 内部工具 ----------------

  Future<String> _newVoicePath() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'diary_media'));
    await dir.create(recursive: true);
    return p.join(dir.path, 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a');
  }

  Future<CapturedMedia?> _importOne(String srcPath, MediaType type) async {
    final year = DateTime.now().year;
    final dest = await DiaryDatabase.instance.importFile(srcPath, type, year);
    final f = File(dest);
    return CapturedMedia(
      dest,
      type,
      sizeBytes: await f.exists() ? await f.length() : 0,
    );
  }

  Future<List<CapturedMedia>> _importMany(List<String> paths, MediaType type) async {
    final out = <CapturedMedia>[];
    for (final s in paths) {
      final m = await _importOne(s, type);
      if (m != null) out.add(m);
    }
    return out;
  }

  /// 打开系统设置（权限被永久拒绝时引导）
  Future<bool> openSettings() => openAppSettings();
}

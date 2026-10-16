import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用锁配置与鉴权服务（UI 层锁，不加密底层数据库）。
///
/// - PIN 由 [FlutterSecureStorage] 加密保管（Android 落 Keystore / iOS 落 Keychain），
///   不依赖额外的哈希依赖；验证时直接比对即可。
/// - 开关 / 指纹开关 / 锁定时机等配置存 [SharedPreferences]。
/// - 平台不支持（如测试宿主无 Keystore）时初始化失败会降级为「不可用」，
///   调用方据此当作「未启用锁」处理，保证 App 永远能进。
class AppLockService {
  AppLockService._();
  static final instance = AppLockService._();

  static const String _kPin = 'app_lock_pin';
  static const String _kEnabled = 'app_lock_enabled';
  static const String _kBiometric = 'app_lock_biometric';
  static const String _kLockMode = 'app_lock_mode';

  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  final LocalAuthentication _auth = LocalAuthentication();
  SharedPreferences? _prefs;

  /// 当前平台是否可用；初始化失败则为 false（等同于未启用锁）。
  bool _available = true;
  bool get available => _available;

  Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (_) {
      _available = false;
    }
  }

  bool get enabled => _prefs?.getBool(_kEnabled) ?? false;
  bool get biometricEnabled => _prefs?.getBool(_kBiometric) ?? false;

  LockMode get lockMode {
    final v = _prefs?.getString(_kLockMode);
    return LockMode.values.firstWhere(
      (e) => e.name == v,
      orElse: () => LockMode.always,
    );
  }

  Future<void> setEnabled(bool v) async => _prefs?.setBool(_kEnabled, v);
  Future<void> setBiometric(bool v) async => _prefs?.setBool(_kBiometric, v);
  Future<void> setLockMode(LockMode m) async => _prefs?.setString(_kLockMode, m.name);

  /// 是否已设置过 PIN（长度 >= 4 视为有效）。
  Future<bool> hasPin() async {
    try {
      final p = await _secure.read(key: _kPin);
      return p != null && p.length >= 4;
    } catch (_) {
      return false;
    }
  }

  static const String _kPinLength = 'app_lock_pin_length';

  /// 已设置 PIN 的目标长度（4-6），默认 4。
  int get pinLength => _prefs?.getInt(_kPinLength) ?? 4;

  Future<void> setPin(String pin) async {
    try {
      await _secure.write(key: _kPin, value: pin);
      _prefs?.setInt(_kPinLength, pin.length);
    } catch (_) {
      // 存储失败（如平台不支持）时静默，由调用方感知 available 判断。
    }
  }

  Future<void> clearPin() async {
    try {
      await _secure.delete(key: _kPin);
    } catch (_) {}
  }

  Future<bool> verifyPin(String pin) async {
    try {
      final stored = await _secure.read(key: _kPin);
      return stored == pin;
    } catch (_) {
      return false;
    }
  }

  /// 设备是否支持且已录入生物识别（指纹/面容）。
  Future<bool> canUseBiometrics() async {
    try {
      if (!await _auth.isDeviceSupported()) return false;
      final list = await _auth.getAvailableBiometrics();
      return list.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// 发起一次生物识别认证；成功返回 true。
  Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: '解锁日历日记',
        biometricOnly: true,
      );
    } catch (_) {
      return false;
    }
  }
}

/// 锁定时机：用户可在设置中自行选择。
enum LockMode {
  /// 每次从后台返回前台都重新锁定（最安全，默认）
  always,
  /// 仅冷启动锁定一次，之后一直可用直到完全退出
  launch,
  /// 后台超过 [kDelayedSeconds] 秒再锁定（短时切换不烦人）
  delayed,
}

/// 延迟锁定阈值（秒）
const kDelayedSeconds = 15;

extension LockModeLabel on LockMode {
  String get label {
    switch (this) {
      case LockMode.always:
        return '每次回到前台';
      case LockMode.launch:
        return '仅启动时';
      case LockMode.delayed:
        return '后台 15 秒后';
    }
  }
}

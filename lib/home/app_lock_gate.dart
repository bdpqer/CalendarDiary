import 'package:flutter/material.dart';

import '../user_data/app_lock.dart';
import 'lock_screen.dart';

/// 应用锁入口拦截层：包裹真正的首页。
///
/// - 冷启动时先读取锁配置，初始化完成前显示白色占位（不闪现主页内容）；
/// - 之后按用户设置的 [LockMode] 在 App 从后台回到前台时决定是否重新锁定。
/// - 平台不支持（如测试宿主无 Keystore）时降级为「不锁」，保证 App 永远能进。
class AppLockGate extends StatefulWidget {
  final Widget child;

  const AppLockGate({super.key, required this.child});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate>
    with WidgetsBindingObserver {
  /// 锁配置是否已读取完成。未完成前显示白色占位，避免内容闪现。
  bool _ready = false;
  bool _locked = false;
  DateTime? _pausedAt;
  /// 上次成功解锁的时间；用于区分「真正离开前台」与「认证对话框关闭后的伪 resume」，
  /// 避免指纹/密码解锁成功后因伪 resume 被立刻重锁（表现为「解锁后还要再输密码」）。
  DateTime? _unlockedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    final svc = AppLockService.instance;
    if (!svc.available) {
      if (mounted) {
        setState(() {
          _ready = true;
          _locked = false;
        });
      }
      return;
    }
    await svc.init();
    if (!mounted) return;
    final lock = svc.enabled && await svc.hasPin();
    setState(() {
      _ready = true;
      _locked = lock;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final svc = AppLockService.instance;
    if (!svc.available || !svc.enabled) return;
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      // 仅当 App 真正离开过前台（paused 发生在上次解锁之后）才重新锁定。
      // 否则指纹/密码认证对话框关闭时系统会再派发一次 resumed，若直接重锁，
      // 会让刚解锁成功的界面又被锁上，表现为「指纹解锁后还要再输密码」。
      final reallyLeft = _pausedAt != null &&
          (_unlockedAt == null || _pausedAt!.isAfter(_unlockedAt!));
      if (reallyLeft) {
        final mode = svc.lockMode;
        final shouldLock = switch (mode) {
          LockMode.always => true,
          LockMode.launch => false,
          LockMode.delayed => _delayedExceeded(),
        };
        if (shouldLock && mounted && !_locked) setState(() => _locked = true);
      }
      _pausedAt = null;
    }
  }

  bool _delayedExceeded() {
    final dt = _pausedAt == null
        ? const Duration(seconds: kDelayedSeconds + 1)
        : DateTime.now().difference(_pausedAt!);
    return dt.inSeconds >= kDelayedSeconds;
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      // 初始化期间显示白色占位：既不闪现未锁定时的主页内容，
      // 也避免启用锁时首帧泄漏日记数据。
      return const ColoredBox(color: Colors.white, child: SizedBox.expand());
    }
    if (_locked) {
      return LockScreen(
        biometricEnabled: AppLockService.instance.biometricEnabled,
        onUnlocked: () {
          if (mounted) {
            _unlockedAt = DateTime.now();
            setState(() => _locked = false);
          }
        },
      );
    }
    return widget.child;
  }
}

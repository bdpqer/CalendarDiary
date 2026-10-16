import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../user_data/app_lock.dart';

/// 锁屏界面：数字 PIN 输入 + 可选指纹解锁。
///
/// [biometricEnabled] 为 true 时显示指纹按钮；[onUnlocked] 解锁成功后回调，
/// 由调用方移除锁层。
class LockScreen extends StatefulWidget {
  final bool biometricEnabled;
  final VoidCallback onUnlocked;

  const LockScreen({
    super.key,
    required this.biometricEnabled,
    required this.onUnlocked,
  });

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final List<String> _digits = [];
  String? _error;
  bool _checking = false;

  int get _target => AppLockService.instance.pinLength;

  void _onKey(String k) {
    if (_checking) return;
    if (k == 'del') {
      if (_digits.isNotEmpty) {
        setState(() {
          _digits.removeLast();
          _error = null;
        });
      }
      return;
    }
    if (_digits.length >= 6) return;
    setState(() => _digits.add(k));
    if (_digits.length == _target) _verify();
  }

  Future<void> _verify() async {
    final pin = _digits.join();
    setState(() => _checking = true);
    final ok = await AppLockService.instance.verifyPin(pin);
    if (!mounted) return;
    if (ok) {
      widget.onUnlocked();
      return;
    }
    setState(() {
      _checking = false;
      _error = '密码错误，请重试';
      _digits.clear();
    });
  }

  Future<void> _onBiometric() async {
    final svc = AppLockService.instance;
    // 先确认设备仍支持生物识别，避免无谓弹窗或静默失败
    final avail = await svc.canUseBiometrics();
    if (!mounted) return;
    if (!avail) {
      setState(() => _error = '该设备暂不支持指纹解锁，请使用密码');
      return;
    }
    final ok = await svc.authenticate();
    if (!mounted) return;
    if (ok) {
      widget.onUnlocked();
    } else {
      setState(() => _error = '指纹识别未通过，请重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 56),
            const Icon(Icons.lock_outline, size: 48, color: AppColors.primary),
            const SizedBox(height: 16),
            const Text('日历日记已锁定',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textStrong)),
            const SizedBox(height: 8),
            const Text('输入密码以继续',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
            const SizedBox(height: 32),
            _Dots(count: _target, filled: _digits.length),
            const SizedBox(height: 12),
            SizedBox(
              height: 18,
              child: _error != null
                  ? Text(_error!,
                      style: const TextStyle(fontSize: 13, color: AppColors.red))
                  : null,
            ),
            const Spacer(),
            if (widget.biometricEnabled)
              IconButton(
                onPressed: _onBiometric,
                icon: const Icon(Icons.fingerprint, size: 42, color: AppColors.primary),
                tooltip: '指纹解锁',
              ),
            const SizedBox(height: 12),
            PinPad(onKey: _onKey),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// PIN 圆点指示器（已输入位数高亮）。
class _Dots extends StatelessWidget {
  final int count;
  final int filled;

  const _Dots({required this.count, required this.filled});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final on = i < filled;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? AppColors.primary : Colors.transparent,
            border: Border.all(color: AppColors.primary, width: 1.5),
          ),
        );
      }),
    );
  }
}

/// 数字键盘（供锁屏与设置页设 PIN 复用）。
///
/// 回调 [onKey] 收到 `'0'..'9'` 或 `'del'`（删除一位）。
class PinPad extends StatelessWidget {
  final void Function(String) onKey;

  const PinPad({super.key, required this.onKey});

  @override
  Widget build(BuildContext context) {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', 'del'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 1.7,
        children: keys.map((k) {
          if (k.isEmpty) return const SizedBox.shrink();
          if (k == 'del') {
            return _Key(
              icon: Icons.backspace_outlined,
              onTap: () => onKey('del'),
            );
          }
          return _Key(text: k, onTap: () => onKey(k));
        }).toList(),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  final String? text;
  final IconData? icon;
  final VoidCallback onTap;

  const _Key({this.text, this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Center(
        child: text != null
            ? Text(text!,
                style: const TextStyle(fontSize: 24, color: AppColors.textStrong))
            : Icon(icon, size: 24, color: AppColors.textStrong),
      ),
    );
  }
}

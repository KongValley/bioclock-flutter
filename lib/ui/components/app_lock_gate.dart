import 'package:bioclock/ui/components/app_icon.dart';
import 'package:bioclock/ui/components/app_primitives.dart';
import 'package:bioclock/ui/components/app_scope.dart';
import 'package:bioclock/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';

/// 校验当前设备是否支持生物识别/设备凭据，并拉起系统认证弹窗。
Future<bool> authenticateBiometricOrDevice({
  required String reason,
  bool requireEnrolledHardware = false,
}) async {
  final auth = LocalAuthentication();
  if (requireEnrolledHardware) {
    final supported = await auth.isDeviceSupported();
    final canCheck = await auth.canCheckBiometrics;
    if (!supported && !canCheck) {
      throw StateError('此设备不支持身份验证，无法开启应用锁。');
    }
    final available = await auth.getAvailableBiometrics();
    if (!supported && available.isEmpty) {
      throw StateError('请先在系统设置中录入指纹、面容或锁屏密码。');
    }
  }
  return auth.authenticate(
    localizedReason: reason,
    authMessages: const [
      AndroidAuthMessages(
        signInTitle: 'BioClock 身份验证',
        signInHint: '请验证身份继续',
        cancelButton: '取消',
      ),
    ],
    biometricOnly: false,
  );
}

/// 应用锁：包在主界面和弹窗外层，后台超过 30 秒回前台重新上锁。
class AppLockGate extends StatefulWidget {
  const AppLockGate({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> {
  static const int _relockThresholdMs = 30000;

  bool _unlocked = false;
  bool _busy = false;
  String? _error;
  bool? _previousLock;
  int _backgroundAt = 0;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: () => _backgroundAt = DateTime.now().millisecondsSinceEpoch,
      onPause: () => _backgroundAt = DateTime.now().millisecondsSinceEpoch,
      onResume: _handleResume,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final lockEnabled = context.store.settings['app_lock'] == '1';
    final prev = _previousLock;
    if (!lockEnabled) {
      _unlocked = false;
      _previousLock = false;
      _error = null;
      return;
    }
    if (prev == false) {
      // 用户刚在设置页开启应用锁：开启前已完成验证，本会话保持解锁。
      _previousLock = true;
      _unlocked = true;
      return;
    }
    _previousLock = true;
    if (!_unlocked && !_busy) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_unlocked && !_busy) {
          _unlock();
        }
      });
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _handleResume() {
    final lockEnabled = context.store.settings['app_lock'] == '1';
    if (!lockEnabled) return;
    final elapsed = DateTime.now().millisecondsSinceEpoch - _backgroundAt;
    if (_backgroundAt > 0 && elapsed > _relockThresholdMs) {
      setState(() => _unlocked = false);
      _unlock();
    }
  }

  Future<bool> _authenticate(String reason) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await authenticateBiometricOrDevice(reason: reason);
      if (ok) return true;
      if (mounted) setState(() => _error = '未通过验证，请重试。');
      return false;
    } catch (_) {
      if (mounted) setState(() => _error = '身份验证失败，请重试。');
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlock() async {
    if (await _authenticate('解锁 BioClock')) {
      if (mounted) setState(() => _unlocked = true);
    }
  }

  Future<void> _closeLock() async {
    if (!(await _authenticate('验证身份后关闭应用锁'))) return;
    if (!mounted) return;
    try {
      final res = await context.store.updateSettings({'app_lock': '0'});
      if (mounted && res.notifyWarning != null) {
        setState(() => _error = res.notifyWarning);
      }
    } catch (err) {
      if (mounted) setState(() => _error = '关闭应用锁失败：$err');
    }
  }

  @override
  Widget build(BuildContext context) {
    final lockEnabled = context.store.settings['app_lock'] == '1';
    if (!lockEnabled || _unlocked) {
      return widget.child;
    }

    final theme = context.appTheme;
    return Scaffold(
      backgroundColor: theme.colors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: theme.spacing.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppIcon(
                  AppIconName.lock,
                  size: 44,
                  color: theme.colors.primary,
                  strokeWidth: 1.5,
                ),
                const SizedBox(height: 12),
                Semantics(
                  header: true,
                  child: Text(
                    'BioClock 已锁定',
                    style: TextStyle(
                      color: theme.colors.text,
                      fontSize: theme.fontSize.xxl,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: Text(
                    '使用指纹、面容或系统凭据解锁，查看你的注射与症状记录。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: theme.colors.textSecondary,
                      fontSize: theme.fontSize.sm,
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 300),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: theme.colors.danger,
                          fontSize: theme.fontSize.sm,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: Column(
                    children: [
                      AppButton(
                        label: _busy ? '验证中…' : '解锁',
                        onPressed: _unlock,
                        loading: _busy,
                        size: AppButtonSize.lg,
                        icon: AppIconName.unlock,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        AppButton(
                          label: '验证后关闭应用锁',
                          onPressed: _closeLock,
                          variant: AppButtonVariant.secondary,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

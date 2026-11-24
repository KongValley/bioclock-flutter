import 'dart:async';

import 'package:bioclock/notify/notify_scheduler.dart';
import 'package:flutter/widgets.dart';

/// 从后台回到前台时续排本地通知；系统权限弹窗导致的短暂失活不触发重排。
class ForegroundReminderWatcher {
  ForegroundReminderWatcher({
    required this.onError,
  }) {
    _listener = AppLifecycleListener(
      onHide: () => _wasBackground = true,
      onPause: () => _wasBackground = true,
      onResume: _handleResume,
    );
  }

  final VoidCallback onError;
  late final AppLifecycleListener _listener;
  bool _wasBackground = false;
  bool _disposed = false;

  void _handleResume() {
    if (!_wasBackground || _disposed) return;
    _wasBackground = false;
    unawaited(
      NotifyScheduler.rescheduleAll().catchError((_) {
        if (!_disposed) onError();
        return 0;
      }),
    );
  }

  void dispose() {
    _disposed = true;
    _listener.dispose();
  }
}

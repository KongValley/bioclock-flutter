import 'dart:async';

import 'package:bioclock/db/database.dart';
import 'package:bioclock/i18n/zh.dart';
import 'package:bioclock/notify/notify_lifecycle.dart';
import 'package:bioclock/notify/notify_scheduler.dart';
import 'package:bioclock/screens/home_tabs_screen.dart';
import 'package:bioclock/screens/onboarding_screen.dart';
import 'package:bioclock/store/app_store.dart';
import 'package:bioclock/ui/components/app_layout.dart';
import 'package:bioclock/ui/components/app_lock_gate.dart';
import 'package:bioclock/ui/components/app_scope.dart';
import 'package:bioclock/ui/theme.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppDatabase.ensureFfiInitialized();
  runApp(BioClockApp(store: AppStore()));
}

class BioClockApp extends StatefulWidget {
  const BioClockApp({
    super.key,
    required this.store,
    this.skipNotifyInit = false,
  });

  final AppStore store;
  final bool skipNotifyInit;

  @override
  State<BioClockApp> createState() => _BioClockAppState();
}

class _BioClockAppState extends State<BioClockApp> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  ForegroundReminderWatcher? _watcher;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void didChangePlatformBrightness() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _watcher?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      if (!widget.store.ready) {
        await AppDatabase.initDatabase();
        await widget.store.reload();
      }

      if (!widget.skipNotifyInit) {
        await NotifyScheduler.initialize(
          onTap: widget.store.handleNotificationPayload,
        );
        final launchPayload = await NotifyScheduler.getLaunchPayload();
        if (launchPayload != null) {
          widget.store.handleNotificationPayload(launchPayload);
        }
        if (widget.store.isOnboarded) {
          unawaited(
            NotifyScheduler.rescheduleAll().catchError((_) {
              showToast(Zh.notify.refreshFailed, isError: true);
              return 0;
            }),
          );
        }
        _watcher?.dispose();
        _watcher = ForegroundReminderWatcher(
          onError: () => showToast(Zh.notify.refreshFailed, isError: true),
        );
      }
    } catch (_) {
      // 错误状态已由 AppStore 写入并渲染 ErrorView
    }
  }

  void _openOnboardingModal() {
    final nav = _navKey.currentState;
    if (nav == null) return;
    nav.push<void>(
      MaterialPageRoute<void>(
        builder: (ctx) => OnboardingScreen(
          canPop: true,
          onCompleted: () {
            if (Navigator.of(ctx).canPop()) {
              Navigator.of(ctx).pop();
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final brightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;

    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final mode = AppThemeMode.parse(widget.store.settings['theme_mode']);
        final appTheme = resolveTheme(mode, brightness);

        Widget home;
        if (!widget.store.ready) {
          home = Scaffold(
            backgroundColor: appTheme.colors.background,
            body: const LoadingView(label: '正在加载本地数据…'),
          );
        } else if (widget.store.error != null &&
            widget.store.medications.isEmpty) {
          home = Scaffold(
            backgroundColor: appTheme.colors.background,
            body: ErrorView(
              message: widget.store.error!,
              onRetry: _bootstrap,
            ),
          );
        } else if (!widget.store.isOnboarded) {
          home = OnboardingScreen(
            onCompleted: () {},
          );
        } else {
          home = HomeTabsScreen(
            onOpenOnboarding: _openOnboardingModal,
          );
        }

        return AppThemeScope(
          theme: appTheme,
          child: AppStoreScope(
            store: widget.store,
            child: MaterialApp(
              navigatorKey: _navKey,
              debugShowCheckedModeBanner: false,
              title: 'BioClock',
              theme: buildMaterialTheme(appTheme),
              builder: (context, child) => Stack(
                children: [
                  AppLockGate(
                    child: child ?? const SizedBox.shrink(),
                  ),
                  const ToastOverlay(),
                ],
              ),
              home: home,
            ),
          ),
        );
      },
    );
  }
}

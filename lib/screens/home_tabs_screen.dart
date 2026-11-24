import 'package:bioclock/i18n/zh.dart';
import 'package:bioclock/models/types.dart';
import 'package:bioclock/screens/modals/injection_modal.dart';
import 'package:bioclock/screens/modals/oral_modal.dart';
import 'package:bioclock/screens/tabs/calendar_tab.dart';
import 'package:bioclock/screens/tabs/history_tab.dart';
import 'package:bioclock/screens/tabs/settings_tab.dart';
import 'package:bioclock/screens/tabs/today_tab.dart';
import 'package:bioclock/screens/tabs/trends_tab.dart';
import 'package:bioclock/ui/components/app_icon.dart';
import 'package:bioclock/ui/components/app_scope.dart';
import 'package:bioclock/ui/theme.dart';
import 'package:flutter/material.dart';

class HomeTabsScreen extends StatefulWidget {
  const HomeTabsScreen({
    super.key,
    required this.onOpenOnboarding,
  });

  final VoidCallback onOpenOnboarding;

  @override
  State<HomeTabsScreen> createState() => _HomeTabsScreenState();
}

class _HomeTabsScreenState extends State<HomeTabsScreen> {
  int _index = 0;
  bool _openingNotificationRoute = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _consumeNotificationIfReady();
  }

  void _consumeNotificationIfReady() {
    if (_openingNotificationRoute) return;
    final store = context.store;
    if (store.pendingNotification == null || !store.isOnboarded) return;
    _openingNotificationRoute = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (!mounted) return;
        final route = store.consumePendingNotification();
        if (route == null) return;
        if (route.kind == LineKind.oral) {
          await showOralModal(
            context,
            initialLineId: route.lineId,
            scheduledAt: route.scheduledAt,
          );
        } else {
          await showInjectionModal(
            context,
            initialLineId: route.lineId,
          );
        }
      } finally {
        _openingNotificationRoute = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;

    return Scaffold(
      backgroundColor: theme.colors.background,
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _index,
          children: [
            TodayTab(onOpenOnboarding: widget.onOpenOnboarding),
            const HistoryTab(),
            CalendarTab(onOpenOnboarding: widget.onOpenOnboarding),
            TrendsTab(onOpenOnboarding: widget.onOpenOnboarding),
            SettingsTab(onOpenOnboarding: widget.onOpenOnboarding),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: theme.colors.surface,
          border: Border(
            top: BorderSide(color: theme.colors.border, width: 0.6),
          ),
        ),
        child: NavigationBar(
          height: 64,
          backgroundColor: theme.colors.surface,
          indicatorColor: theme.colors.primaryMuted,
          selectedIndex: _index,
          onDestinationSelected: (idx) => setState(() => _index = idx),
          destinations: [
            NavigationDestination(
              icon: AppIcon(
                AppIconName.home,
                size: 22,
                color: theme.colors.textTertiary,
              ),
              selectedIcon: AppIcon(
                AppIconName.home,
                size: 22,
                color: theme.colors.primary,
              ),
              label: Zh.tabs.today,
            ),
            NavigationDestination(
              icon: AppIcon(
                AppIconName.list,
                size: 22,
                color: theme.colors.textTertiary,
              ),
              selectedIcon: AppIcon(
                AppIconName.list,
                size: 22,
                color: theme.colors.primary,
              ),
              label: Zh.tabs.history,
            ),
            NavigationDestination(
              icon: AppIcon(
                AppIconName.calendar,
                size: 22,
                color: theme.colors.textTertiary,
              ),
              selectedIcon: AppIcon(
                AppIconName.calendar,
                size: 22,
                color: theme.colors.primary,
              ),
              label: Zh.tabs.calendar,
            ),
            NavigationDestination(
              icon: AppIcon(
                AppIconName.activity,
                size: 22,
                color: theme.colors.textTertiary,
              ),
              selectedIcon: AppIcon(
                AppIconName.activity,
                size: 22,
                color: theme.colors.primary,
              ),
              label: Zh.tabs.trends,
            ),
            NavigationDestination(
              icon: AppIcon(
                AppIconName.settings,
                size: 22,
                color: theme.colors.textTertiary,
              ),
              selectedIcon: AppIcon(
                AppIconName.settings,
                size: 22,
                color: theme.colors.primary,
              ),
              label: Zh.tabs.settings,
            ),
          ],
        ),
      ),
    );
  }
}

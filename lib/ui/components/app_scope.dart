import 'package:bioclock/store/app_store.dart';
import 'package:flutter/material.dart';

class AppStoreScope extends InheritedNotifier<AppStore> {
  const AppStoreScope({
    super.key,
    required AppStore store,
    required super.child,
  }) : super(notifier: store);

  static AppStore of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppStoreScope>();
    assert(scope != null, 'AppStoreScope not found in widget tree');
    return scope!.notifier!;
  }
}

extension AppStoreContext on BuildContext {
  AppStore get store => AppStoreScope.of(this);
}

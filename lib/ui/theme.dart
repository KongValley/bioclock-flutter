import 'package:flutter/material.dart';

/// 主题模式：跟随系统 / 强制浅色 / 强制深色。
enum AppThemeMode {
  system('system'),
  light('light'),
  dark('dark');

  const AppThemeMode(this.wire);
  final String wire;

  static AppThemeMode parse(String? raw) => switch (raw) {
        'light' => light,
        'dark' => dark,
        _ => system,
      };
}

class AppColors {
  const AppColors({
    required this.primary,
    required this.primaryMuted,
    required this.onPrimary,
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.border,
    required this.text,
    required this.textSecondary,
    required this.textTertiary,
    required this.success,
    required this.successMuted,
    required this.warning,
    required this.warningMuted,
    required this.danger,
    required this.dangerMuted,
    required this.overlay,
  });

  final Color primary;
  final Color primaryMuted;
  final Color onPrimary;
  final Color background;
  final Color surface;
  final Color surfaceMuted;
  final Color border;
  final Color text;
  final Color textSecondary;
  final Color textTertiary;
  final Color success;
  final Color successMuted;
  final Color warning;
  final Color warningMuted;
  final Color danger;
  final Color dangerMuted;
  final Color overlay;
}

class AppSpacing {
  const AppSpacing();
  final double xs = 4;
  final double sm = 8;
  final double md = 12;
  final double lg = 16;
  final double xl = 24;
  final double xxl = 32;
}

class AppRadius {
  const AppRadius();
  final double sm = 6;
  final double md = 10;
  final double lg = 14;
  final double xl = 20;
  final double pill = 999;
}

class AppFontSize {
  const AppFontSize();
  final double xs = 11;
  final double sm = 13;
  final double md = 15;
  final double lg = 17;
  final double xl = 20;
  final double xxl = 26;
  final double display = 34;
}

class AppLineHeight {
  const AppLineHeight();
  final double xs = 16;
  final double sm = 19;
  final double md = 22;
  final double lg = 24;
  final double xl = 28;
  final double xxl = 34;
  final double display = 42;
}

class AppThemeData {
  const AppThemeData({
    required this.name,
    required this.isDark,
    required this.colors,
    this.spacing = const AppSpacing(),
    this.radius = const AppRadius(),
    this.fontSize = const AppFontSize(),
    this.lineHeight = const AppLineHeight(),
  });

  final String name;
  final bool isDark;
  final AppColors colors;
  final AppSpacing spacing;
  final AppRadius radius;
  final AppFontSize fontSize;
  final AppLineHeight lineHeight;
}

const AppThemeData lightAppTheme = AppThemeData(
  name: 'light',
  isDark: false,
  colors: AppColors(
    primary: Color(0xFF2B6CB0),
    primaryMuted: Color(0xFFE6EFF8),
    onPrimary: Color(0xFFFFFFFF),
    background: Color(0xFFF7F9FB),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFEEF2F6),
    border: Color(0xFFDFE5EC),
    text: Color(0xFF1A202C),
    textSecondary: Color(0xFF4A5568),
    textTertiary: Color(0xFF7A8797),
    success: Color(0xFF2F855A),
    successMuted: Color(0xFFE6F4EC),
    warning: Color(0xFFB7791F),
    warningMuted: Color(0xFFFBF1DF),
    danger: Color(0xFFC53030),
    dangerMuted: Color(0xFFFBEAEA),
    overlay: Color.fromRGBO(15, 20, 25, 0.45),
  ),
);

const AppThemeData darkAppTheme = AppThemeData(
  name: 'dark',
  isDark: true,
  colors: AppColors(
    primary: Color(0xFF6AA9DE),
    primaryMuted: Color(0xFF1B2A3A),
    onPrimary: Color(0xFF0B1520),
    background: Color(0xFF0F1419),
    surface: Color(0xFF171E26),
    surfaceMuted: Color(0xFF1F2933),
    border: Color(0xFF2D3748),
    text: Color(0xFFF0F4F8),
    textSecondary: Color(0xFFA8B3C1),
    textTertiary: Color(0xFF7A8797),
    success: Color(0xFF68D391),
    successMuted: Color(0xFF17301F),
    warning: Color(0xFFF6C177),
    warningMuted: Color(0xFF332512),
    danger: Color(0xFFFC8181),
    dangerMuted: Color(0xFF3A1A1A),
    overlay: Color.fromRGBO(0, 0, 0, 0.6),
  ),
);

/// 解析用户模式与系统深浅色为当前主题，纯函数便于单测。
AppThemeData resolveTheme(AppThemeMode mode, Brightness? systemBrightness) {
  if (mode == AppThemeMode.dark) return darkAppTheme;
  if (mode == AppThemeMode.light) return lightAppTheme;
  return systemBrightness == Brightness.dark ? darkAppTheme : lightAppTheme;
}

/// 应用主字体：嵌入 MiSans（400/500/600/700 静态字重），避免 Windows 默认落回宋体。
const String appFontFamily = 'MiSans';
const List<String> appFontFamilyFallback = [
  'MiSans',
  'Microsoft YaHei UI',
  'Microsoft YaHei',
  'PingFang SC',
  'Noto Sans CJK SC',
  'Segoe UI',
];

ThemeData buildMaterialTheme(AppThemeData t) {
  final brightness = t.isDark ? Brightness.dark : Brightness.light;
  final baseText =
      (t.isDark ? Typography.material2021().white : Typography.material2021().black)
          .apply(
    fontFamily: appFontFamily,
    fontFamilyFallback: appFontFamilyFallback,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: appFontFamily,
    fontFamilyFallback: appFontFamilyFallback,
    textTheme: baseText,
    scaffoldBackgroundColor: t.colors.background,
    canvasColor: t.colors.surface,
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: t.colors.primary,
      onPrimary: t.colors.onPrimary,
      secondary: t.colors.primaryMuted,
      onSecondary: t.colors.primary,
      error: t.colors.danger,
      onError: t.colors.onPrimary,
      surface: t.colors.surface,
      onSurface: t.colors.text,
      outline: t.colors.border,
    ),
    dividerColor: t.colors.border,
    dialogTheme: DialogThemeData(
      backgroundColor: t.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.radius.lg),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.colors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(t.radius.xl)),
      ),
    ),
  );
}

class AppThemeScope extends InheritedWidget {
  const AppThemeScope({
    super.key,
    required this.theme,
    required super.child,
  });

  final AppThemeData theme;

  static AppThemeData of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppThemeScope>();
    return scope?.theme ?? lightAppTheme;
  }

  @override
  bool updateShouldNotify(covariant AppThemeScope oldWidget) =>
      oldWidget.theme != theme;
}

extension AppThemeBuildContext on BuildContext {
  AppThemeData get appTheme => AppThemeScope.of(this);
}

/// 将 `#RRGGBB` 转为 Color，非法格式返回主题主色。
Color parseHexColor(String hex, {Color fallback = const Color(0xFF2B6CB0)}) {
  final clean = hex.trim().replaceFirst('#', '');
  if (clean.length == 6) {
    final v = int.tryParse('FF$clean', radix: 16);
    if (v != null) return Color(v);
  }
  if (clean.length == 8) {
    final v = int.tryParse(clean, radix: 16);
    if (v != null) return Color(v);
  }
  return fallback;
}

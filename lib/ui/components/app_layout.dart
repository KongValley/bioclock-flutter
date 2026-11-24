import 'package:bioclock/i18n/zh.dart';
import 'package:bioclock/store/app_store.dart';
import 'package:bioclock/ui/components/app_icon.dart';
import 'package:bioclock/ui/components/app_primitives.dart';
import 'package:bioclock/ui/theme.dart';
import 'package:flutter/material.dart';

/// 桌面窗口宽度较大时自动收窄内容列（maxWidth: 680），手机端占满宽度。
class ResponsiveContainer extends StatelessWidget {
  const ResponsiveContainer({
    super.key,
    required this.child,
    this.maxWidth = 680,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.right,
  });

  final String title;
  final String? subtitle;
  final Widget? right;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return ResponsiveContainer(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          theme.spacing.lg,
          theme.spacing.md,
          theme.spacing.lg,
          theme.spacing.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: TextStyle(
                        color: theme.colors.text,
                        fontSize: theme.fontSize.xxl,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        color: theme.colors.textSecondary,
                        fontSize: theme.fontSize.sm,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (right != null) ...[
              SizedBox(width: theme.spacing.md),
              right!,
            ],
          ],
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.title,
    this.hint,
    this.right,
  });

  final String title;
  final String? hint;
  final Widget? right;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: theme.colors.text,
                  fontSize: theme.fontSize.lg,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (hint != null && hint!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  hint!,
                  style: TextStyle(
                    color: theme.colors.textTertiary,
                    fontSize: theme.fontSize.xs,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (right != null) ...[
          const SizedBox(width: 8),
          right!,
        ],
      ],
    );
  }
}

class InlineError extends StatelessWidget {
  const InlineError({
    super.key,
    required this.message,
    this.onRetry,
  });

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colors.dangerMuted,
          borderRadius: BorderRadius.circular(theme.radius.md),
          border: Border.all(color: theme.colors.danger, width: 0.7),
        ),
        padding: EdgeInsets.all(theme.spacing.md),
        child: Row(
          children: [
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: theme.colors.danger,
                  fontSize: theme.fontSize.sm,
                ),
              ),
            ),
            if (onRetry != null)
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
                child: TextButton(
                  onPressed: onRetry,
                  child: Text(
                    Zh.common.retry,
                    style: TextStyle(
                      color: theme.colors.danger,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class StateView extends StatelessWidget {
  const StateView({
    super.key,
    this.icon = AppIconName.inbox,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final AppIconName icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final boxSize = compact ? 44.0 : 56.0;
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: compact ? theme.spacing.xl : theme.spacing.xxl,
        horizontal: theme.spacing.lg,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: boxSize,
            height: boxSize,
            decoration: BoxDecoration(
              color: theme.colors.surfaceMuted,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: AppIcon(
              icon,
              size: compact ? 22 : 28,
              color: theme.colors.textTertiary,
              strokeWidth: 1.75,
            ),
          ),
          const SizedBox(height: 10),
          Semantics(
            header: true,
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.colors.text,
                fontSize: theme.fontSize.lg,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (message != null && message!.isNotEmpty) ...[
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                message!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.colors.textSecondary,
                  fontSize: theme.fontSize.sm,
                ),
              ),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 14),
            AppButton(
              label: actionLabel!,
              onPressed: onAction,
              variant: AppButtonVariant.secondary,
              fullWidth: false,
            ),
          ],
        ],
      ),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: theme.colors.primary),
          const SizedBox(height: 12),
          Text(
            label ?? Zh.common.loading,
            style: TextStyle(
              color: theme.colors.textSecondary,
              fontSize: theme.fontSize.sm,
            ),
          ),
        ],
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.message,
    this.onRetry,
  });

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: StateView(
        icon: AppIconName.alert,
        title: Zh.common.loadFailed,
        message: message,
        actionLabel: onRetry != null ? Zh.common.retry : null,
        onAction: onRetry,
      ),
    );
  }
}

class SegmentOption<T> {
  const SegmentOption({required this.value, required this.label});
  final T value;
  final String label;
}

class SegmentedControl<T> extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.options,
    required this.value,
    required this.onChange,
    this.semanticLabel,
  });

  final List<SegmentOption<T>> options;
  final T value;
  final ValueChanged<T> onChange;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Semantics(
      label: semanticLabel,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colors.surfaceMuted,
          borderRadius: BorderRadius.circular(theme.radius.md),
        ),
        padding: const EdgeInsets.all(3),
        child: Row(
          children: [
            for (var i = 0; i < options.length; i += 1) ...[
              if (i > 0) const SizedBox(width: 3),
              Expanded(
                child: _SegmentItem(
                  label: options[i].label,
                  selected: options[i].value == value,
                  onTap: () => onChange(options[i].value),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SegmentItem extends StatelessWidget {
  const _SegmentItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? theme.colors.surface : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(theme.radius.sm),
          side: BorderSide(
            color: selected ? theme.colors.border : Colors.transparent,
            width: 0.7,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(theme.radius.sm),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Center(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected
                      ? theme.colors.text
                      : theme.colors.textSecondary,
                  fontSize: theme.fontSize.sm,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class StepperField extends StatelessWidget {
  const StepperField({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = -999999,
    this.max = 999999,
    this.step = 1,
    this.suffix,
    this.label,
    this.decreaseLabel = '减少',
    this.increaseLabel = '增加',
    this.formatValue,
    this.disabled = false,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;
  final int step;
  final String? suffix;
  final String? label;
  final String decreaseLabel;
  final String increaseLabel;
  final String Function(int)? formatValue;
  final bool disabled;

  Widget _stepBtn(
    BuildContext context, {
    required AppIconName icon,
    required bool enabled,
    required String semantic,
    required VoidCallback onTap,
  }) {
    final theme = context.appTheme;
    return Semantics(
      button: true,
      enabled: enabled,
      label: semantic,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.35,
        child: Material(
          color: theme.colors.surfaceMuted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(theme.radius.sm),
            side: BorderSide(color: theme.colors.border),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(theme.radius.sm),
            onTap: enabled ? onTap : null,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: AppIcon(
                  icon,
                  size: 20,
                  color: theme.colors.text,
                  strokeWidth: 2.25,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final canDec = !disabled && value - step >= min;
    final canInc = !disabled && value + step <= max;
    final text = formatValue != null ? formatValue!(value) : '$value';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: TextStyle(
              color: theme.colors.textSecondary,
              fontSize: theme.fontSize.sm,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Row(
          children: [
            _stepBtn(
              context,
              icon: AppIconName.minus,
              enabled: canDec,
              semantic: decreaseLabel,
              onTap: () => onChanged((value - step).clamp(min, max)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colors.surface,
                  borderRadius: BorderRadius.circular(theme.radius.sm),
                  border: Border.all(color: theme.colors.border),
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text.rich(
                  TextSpan(
                    text: text,
                    style: TextStyle(
                      color: theme.colors.text,
                      fontSize: theme.fontSize.lg,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    children: [
                      if (suffix != null)
                        TextSpan(
                          text: ' $suffix',
                          style: TextStyle(
                            color: theme.colors.textTertiary,
                            fontSize: theme.fontSize.sm,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _stepBtn(
              context,
              icon: AppIconName.plus,
              enabled: canInc,
              semantic: increaseLabel,
              onTap: () => onChanged((value + step).clamp(min, max)),
            ),
          ],
        ),
      ],
    );
  }
}

class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.label,
    this.hint,
    this.value,
    this.onTap,
    this.right,
    this.destructive = false,
    this.last = false,
  });

  final String label;
  final String? hint;
  final String? value;
  final VoidCallback? onTap;
  final Widget? right;
  final bool destructive;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final content = Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: EdgeInsets.symmetric(
        horizontal: theme.spacing.lg,
        vertical: theme.spacing.md,
      ),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(
                bottom: BorderSide(color: theme.colors.border, width: 0.6),
              ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: destructive
                        ? theme.colors.danger
                        : theme.colors.text,
                    fontSize: theme.fontSize.md,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (hint != null && hint!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    hint!,
                    style: TextStyle(
                      color: theme.colors.textTertiary,
                      fontSize: theme.fontSize.xs,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (value != null && value!.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              value!,
              style: TextStyle(
                color: theme.colors.textSecondary,
                fontSize: theme.fontSize.sm,
              ),
            ),
          ],
          if (right != null) ...[
            const SizedBox(width: 8),
            right!,
          ],
          if (onTap != null) ...[
            const SizedBox(width: 4),
            AppIcon(
              AppIconName.chevronRight,
              size: 20,
              color: theme.colors.textTertiary,
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return content;
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        child: content,
      ),
    );
  }
}

class SwitchRow extends StatelessWidget {
  const SwitchRow({
    super.key,
    required this.label,
    this.hint,
    required this.value,
    required this.onChanged,
    this.disabled = false,
    this.last = false,
  });

  final String label;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool disabled;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Opacity(
      opacity: disabled ? 0.5 : 1.0,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: EdgeInsets.symmetric(
          horizontal: theme.spacing.lg,
          vertical: theme.spacing.md,
        ),
        decoration: BoxDecoration(
          border: last
              ? null
              : Border(
                  bottom: BorderSide(color: theme.colors.border, width: 0.6),
                ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: theme.colors.text,
                      fontSize: theme.fontSize.md,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (hint != null && hint!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      hint!,
                      style: TextStyle(
                        color: theme.colors.textTertiary,
                        fontSize: theme.fontSize.xs,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Semantics(
              toggled: value,
              label: label,
              child: Switch(
                value: value,
                onChanged: disabled ? null : onChanged,
                activeThumbColor: theme.colors.surface,
                activeTrackColor: theme.colors.primary,
                inactiveThumbColor: theme.colors.surface,
                inactiveTrackColor: theme.colors.border,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ToastOverlay extends StatelessWidget {
  const ToastOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return ListenableBuilder(
      listenable: ToastController.instance,
      builder: (context, _) {
        final msg = ToastController.instance.current;
        if (msg == null) return const SizedBox.shrink();
        final bg = msg.isError ? theme.colors.danger : theme.colors.text;
        return IgnorePointer(
          child: SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 96),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Material(
                    elevation: 6,
                    color: bg,
                    borderRadius: BorderRadius.circular(theme.radius.md),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          msg.text,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: theme.colors.onPrimary,
                            fontSize: theme.fontSize.sm,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String? confirmLabel,
  bool destructive = false,
}) async {
  final theme = context.appTheme;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: theme.colors.surface,
      title: Text(
        title,
        style: TextStyle(
          color: theme.colors.text,
          fontSize: theme.fontSize.lg,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: message == null
          ? null
          : Text(
              message,
              style: TextStyle(
                color: theme.colors.textSecondary,
                fontSize: theme.fontSize.sm,
              ),
            ),
      actions: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 64),
          child: TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              Zh.common.cancel,
              style: TextStyle(color: theme.colors.textSecondary),
            ),
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 64),
          child: TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              confirmLabel ?? Zh.common.confirm,
              style: TextStyle(
                color: destructive ? theme.colors.danger : theme.colors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    ),
  );
  return result == true;
}

class SheetActionItem {
  const SheetActionItem({
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool destructive;
}

Future<void> showActionSheet(
  BuildContext context, {
  String? title,
  required List<SheetActionItem> actions,
}) async {
  final theme = context.appTheme;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: theme.colors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(theme.radius.xl)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null)
            Padding(
              padding: EdgeInsets.fromLTRB(
                theme.spacing.lg,
                theme.spacing.lg,
                theme.spacing.lg,
                theme.spacing.sm,
              ),
              child: Text(
                title,
                style: TextStyle(
                  color: theme.colors.textTertiary,
                  fontSize: theme.fontSize.sm,
                ),
              ),
            ),
          for (final item in actions)
            ListTile(
              minTileHeight: 52,
              title: Text(
                item.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: item.destructive
                      ? theme.colors.danger
                      : theme.colors.text,
                  fontSize: theme.fontSize.md,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                item.onTap();
              },
            ),
          const Divider(height: 1),
          ListTile(
            minTileHeight: 52,
            title: Text(
              Zh.common.cancel,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.colors.textSecondary,
                fontSize: theme.fontSize.md,
              ),
            ),
            onTap: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    ),
  );
}

class SheetScaffold extends StatelessWidget {
  const SheetScaffold({
    super.key,
    required this.title,
    required this.body,
    this.footer,
    this.heightFactor = 0.88,
  });

  final String title;
  final Widget body;
  final Widget? footer;
  final double heightFactor;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final maxHeight = MediaQuery.sizeOf(context).height * heightFactor;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight, maxWidth: 680),
      decoration: BoxDecoration(
        color: theme.colors.background,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(theme.radius.xl)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                theme.spacing.lg,
                theme.spacing.lg,
                theme.spacing.sm,
                theme.spacing.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: TextStyle(
                          color: theme.colors.text,
                          fontSize: theme.fontSize.xl,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: Zh.common.close,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(theme.radius.pill),
                      onTap: () => Navigator.of(context).pop(),
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Center(
                          child: AppIcon(
                            AppIconName.close,
                            size: 22,
                            color: theme.colors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(child: body),
            if (footer != null)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  theme.spacing.lg,
                  theme.spacing.sm,
                  theme.spacing.lg,
                  theme.spacing.md,
                ),
                child: footer!,
              ),
          ],
        ),
      ),
    );
  }
}

Future<T?> showAppBottomSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: builder(ctx),
      ),
    ),
  );
}

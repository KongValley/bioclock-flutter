import 'package:bioclock/ui/components/app_icon.dart';
import 'package:bioclock/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum AppCardTone { defaultTone, primary, danger, warning, success }

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.tone = AppCardTone.defaultTone,
    this.padding = true,
  });

  final Widget child;
  final AppCardTone tone;
  final bool padding;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final bg = switch (tone) {
      AppCardTone.defaultTone => theme.colors.surface,
      AppCardTone.primary => theme.colors.primaryMuted,
      AppCardTone.danger => theme.colors.dangerMuted,
      AppCardTone.warning => theme.colors.warningMuted,
      AppCardTone.success => theme.colors.successMuted,
    };
    final borderColor = switch (tone) {
      AppCardTone.defaultTone => theme.colors.border,
      AppCardTone.primary => theme.colors.primary,
      AppCardTone.danger => theme.colors.danger,
      AppCardTone.warning => theme.colors.warning,
      AppCardTone.success => theme.colors.success,
    };

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(theme.radius.lg),
        border: Border.all(
          color: borderColor,
          width: tone == AppCardTone.defaultTone ? 0.6 : 1.0,
        ),
      ),
      padding: padding ? EdgeInsets.all(theme.spacing.lg) : EdgeInsets.zero,
      child: child,
    );
  }
}

enum AppButtonVariant { primary, secondary, outline, danger }

enum AppButtonSize { md, lg }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.md,
    this.disabled = false,
    this.loading = false,
    this.icon,
    this.semanticLabel,
    this.fullWidth = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final bool disabled;
  final bool loading;
  final AppIconName? icon;
  final String? semanticLabel;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final bg = switch (variant) {
      AppButtonVariant.primary => theme.colors.primary,
      AppButtonVariant.secondary => theme.colors.surfaceMuted,
      AppButtonVariant.outline => Colors.transparent,
      AppButtonVariant.danger => theme.colors.danger,
    };
    final fg = switch (variant) {
      AppButtonVariant.primary => theme.colors.onPrimary,
      AppButtonVariant.secondary => theme.colors.text,
      AppButtonVariant.outline => theme.colors.primary,
      AppButtonVariant.danger => theme.colors.onPrimary,
    };
    final borderColor =
        variant == AppButtonVariant.outline ? theme.colors.border : bg;
    final height = size == AppButtonSize.lg ? 52.0 : 48.0;
    final inactive = disabled || loading || onPressed == null;

    return Semantics(
      button: true,
      enabled: !inactive,
      label: semanticLabel ?? label,
      child: Opacity(
        opacity: inactive ? 0.45 : 1.0,
        child: Material(
          color: bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(theme.radius.md),
            side: BorderSide(color: borderColor),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(theme.radius.md),
            onTap: inactive ? null : onPressed,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: height,
                minWidth: fullWidth ? double.infinity : 44,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (loading)
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: (variant == AppButtonVariant.secondary ||
                                  variant == AppButtonVariant.outline)
                              ? theme.colors.primary
                              : fg,
                        ),
                      )
                    else ...[
                      if (icon != null) ...[
                        AppIcon(
                          icon!,
                          size: size == AppButtonSize.lg ? 20 : 18,
                          color: fg,
                          strokeWidth: 2.25,
                        ),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: fg,
                            fontSize: theme.fontSize.md,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onPressed,
    this.semanticLabel,
    this.disabled = false,
  });

  final String label;
  final bool selected;
  final VoidCallback? onPressed;
  final String? semanticLabel;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final interactive = onPressed != null && !disabled;

    return Semantics(
      button: onPressed != null,
      selected: selected,
      enabled: !disabled,
      label: semanticLabel ?? label,
      child: Opacity(
        opacity: disabled ? 0.4 : 1.0,
        child: Material(
          color: selected ? theme.colors.primaryMuted : theme.colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(theme.radius.pill),
            side: BorderSide(
              color: selected ? theme.colors.primary : theme.colors.border,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(theme.radius.pill),
            onTap: interactive ? onPressed : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected
                          ? theme.colors.primary
                          : theme.colors.textSecondary,
                      fontSize: theme.fontSize.sm,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.hint,
    this.error,
    this.suffix,
    this.placeholder,
    this.multiline = false,
    this.enabled = true,
    this.maxLength,
    this.keyboardType,
    this.inputFormatters,
    this.onSubmitted,
    this.semanticLabel,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String? label;
  final String? hint;
  final String? error;
  final String? suffix;
  final String? placeholder;
  final bool multiline;
  final bool enabled;
  final int? maxLength;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final VoidCallback? onSubmitted;
  final String? semanticLabel;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant AppTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: TextStyle(
              color: theme.colors.textSecondary,
              fontSize: theme.fontSize.sm,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Semantics(
          textField: true,
          label: widget.semanticLabel ?? widget.label,
          child: Container(
            constraints: BoxConstraints(minHeight: widget.multiline ? 96 : 48),
            decoration: BoxDecoration(
              color: theme.colors.surfaceMuted,
              borderRadius: BorderRadius.circular(theme.radius.md),
              border: Border.all(
                color: widget.error != null
                    ? theme.colors.danger
                    : theme.colors.border,
                width: 0.8,
              ),
            ),
            padding: EdgeInsets.symmetric(horizontal: theme.spacing.md),
            child: Row(
              crossAxisAlignment: widget.multiline
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: widget.enabled,
                    maxLines: widget.multiline ? 4 : 1,
                    minLines: widget.multiline ? 3 : 1,
                    maxLength: widget.maxLength,
                    keyboardType: widget.multiline
                        ? TextInputType.multiline
                        : widget.keyboardType,
                    inputFormatters: widget.inputFormatters,
                    onChanged: widget.onChanged,
                    onSubmitted: widget.onSubmitted == null
                        ? null
                        : (_) => widget.onSubmitted!(),
                    style: TextStyle(
                      color: widget.enabled
                          ? theme.colors.text
                          : theme.colors.textTertiary,
                      fontSize: theme.fontSize.md,
                    ),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      counterText: '',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        vertical: widget.multiline ? theme.spacing.md : 12,
                      ),
                      hintText: widget.placeholder,
                      hintStyle: TextStyle(
                        color: theme.colors.textTertiary,
                        fontSize: theme.fontSize.md,
                      ),
                    ),
                  ),
                ),
                if (widget.suffix != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    widget.suffix!,
                    style: TextStyle(
                      color: theme.colors.textTertiary,
                      fontSize: theme.fontSize.sm,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (widget.error != null) ...[
          const SizedBox(height: 6),
          Text(
            widget.error!,
            style: TextStyle(
              color: theme.colors.danger,
              fontSize: theme.fontSize.xs,
            ),
          ),
        ] else if (widget.hint != null) ...[
          const SizedBox(height: 6),
          Text(
            widget.hint!,
            style: TextStyle(
              color: theme.colors.textTertiary,
              fontSize: theme.fontSize.xs,
            ),
          ),
        ],
      ],
    );
  }
}

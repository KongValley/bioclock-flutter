import 'package:bioclock/domain/date_utils.dart';
import 'package:bioclock/ui/components/app_icon.dart';
import 'package:bioclock/ui/components/app_primitives.dart';
import 'package:bioclock/ui/theme.dart';
import 'package:flutter/material.dart';

class _TimeStepButton extends StatelessWidget {
  const _TimeStepButton({
    required this.label,
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  final String label;
  final AppIconName icon;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: theme.colors.surfaceMuted,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(theme.radius.sm),
          side: BorderSide(color: theme.colors.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(theme.radius.sm),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppIcon(
                    icon,
                    size: 16,
                    color: theme.colors.text,
                    strokeWidth: 2.25,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: TextStyle(
                      color: theme.colors.text,
                      fontSize: theme.fontSize.sm,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// HH:mm 时间选择：小时/分钟步进 + 手动输入。
class TimeOfDayField extends StatefulWidget {
  const TimeOfDayField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String? label;

  @override
  State<TimeOfDayField> createState() => _TimeOfDayFieldState();
}

class _TimeOfDayFieldState extends State<TimeOfDayField> {
  late String _draft;
  String? _error;

  @override
  void initState() {
    super.initState();
    _draft = widget.value;
  }

  @override
  void didUpdateWidget(covariant TimeOfDayField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _draft = widget.value;
    }
  }

  void _apply(int hour, int minute) {
    final next = toTimeOfDay(hour, minute);
    setState(() {
      _error = null;
      _draft = next;
    });
    widget.onChanged(next);
  }

  void _commitManual() {
    final parsed = parseTimeOfDay(_draft);
    if (parsed == null) {
      setState(() => _error = '时间格式应为 HH:mm，例如 09:00');
      return;
    }
    setState(() => _error = null);
    widget.onChanged(toTimeOfDay(parsed.hour, parsed.minute));
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final parsed = parseTimeOfDay(widget.value) ?? (hour: 9, minute: 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: TextStyle(
              color: theme.colors.textSecondary,
              fontSize: theme.fontSize.sm,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Semantics(
              label: '当前时间 ${widget.value}',
              child: Text(
                widget.value,
                style: TextStyle(
                  color: theme.colors.text,
                  fontSize: theme.fontSize.xxl,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const Spacer(),
            Wrap(
              spacing: 6,
              children: [
                _TimeStepButton(
                  label: '1 时',
                  icon: AppIconName.minus,
                  semanticLabel: '时间减少一小时',
                  onTap: () => _apply(parsed.hour - 1, parsed.minute),
                ),
                _TimeStepButton(
                  label: '1 时',
                  icon: AppIconName.plus,
                  semanticLabel: '时间增加一小时',
                  onTap: () => _apply(parsed.hour + 1, parsed.minute),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _TimeStepButton(
              label: '5 分',
              icon: AppIconName.minus,
              semanticLabel: '时间减少五分钟',
              onTap: () => _apply(parsed.hour, parsed.minute - 5),
            ),
            _TimeStepButton(
              label: '5 分',
              icon: AppIconName.plus,
              semanticLabel: '时间增加五分钟',
              onTap: () => _apply(parsed.hour, parsed.minute + 5),
            ),
            _TimeStepButton(
              label: '整点',
              icon: AppIconName.check,
              semanticLabel: '分钟归零',
              onTap: () => _apply(parsed.hour, 0),
            ),
          ],
        ),
        const SizedBox(height: 8),
        AppTextField(
          value: _draft,
          onChanged: (text) => setState(() {
            _draft = text;
            _error = null;
          }),
          onSubmitted: _commitManual,
          placeholder: '09:00',
          error: _error,
          semanticLabel: '手动输入提醒时间',
          maxLength: 5,
        ),
      ],
    );
  }
}

/// 日期时间选择：现在 / 昨天 / 手动输入 + 天、分钟步进。
class DateTimeField extends StatefulWidget {
  const DateTimeField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final String? label;

  @override
  State<DateTimeField> createState() => _DateTimeFieldState();
}

class _DateTimeFieldState extends State<DateTimeField> {
  bool _manual = false;
  late String _draft;
  String? _error;

  @override
  void initState() {
    super.initState();
    _draft = formatManualInput(widget.value);
  }

  @override
  void didUpdateWidget(covariant DateTimeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_manual && oldWidget.value != widget.value) {
      _draft = formatManualInput(widget.value);
    }
  }

  void _quick(int ts) {
    setState(() {
      _manual = false;
      _error = null;
    });
    widget.onChanged(ts);
  }

  void _applyManual() {
    final parsed = parseManualDateTime(_draft);
    if (parsed == null) {
      setState(() => _error = '请输入有效时间，例如 2026-10-31 09:00');
      return;
    }
    setState(() {
      _error = null;
      _manual = false;
    });
    widget.onChanged(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final yesterdayFormatted =
        formatManualInput(addDays(DateTime.now().millisecondsSinceEpoch, -1));
    final isYesterday =
        !_manual && formatManualInput(widget.value) == yesterdayFormatted;

    Widget quickBtn(String text, bool active, VoidCallback onTap) {
      return Semantics(
        button: true,
        selected: active,
        label: text,
        child: Material(
          color: active ? theme.colors.primaryMuted : theme.colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(theme.radius.sm),
            side: BorderSide(
              color: active ? theme.colors.primary : theme.colors.border,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(theme.radius.sm),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44, minWidth: 80),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    text,
                    style: TextStyle(
                      color: active
                          ? theme.colors.primary
                          : theme.colors.textSecondary,
                      fontSize: theme.fontSize.sm,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: TextStyle(
              color: theme.colors.textSecondary,
              fontSize: theme.fontSize.sm,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Container(
          decoration: BoxDecoration(
            color: theme.colors.surfaceMuted,
            borderRadius: BorderRadius.circular(theme.radius.md),
          ),
          padding: EdgeInsets.all(theme.spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                formatDateTimeFull(widget.value),
                style: TextStyle(
                  color: theme.colors.text,
                  fontSize: theme.fontSize.lg,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '当地时间 · ${formatTime(widget.value)}',
                style: TextStyle(
                  color: theme.colors.textTertiary,
                  fontSize: theme.fontSize.xs,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            quickBtn(
              '现在',
              false,
              () => _quick(DateTime.now().millisecondsSinceEpoch),
            ),
            quickBtn(
              '昨天',
              isYesterday,
              () => _quick(addDays(DateTime.now().millisecondsSinceEpoch, -1)),
            ),
            quickBtn('手动输入', _manual, () {
              setState(() {
                _manual = !_manual;
                _error = null;
                if (_manual) _draft = formatManualInput(widget.value);
              });
            }),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _TimeStepButton(
              label: '1 天',
              icon: AppIconName.minus,
              semanticLabel: '时间提前一天',
              onTap: () => widget.onChanged(addDays(widget.value, -1)),
            ),
            _TimeStepButton(
              label: '1 天',
              icon: AppIconName.plus,
              semanticLabel: '时间推后一天',
              onTap: () => widget.onChanged(addDays(widget.value, 1)),
            ),
            _TimeStepButton(
              label: '15 分',
              icon: AppIconName.minus,
              semanticLabel: '时间提前十五分钟',
              onTap: () => widget.onChanged(addMinutes(widget.value, -15)),
            ),
            _TimeStepButton(
              label: '15 分',
              icon: AppIconName.plus,
              semanticLabel: '时间推后十五分钟',
              onTap: () => widget.onChanged(addMinutes(widget.value, 15)),
            ),
          ],
        ),
        if (_manual) ...[
          const SizedBox(height: 10),
          AppTextField(
            value: _draft,
            onChanged: (text) => setState(() {
              _draft = text;
              _error = null;
            }),
            placeholder: '2026-10-31 09:00',
            error: _error,
            semanticLabel: '手动输入时间',
            hint: '格式：年-月-日 时:分',
            onSubmitted: _applyManual,
          ),
          const SizedBox(height: 8),
          AppButton(
            label: '应用时间',
            onPressed: _applyManual,
            semanticLabel: '应用手动输入的时间',
          ),
        ],
      ],
    );
  }
}

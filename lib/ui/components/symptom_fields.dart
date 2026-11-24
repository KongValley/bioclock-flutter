import 'package:bioclock/domain/pain.dart';
import 'package:bioclock/i18n/zh.dart';
import 'package:bioclock/store/app_store.dart';
import 'package:bioclock/ui/components/app_icon.dart';
import 'package:bioclock/ui/components/app_primitives.dart';
import 'package:bioclock/ui/components/app_scope.dart';
import 'package:bioclock/ui/theme.dart';
import 'package:flutter/material.dart';

/// 疼痛评分（NRS 0–10）选择器：分 6 + 5 两行，保证不小于 44×44。
class PainScale extends StatelessWidget {
  const PainScale({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final int? value;
  final ValueChanged<int?> onChanged;

  Color _bandColor(AppThemeData theme, PainBand band) => switch (band) {
        PainBand.none => theme.colors.success,
        PainBand.mild => theme.colors.primary,
        PainBand.moderate => theme.colors.warning,
        PainBand.severe => theme.colors.danger,
      };

  String _bandLabel(PainBand band) => switch (band) {
        PainBand.none => Zh.form.painNone,
        PainBand.mild => Zh.form.painMild,
        PainBand.moderate => Zh.form.painModerate,
        PainBand.severe => Zh.form.painSevere,
      };

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final row1 = List.generate(6, (i) => i);
    final row2 = List.generate(5, (i) => i + 6);

    Widget buildRow(List<int> items) {
      return Row(
        children: [
          for (var i = 0; i < items.length; i += 1) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: () {
                final score = items[i];
                final selected = value == score;
                final band = painBand(score);
                final color = _bandColor(theme, band);
                return Semantics(
                  button: true,
                  selected: selected,
                  label: '疼痛评分 $score，${_bandLabel(band)}',
                  child: Material(
                    color: selected ? color : theme.colors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(theme.radius.sm),
                      side: BorderSide(
                        color: selected ? color : theme.colors.border,
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(theme.radius.sm),
                      onTap: () => onChanged(selected ? null : score),
                      child: SizedBox(
                        height: 48,
                        child: Center(
                          child: Text(
                            '$score',
                            style: TextStyle(
                              color: selected
                                  ? theme.colors.onPrimary
                                  : theme.colors.text,
                              fontSize: theme.fontSize.md,
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w500,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }(),
            ),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              Zh.form.pain,
              style: TextStyle(
                color: theme.colors.textSecondary,
                fontSize: theme.fontSize.sm,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'NRS 0–10',
              style: TextStyle(
                color: theme.colors.textTertiary,
                fontSize: theme.fontSize.xs,
              ),
            ),
            const Spacer(),
            Text(
              value == null
                  ? '未记录'
                  : '$value · ${_bandLabel(painBand(value!))}',
              style: TextStyle(
                color: theme.colors.text,
                fontSize: theme.fontSize.sm,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        buildRow(row1),
        const SizedBox(height: 6),
        buildRow(row2),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            for (final band in painBandValues)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _bandColor(theme, band),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    switch (band) {
                      PainBand.none => '0 ${_bandLabel(band)}',
                      PainBand.mild => '1–3 ${_bandLabel(band)}',
                      PainBand.moderate => '4–6 ${_bandLabel(band)}',
                      PainBand.severe => '7–10 ${_bandLabel(band)}',
                    },
                    style: TextStyle(
                      color: theme.colors.textTertiary,
                      fontSize: theme.fontSize.xs,
                    ),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          Zh.form.painHint,
          style: TextStyle(
            color: theme.colors.textTertiary,
            fontSize: theme.fontSize.xs,
          ),
        ),
      ],
    );
  }
}

/// 症状标签维护：新增 / 删除。删除只影响之后的可选项，历史记录文字不变。
class SymptomTagManager extends StatefulWidget {
  const SymptomTagManager({
    super.key,
    this.onAdded,
    this.onRemoved,
  });

  final ValueChanged<String>? onAdded;
  final ValueChanged<String>? onRemoved;

  @override
  State<SymptomTagManager> createState() => _SymptomTagManagerState();
}

class _SymptomTagManagerState extends State<SymptomTagManager> {
  String _draft = '';
  bool _busy = false;
  String? _error;

  Future<void> _add() async {
    final name = _draft.trim();
    if (name.isEmpty) {
      setState(() => _error = '请输入症状名称');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await context.store.addSymptomTag(name);
      if (!mounted) return;
      setState(() => _draft = '');
      widget.onAdded?.call(name);
      if (result.notifyWarning != null) {
        showToast(result.notifyWarning!, isError: true);
      }
    } catch (err) {
      if (mounted) setState(() => _error = friendlyErrorMessage(err));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(String id, String name) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await context.store.removeSymptomTag(id);
      if (!mounted) return;
      showToast('已删除「$name」');
      widget.onRemoved?.call(id);
      if (result.notifyWarning != null) {
        showToast(result.notifyWarning!, isError: true);
      }
    } catch (err) {
      if (mounted) setState(() => _error = friendlyErrorMessage(err));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final tags = context.store.symptomTags;

    return Container(
      padding: EdgeInsets.all(theme.spacing.md),
      decoration: BoxDecoration(
        color: theme.colors.surfaceMuted,
        borderRadius: BorderRadius.circular(theme.radius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            Zh.form.tagManagerTitle,
            style: TextStyle(
              color: theme.colors.text,
              fontSize: theme.fontSize.sm,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            Zh.form.tagManagerHint,
            style: TextStyle(
              color: theme.colors.textTertiary,
              fontSize: theme.fontSize.xs,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppTextField(
                  value: _draft,
                  onChanged: (text) => setState(() {
                    _draft = text;
                    _error = null;
                  }),
                  placeholder: Zh.form.tagAddPlaceholder,
                  semanticLabel: '新增症状名称',
                  maxLength: 20,
                  onSubmitted: _add,
                ),
              ),
              const SizedBox(width: 8),
              AppButton(
                label: Zh.form.tagAdd,
                onPressed: _add,
                loading: _busy,
                icon: AppIconName.plus,
                fullWidth: false,
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(
                color: theme.colors.danger,
                fontSize: theme.fontSize.xs,
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (tags.isEmpty)
            Text(
              Zh.form.tagEmpty,
              style: TextStyle(
                color: theme.colors.textTertiary,
                fontSize: theme.fontSize.xs,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in tags)
                  Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    padding: const EdgeInsets.only(left: 12, right: 4),
                    decoration: BoxDecoration(
                      color: theme.colors.surface,
                      borderRadius: BorderRadius.circular(theme.radius.pill),
                      border: Border.all(color: theme.colors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          tag.name,
                          style: TextStyle(
                            color: theme.colors.textSecondary,
                            fontSize: theme.fontSize.sm,
                          ),
                        ),
                        Semantics(
                          button: true,
                          enabled: !_busy,
                          label: '删除症状 ${tag.name}',
                          child: InkWell(
                            borderRadius:
                                BorderRadius.circular(theme.radius.pill),
                            onTap: _busy
                                ? null
                                : () => _remove(tag.id, tag.name),
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: Center(
                                child: AppIcon(
                                  AppIconName.close,
                                  size: 14,
                                  color: theme.colors.textTertiary,
                                  strokeWidth: 2.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

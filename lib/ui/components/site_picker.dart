import 'package:bioclock/domain/rotation.dart';
import 'package:bioclock/models/types.dart';
import 'package:bioclock/ui/theme.dart';
import 'package:flutter/material.dart';

const Map<InjectionSite, String> _shortLabels = {
  InjectionSite.abdomenUl: '腹左上',
  InjectionSite.abdomenUr: '腹右上',
  InjectionSite.abdomenLl: '腹左下',
  InjectionSite.abdomenLr: '腹右下',
  InjectionSite.thighL: '左大腿',
  InjectionSite.thighR: '右大腿',
  InjectionSite.armL: '左上臂',
  InjectionSite.armR: '右上臂',
};

const List<InjectionSite> _rowOne = [
  InjectionSite.abdomenUl,
  InjectionSite.abdomenUr,
  InjectionSite.abdomenLl,
  InjectionSite.abdomenLr,
];

const List<InjectionSite> _rowTwo = [
  InjectionSite.thighL,
  InjectionSite.thighR,
  InjectionSite.armL,
  InjectionSite.armR,
];

/// 8 宫格部位选择，带无障碍语义与推荐标记。
class SitePicker extends StatelessWidget {
  const SitePicker({
    super.key,
    required this.value,
    required this.onChange,
    this.recommended,
    this.disabled = false,
  });

  final InjectionSite value;
  final ValueChanged<InjectionSite> onChange;
  final InjectionSite? recommended;
  final bool disabled;

  Widget _buildRow(BuildContext context, List<InjectionSite> sites) {
    final theme = context.appTheme;
    return Row(
      children: [
        for (var i = 0; i < sites.length; i += 1) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _SiteTile(
              site: sites[i],
              selected: value == sites[i],
              isRecommended: recommended == sites[i],
              disabled: disabled,
              theme: theme,
              onTap: () => onChange(sites[i]),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildRow(context, _rowOne),
        const SizedBox(height: 8),
        _buildRow(context, _rowTwo),
        const SizedBox(height: 8),
        Text(
          '腹部注射点需与肚脐保持 5cm 以上距离，并避开硬结、疤痕。',
          style: TextStyle(
            color: theme.colors.textTertiary,
            fontSize: theme.fontSize.xs,
          ),
        ),
      ],
    );
  }
}

class _SiteTile extends StatelessWidget {
  const _SiteTile({
    required this.site,
    required this.selected,
    required this.isRecommended,
    required this.disabled,
    required this.theme,
    required this.onTap,
  });

  final InjectionSite site;
  final bool selected;
  final bool isRecommended;
  final bool disabled;
  final AppThemeData theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fullLabel = siteLabels[site] ?? '';
    return Semantics(
      button: true,
      selected: selected,
      enabled: !disabled,
      label: '$fullLabel${isRecommended ? '，推荐部位' : ''}',
      child: Material(
        color: selected ? theme.colors.primaryMuted : theme.colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(theme.radius.md),
          side: BorderSide(
            color: selected ? theme.colors.primary : theme.colors.border,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(theme.radius.md),
          onTap: disabled ? null : onTap,
          child: Opacity(
            opacity: disabled ? 0.5 : 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 58, minWidth: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _shortLabels[site] ?? fullLabel,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: selected
                            ? theme.colors.primary
                            : theme.colors.text,
                        fontSize: theme.fontSize.sm,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    if (isRecommended) ...[
                      const SizedBox(height: 2),
                      Text(
                        '推荐',
                        style: TextStyle(
                          color: theme.colors.primary,
                          fontSize: theme.fontSize.xs,
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

import 'package:bioclock/data/diseases.dart';
import 'package:bioclock/db/repo.dart';
import 'package:bioclock/domain/medication.dart';
import 'package:bioclock/i18n/zh.dart';
import 'package:bioclock/models/types.dart';
import 'package:bioclock/store/app_store.dart';
import 'package:bioclock/ui/components/app_icon.dart';
import 'package:bioclock/ui/components/app_layout.dart';
import 'package:bioclock/ui/components/app_primitives.dart';
import 'package:bioclock/ui/components/app_scope.dart';
import 'package:bioclock/ui/theme.dart';
import 'package:flutter/material.dart';

class _MedDraft {
  _MedDraft({
    required this.name,
    required this.genericName,
    required this.brandNames,
    required this.route,
    required this.dose,
    required this.unit,
  });

  factory _MedDraft.fromMedication(Medication? m) => _MedDraft(
        name: m?.name ?? '',
        genericName: m?.genericName ?? '',
        brandNames: m != null ? m.brandNames.join('、') : '',
        route: m?.route ?? MedicationRoute.sc,
        dose: m?.defaultDose == null ? '' : '${m!.defaultDose}',
        unit: m?.unit ?? 'mg',
      );

  String name;
  String genericName;
  String brandNames;
  MedicationRoute route;
  String dose;
  String unit;
}

List<String> _parseBrandNames(String value) {
  final seen = <String>{};
  final result = <String>[];
  for (final item in value.split(RegExp(r'[、,，;；/\n]+'))) {
    final trimmed = item.trim();
    if (trimmed.isEmpty || !seen.add(trimmed)) continue;
    result.add(trimmed);
  }
  return result;
}

String _routeLabel(MedicationRoute route) => switch (route) {
      MedicationRoute.iv => '医院输注',
      MedicationRoute.oral => '口服',
      MedicationRoute.sc => '皮下注射',
    };

/// 药物管理：内置药默认剂量可改，自定义药可增删改。
class MedicationManager extends StatefulWidget {
  const MedicationManager({super.key});

  @override
  State<MedicationManager> createState() => _MedicationManagerState();
}

class _MedicationManagerState extends State<MedicationManager> {
  String? _editingId;
  bool _creating = false;
  _MedDraft _draft = _MedDraft.fromMedication(null);
  String? _error;
  bool _saving = false;

  void _startCreate() {
    setState(() {
      _creating = true;
      _editingId = null;
      _draft = _MedDraft.fromMedication(null);
      _error = null;
    });
  }

  void _startEdit(Medication m) {
    setState(() {
      _creating = false;
      _editingId = m.id;
      _draft = _MedDraft.fromMedication(m);
      _error = null;
    });
  }

  void _cancel() {
    setState(() {
      _creating = false;
      _editingId = null;
      _error = null;
    });
  }

  Future<void> _save() async {
    final store = context.store;
    final medications = store.medications;
    final editing = _editingId == null
        ? null
        : medications.cast<Medication?>().firstWhere(
              (m) => m?.id == _editingId,
              orElse: () => null,
            );
    final builtin = editing?.isBuiltin == true;

    final name = _draft.name.trim();
    if (name.isEmpty) {
      setState(() => _error = '请填写药名');
      return;
    }
    final unit = _draft.unit.trim();
    if (unit.isEmpty) {
      setState(() => _error = '请填写单位');
      return;
    }

    double? defaultDose;
    if (_draft.dose.trim().isNotEmpty) {
      final parsed = double.tryParse(_draft.dose.trim());
      if (parsed == null || !parsed.isFinite || parsed < 0) {
        setState(() => _error = '默认剂量必须是大于等于 0 的数字');
        return;
      }
      defaultDose = parsed;
    }

    if (!builtin) {
      final dup = medications.any(
        (m) =>
            m.id != _editingId &&
            normalizeMedicationName(m.name) == normalizeMedicationName(name),
      );
      if (dup) {
        setState(() => _error = '已经有同名药物了');
        return;
      }
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final generic = _draft.genericName.trim();
      final MutationResult result;
      if (editing != null) {
        result = await store.updateMedication(
          editing.id,
          builtin
              ? MedicationPatch(defaultDose: PatchValue(defaultDose))
              : MedicationPatch(
                  name: name,
                  genericName: PatchValue(generic.isEmpty ? null : generic),
                  brandNames: _parseBrandNames(_draft.brandNames),
                  defaultDose: PatchValue(defaultDose),
                  unit: unit,
                  route: _draft.route,
                ),
        );
      } else {
        final primaryHex =
            '#${context.appTheme.colors.primary.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
        result = await store.addMedication(
          MedicationInput(
            name: name,
            genericName: generic.isEmpty ? null : generic,
            brandNames: _parseBrandNames(_draft.brandNames),
            defaultDose: defaultDose,
            unit: unit,
            color: primaryHex,
            route: _draft.route,
            diseaseIds: resolveDiseaseIds(store.settings),
          ),
        );
      }
      if (!mounted) return;
      _cancel();
      showToast(editing != null ? '药物已更新' : '药物已添加');
      if (result.notifyWarning != null) {
        showToast(result.notifyWarning!, isError: true);
      }
    } catch (err) {
      if (mounted) setState(() => _error = friendlyErrorMessage(err));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmRemove(Medication m) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除药物？',
      message: '将删除「${m.name}」。已被用药方案使用的药物不能删除。',
      confirmLabel: Zh.common.delete,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      final result = await context.store.removeMedication(m.id);
      if (!mounted) return;
      _cancel();
      showToast('药物已删除');
      if (result.notifyWarning != null) {
        showToast(result.notifyWarning!, isError: true);
      }
    } catch (err) {
      if (mounted) showToast(friendlyErrorMessage(err), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final medications = context.store.medications;
    final editing = _editingId == null
        ? null
        : medications.cast<Medication?>().firstWhere(
              (m) => m?.id == _editingId,
              orElse: () => null,
            );
    final builtin = editing?.isBuiltin == true;

    if (_creating || editing != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            editing != null ? '编辑「${editing.name}」' : '添加药物',
            style: TextStyle(
              color: theme.colors.text,
              fontSize: theme.fontSize.lg,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          AppTextField(
            label: '药名',
            value: _draft.name,
            onChanged: (v) => _draft.name = v,
            placeholder: '例如：阿达木单抗 / 修美乐',
            enabled: !builtin,
            semanticLabel: '药物名称',
          ),
          const SizedBox(height: 12),
          AppTextField(
            label: '通用名（${Zh.common.optional}）',
            value: _draft.genericName,
            onChanged: (v) => _draft.genericName = v,
            placeholder: '通用名',
            enabled: !builtin,
            semanticLabel: '药物通用名',
          ),
          const SizedBox(height: 12),
          AppTextField(
            label: '商品名（${Zh.common.optional}）',
            value: _draft.brandNames,
            onChanged: (v) => _draft.brandNames = v,
            placeholder: '多个商品名用顿号分隔，如 修美乐、格乐立',
            enabled: !builtin,
            hint: '导入时按药名、通用名、商品名互相认领，避免同一种药重复建档。',
            semanticLabel: '药物商品名',
          ),
          const SizedBox(height: 12),
          if (builtin)
            Text(
              '目录药的名称、通用名、商品名和给药途径跟随版本更新，只能修改默认剂量。',
              style: TextStyle(
                color: theme.colors.textTertiary,
                fontSize: theme.fontSize.xs,
              ),
            )
          else ...[
            Text(
              '给药途径',
              style: TextStyle(
                color: theme.colors.textSecondary,
                fontSize: theme.fontSize.sm,
              ),
            ),
            const SizedBox(height: 6),
            SegmentedControl<MedicationRoute>(
              options: const [
                SegmentOption(value: MedicationRoute.sc, label: '皮下'),
                SegmentOption(value: MedicationRoute.iv, label: '医院输注'),
                SegmentOption(value: MedicationRoute.oral, label: '口服'),
              ],
              value: _draft.route,
              onChange: (r) => setState(() => _draft.route = r),
              semanticLabel: '给药途径',
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  label: '默认剂量（${Zh.common.optional}）',
                  value: _draft.dose,
                  onChanged: (v) => _draft.dose = v,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  placeholder: '40',
                  semanticLabel: '默认剂量',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppTextField(
                  label: '单位',
                  value: _draft.unit,
                  onChanged: (v) => _draft.unit = v,
                  placeholder: 'mg',
                  enabled: !builtin,
                  semanticLabel: '剂量单位',
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: TextStyle(
                color: theme.colors.danger,
                fontSize: theme.fontSize.sm,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: Zh.common.cancel,
                  variant: AppButtonVariant.secondary,
                  onPressed: _cancel,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: AppButton(
                  label: Zh.common.save,
                  onPressed: _save,
                  loading: _saving,
                ),
              ),
            ],
          ),
          if (editing != null && !builtin) ...[
            const SizedBox(height: 12),
            AppButton(
              label: '删除这种药',
              variant: AppButtonVariant.danger,
              onPressed: () => _confirmRemove(editing),
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
            Expanded(
              child: Text(
                '共 ${medications.length} 种。目录药只读，默认剂量可以按医嘱改。',
                style: TextStyle(
                  color: theme.colors.textTertiary,
                  fontSize: theme.fontSize.xs,
                ),
              ),
            ),
            const SizedBox(width: 8),
            AppButton(
              label: '添加药物',
              icon: AppIconName.plus,
              onPressed: _startCreate,
              fullWidth: false,
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final med in medications) ...[
          Semantics(
            button: true,
            label: '编辑 ${med.name}',
            child: Material(
              color: theme.colors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(theme.radius.md),
                side: BorderSide(color: theme.colors.border),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(theme.radius.md),
                onTap: () => _startEdit(med),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 56),
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    med.name,
                                    style: TextStyle(
                                      color: theme.colors.text,
                                      fontSize: theme.fontSize.md,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (med.isBuiltin) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: theme.colors.surfaceMuted,
                                      borderRadius: BorderRadius.circular(
                                        theme.radius.pill,
                                      ),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 1,
                                    ),
                                    child: Text(
                                      '目录',
                                      style: TextStyle(
                                        color: theme.colors.textTertiary,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              [
                                if (med.genericName != null &&
                                    med.genericName != med.name)
                                  med.genericName!,
                                if (med.brandNames.isNotEmpty)
                                  '商品名：${med.brandNames.join('、')}',
                                _routeLabel(med.route),
                                med.defaultDose != null
                                    ? '${med.defaultDose} ${med.unit}'
                                    : '未设默认剂量',
                              ].join(' · '),
                              style: TextStyle(
                                color: theme.colors.textTertiary,
                                fontSize: theme.fontSize.xs,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      AppIcon(
                        AppIconName.chevronRight,
                        size: 18,
                        color: theme.colors.textTertiary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

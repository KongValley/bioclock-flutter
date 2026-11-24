import 'package:bioclock/db/repo.dart';
import 'package:bioclock/domain/date_utils.dart';
import 'package:bioclock/domain/rotation.dart';
import 'package:bioclock/domain/schedule.dart';
import 'package:bioclock/i18n/zh.dart';
import 'package:bioclock/models/types.dart';
import 'package:bioclock/store/app_store.dart';
import 'package:bioclock/ui/components/app_layout.dart';
import 'package:bioclock/ui/components/app_primitives.dart';
import 'package:bioclock/ui/components/app_scope.dart';
import 'package:bioclock/ui/components/site_picker.dart';
import 'package:bioclock/ui/components/time_fields.dart';
import 'package:bioclock/ui/theme.dart';
import 'package:flutter/material.dart';

Future<void> showInjectionModal(
  BuildContext context, {
  String? editingId,
  String? initialLineId,
}) {
  return showAppBottomSheet<void>(
    context,
    builder: (_) => _InjectionModalContent(
      editingId: editingId,
      initialLineId: initialLineId,
    ),
  );
}

class _InjectionModalContent extends StatefulWidget {
  const _InjectionModalContent({
    this.editingId,
    this.initialLineId,
  });

  final String? editingId;
  final String? initialLineId;

  @override
  State<_InjectionModalContent> createState() => _InjectionModalContentState();
}

class _InjectionModalContentState extends State<_InjectionModalContent> {
  String _lineId = '';
  int _takenAt = DateTime.now().millisecondsSinceEpoch;
  String _doseText = '';
  String _unit = 'mg';
  InjectionSite _site = InjectionSite.abdomenUl;
  String _lotNumber = '';
  String _note = '';
  bool _initialized = false;
  bool _saving = false;
  String? _formError;

  DoseLog? _findEditing(AppStore store) {
    if (widget.editingId == null) return null;
    for (final log in store.doseLogs) {
      if (log.id == widget.editingId) return log;
    }
    return null;
  }

  Treatment? _findTreatment(AppStore store, DoseLog? editing) {
    if (editing == null) return store.treatment;
    for (final t in store.treatments) {
      if (t.lines.any((l) => l.id == editing.lineId)) return t;
    }
    return null;
  }

  SchedulePlan? _nextPlanFor(
    Treatment? treatment,
    List<DoseLog> doseLogs,
    String targetLineId,
  ) {
    if (treatment == null) return null;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final plans = buildSchedule(lines: treatment.lines, logs: doseLogs, now: now);
      final linePlans = plans.where((p) => p.lineId == targetLineId).toList();
      return selectNextPlan(linePlans, now);
    } catch (_) {
      return null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = context.store;
    if (!store.ready || _initialized) return;

    final editing = _findEditing(store);
    final treatment = _findTreatment(store, editing);
    if (treatment == null) return;

    final medById = {for (final m in store.medications) m.id: m};
    final history = [
      for (final log in store.doseLogs)
        if (log.site != null)
          SiteHistoryEntry(
            site: log.site!,
            injectedAt: log.takenAt ?? log.scheduledAt ?? log.createdAt,
          ),
    ];
    final recommended = recommendSite(history);

    if (editing != null) {
      TreatmentLine? line;
      for (final item in treatment.lines) {
        if (item.id == editing.lineId) {
          line = item;
          break;
        }
      }
      final med = line != null ? medById[line.medicationId] : null;
      _lineId = editing.lineId;
      _takenAt = editing.takenAt ?? DateTime.now().millisecondsSinceEpoch;
      _doseText = editing.dose != null ? _numText(editing.dose!) : '';
      _unit = editing.unit.isNotEmpty ? editing.unit : (med?.unit ?? 'mg');
      _site = editing.site ?? recommended;
      _lotNumber = editing.lotNumber ?? '';
      _note = editing.note ?? '';
      _initialized = true;
      return;
    }

    final injectionLines = treatment.lines
        .where((l) => l.kind == LineKind.injection && l.endedAt == null)
        .toList();
    TreatmentLine? preferred;
    if (widget.initialLineId != null) {
      for (final l in injectionLines) {
        if (l.id == widget.initialLineId) {
          preferred = l;
          break;
        }
      }
    }
    preferred ??= injectionLines.cast<TreatmentLine?>().firstWhere(
          (l) => l?.isHost == true,
          orElse: () => injectionLines.isNotEmpty ? injectionLines.first : null,
        );
    if (preferred != null) {
      final med = medById[preferred.medicationId];
      final plan = _nextPlanFor(treatment, store.doseLogs, preferred.id);
      final dose = plan?.dose ?? med?.defaultDose;
      _lineId = preferred.id;
      _doseText = dose != null ? _numText(dose) : '';
      _unit = (plan?.unit.isNotEmpty == true ? plan!.unit : null) ??
          med?.unit ??
          'mg';
    }
    _site = recommended;
    _initialized = true;
  }

  void _selectLine(Treatment? treatment, Map<String, Medication> medById, String id) {
    if (treatment == null) return;
    TreatmentLine? line;
    for (final l in treatment.lines) {
      if (l.id == id) {
        line = l;
        break;
      }
    }
    if (line == null) return;
    final med = medById[line.medicationId];
    final plan = _nextPlanFor(treatment, context.store.doseLogs, line.id);
    final dose = plan?.dose ?? med?.defaultDose;
    setState(() {
      _lineId = id;
      _doseText = dose != null ? _numText(dose) : '';
      _unit = (plan?.unit.isNotEmpty == true ? plan!.unit : null) ??
          med?.unit ??
          'mg';
      if (med?.route == MedicationRoute.iv ||
          med?.route == MedicationRoute.oral) {
        _site = InjectionSite.abdomenUl;
      }
    });
  }

  int? _matchScheduledAt(
    Treatment treatment,
    List<DoseLog> allLogs,
    DoseLog? editing,
    String targetLineId,
    int at,
  ) {
    try {
      final logs = editing != null
          ? allLogs.where((l) => l.id != editing.id).toList()
          : allLogs;
      final plans = buildSchedule(lines: treatment.lines, logs: logs, now: at);
      for (final plan in plans) {
        if (plan.lineId == targetLineId &&
            calendarDayDiff(plan.plannedAt, at) == 0) {
          return plan.plannedAt;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _save({required bool continueAfter}) async {
    final store = context.store;
    final editing = _findEditing(store);
    final treatment = _findTreatment(store, editing);
    final medById = {for (final m in store.medications) m.id: m};

    setState(() => _formError = null);
    if (treatment == null) {
      setState(() => _formError = '还没有治疗方案，请先在设置中完成配置。');
      return;
    }
    TreatmentLine? selectedLine;
    for (final l in treatment.lines) {
      if (l.id == _lineId) {
        selectedLine = l;
        break;
      }
    }
    if (selectedLine == null) {
      setState(() => _formError = '请选择要登记的用药。');
      return;
    }
    if (_unit.trim().isEmpty) {
      setState(() => _formError = '单位不能为空。');
      return;
    }
    double? parsedDose;
    if (_doseText.trim().isNotEmpty) {
      final val = double.tryParse(_doseText.trim());
      if (val == null || !val.isFinite || val < 0) {
        setState(() => _formError = '剂量必须是大于或等于 0 的数字。');
        return;
      }
      parsedDose = val;
    }
    if (_takenAt <= 0) {
      setState(() => _formError = '注射时间不合法。');
      return;
    }

    final med = medById[selectedLine.medicationId];
    final isSc = med?.route == MedicationRoute.sc;
    final scheduledAt = _matchScheduledAt(
      treatment,
      store.doseLogs,
      editing,
      selectedLine.id,
      _takenAt,
    );

    setState(() => _saving = true);
    try {
      final MutationResult result;
      if (editing != null) {
        result = await store.updateDoseLog(
          editing.id,
          DoseLogPatch(
            scheduledAt: PatchValue(scheduledAt),
            takenAt: PatchValue(_takenAt),
            status: DoseStatus.done,
            dose: PatchValue(parsedDose),
            unit: PatchValue(_unit.trim()),
            site: PatchValue(isSc ? _site : null),
            lotNumber: PatchValue(
              _lotNumber.trim().isEmpty ? null : _lotNumber.trim(),
            ),
            note: PatchValue(_note.trim().isEmpty ? null : _note.trim()),
          ),
        );
      } else {
        result = await store.addDoseLog(
          DoseLogInput(
            lineId: selectedLine.id,
            scheduledAt: scheduledAt,
            takenAt: _takenAt,
            status: DoseStatus.done,
            dose: parsedDose,
            unit: _unit.trim(),
            site: isSc ? _site : null,
            lotNumber: _lotNumber.trim().isEmpty ? null : _lotNumber.trim(),
            note: _note.trim().isEmpty ? null : _note.trim(),
          ),
        );
      }
      if (!mounted) return;
      if (continueAfter) {
        setState(() {
          _note = '';
          _lotNumber = '';
        });
        showToast('已保存，继续补录下一条');
      } else {
        Navigator.of(context).pop();
        showToast(editing != null ? '注射记录已更新' : '已记录，下次提醒已更新');
      }
      if (result.notifyWarning != null) {
        showToast(result.notifyWarning!, isError: true);
      }
    } catch (err) {
      final msg = friendlyErrorMessage(err);
      if (mounted) {
        setState(() => _formError = msg);
        showToast(msg, isError: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final store = context.store;
    final editing = _findEditing(store);
    final treatment = _findTreatment(store, editing);
    final medById = {for (final m in store.medications) m.id: m};
    final activeInjectionLines = treatment?.lines
            .where((l) => l.kind == LineKind.injection && l.endedAt == null)
            .toList() ??
        [];
    final selectableLines = editing != null && treatment != null
        ? treatment.lines.where((l) => l.id == editing.lineId).toList()
        : activeInjectionLines;
    final selectedLine = treatment?.lines.cast<TreatmentLine?>().firstWhere(
          (l) => l?.id == _lineId,
          orElse: () => null,
        );
    final selectedMed =
        selectedLine != null ? medById[selectedLine.medicationId] : null;
    final route = selectedMed?.route ?? MedicationRoute.sc;

    final recommended = recommendSite([
      for (final log in store.doseLogs)
        if (log.site != null)
          SiteHistoryEntry(
            site: log.site!,
            injectedAt: log.takenAt ?? log.scheduledAt ?? log.createdAt,
          ),
    ]);

    return SheetScaffold(
      title: editing != null ? '编辑注射记录' : Zh.today.registerInjection,
      heightFactor: 0.94,
      body: !store.ready
          ? const LoadingView()
          : SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                theme.spacing.lg,
                0,
                theme.spacing.lg,
                theme.spacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (treatment == null && editing == null) ...[
                    const InlineError(
                      message: '还没有治疗方案，请先在设置里完成配置后再登记注射。',
                    ),
                    const SizedBox(height: 16),
                  ],
                  DateTimeField(
                    label: Zh.form.injectedAt,
                    value: _takenAt,
                    onChanged: (v) => setState(() => _takenAt = v),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    Zh.form.medicationName,
                    style: TextStyle(
                      color: theme.colors.textSecondary,
                      fontSize: theme.fontSize.sm,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final line in selectableLines)
                        AppChip(
                          label: medById[line.medicationId]?.name ?? line.label,
                          selected: line.id == _lineId,
                          onPressed: () =>
                              _selectLine(treatment, medById, line.id),
                        ),
                    ],
                  ),
                  if (selectedMed?.genericName != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '通用名 ${selectedMed!.genericName}',
                      style: TextStyle(
                        color: theme.colors.textTertiary,
                        fontSize: theme.fontSize.xs,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: AppTextField(
                          label: Zh.form.dose,
                          value: _doseText,
                          onChanged: (v) => _doseText = v,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          placeholder: '40',
                          semanticLabel: '注射剂量',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppTextField(
                          label: Zh.form.unit,
                          value: _unit,
                          onChanged: (v) => _unit = v,
                          placeholder: 'mg',
                          semanticLabel: '剂量单位',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (route == MedicationRoute.sc) ...[
                    Text(
                      Zh.form.site,
                      style: TextStyle(
                        color: theme.colors.textSecondary,
                        fontSize: theme.fontSize.sm,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SitePicker(
                      value: _site,
                      onChange: (s) => setState(() => _site = s),
                      recommended: recommended,
                    ),
                  ] else
                    Container(
                      decoration: BoxDecoration(
                        color: theme.colors.primaryMuted,
                        borderRadius: BorderRadius.circular(theme.radius.md),
                      ),
                      padding: EdgeInsets.all(theme.spacing.md),
                      child: Text(
                        route == MedicationRoute.oral
                            ? '这是口服用药，不需要记录注射部位。'
                            : '这是静脉输注药物，通常在医院完成，不需要记录注射部位。',
                        style: TextStyle(
                          color: theme.colors.primary,
                          fontSize: theme.fontSize.sm,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  AppTextField(
                    label: '${Zh.form.lotNumber}（${Zh.common.optional}）',
                    value: _lotNumber,
                    onChanged: (v) => _lotNumber = v,
                    placeholder: '药盒上的批号',
                    semanticLabel: '药品批号',
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    label: '${Zh.form.note}（${Zh.common.optional}）',
                    value: _note,
                    onChanged: (v) => _note = v,
                    multiline: true,
                    placeholder: '注射后的感受、异常情况等',
                    semanticLabel: '注射备注',
                  ),
                  if (_formError != null) ...[
                    const SizedBox(height: 16),
                    InlineError(message: _formError!),
                  ],
                ],
              ),
            ),
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (editing == null) ...[
            AppButton(
              label: '保存并继续补录',
              onPressed: () => _save(continueAfter: true),
              loading: _saving,
              disabled: !store.ready || treatment == null,
              variant: AppButtonVariant.secondary,
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: Zh.common.cancel,
                  onPressed: () => Navigator.of(context).pop(),
                  variant: AppButtonVariant.secondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: AppButton(
                  label: editing != null ? Zh.common.save : '保存记录',
                  onPressed: () => _save(continueAfter: false),
                  loading: _saving,
                  disabled: !store.ready || (treatment == null && editing == null),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _numText(double v) =>
    v == v.truncateToDouble() ? v.toInt().toString() : v.toString();

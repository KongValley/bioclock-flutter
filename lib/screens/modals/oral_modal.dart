import 'package:bioclock/db/repo.dart';
import 'package:bioclock/domain/date_utils.dart';
import 'package:bioclock/domain/schedule.dart';
import 'package:bioclock/i18n/zh.dart';
import 'package:bioclock/models/types.dart';
import 'package:bioclock/store/app_store.dart';
import 'package:bioclock/ui/components/app_layout.dart';
import 'package:bioclock/ui/components/app_primitives.dart';
import 'package:bioclock/ui/components/app_scope.dart';
import 'package:bioclock/ui/components/time_fields.dart';
import 'package:bioclock/ui/theme.dart';
import 'package:flutter/material.dart';

Future<void> showOralModal(
  BuildContext context, {
  String? editingId,
  String? initialLineId,
  int? scheduledAt,
}) {
  return showAppBottomSheet<void>(
    context,
    builder: (_) => _OralModalContent(
      editingId: editingId,
      initialLineId: initialLineId,
      scheduledAt: scheduledAt,
    ),
  );
}

class _OralModalContent extends StatefulWidget {
  const _OralModalContent({
    this.editingId,
    this.initialLineId,
    this.scheduledAt,
  });

  final String? editingId;
  final String? initialLineId;
  final int? scheduledAt;

  @override
  State<_OralModalContent> createState() => _OralModalContentState();
}

class _OralModalContentState extends State<_OralModalContent> {
  String _selectedLineId = '';
  int _takenAt = DateTime.now().millisecondsSinceEpoch;
  String _note = '';
  bool _initialized = false;
  DoseStatus? _savingStatus;
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = context.store;
    if (!store.ready || _initialized) return;

    final editing = _findEditing(store);
    final treatment = _findTreatment(store, editing);
    final allOral =
        treatment?.lines.where((l) => l.kind == LineKind.oral).toList() ?? [];
    final available = editing != null
        ? allOral.where((l) => l.id == editing.lineId).toList()
        : allOral.where((l) => l.endedAt == null).toList();

    if (editing != null) {
      _selectedLineId = editing.lineId;
      _takenAt = editing.takenAt ??
          editing.scheduledAt ??
          DateTime.now().millisecondsSinceEpoch;
      _note = editing.note ?? '';
    } else if (widget.initialLineId != null &&
        available.any((l) => l.id == widget.initialLineId)) {
      _selectedLineId = widget.initialLineId!;
    } else if (available.isNotEmpty) {
      _selectedLineId = available.first.id;
    }
    _initialized = true;
  }

  int? _resolveScheduledAt(
    Treatment? treatment,
    TreatmentLine? line,
    DoseLog? editing,
    List<DoseLog> logs,
  ) {
    if (editing != null) return editing.scheduledAt;
    if (widget.scheduledAt != null) return widget.scheduledAt;
    if (treatment == null || line == null) return null;
    try {
      final plans = buildSchedule(
        lines: treatment.lines,
        logs: logs,
        now: _takenAt,
      );
      for (final plan in plans) {
        if (plan.lineId == line.id &&
            calendarDayDiff(plan.plannedAt, _takenAt) == 0) {
          return plan.plannedAt;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _submit(DoseStatus status) async {
    final store = context.store;
    final editing = _findEditing(store);
    final treatment = _findTreatment(store, editing);
    final allOral =
        treatment?.lines.where((l) => l.kind == LineKind.oral).toList() ?? [];
    final oralLines = editing != null
        ? allOral.where((l) => l.id == editing.lineId).toList()
        : allOral.where((l) => l.endedAt == null).toList();
    final line = oralLines.cast<TreatmentLine?>().firstWhere(
          (l) => l?.id == _selectedLineId,
          orElse: () => oralLines.isNotEmpty ? oralLines.first : null,
        );

    setState(() => _formError = null);
    if (line == null) {
      setState(() => _formError = '没有可登记的口服用药。');
      return;
    }

    final med = store.medications.cast<Medication?>().firstWhere(
          (m) => m?.id == line.medicationId,
          orElse: () => null,
        );
    final scheduledAt =
        _resolveScheduledAt(treatment, line, editing, store.doseLogs);

    setState(() => _savingStatus = status);
    try {
      final MutationResult result;
      if (editing != null) {
        result = await store.updateDoseLog(
          editing.id,
          DoseLogPatch(
            scheduledAt: PatchValue(scheduledAt),
            takenAt: PatchValue(status == DoseStatus.done ? _takenAt : null),
            status: status,
            dose: PatchValue(med?.defaultDose),
            unit: PatchValue(
              med != null && med.unit.trim().isNotEmpty ? med.unit : null,
            ),
            note: PatchValue(_note.trim().isEmpty ? null : _note.trim()),
          ),
        );
      } else {
        result = await store.addDoseLog(
          DoseLogInput(
            lineId: line.id,
            scheduledAt: scheduledAt,
            takenAt: status == DoseStatus.done ? _takenAt : null,
            status: status,
            dose: med?.defaultDose,
            unit: med != null && med.unit.trim().isNotEmpty ? med.unit : null,
            note: _note.trim().isEmpty ? null : _note.trim(),
          ),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      showToast(
        editing != null
            ? '口服记录已更新'
            : status == DoseStatus.done
                ? '已记录服用'
                : '已跳过这次',
      );
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
      if (mounted) setState(() => _savingStatus = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final store = context.store;
    final editing = _findEditing(store);
    final treatment = _findTreatment(store, editing);
    final allOral =
        treatment?.lines.where((l) => l.kind == LineKind.oral).toList() ?? [];
    final oralLines = editing != null
        ? allOral.where((l) => l.id == editing.lineId).toList()
        : allOral.where((l) => l.endedAt == null).toList();
    final line = oralLines.cast<TreatmentLine?>().firstWhere(
          (l) => l?.id == _selectedLineId,
          orElse: () => oralLines.isNotEmpty ? oralLines.first : null,
        );
    final med = line == null
        ? null
        : store.medications.cast<Medication?>().firstWhere(
              (m) => m?.id == line.medicationId,
              orElse: () => null,
            );
    final scheduledAt =
        _resolveScheduledAt(treatment, line, editing, store.doseLogs);
    final doseLabel = med?.defaultDose != null
        ? '${_numText(med!.defaultDose!)} ${med.unit}'
        : null;

    return SheetScaffold(
      title: editing != null ? '编辑口服打卡' : '口服打卡',
      heightFactor: 0.9,
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
                  if (editing == null && oralLines.length > 1) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final item in oralLines)
                          AppChip(
                            label: store.medications
                                    .cast<Medication?>()
                                    .firstWhere(
                                      (m) => m?.id == item.medicationId,
                                      orElse: () => null,
                                    )
                                    ?.name ??
                                item.label,
                            selected: item.id == line?.id,
                            onPressed: () =>
                                setState(() => _selectedLineId = item.id),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (line == null)
                    const InlineError(message: '没有可登记的口服用药，请先在设置里添加口服用药。')
                  else
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            med?.name ?? line.label,
                            style: TextStyle(
                              color: theme.colors.text,
                              fontSize: theme.fontSize.lg,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (doseLabel != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              '剂量 $doseLabel',
                              style: TextStyle(
                                color: theme.colors.textSecondary,
                                fontSize: theme.fontSize.sm,
                              ),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            '计划时间：${scheduledAt != null ? formatDateTimeFull(scheduledAt) : '未匹配到计划时间'}',
                            style: TextStyle(
                              color: theme.colors.textTertiary,
                              fontSize: theme.fontSize.xs,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  DateTimeField(
                    label: '服用时间',
                    value: _takenAt,
                    onChanged: (v) => setState(() => _takenAt = v),
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    label: '${Zh.form.note}（${Zh.common.optional}）',
                    value: _note,
                    onChanged: (v) => _note = v,
                    multiline: true,
                    placeholder: '服用后的感受、漏服原因等',
                    semanticLabel: '口服备注',
                  ),
                  if (_formError != null) ...[
                    const SizedBox(height: 16),
                    InlineError(message: _formError!),
                  ],
                ],
              ),
            ),
      footer: Row(
        children: [
          Expanded(
            child: AppButton(
              label: '跳过',
              onPressed: () => _submit(DoseStatus.skipped),
              variant: AppButtonVariant.secondary,
              loading: _savingStatus == DoseStatus.skipped,
              disabled: !store.ready || line == null || _savingStatus != null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: AppButton(
              label: '完成',
              onPressed: () => _submit(DoseStatus.done),
              loading: _savingStatus == DoseStatus.done,
              disabled: !store.ready || line == null || _savingStatus != null,
            ),
          ),
        ],
      ),
    );
  }
}

String _numText(double v) =>
    v == v.truncateToDouble() ? v.toInt().toString() : v.toString();

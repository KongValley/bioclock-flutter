import 'package:bioclock/db/repo.dart';
import 'package:bioclock/domain/date_utils.dart';
import 'package:bioclock/i18n/zh.dart';
import 'package:bioclock/models/types.dart';
import 'package:bioclock/store/app_store.dart';
import 'package:bioclock/ui/components/app_icon.dart';
import 'package:bioclock/ui/components/app_layout.dart';
import 'package:bioclock/ui/components/app_primitives.dart';
import 'package:bioclock/ui/components/app_scope.dart';
import 'package:bioclock/ui/components/time_fields.dart';
import 'package:bioclock/ui/theme.dart';
import 'package:flutter/material.dart';

const List<String> _weekdayLabels = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];

const List<(EfficacyKind, String)> _efficacyKindOptions = [
  (EfficacyKind.reduced, '疗效下降'),
  (EfficacyKind.failed, '疗效失效'),
  (EfficacyKind.intolerance, '不耐受'),
  (EfficacyKind.antibody, '抗药抗体'),
  (EfficacyKind.other, '其他'),
];

String _efficacyKindLabel(EfficacyKind kind) {
  for (final (k, label) in _efficacyKindOptions) {
    if (k == kind) return label;
  }
  return '其他';
}

String oralFrequencyText(OralPlan oral) {
  if (oral.frequency == OralFrequency.daily) return '每天';
  if (oral.frequency == OralFrequency.weekly) {
    return '每周 ${oral.timesPerPeriod} 次';
  }
  final days = ([...oral.daysOfWeek]..sort())
      .map((d) => _weekdayLabels[d.clamp(0, 6)])
      .join('、');
  return days.isEmpty ? '自定义' : '每周 $days';
}

String describeLine(TreatmentLine line, List<Medication> medications) {
  final med = medications.cast<Medication?>().firstWhere(
        (m) => m?.id == line.medicationId,
        orElse: () => null,
      );
  final name = med?.name ?? line.label;
  final ended = line.endedAt != null ? ' · 已停用' : '';
  if (line.kind == LineKind.oral) {
    final oral = line.oral;
    if (oral == null) return '$name · 口服$ended';
    final duration =
        oral.durationDays == null ? '长期' : '${oral.durationDays} 天';
    return '$name · 口服 · ${oralFrequencyText(oral)} · $duration$ended';
  }
  final last = line.phases.isNotEmpty ? line.phases.last : null;
  final interval = last != null ? '每 ${last.intervalDays} 天' : '未设间隔';
  final dose = last != null && last.dose != null
      ? ' · ${last.dose! == last.dose!.truncateToDouble() ? last.dose!.toInt() : last.dose!} ${last.unit}'
      : '';
  final host = line.isHost ? ' · 主药' : '';
  return '$name · 注射 · $interval$dose$host$ended';
}

class _PhaseDraft {
  _PhaseDraft({
    required this.kind,
    required this.intervalDays,
    required this.repeatCount,
    required this.doseText,
    required this.unit,
    this.effectiveFrom,
  });

  factory _PhaseDraft.empty() => _PhaseDraft(
        kind: PhaseKind.maintenance,
        intervalDays: 28,
        repeatCount: 0,
        doseText: '',
        unit: 'mg',
      );

  PhaseKind kind;
  int intervalDays;
  int repeatCount;
  String doseText;
  String unit;
  int? effectiveFrom;

  _PhaseDraft copy() => _PhaseDraft(
        kind: kind,
        intervalDays: intervalDays,
        repeatCount: repeatCount,
        doseText: doseText,
        unit: unit,
        effectiveFrom: effectiveFrom,
      );
}

class _OralDraft {
  _OralDraft({
    required this.startDate,
    required this.durationText,
    required this.frequency,
    required this.timesPerPeriod,
    required this.daysOfWeek,
    required this.remindTime,
  });

  factory _OralDraft.empty() => _OralDraft(
        startDate: DateTime.now().millisecondsSinceEpoch,
        durationText: '',
        frequency: OralFrequency.daily,
        timesPerPeriod: 1,
        daysOfWeek: [],
        remindTime: '09:00',
      );

  int startDate;
  String durationText;
  OralFrequency frequency;
  int timesPerPeriod;
  List<int> daysOfWeek;
  String remindTime;

  _OralDraft copy() => _OralDraft(
        startDate: startDate,
        durationText: durationText,
        frequency: frequency,
        timesPerPeriod: timesPerPeriod,
        daysOfWeek: List<int>.from(daysOfWeek),
        remindTime: remindTime,
      );
}

class _LineDraft {
  _LineDraft({
    required this.key,
    required this.id,
    required this.kind,
    required this.medicationId,
    required this.label,
    required this.isHost,
    required this.syncWithHost,
    required this.anchor,
    required this.windowDays,
    required this.phases,
    required this.oral,
  });

  final String key;
  final String? id;
  final LineKind kind;
  String medicationId;
  String label;
  bool isHost;
  bool syncWithHost;
  RegimenAnchor anchor;
  int windowDays;
  List<_PhaseDraft> phases;
  _OralDraft oral;

  _LineDraft copy() => _LineDraft(
        key: key,
        id: id,
        kind: kind,
        medicationId: medicationId,
        label: label,
        isHost: isHost,
        syncWithHost: syncWithHost,
        anchor: anchor,
        windowDays: windowDays,
        phases: [for (final p in phases) p.copy()],
        oral: oral.copy(),
      );
}

int _draftSeq = 0;

String _nextDraftKey(String prefix) {
  _draftSeq += 1;
  return '$prefix-${DateTime.now().millisecondsSinceEpoch}-$_draftSeq';
}

Future<void> showTreatmentEditorSheet(
  BuildContext context, {
  required Treatment? treatment,
}) {
  return showAppBottomSheet<void>(
    context,
    builder: (_) => _TreatmentEditorSheet(treatment: treatment),
  );
}

class _TreatmentEditorSheet extends StatefulWidget {
  const _TreatmentEditorSheet({required this.treatment});
  final Treatment? treatment;

  @override
  State<_TreatmentEditorSheet> createState() => _TreatmentEditorSheetState();
}

class _TreatmentEditorSheetState extends State<_TreatmentEditorSheet> {
  String _view = 'list';
  late String _name;
  late List<_LineDraft> _lines;
  _LineDraft? _lineDraft;
  String? _editingKey;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = widget.treatment?.name ?? '';
    _lines = widget.treatment == null
        ? []
        : [for (final line in widget.treatment!.lines) _lineToDraft(line)];
  }

  _LineDraft _lineToDraft(TreatmentLine line) => _LineDraft(
        key: line.id,
        id: line.id,
        kind: line.kind,
        medicationId: line.medicationId,
        label: line.label,
        isHost: line.isHost,
        syncWithHost: line.syncWithHost,
        anchor: line.anchor,
        windowDays: line.windowDays,
        phases: [
          for (final p in line.phases)
            _PhaseDraft(
              kind: p.kind,
              intervalDays: p.intervalDays,
              repeatCount: p.repeatCount,
              doseText: p.dose == null ? '' : '${p.dose}',
              unit: p.unit,
              effectiveFrom: p.effectiveFrom,
            ),
        ],
        oral: line.oral == null
            ? _OralDraft.empty()
            : _OralDraft(
                startDate: line.oral!.startDate,
                durationText: line.oral!.durationDays == null
                    ? ''
                    : '${line.oral!.durationDays}',
                frequency: line.oral!.frequency,
                timesPerPeriod: line.oral!.timesPerPeriod,
                daysOfWeek: List<int>.from(line.oral!.daysOfWeek),
                remindTime: line.oral!.remindTime,
              ),
      );

  _LineDraft _newLineDraft(LineKind kind, List<Medication> medications) {
    final eligible = kind == LineKind.injection
        ? medications.where((m) => m.route != MedicationRoute.oral).toList()
        : medications;
    final med = eligible.isNotEmpty ? eligible.first : null;
    return _LineDraft(
      key: _nextDraftKey('line'),
      id: null,
      kind: kind,
      medicationId: med?.id ?? '',
      label: med?.name ?? '',
      isHost: false,
      syncWithHost: false,
      anchor: RegimenAnchor.actual,
      windowDays: 2,
      phases: [_PhaseDraft.empty()],
      oral: _OralDraft.empty(),
    );
  }

  String _draftSummary(_LineDraft line, List<Medication> medications) {
    final med = medications.cast<Medication?>().firstWhere(
          (m) => m?.id == line.medicationId,
          orElse: () => null,
        );
    final name =
        med?.name ?? (line.label.trim().isEmpty ? '未选择药物' : line.label);
    if (line.kind == LineKind.oral) {
      final freq = oralFrequencyText(OralPlan(
        startDate: line.oral.startDate,
        durationDays: null,
        frequency: line.oral.frequency,
        timesPerPeriod: line.oral.timesPerPeriod,
        daysOfWeek: line.oral.daysOfWeek,
        remindTime: line.oral.remindTime,
      ));
      final dur = line.oral.durationText.trim().isEmpty
          ? '长期'
          : '${line.oral.durationText.trim()} 天';
      return '$name · 口服 · $freq · $dur';
    }
    final last = line.phases.isNotEmpty ? line.phases.last : null;
    final interval = last != null ? '每 ${last.intervalDays} 天' : '未设间隔';
    final dose = last != null && last.doseText.trim().isNotEmpty
        ? ' · ${last.doseText.trim()} ${last.unit}'
        : '';
    final ph = line.phases.length > 1 ? ' · ${line.phases.length} 个阶段' : '';
    final host = line.isHost ? ' · 主药' : '';
    return '$name · 注射 · $interval$dose$ph$host';
  }

  String? _validateLine(_LineDraft line) {
    if (line.medicationId.isEmpty) return '请选择药物';
    if (line.label.trim().isEmpty) return '请填写用药线名称';
    if (line.kind == LineKind.injection) {
      if (line.phases.isEmpty) return '注射线至少需要一个阶段';
      for (final p in line.phases) {
        if (p.intervalDays < 1) return '间隔天数至少为 1';
        if (p.unit.trim().isEmpty) return '阶段单位不能为空';
        if (p.doseText.trim().isNotEmpty) {
          final dose = double.tryParse(p.doseText.trim());
          if (dose == null || !dose.isFinite || dose < 0) {
            return '剂量必须是大于或等于 0 的数字';
          }
        }
      }
      return null;
    }
    if (line.oral.durationText.trim().isNotEmpty) {
      final days = int.tryParse(line.oral.durationText.trim());
      if (days == null || days < 1) return '疗程天数必须是大于 0 的整数';
    }
    if (line.oral.frequency == OralFrequency.weekly &&
        (line.oral.timesPerPeriod < 1 || line.oral.timesPerPeriod > 7)) {
      return '每周服药次数需要在 1 到 7 之间';
    }
    if (line.oral.frequency == OralFrequency.custom &&
        line.oral.daysOfWeek.isEmpty) {
      return '请至少选择一天服药';
    }
    return null;
  }

  TreatmentLineDraft _buildLineInput(_LineDraft line) {
    final safeLabel = line.label.trim().isEmpty ? '用药' : line.label.trim();
    if (line.kind == LineKind.oral) {
      final durText = line.oral.durationText.trim();
      return TreatmentLineDraft(
        id: line.id,
        medicationId: line.medicationId,
        kind: LineKind.oral,
        label: safeLabel,
        isHost: false,
        syncWithHost: false,
        anchor: line.anchor,
        windowDays: line.windowDays,
        oral: OralPlan(
          startDate: line.oral.startDate,
          durationDays: durText.isEmpty ? null : int.parse(durText),
          frequency: line.oral.frequency,
          timesPerPeriod: line.oral.frequency == OralFrequency.weekly
              ? line.oral.timesPerPeriod
              : 0,
          daysOfWeek: line.oral.frequency == OralFrequency.custom
              ? line.oral.daysOfWeek
              : const [],
          remindTime: line.oral.remindTime,
        ),
      );
    }
    return TreatmentLineDraft(
      id: line.id,
      medicationId: line.medicationId,
      kind: LineKind.injection,
      label: safeLabel,
      isHost: line.isHost,
      syncWithHost: !line.isHost && line.syncWithHost,
      anchor: line.anchor,
      windowDays: line.windowDays,
      phases: [
        for (var i = 0; i < line.phases.length; i += 1)
          TreatmentPhaseInput(
            orderIdx: i,
            kind: line.phases[i].kind,
            intervalDays: line.phases[i].intervalDays,
            repeatCount: line.phases[i].repeatCount,
            dose: line.phases[i].doseText.trim().isEmpty
                ? null
                : double.parse(line.phases[i].doseText.trim()),
            unit: line.phases[i].unit.trim(),
            effectiveFrom: line.phases[i].effectiveFrom,
          ),
      ],
    );
  }

  void _openNewLine(LineKind kind) {
    setState(() {
      _lineDraft = _newLineDraft(kind, context.store.medications);
      _editingKey = null;
      _error = null;
      _view = 'line';
    });
  }

  void _openEditLine(String key) {
    final found = _lines.cast<_LineDraft?>().firstWhere(
          (l) => l?.key == key,
          orElse: () => null,
        );
    if (found == null) return;
    setState(() {
      _lineDraft = found.copy();
      _editingKey = key;
      _error = null;
      _view = 'line';
    });
  }

  void _commitLine() {
    final draft = _lineDraft;
    if (draft == null) return;
    final problem = _validateLine(draft);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      var next = _editingKey != null
          ? [for (final l in _lines) l.key == _editingKey ? draft : l]
          : [..._lines, draft];
      if (draft.isHost) {
        next = [
          for (final l in next)
            if (l.key == draft.key)
              l
            else
              l..isHost = false,
        ];
      }
      _lines = next;
      _view = 'list';
      _lineDraft = null;
      _editingKey = null;
      _error = null;
    });
  }

  Future<void> _removeLine(String key) async {
    final target = _lines.cast<_LineDraft?>().firstWhere(
          (l) => l?.key == key,
          orElse: () => null,
        );
    if (target?.id != null) {
      final confirmed = await showConfirmDialog(
        context,
        title: '删除这条用药线？',
        message: '这条线的历史打卡记录会一起删除，且无法恢复。只是暂时不打这种药的话，可以在保存后到「疗效记录」里停用这条线。',
        confirmLabel: Zh.common.delete,
        destructive: true,
      );
      if (!confirmed || !mounted) return;
    }
    setState(() => _lines = _lines.where((l) => l.key != key).toList());
  }

  Future<void> _saveEditor() async {
    final trimmed = _name.trim();
    if (trimmed.isEmpty) {
      setState(() => _error = '请填写方案名称');
      return;
    }
    if (_lines.isEmpty) {
      setState(() => _error = '至少需要一条用药线');
      return;
    }
    if (_lines.where((l) => l.isHost).length > 1) {
      setState(() => _error = '方案内只能有一条主药');
      return;
    }
    for (final line in _lines) {
      final problem = _validateLine(line);
      if (problem != null) {
        setState(() => _error = problem);
        return;
      }
    }

    final store = context.store;
    final beforeIds = {for (final t in store.treatments) t.id};
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final res = await store.saveTreatment(
        SaveTreatmentInput(
          id: widget.treatment?.id,
          name: trimmed,
          lines: [_lines.map(_buildLineInput)].expand((e) => e).toList(),
        ),
      );
      if (!mounted) return;
      if (widget.treatment == null) {
        final created = store.treatments.cast<Treatment?>().firstWhere(
              (t) => t != null && !beforeIds.contains(t.id),
              orElse: () => null,
            );
        if (created != null && !created.isActive) {
          final actRes = await store.setActiveTreatment(created.id, true);
          if (actRes.notifyWarning != null) {
            showToast(actRes.notifyWarning!, isError: true);
          }
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      showToast(widget.treatment != null ? '治疗方案已更新' : '治疗方案已创建');
      if (res.notifyWarning != null) showToast(res.notifyWarning!, isError: true);
    } catch (err) {
      if (mounted) setState(() => _error = friendlyErrorMessage(err));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final medications = context.store.medications;

    return SheetScaffold(
      title: widget.treatment != null ? '编辑治疗方案' : '新建治疗方案',
      heightFactor: 0.92,
      body: _view == 'line' && _lineDraft != null
          ? _buildLineForm(theme, _lineDraft!, medications)
          : _buildListView(theme, medications),
      footer: _view == 'line'
          ? AppButton(
              label: Zh.common.confirm,
              onPressed: _commitLine,
              size: AppButtonSize.lg,
            )
          : AppButton(
              label: '保存治疗方案',
              onPressed: _saveEditor,
              loading: _saving,
              size: AppButtonSize.lg,
            ),
    );
  }

  Widget _buildListView(AppThemeData theme, List<Medication> medications) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        theme.spacing.lg,
        0,
        theme.spacing.lg,
        theme.spacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            label: Zh.settings.regimenName,
            value: _name,
            onChanged: (v) => _name = v,
            placeholder: '例如：阿达木单抗 + 甲氨蝶呤',
            semanticLabel: '治疗方案名称',
          ),
          const SizedBox(height: 14),
          Text(
            '用药线',
            style: TextStyle(
              color: theme.colors.text,
              fontSize: theme.fontSize.md,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '一个方案里可以有多种药；注射线只能有一条「主药」，排程以它的实际注射时间为锚点。',
            style: TextStyle(
              color: theme.colors.textTertiary,
              fontSize: theme.fontSize.xs,
            ),
          ),
          const SizedBox(height: 10),
          if (_lines.isEmpty)
            Text(
              '还没有用药线，先添加一条注射线或口服线。',
              style: TextStyle(
                color: theme.colors.textTertiary,
                fontSize: theme.fontSize.xs,
              ),
            )
          else
            for (final line in _lines) ...[
              Container(
                decoration: BoxDecoration(
                  color: theme.colors.surface,
                  borderRadius: BorderRadius.circular(theme.radius.md),
                  border: Border.all(color: theme.colors.border, width: 0.7),
                ),
                padding: EdgeInsets.all(theme.spacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _draftSummary(line, medications),
                      style: TextStyle(
                        color: theme.colors.text,
                        fontSize: theme.fontSize.sm,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: AppButton(
                            label: Zh.common.edit,
                            variant: AppButtonVariant.secondary,
                            onPressed: () => _openEditLine(line.key),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: AppButton(
                            label: Zh.common.delete,
                            variant: AppButtonVariant.danger,
                            onPressed: () => _removeLine(line.key),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: '添加注射线',
                  variant: AppButtonVariant.secondary,
                  icon: AppIconName.plus,
                  onPressed: () => _openNewLine(LineKind.injection),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppButton(
                  label: '添加口服线',
                  variant: AppButtonVariant.secondary,
                  icon: AppIconName.plus,
                  onPressed: () => _openNewLine(LineKind.oral),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            InlineError(message: _error!),
          ],
        ],
      ),
    );
  }

  Widget _buildLineForm(
    AppThemeData theme,
    _LineDraft draft,
    List<Medication> medications,
  ) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        theme.spacing.lg,
        0,
        theme.spacing.lg,
        theme.spacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Semantics(
                button: true,
                label: Zh.common.back,
                child: InkWell(
                  borderRadius: BorderRadius.circular(theme.radius.pill),
                  onTap: () => setState(() {
                    _view = 'list';
                    _lineDraft = null;
                    _editingKey = null;
                    _error = null;
                  }),
                  child: const SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: AppIcon(AppIconName.chevronLeft, size: 22),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _editingKey != null
                      ? '编辑用药线'
                      : draft.kind == LineKind.injection
                          ? '添加注射线'
                          : '添加口服线',
                  style: TextStyle(
                    color: theme.colors.text,
                    fontSize: theme.fontSize.lg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (draft.kind == LineKind.injection)
            ..._buildInjectionFields(theme, draft, medications)
          else
            ..._buildOralFields(theme, draft, medications),
          if (_error != null) ...[
            const SizedBox(height: 12),
            InlineError(message: _error!),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildInjectionFields(
    AppThemeData theme,
    _LineDraft draft,
    List<Medication> medications,
  ) {
    final eligible =
        medications.where((m) => m.route != MedicationRoute.oral).toList();
    final hostExists = _lines.any((l) => l.isHost && l.key != _editingKey);
    final canSync = !draft.isHost && hostExists;

    return [
      Text(
        Zh.form.medicationName,
        style: TextStyle(
          color: theme.colors.textSecondary,
          fontSize: theme.fontSize.sm,
        ),
      ),
      const SizedBox(height: 8),
      if (draft.id != null)
        Text(
          '${medications.cast<Medication?>().firstWhere((m) => m?.id == draft.medicationId, orElse: () => null)?.name ?? '已选药物'}（换药请新建一条用药线，历史记录会按原药保留）',
          style: TextStyle(
            color: theme.colors.textSecondary,
            fontSize: theme.fontSize.sm,
          ),
        )
      else
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final med in eligible)
              AppChip(
                label: med.name,
                selected: med.id == draft.medicationId,
                onPressed: () => setState(() {
                  draft.medicationId = med.id;
                  if (draft.label.trim().isEmpty) draft.label = med.name;
                }),
              ),
          ],
        ),
      const SizedBox(height: 14),
      AppTextField(
        label: '用药线名称',
        value: draft.label,
        onChanged: (v) => draft.label = v,
        placeholder: '默认用药名',
        semanticLabel: '用药线名称',
      ),
      const SizedBox(height: 8),
      SwitchRow(
        label: '设为主药',
        hint: '方案内只能有一条主药',
        value: draft.isHost,
        onChanged: (v) => setState(() {
          draft.isHost = v;
          if (v) draft.syncWithHost = false;
        }),
        last: true,
      ),
      SwitchRow(
        label: '跟随主药时间',
        hint: hostExists ? '和主药同一天注射' : '方案里还没有主药，无法跟随',
        value: canSync && draft.syncWithHost,
        onChanged: (v) => setState(() => draft.syncWithHost = v),
        disabled: !canSync,
        last: true,
      ),
      const SizedBox(height: 8),
      StepperField(
        label: Zh.settings.windowDays,
        value: draft.windowDays,
        onChanged: (v) => setState(() => draft.windowDays = v),
        min: 0,
        max: 30,
        suffix: Zh.common.unitDay,
        decreaseLabel: '按时窗口减少一天',
        increaseLabel: '按时窗口增加一天',
      ),
      const SizedBox(height: 14),
      Text(
        Zh.settings.phases,
        style: TextStyle(
          color: theme.colors.text,
          fontSize: theme.fontSize.md,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 8),
      for (var i = 0; i < draft.phases.length; i += 1) ...[
        () {
          final phase = draft.phases[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '阶段 ${i + 1}',
                          style: TextStyle(
                            color: theme.colors.text,
                            fontSize: theme.fontSize.sm,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Semantics(
                        button: true,
                        enabled: draft.phases.length > 1,
                        label: '删除阶段 ${i + 1}',
                        child: Opacity(
                          opacity: draft.phases.length <= 1 ? 0.35 : 1.0,
                          child: InkWell(
                            borderRadius:
                                BorderRadius.circular(theme.radius.sm),
                            onTap: draft.phases.length <= 1
                                ? null
                                : () => setState(() {
                                      draft.phases.removeAt(i);
                                    }),
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: Center(
                                child: AppIcon(
                                  AppIconName.trash,
                                  size: 18,
                                  color: theme.colors.danger,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SegmentedControl<PhaseKind>(
                    options: [
                      SegmentOption(
                        value: PhaseKind.loading,
                        label: Zh.settings.phaseLoading,
                      ),
                      SegmentOption(
                        value: PhaseKind.maintenance,
                        label: Zh.settings.phaseMaintenance,
                      ),
                    ],
                    value: phase.kind,
                    onChange: (k) => setState(() => phase.kind = k),
                    semanticLabel: '阶段 ${i + 1} 类型',
                  ),
                  const SizedBox(height: 12),
                  StepperField(
                    label: Zh.settings.intervalDays,
                    value: phase.intervalDays,
                    onChanged: (v) => setState(() => phase.intervalDays = v),
                    min: 1,
                    max: 365,
                    suffix: Zh.common.unitDay,
                    decreaseLabel: '间隔减少一天',
                    increaseLabel: '间隔增加一天',
                  ),
                  const SizedBox(height: 12),
                  StepperField(
                    label: Zh.settings.repeatCount,
                    value: phase.repeatCount,
                    onChanged: (v) => setState(() => phase.repeatCount = v),
                    min: 0,
                    max: 52,
                    suffix: '次',
                    decreaseLabel: '重复次数减少',
                    increaseLabel: '重复次数增加',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: AppTextField(
                          label: '${Zh.settings.dose}（${Zh.common.optional}）',
                          value: phase.doseText,
                          onChanged: (v) => phase.doseText = v,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          placeholder: '40',
                          semanticLabel: '阶段 ${i + 1} 剂量',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppTextField(
                          label: '单位',
                          value: phase.unit,
                          onChanged: (v) => phase.unit = v,
                          placeholder: 'mg',
                          semanticLabel: '阶段 ${i + 1} 单位',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }(),
      ],
      AppButton(
        label: Zh.settings.addPhase,
        variant: AppButtonVariant.outline,
        icon: AppIconName.plus,
        onPressed: () =>
            setState(() => draft.phases = [...draft.phases, _PhaseDraft.empty()]),
      ),
    ];
  }

  List<Widget> _buildOralFields(
    AppThemeData theme,
    _LineDraft draft,
    List<Medication> medications,
  ) {
    final eligible = [...medications]
      ..sort((a, b) =>
          (a.route == MedicationRoute.oral ? 0 : 1) -
          (b.route == MedicationRoute.oral ? 0 : 1));
    return [
      Text(
        Zh.form.medicationName,
        style: TextStyle(
          color: theme.colors.textSecondary,
          fontSize: theme.fontSize.sm,
        ),
      ),
      const SizedBox(height: 8),
      if (draft.id != null)
        Text(
          medications
                  .cast<Medication?>()
                  .firstWhere((m) => m?.id == draft.medicationId,
                      orElse: () => null)
                  ?.name ??
              '已选药物',
          style: TextStyle(
            color: theme.colors.textSecondary,
            fontSize: theme.fontSize.sm,
          ),
        )
      else
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final med in eligible)
              AppChip(
                label: med.name,
                selected: med.id == draft.medicationId,
                onPressed: () => setState(() {
                  draft.medicationId = med.id;
                  if (draft.label.trim().isEmpty) draft.label = med.name;
                }),
              ),
          ],
        ),
      const SizedBox(height: 14),
      AppTextField(
        label: '用药线名称',
        value: draft.label,
        onChanged: (v) => draft.label = v,
        placeholder: '默认用药名',
        semanticLabel: '用药线名称',
      ),
      const SizedBox(height: 14),
      DateTimeField(
        label: '开始日期',
        value: draft.oral.startDate,
        onChanged: (v) => setState(() => draft.oral.startDate = v),
      ),
      const SizedBox(height: 14),
      AppTextField(
        label: '疗程天数（${Zh.common.optional}）',
        value: draft.oral.durationText,
        onChanged: (v) => draft.oral.durationText = v,
        keyboardType: TextInputType.number,
        placeholder: '留空表示长期',
        hint: '留空表示长期服用',
        semanticLabel: '疗程天数',
      ),
      const SizedBox(height: 14),
      Text(
        '服药频次',
        style: TextStyle(
          color: theme.colors.textSecondary,
          fontSize: theme.fontSize.sm,
        ),
      ),
      const SizedBox(height: 6),
      SegmentedControl<OralFrequency>(
        options: const [
          SegmentOption(value: OralFrequency.daily, label: '每天'),
          SegmentOption(value: OralFrequency.weekly, label: '每周 N 次'),
          SegmentOption(value: OralFrequency.custom, label: '固定周几'),
        ],
        value: draft.oral.frequency,
        onChange: (f) => setState(() => draft.oral.frequency = f),
        semanticLabel: '服药频次',
      ),
      const SizedBox(height: 14),
      if (draft.oral.frequency == OralFrequency.weekly) ...[
        StepperField(
          label: '每周次数',
          value: draft.oral.timesPerPeriod,
          onChanged: (v) => setState(() => draft.oral.timesPerPeriod = v),
          min: 1,
          max: 7,
          suffix: '次',
          decreaseLabel: '每周次数减少',
          increaseLabel: '每周次数增加',
        ),
        const SizedBox(height: 14),
      ],
      if (draft.oral.frequency == OralFrequency.custom) ...[
        Text(
          '服药星期（可多选）',
          style: TextStyle(
            color: theme.colors.textSecondary,
            fontSize: theme.fontSize.sm,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var d = 0; d < _weekdayLabels.length; d += 1)
              AppChip(
                label: _weekdayLabels[d],
                selected: draft.oral.daysOfWeek.contains(d),
                onPressed: () {
                  setState(() {
                    if (draft.oral.daysOfWeek.contains(d)) {
                      draft.oral.daysOfWeek =
                          draft.oral.daysOfWeek.where((x) => x != d).toList();
                    } else {
                      draft.oral.daysOfWeek = [...draft.oral.daysOfWeek, d]
                        ..sort();
                    }
                  });
                },
              ),
          ],
        ),
        const SizedBox(height: 14),
      ],
      TimeOfDayField(
        label: '服药提醒时间',
        value: draft.oral.remindTime,
        onChanged: (v) => setState(() => draft.oral.remindTime = v),
      ),
    ];
  }
}

Future<void> showEfficacyManagerSheet(BuildContext context) {
  return showAppBottomSheet<void>(
    context,
    builder: (_) => const _EfficacyManagerSheet(),
  );
}

class _EfficacyManagerSheet extends StatefulWidget {
  const _EfficacyManagerSheet();

  @override
  State<_EfficacyManagerSheet> createState() => _EfficacyManagerSheetState();
}

class _EfficacyManagerSheetState extends State<_EfficacyManagerSheet> {
  String _lineId = '';
  EfficacyKind _kind = EfficacyKind.reduced;
  int _occurredAt = DateTime.now().millisecondsSinceEpoch;
  String _note = '';
  bool _stopLine = true;
  bool _saving = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final lines = context.store.treatment?.lines ?? const <TreatmentLine>[];
    if (_lineId.isEmpty && lines.isNotEmpty) {
      final sorted = [...lines]
        ..sort((a, b) =>
            (a.kind == LineKind.injection ? 0 : 1) -
            (b.kind == LineKind.injection ? 0 : 1));
      _lineId = sorted.first.id;
    }
  }

  Future<void> _save(TreatmentLine? selectedLine) async {
    setState(() => _error = null);
    if (selectedLine == null) {
      setState(() => _error = '请先选择一条用药线。');
      return;
    }
    if (_occurredAt <= 0) {
      setState(() => _error = '请选择有效的事件时间。');
      return;
    }
    setState(() => _saving = true);
    try {
      final res = await context.store.addEfficacyEvent(
        EfficacyEventInput(
          lineId: selectedLine.id,
          kind: _kind,
          occurredAt: _occurredAt,
          note: _note.trim().isEmpty ? null : _note.trim(),
          stopLine: selectedLine.endedAt == null ? _stopLine : false,
        ),
      );
      if (!mounted) return;
      showToast(
        selectedLine.endedAt == null && _stopLine
            ? '已记录，并停用这条用药线'
            : '已记录疗效事件',
      );
      if (res.notifyWarning != null) showToast(res.notifyWarning!, isError: true);
      setState(() {
        _note = '';
        _occurredAt = DateTime.now().millisecondsSinceEpoch;
        _stopLine = true;
      });
    } catch (err) {
      final msg = friendlyErrorMessage(err);
      if (mounted) {
        setState(() => _error = msg);
        showToast(msg, isError: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _restoreLine(TreatmentLine line) async {
    try {
      final res = await context.store.setLineEnded(line.id, null);
      if (!mounted) return;
      showToast('已恢复这条用药线');
      if (res.notifyWarning != null) showToast(res.notifyWarning!, isError: true);
    } catch (err) {
      if (mounted) showToast(friendlyErrorMessage(err), isError: true);
    }
  }

  Future<void> _removeEvent(EfficacyEvent event) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除疗效记录',
      message: '确定删除「${_efficacyKindLabel(event.kind)}」这条记录吗？用药线不会自动恢复。',
      confirmLabel: Zh.common.delete,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      final res = await context.store.removeEfficacyEvent(event.id);
      if (!mounted) return;
      showToast('已删除疗效记录');
      if (res.notifyWarning != null) showToast(res.notifyWarning!, isError: true);
    } catch (err) {
      if (mounted) showToast(friendlyErrorMessage(err), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final store = context.store;
    final lines = store.treatment?.lines ?? const <TreatmentLine>[];
    final orderedLines = [...lines]
      ..sort((a, b) =>
          (a.kind == LineKind.injection ? 0 : 1) -
          (b.kind == LineKind.injection ? 0 : 1));
    final selectedLine = orderedLines.cast<TreatmentLine?>().firstWhere(
          (l) => l?.id == _lineId,
          orElse: () => orderedLines.isNotEmpty ? orderedLines.first : null,
        );
    final scopedEvents = store.efficacyEvents
        .where((e) => lines.any((l) => l.id == e.lineId))
        .toList();

    String lineName(TreatmentLine line) {
      final med = store.medications.cast<Medication?>().firstWhere(
            (m) => m?.id == line.medicationId,
            orElse: () => null,
          );
      return med?.name ?? line.label;
    }

    return SheetScaffold(
      title: '疗效记录',
      heightFactor: 0.92,
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          theme.spacing.lg,
          0,
          theme.spacing.lg,
          theme.spacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (orderedLines.isEmpty)
              AppCard(
                child: Text(
                  '还没有用药线，请先创建治疗方案。',
                  style: TextStyle(
                    color: theme.colors.textSecondary,
                    fontSize: theme.fontSize.sm,
                  ),
                ),
              )
            else
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '用药线',
                      style: TextStyle(
                        color: theme.colors.textSecondary,
                        fontSize: theme.fontSize.sm,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final l in orderedLines)
                          AppChip(
                            label:
                                '${lineName(l)}${l.kind == LineKind.injection ? ' · 注射' : ' · 口服'}',
                            selected: l.id == selectedLine?.id,
                            onPressed: () => setState(() => _lineId = l.id),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '事件类型',
                      style: TextStyle(
                        color: theme.colors.textSecondary,
                        fontSize: theme.fontSize.sm,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final (k, label) in _efficacyKindOptions)
                          AppChip(
                            label: label,
                            selected: k == _kind,
                            onPressed: () => setState(() => _kind = k),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    DateTimeField(
                      label: '发生时间',
                      value: _occurredAt,
                      onChanged: (v) => setState(() => _occurredAt = v),
                    ),
                    const SizedBox(height: 14),
                    AppTextField(
                      label: '备注（${Zh.common.optional}）',
                      value: _note,
                      onChanged: (v) => _note = v,
                      placeholder: '例如：医生评估后调整方案',
                      multiline: true,
                      semanticLabel: '疗效事件备注',
                    ),
                    const SizedBox(height: 8),
                    if (selectedLine?.endedAt == null)
                      SwitchRow(
                        label: '同时停用这条用药线',
                        hint: '停用后不再生成后续计划，历史打卡保留',
                        value: _stopLine,
                        onChanged: (v) => setState(() => _stopLine = v),
                        last: true,
                      )
                    else if (selectedLine != null) ...[
                      Text(
                        '这条用药线已于 ${formatDate(selectedLine.endedAt!)} 停用',
                        style: TextStyle(
                          color: theme.colors.textSecondary,
                          fontSize: theme.fontSize.sm,
                        ),
                      ),
                      const SizedBox(height: 8),
                      AppButton(
                        label: '恢复这条用药线',
                        variant: AppButtonVariant.secondary,
                        onPressed: () => _restoreLine(selectedLine),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      InlineError(message: _error!),
                    ],
                    const SizedBox(height: 12),
                    AppButton(
                      label: '保存疗效记录',
                      onPressed: () => _save(selectedLine),
                      loading: _saving,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '仅用于自我观察和就诊时回顾，不构成疗效或因果判断。是否停药、换药请遵医嘱。',
                      style: TextStyle(
                        color: theme.colors.textTertiary,
                        fontSize: theme.fontSize.xs,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            SectionTitle(title: '已有记录', hint: '${scopedEvents.length} 条'),
            const SizedBox(height: 10),
            if (scopedEvents.isEmpty)
              AppCard(
                child: Text(
                  '还没有疗效记录。',
                  style: TextStyle(
                    color: theme.colors.textSecondary,
                    fontSize: theme.fontSize.sm,
                  ),
                ),
              )
            else
              for (final event in scopedEvents) ...[
                () {
                  final l = lines.cast<TreatmentLine?>().firstWhere(
                        (item) => item?.id == event.lineId,
                        orElse: () => null,
                      );
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppCard(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${l != null ? lineName(l) : '已删除的用药线'} · ${_efficacyKindLabel(event.kind)}',
                                  style: TextStyle(
                                    color: theme.colors.text,
                                    fontSize: theme.fontSize.md,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${formatDate(event.occurredAt)} · 当时已完成 ${event.dosesCount} 次',
                                  style: TextStyle(
                                    color: theme.colors.textTertiary,
                                    fontSize: theme.fontSize.xs,
                                  ),
                                ),
                                if (event.note != null &&
                                    event.note!.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    event.note!,
                                    style: TextStyle(
                                      color: theme.colors.textSecondary,
                                      fontSize: theme.fontSize.sm,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Semantics(
                            button: true,
                            label: '删除 ${_efficacyKindLabel(event.kind)} 记录',
                            child: InkWell(
                              borderRadius:
                                  BorderRadius.circular(theme.radius.pill),
                              onTap: () => _removeEvent(event),
                              child: SizedBox(
                                width: 44,
                                height: 44,
                                child: Center(
                                  child: AppIcon(
                                    AppIconName.trash,
                                    size: 18,
                                    color: theme.colors.textTertiary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }(),
              ],
          ],
        ),
      ),
    );
  }
}

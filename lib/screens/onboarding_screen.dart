import 'dart:convert';
import 'dart:io';

import 'package:app_settings/app_settings.dart' as app_settings;
import 'package:bioclock/data/catalog.dart';
import 'package:bioclock/data/diseases.dart';
import 'package:bioclock/db/repo.dart';
import 'package:bioclock/domain/date_utils.dart';
import 'package:bioclock/domain/preview.dart';
import 'package:bioclock/i18n/zh.dart';
import 'package:bioclock/import/transfer_restore.dart';
import 'package:bioclock/models/types.dart';
import 'package:bioclock/notify/notify_scheduler.dart';
import 'package:bioclock/store/app_store.dart';
import 'package:bioclock/ui/components/app_icon.dart';
import 'package:bioclock/ui/components/app_layout.dart';
import 'package:bioclock/ui/components/app_primitives.dart';
import 'package:bioclock/ui/components/app_scope.dart';
import 'package:bioclock/ui/components/time_fields.dart';
import 'package:bioclock/ui/theme.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

const String _customKey = '__custom__';

class _EditablePhase {
  _EditablePhase({
    required this.key,
    required this.kind,
    required this.intervalDays,
    required this.repeatCount,
    required this.doseText,
    required this.unit,
  });

  final String key;
  final PhaseKind kind;
  int intervalDays;
  int repeatCount;
  String doseText;
  String unit;
}

List<_EditablePhase> _toEditablePhases(
  List<RegimenPhaseTemplate> template, {
  required String fallbackDose,
  required String fallbackUnit,
}) {
  if (template.isEmpty) {
    return [
      _EditablePhase(
        key: 'phase-0',
        kind: PhaseKind.maintenance,
        intervalDays: 28,
        repeatCount: 0,
        doseText: fallbackDose,
        unit: fallbackUnit.isEmpty ? 'mg' : fallbackUnit,
      ),
    ];
  }
  return [
    for (var i = 0; i < template.length; i += 1)
      _EditablePhase(
        key: 'phase-$i',
        kind: template[i].kind,
        intervalDays: template[i].intervalDays,
        repeatCount: template[i].repeatCount,
        doseText: template[i].dose != null ? _numText(template[i].dose!) : '',
        unit: template[i].unit,
      ),
  ];
}

String _phaseLabel(PhaseKind kind) =>
    kind == PhaseKind.loading ? Zh.settings.phaseLoading : Zh.settings.phaseMaintenance;

String _routeLabel(MedicationRoute route) => switch (route) {
      MedicationRoute.iv => '医院输注',
      MedicationRoute.oral => '口服',
      MedicationRoute.sc => '皮下注射',
    };

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.onCompleted,
    this.canPop = false,
  });

  final VoidCallback onCompleted;
  final bool canPop;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;
  String _query = '';
  List<String> _diseaseIds = [];

  String? _drugKey;
  bool _customOpen = false;
  String _customName = '';
  String _customGeneric = '';
  MedicationRoute _customRoute = MedicationRoute.sc;
  String _customDose = '';
  String _customUnit = 'mg';
  String? _customError;

  String _treatmentName = '';
  List<_EditablePhase> _basePhases = [];
  List<_EditablePhase> _phases = [];
  bool _noLoading = false;
  bool _hasLastInjection = false;
  int _lastInjectionAt = DateTime.now().millisecondsSinceEpoch;

  String _timeOfDay = '09:00';
  List<int> _offsets = [-2, -1, 0];
  String _dndStart = '22:00';
  String _dndEnd = '08:00';
  NotificationPermissionStatus? _permission;
  String? _permissionError;
  bool _checkingPermission = false;
  bool _finishing = false;
  String? _finishError;
  bool _restoring = false;

  MedicationRoute get _selectedRoute {
    if (_drugKey == _customKey) return _customRoute;
    if (_drugKey != null && drugsByKey[_drugKey!]?.route == MedicationRoute.iv) {
      return MedicationRoute.iv;
    }
    return MedicationRoute.sc;
  }

  String get _selectedDrugName {
    if (_drugKey == _customKey) {
      return _customName.trim().isEmpty ? '自定义药物' : _customName.trim();
    }
    if (_drugKey != null) {
      return drugsByKey[_drugKey!]?.name ?? '所选药物';
    }
    return '所选药物';
  }

  Future<void> _requestPermission() async {
    setState(() {
      _checkingPermission = true;
      _permissionError = null;
    });
    try {
      final result = await NotifyScheduler.ensurePermissions();
      if (!mounted) return;
      setState(() => _permission = result);
      if (!result.granted) {
        showToast('通知权限未开启，仍可先完成设置', isError: true);
      }
    } catch (err) {
      if (mounted) {
        setState(() => _permissionError = friendlyErrorMessage(err));
      }
    } finally {
      if (mounted) setState(() => _checkingPermission = false);
    }
  }

  Future<void> _restoreFromBackup() async {
    setState(() => _restoring = true);
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: '选择换机备份 (.json)',
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final text = utf8.decode(bytes);
      if (!mounted) return;
      final outcome = await restoreTransferBackup(context.store, text);
      if (!mounted) return;
      final restored = outcome.result.injections +
          outcome.result.oralLogs +
          outcome.result.symptoms;
      showToast(restored > 0 ? '已从备份恢复 $restored 条记录' : '已从备份恢复');
      if (outcome.notifyWarning != null) {
        showToast(outcome.notifyWarning!, isError: true);
      }
      widget.onCompleted();
    } catch (err) {
      if (mounted) showToast(friendlyErrorMessage(err), isError: true);
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  void _toggleDisease(Disease disease) {
    setState(() {
      if (_diseaseIds.contains(disease.id)) {
        _diseaseIds = _diseaseIds.where((id) => id != disease.id).toList();
      } else {
        _diseaseIds = [..._diseaseIds, disease.id];
      }
      if (_drugKey != null && _drugKey != _customKey) {
        final stillValid = drugsForDiseases(_diseaseIds)
            .any((e) => e.drug.key == _drugKey);
        if (!stillValid) {
          _drugKey = null;
          _customOpen = false;
          _customError = null;
        }
      }
    });
  }

  String? _customProblem() {
    if (_customName.trim().isEmpty) return '请输入药物名称。';
    if (_customUnit.trim().isEmpty) return '请输入剂量单位。';
    if (_customDose.trim().isNotEmpty) {
      final dose = double.tryParse(_customDose.trim());
      if (dose == null || !dose.isFinite || dose < 0) {
        return '默认剂量必须是大于或等于 0 的数字。';
      }
    }
    return null;
  }

  void _goNext() {
    if (_step == 0) {
      if (_diseaseIds.isEmpty) {
        showToast('请至少选择一个病种');
        return;
      }
      setState(() => _step = 1);
      return;
    }

    if (_step == 1) {
      if (_drugKey == null) {
        showToast('请选择一种药物，或使用自定义药物');
        return;
      }
      if (_drugKey == _customKey) {
        final problem = _customProblem();
        if (problem != null) {
          setState(() => _customError = problem);
          showToast(problem, isError: true);
          return;
        }
        setState(() {
          _customError = null;
          final editable = _toEditablePhases(
            const [],
            fallbackDose: _customDose.trim(),
            fallbackUnit: _customUnit.trim(),
          );
          _basePhases = editable;
          _phases = [
            for (final p in editable)
              _EditablePhase(
                key: p.key,
                kind: p.kind,
                intervalDays: p.intervalDays,
                repeatCount: p.repeatCount,
                doseText: p.doseText,
                unit: p.unit,
              ),
          ];
          _noLoading = false;
          _treatmentName = '${_customName.trim()} 方案';
          _step = 2;
        });
        return;
      }
      final selectedEntry = regimenForDiseases(_diseaseIds, _drugKey!);
      final editable = _toEditablePhases(
        selectedEntry?.regimen.phases ?? const [],
        fallbackDose: '',
        fallbackUnit: 'mg',
      );
      setState(() {
        _basePhases = editable;
        _phases = [
          for (final p in editable)
            _EditablePhase(
              key: p.key,
              kind: p.kind,
              intervalDays: p.intervalDays,
              repeatCount: p.repeatCount,
              doseText: p.doseText,
              unit: p.unit,
            ),
        ];
        _noLoading = false;
        _treatmentName = selectedEntry?.regimen.name ?? '我的用药方案';
        _step = 2;
      });
      return;
    }

    if (_step == 2) {
      if (_treatmentName.trim().isEmpty) {
        showToast('请给方案起个名字');
        return;
      }
      if (_phases.isEmpty) {
        showToast('至少需要一个剂量阶段');
        return;
      }
      for (final phase in _phases) {
        if (phase.unit.trim().isEmpty) {
          showToast('阶段单位不能为空');
          return;
        }
        if (phase.doseText.trim().isNotEmpty) {
          final dose = double.tryParse(phase.doseText.trim());
          if (dose == null || !dose.isFinite || dose < 0) {
            showToast('剂量必须是大于或等于 0 的数字');
            return;
          }
        }
      }
      setState(() => _step = 3);
      if (Platform.isAndroid) {
        _requestPermission();
      } else {
        setState(() {
          _permission =
              const NotificationPermissionStatus(granted: true, exactAlarm: true);
        });
      }
    }
  }

  void _toggleNoLoading(bool value) {
    setState(() {
      _noLoading = value;
      if (!value) {
        _phases = _basePhases;
        return;
      }
      final maintenance =
          _basePhases.where((p) => p.kind == PhaseKind.maintenance).toList();
      if (maintenance.isNotEmpty) {
        _phases = maintenance;
        return;
      }
      final last = _basePhases.isNotEmpty ? _basePhases.last : null;
      _phases = [
        _EditablePhase(
          key: 'phase-maintenance',
          kind: PhaseKind.maintenance,
          intervalDays: last?.intervalDays ?? 28,
          repeatCount: 0,
          doseText: last?.doseText ?? '',
          unit: last?.unit ?? 'mg',
        ),
      ];
    });
  }

  Future<void> _finish() async {
    setState(() => _finishError = null);
    if (_diseaseIds.isEmpty || _drugKey == null) {
      setState(() => _finishError = '请先完成病种与药物选择。');
      return;
    }
    if (_offsets.isEmpty) {
      setState(() => _finishError = '至少选择一个提醒时间点。');
      return;
    }
    if (parseTimeOfDay(_timeOfDay) == null) {
      setState(() => _finishError = '提醒时间格式不合法。');
      return;
    }
    if (parseTimeOfDay(_dndStart) == null || parseTimeOfDay(_dndEnd) == null) {
      setState(() => _finishError = '免打扰时间格式不合法。');
      return;
    }
    if (_selectedRoute != MedicationRoute.oral &&
        _hasLastInjection &&
        (_lastInjectionAt <= 0 ||
            _lastInjectionAt >
                DateTime.now().millisecondsSinceEpoch + 24 * 60 * 60 * 1000)) {
      setState(() => _finishError = '上次注射时间不能晚于今天。');
      return;
    }

    setState(() => _finishing = true);
    try {
      String medicationId;
      if (_drugKey == _customKey) {
        final problem = _customProblem();
        if (problem != null) {
          setState(() {
            _finishError = '$problem请返回第二步检查。';
            _finishing = false;
          });
          return;
        }
        final dose = _customDose.trim().isEmpty
            ? null
            : double.tryParse(_customDose.trim());
        final primaryHex =
            '#${context.appTheme.colors.primary.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
        final created = await MedicationsRepo.create(
          MedicationInput(
            name: _customName.trim(),
            genericName:
                _customGeneric.trim().isEmpty ? null : _customGeneric.trim(),
            brandNames: const [],
            defaultDose: dose,
            unit: _customUnit.trim(),
            color: primaryHex,
            route: _customRoute,
            diseaseIds: _diseaseIds,
          ),
        );
        medicationId = created.id;
      } else {
        final allMeds = await MedicationsRepo.list();
        final existing = allMeds.cast<Medication?>().firstWhere(
              (m) => m?.catalogKey == _drugKey,
              orElse: () => null,
            );
        if (existing != null) {
          medicationId = existing.id;
        } else {
          final drug = drugsByKey[_drugKey!];
          if (drug == null) throw StateError('所选药物不在目录中，请改用自定义药物');
          final created = await MedicationsRepo.create(
            MedicationInput(
              name: drug.name,
              genericName: drug.genericName,
              brandNames: drug.brandNames,
              defaultDose: drug.defaultDose,
              unit: drug.unit,
              color: drug.color,
              route: drug.route,
              diseaseIds: diseaseIdsForDrug(drug.key),
              catalogKey: drug.key,
              isBuiltin: true,
            ),
          );
          medicationId = created.id;
        }
      }

      final oralRoute = _selectedRoute == MedicationRoute.oral;
      final selectedEntry = _drugKey != null && _drugKey != _customKey
          ? regimenForDiseases(_diseaseIds, _drugKey!)
          : null;
      final windowDays = selectedEntry?.regimen.windowDays ?? 2;
      final todayStart = startOfDay(DateTime.now().millisecondsSinceEpoch);

      final treatment = await TreatmentsRepo.create(
        TreatmentInput(
          name: _treatmentName.trim(),
          lines: [
            if (oralRoute)
              TreatmentLineInput(
                medicationId: medicationId,
                kind: LineKind.oral,
                label: _selectedDrugName,
                anchor: RegimenAnchor.actual,
                windowDays: windowDays,
                phases: const [],
                oral: OralPlan(
                  startDate: todayStart,
                  durationDays: null,
                  frequency: OralFrequency.daily,
                  timesPerPeriod: 1,
                  daysOfWeek: const [],
                  remindTime: _timeOfDay,
                ),
              )
            else
              TreatmentLineInput(
                medicationId: medicationId,
                kind: LineKind.injection,
                label: _selectedDrugName,
                isHost: true,
                anchor: RegimenAnchor.actual,
                windowDays: windowDays,
                phases: [
                  for (var i = 0; i < _phases.length; i += 1)
                    TreatmentPhaseInput(
                      orderIdx: i,
                      kind: _phases[i].kind,
                      intervalDays: _phases[i].intervalDays,
                      repeatCount: _phases[i].repeatCount,
                      dose: _phases[i].doseText.trim().isEmpty
                          ? null
                          : double.tryParse(_phases[i].doseText.trim()),
                      unit: _phases[i].unit.trim(),
                    ),
                ],
                oral: null,
              ),
          ],
        ),
      );
      await TreatmentsRepo.setActive(treatment.id, true);

      if (!oralRoute && _hasLastInjection && treatment.lines.isNotEmpty) {
        final createdLine = treatment.lines.first;
        final lastPhase = _phases.isNotEmpty ? _phases.last : null;
        await DoseLogsRepo.create(
          DoseLogInput(
            lineId: createdLine.id,
            scheduledAt: _lastInjectionAt,
            takenAt: _lastInjectionAt,
            status: DoseStatus.done,
            dose: lastPhase != null && lastPhase.doseText.trim().isNotEmpty
                ? double.tryParse(lastPhase.doseText.trim())
                : null,
            unit: lastPhase != null && lastPhase.unit.trim().isNotEmpty
                ? lastPhase.unit.trim()
                : 'mg',
            note: '首次设置时录入的历史注射',
          ),
        );
      }

      await ReminderRulesRepo.upsert(
        ReminderRuleInput(
          treatmentId: treatment.id,
          offsets: _offsets,
          timeOfDay: _timeOfDay,
          snoozeMinutes: 10,
          enabled: true,
        ),
      );
      await SettingsRepo.set('disease_ids', jsonEncode(_diseaseIds));
      await SettingsRepo.set(
        'disease_id',
        _diseaseIds.isNotEmpty ? _diseaseIds.first : '',
      );
      await SettingsRepo.set(
        'onboarded_at',
        DateTime.now().millisecondsSinceEpoch.toString(),
      );
      await SettingsRepo.set('dnd_start', _dndStart);
      await SettingsRepo.set('dnd_end', _dndEnd);

      String? warning;
      try {
        await NotifyScheduler.rescheduleAll();
      } catch (err) {
        warning = '提醒排程失败：${friendlyErrorMessage(err)}';
      }
      if (!mounted) return;
      try {
        await context.store.reload();
      } catch (err) {
        final reloadMsg = '数据刷新失败：${friendlyErrorMessage(err)}';
        warning = warning == null ? reloadMsg : '$warning；$reloadMsg';
      }

      if (!mounted) return;
      setState(() => _finishing = false);
      widget.onCompleted();
      showToast('设置完成，可以开始记录了');
      if (warning != null) showToast(warning, isError: true);
    } catch (err) {
      if (mounted) {
        final msg = friendlyErrorMessage(err);
        setState(() {
          _finishing = false;
          _finishError = msg;
        });
        showToast(msg, isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    const stepTitles = [
      '选择病种（可多选）',
      '选择你正在使用的药物',
      '确认用药方案',
      '设置提醒时间',
    ];
    final stepHints = [
      '同时有多种免疫介导疾病时可以多选，例如克罗恩病 + 强直性脊柱炎；病种只用于缩小药物列表。',
      '药名与剂量仅用于快速录入，请以医生处方为准。',
      Zh.onboarding.loadingDoseHint,
      Zh.onboarding.reminderHint,
    ];

    return Scaffold(
      backgroundColor: theme.colors.background,
      body: SafeArea(
        child: ResponsiveContainer(
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  theme.spacing.lg,
                  theme.spacing.sm,
                  theme.spacing.lg,
                  theme.spacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        if (_step > 0 || widget.canPop)
                          Semantics(
                            button: true,
                            label: Zh.common.previous,
                            child: InkWell(
                              borderRadius:
                                  BorderRadius.circular(theme.radius.pill),
                              onTap: _finishing
                                  ? null
                                  : () {
                                      if (_step > 0) {
                                        setState(() {
                                          _finishError = null;
                                          _step -= 1;
                                        });
                                      } else if (widget.canPop) {
                                        Navigator.of(context).pop();
                                      }
                                    },
                              child: const SizedBox(
                                width: 44,
                                height: 44,
                                child: Center(
                                  child: AppIcon(
                                    AppIconName.chevronLeft,
                                    size: 22,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Semantics(
                                header: true,
                                child: Text(
                                  stepTitles[_step],
                                  style: TextStyle(
                                    color: theme.colors.text,
                                    fontSize: theme.fontSize.xl,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Text(
                                '第 ${_step + 1} 步 / 共 4 步',
                                style: TextStyle(
                                  color: theme.colors.textTertiary,
                                  fontSize: theme.fontSize.xs,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          'BioClock',
                          style: TextStyle(
                            color: theme.colors.primary,
                            fontSize: theme.fontSize.sm,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (var i = 0; i < 4; i += 1) ...[
                          if (i > 0) const SizedBox(width: 6),
                          Expanded(
                            child: Container(
                              height: 5,
                              decoration: BoxDecoration(
                                color: i <= _step
                                    ? theme.colors.primary
                                    : theme.colors.surfaceMuted,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      stepHints[_step],
                      style: TextStyle(
                        color: theme.colors.textTertiary,
                        fontSize: theme.fontSize.xs,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: switch (_step) {
                  0 => _buildDiseaseStep(theme),
                  1 => _buildMedicationStep(theme),
                  2 => _buildRegimenStep(theme),
                  _ => _buildReminderStep(theme),
                },
              ),
              Container(
                decoration: BoxDecoration(
                  color: theme.colors.background,
                  border: Border(
                    top: BorderSide(color: theme.colors.border, width: 0.6),
                  ),
                ),
                padding: EdgeInsets.fromLTRB(
                  theme.spacing.lg,
                  theme.spacing.sm,
                  theme.spacing.lg,
                  theme.spacing.md,
                ),
                child: Row(
                  children: [
                    if (_step > 0) ...[
                      Expanded(
                        child: AppButton(
                          label: Zh.common.previous,
                          variant: AppButtonVariant.secondary,
                          disabled: _finishing,
                          onPressed: () => setState(() {
                            _finishError = null;
                            _step -= 1;
                          }),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    if (_step < 3)
                      Expanded(
                        flex: 2,
                        child: AppButton(
                          label: Zh.common.next,
                          onPressed: _goNext,
                          disabled: _step == 0
                              ? _diseaseIds.isEmpty
                              : _step == 1
                                  ? _drugKey == null
                                  : false,
                        ),
                      )
                    else
                      Expanded(
                        flex: 2,
                        child: AppButton(
                          label: Zh.onboarding.finish,
                          onPressed: _finish,
                          loading: _finishing,
                          size: AppButtonSize.lg,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDiseaseStep(AppThemeData theme) {
    final kw = _query.trim().toLowerCase();
    final rows = <({String? groupTitle, Disease? disease})>[];
    for (final group in diseaseGroups) {
      final matches = diseasesByGroup(group.id).where((d) {
        if (kw.isEmpty) return true;
        if (d.name.toLowerCase().contains(kw)) return true;
        return d.aliases.any((a) => a.toLowerCase().contains(kw));
      }).toList();
      if (matches.isEmpty) continue;
      rows.add((groupTitle: group.name, disease: null));
      for (final d in matches) {
        rows.add((groupTitle: null, disease: d));
      }
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(
        theme.spacing.lg,
        4,
        theme.spacing.lg,
        theme.spacing.xl,
      ),
      children: [
        AppCard(
          tone: AppCardTone.primary,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                Zh.onboarding.restoreTitle,
                style: TextStyle(
                  color: theme.colors.primary,
                  fontSize: theme.fontSize.sm,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                Zh.onboarding.restoreHint,
                style: TextStyle(
                  color: theme.colors.textSecondary,
                  fontSize: theme.fontSize.xs,
                ),
              ),
              const SizedBox(height: 10),
              AppButton(
                label: Zh.onboarding.restoreAction,
                onPressed: _restoreFromBackup,
                variant: AppButtonVariant.secondary,
                loading: _restoring,
                disabled: _finishing,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppTextField(
          value: _query,
          onChanged: (v) => setState(() => _query = v),
          placeholder: '搜索病名或别名，如 银屑病 / CD',
          semanticLabel: '搜索病种',
        ),
        const SizedBox(height: 6),
        Text(
          '找不到？可选择最接近的病种，或直接自定义药物。',
          style: TextStyle(
            color: theme.colors.textTertiary,
            fontSize: theme.fontSize.xs,
          ),
        ),
        if (_diseaseIds.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            '已选 ${_diseaseIds.length} 个病种',
            style: TextStyle(
              color: theme.colors.primary,
              fontSize: theme.fontSize.xs,
            ),
          ),
        ],
        const SizedBox(height: 8),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              '没有匹配的病种，换个关键词试试。',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.colors.textSecondary,
                fontSize: theme.fontSize.sm,
              ),
            ),
          )
        else
          for (final item in rows)
            if (item.groupTitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 6),
                child: Semantics(
                  header: true,
                  child: Text(
                    item.groupTitle!,
                    style: TextStyle(
                      color: theme.colors.textSecondary,
                      fontSize: theme.fontSize.sm,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              )
            else
              () {
                final d = item.disease!;
                final selected = _diseaseIds.contains(d.id);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Semantics(
                    checked: selected,
                    label: d.name,
                    child: Material(
                      color: selected
                          ? theme.colors.primaryMuted
                          : theme.colors.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(theme.radius.md),
                        side: BorderSide(
                          color: selected
                              ? theme.colors.primary
                              : theme.colors.border,
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(theme.radius.md),
                        onTap: () => _toggleDisease(d),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 64),
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      d.name,
                                      style: TextStyle(
                                        color: theme.colors.text,
                                        fontSize: theme.fontSize.md,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      d.summary,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: theme.colors.textSecondary,
                                        fontSize: theme.fontSize.xs,
                                      ),
                                    ),
                                    if (d.aliases.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        '别名：${d.aliases.join('、')}',
                                        style: TextStyle(
                                          color: theme.colors.textTertiary,
                                          fontSize: theme.fontSize.xs,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              AppIcon(
                                selected
                                    ? AppIconName.check
                                    : AppIconName.chevronRight,
                                size: 20,
                                color: selected
                                    ? theme.colors.primary
                                    : theme.colors.textTertiary,
                                strokeWidth: selected ? 2.5 : 2.0,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }(),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: theme.colors.surfaceMuted,
            borderRadius: BorderRadius.circular(theme.radius.md),
          ),
          padding: EdgeInsets.all(theme.spacing.md),
          child: Text(
            diseaseDisclaimer,
            style: TextStyle(
              color: theme.colors.textTertiary,
              fontSize: theme.fontSize.xs,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMedicationStep(AppThemeData theme) {
    final entries = drugsForDiseases(_diseaseIds);
    return ListView(
      padding: EdgeInsets.fromLTRB(
        theme.spacing.lg,
        4,
        theme.spacing.lg,
        theme.spacing.xl,
      ),
      children: [
        Semantics(
          button: true,
          label: '我的药不在列表里，自定义录入',
          child: Material(
            color: _drugKey == _customKey
                ? theme.colors.primaryMuted
                : theme.colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(theme.radius.md),
              side: BorderSide(
                color: _drugKey == _customKey
                    ? theme.colors.primary
                    : theme.colors.border,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(theme.radius.md),
              onTap: () => setState(() {
                _customOpen = !_customOpen;
                _drugKey = _customKey;
              }),
              child: Container(
                constraints: const BoxConstraints(minHeight: 56),
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '我的药不在列表里',
                            style: TextStyle(
                              color: theme.colors.text,
                              fontSize: theme.fontSize.md,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '手动填写药名、剂型与默认剂量',
                            style: TextStyle(
                              color: theme.colors.textTertiary,
                              fontSize: theme.fontSize.xs,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      _customOpen ? '收起' : '展开',
                      style: TextStyle(
                        color: theme.colors.textTertiary,
                        fontSize: theme.fontSize.md,
                      ),
                    ),
                    const SizedBox(width: 4),
                    AppIcon(
                      _customOpen ? AppIconName.chevronLeft : AppIconName.plus,
                      size: 18,
                      color: theme.colors.textTertiary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_customOpen) ...[
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppTextField(
                  label: Zh.onboarding.medicationName,
                  value: _customName,
                  onChanged: (v) => _customName = v,
                  placeholder: '例如：某单抗',
                  semanticLabel: '自定义药物名称',
                ),
                const SizedBox(height: 12),
                AppTextField(
                  label: '${Zh.onboarding.genericName}（${Zh.common.optional}）',
                  value: _customGeneric,
                  onChanged: (v) => _customGeneric = v,
                  placeholder: '通用名',
                  semanticLabel: '自定义药物通用名',
                ),
                const SizedBox(height: 12),
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
                    SegmentOption(value: MedicationRoute.sc, label: '皮下注射'),
                    SegmentOption(value: MedicationRoute.iv, label: '医院输注'),
                    SegmentOption(value: MedicationRoute.oral, label: '口服'),
                  ],
                  value: _customRoute,
                  onChange: (r) => setState(() => _customRoute = r),
                  semanticLabel: '给药途径',
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: AppTextField(
                        label: Zh.onboarding.defaultDose,
                        value: _customDose,
                        onChanged: (v) => _customDose = v,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        placeholder: '40',
                        semanticLabel: '自定义药物默认剂量',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppTextField(
                        label: Zh.onboarding.unit,
                        value: _customUnit,
                        onChanged: (v) => _customUnit = v,
                        placeholder: 'mg',
                        semanticLabel: '自定义药物剂量单位',
                      ),
                    ),
                  ],
                ),
                if (_customError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _customError!,
                    style: TextStyle(
                      color: theme.colors.danger,
                      fontSize: theme.fontSize.xs,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          '选择后可在下一步调整间隔；实际用法请以医生处方为准。',
          style: TextStyle(
            color: theme.colors.textTertiary,
            fontSize: theme.fontSize.xs,
          ),
        ),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              '该病种暂未收录药物，请用上方的自定义录入。',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.colors.textSecondary,
                fontSize: theme.fontSize.sm,
              ),
            ),
          )
        else
          for (final item in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: () {
                final selected = _drugKey == item.drug.key;
                return Semantics(
                  button: true,
                  selected: selected,
                  label:
                      '${item.drug.name}${item.entry.firstLine ? '，常用' : ''}',
                  child: Material(
                    color: selected
                        ? theme.colors.primaryMuted
                        : theme.colors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(theme.radius.md),
                      side: BorderSide(
                        color: selected
                            ? theme.colors.primary
                            : theme.colors.border,
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(theme.radius.md),
                      onTap: () => setState(() {
                        _drugKey = item.drug.key;
                        _customOpen = false;
                      }),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 64),
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        item.drug.name,
                                        style: TextStyle(
                                          color: theme.colors.text,
                                          fontSize: theme.fontSize.md,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (item.entry.firstLine)
                                        Container(
                                          decoration: BoxDecoration(
                                            color: theme.colors.successMuted,
                                            borderRadius: BorderRadius.circular(
                                              theme.radius.pill,
                                            ),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          child: Text(
                                            '常用',
                                            style: TextStyle(
                                              color: theme.colors.success,
                                              fontSize: theme.fontSize.xs,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      Container(
                                        decoration: BoxDecoration(
                                          color: theme.colors.surfaceMuted,
                                          borderRadius: BorderRadius.circular(
                                            theme.radius.pill,
                                          ),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        child: Text(
                                          item.drug.route == MedicationRoute.iv
                                              ? '医院输注'
                                              : '皮下',
                                          style: TextStyle(
                                            color: theme.colors.textTertiary,
                                            fontSize: theme.fontSize.xs,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '商品名：${item.drug.brandNames.isEmpty ? '—' : item.drug.brandNames.join('、')}',
                                    style: TextStyle(
                                      color: theme.colors.textTertiary,
                                      fontSize: theme.fontSize.xs,
                                    ),
                                  ),
                                  if (item.entry.doseNote != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      item.entry.doseNote!,
                                      style: TextStyle(
                                        color: theme.colors.textSecondary,
                                        fontSize: theme.fontSize.xs,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            AppIcon(
                              selected
                                  ? AppIconName.check
                                  : AppIconName.chevronRight,
                              size: 20,
                              color: selected
                                  ? theme.colors.primary
                                  : theme.colors.textTertiary,
                              strokeWidth: selected ? 2.5 : 2.0,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }(),
            ),
        const SizedBox(height: 12),
        Text(
          '同一通用名下的国产药（生物类似药）药效相同，选任意一个品牌都能用。若你的品牌没列出来，按通用名选即可，或用上方的自定义录入。',
          style: TextStyle(
            color: theme.colors.textTertiary,
            fontSize: theme.fontSize.xs,
          ),
        ),
      ],
    );
  }

  Widget _buildRegimenStep(AppThemeData theme) {
    final hasLoading = _basePhases.any((p) => p.kind == PhaseKind.loading);
    final preview = buildPhasePreview(
      [
        for (final p in _phases)
          PreviewPhase(
            kind: p.kind,
            intervalDays: p.intervalDays,
            repeatCount: p.repeatCount,
            dose: p.doseText.trim().isEmpty
                ? null
                : double.tryParse(p.doseText.trim()),
            unit: p.unit,
          ),
      ],
      max: 5,
    );

    return ListView(
      padding: EdgeInsets.fromLTRB(
        theme.spacing.lg,
        4,
        theme.spacing.lg,
        theme.spacing.xl,
      ),
      children: [
        Container(
          decoration: BoxDecoration(
            color: theme.colors.primaryMuted,
            borderRadius: BorderRadius.circular(theme.radius.md),
          ),
          padding: EdgeInsets.all(theme.spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _selectedDrugName,
                style: TextStyle(
                  color: theme.colors.primary,
                  fontSize: theme.fontSize.sm,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                _routeLabel(_selectedRoute),
                style: TextStyle(
                  color: theme.colors.textSecondary,
                  fontSize: theme.fontSize.xs,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppTextField(
          label: Zh.settings.regimenName,
          value: _treatmentName,
          onChanged: (v) => _treatmentName = v,
          placeholder: '例如：阿达木单抗 每 2 周',
          semanticLabel: '用药方案名称',
        ),
        const SizedBox(height: 12),
        if (_selectedRoute != MedicationRoute.oral) ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchRow(
                  label: '我已经打过至少一针',
                  hint: '录入上次注射时间后，下一次会从这次起算；不填则从今天开始。',
                  value: _hasLastInjection,
                  onChanged: (v) => setState(() => _hasLastInjection = v),
                  last: true,
                ),
                if (_hasLastInjection) ...[
                  const SizedBox(height: 8),
                  DateTimeField(
                    label: '上次注射时间',
                    value: _lastInjectionAt,
                    onChanged: (v) => setState(() => _lastInjectionAt = v),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (hasLoading) ...[
          AppCard(
            padding: false,
            child: SwitchRow(
              label: '只做提醒，不设负荷期',
              hint: '开启后会移除负荷剂量阶段，只保留维持阶段。',
              value: _noLoading,
              onChanged: _toggleNoLoading,
              last: true,
            ),
          ),
          const SizedBox(height: 12),
        ],
        for (var i = 0; i < _phases.length; i += 1) ...[
          () {
            final phase = _phases[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text(
                          '阶段 ${i + 1}',
                          style: TextStyle(
                            color: theme.colors.text,
                            fontSize: theme.fontSize.md,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: phase.kind == PhaseKind.loading
                                ? theme.colors.warningMuted
                                : theme.colors.successMuted,
                            borderRadius:
                                BorderRadius.circular(theme.radius.pill),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          child: Text(
                            _phaseLabel(phase.kind),
                            style: TextStyle(
                              color: phase.kind == PhaseKind.loading
                                  ? theme.colors.warning
                                  : theme.colors.success,
                              fontSize: theme.fontSize.xs,
                            ),
                          ),
                        ),
                      ],
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
                    AppTextField(
                      label: '${Zh.settings.dose}（${Zh.common.optional}）',
                      value: phase.doseText,
                      onChanged: (v) => setState(() => phase.doseText = v),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      placeholder: '留空表示不记录剂量',
                      suffix: phase.unit,
                      semanticLabel: '阶段 ${i + 1} 剂量',
                    ),
                  ],
                ),
              ),
            );
          }(),
        ],
        AppCard(
          tone: AppCardTone.primary,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '方案总览',
                style: TextStyle(
                  color: theme.colors.primary,
                  fontSize: theme.fontSize.sm,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              for (final dose in preview)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${dose.index == 0 ? '第 1 针：首针（${_phaseLabel(dose.kind)}）' : '第 ${dose.index + 1} 针：首针后 ${dose.dayOffset} 天（${_phaseLabel(dose.kind)}）'}${dose.dose != null ? ' · ${_numText(dose.dose!)} ${dose.unit}' : ''}',
                    style: TextStyle(
                      color: theme.colors.textSecondary,
                      fontSize: theme.fontSize.sm,
                    ),
                  ),
                ),
              if (preview.length >= 5)
                Text(
                  '…后续按阶段顺序继续推进',
                  style: TextStyle(
                    color: theme.colors.textTertiary,
                    fontSize: theme.fontSize.xs,
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                '以上仅为根据你填写的参数推算的时间，请以医生处方为准。',
                style: TextStyle(
                  color: theme.colors.textTertiary,
                  fontSize: theme.fontSize.xs,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          diseaseDisclaimer,
          style: TextStyle(
            color: theme.colors.textTertiary,
            fontSize: theme.fontSize.xs,
          ),
        ),
      ],
    );
  }

  Widget _buildReminderStep(AppThemeData theme) {
    const offsetChoices = [
      (-3, '提前 3 天'),
      (-2, '提前 2 天'),
      (-1, '提前 1 天'),
      (0, '当天'),
    ];
    return ListView(
      padding: EdgeInsets.fromLTRB(
        theme.spacing.lg,
        4,
        theme.spacing.lg,
        theme.spacing.xl,
      ),
      children: [
        AppCard(
          child: TimeOfDayField(
            label: Zh.settings.reminderTime,
            value: _timeOfDay,
            onChanged: (v) => setState(() => _timeOfDay = v),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          Zh.settings.reminderOffsets,
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
            for (final (val, label) in offsetChoices)
              AppChip(
                label: label,
                selected: _offsets.contains(val),
                onPressed: () {
                  setState(() {
                    if (_offsets.contains(val)) {
                      _offsets = _offsets.where((o) => o != val).toList();
                    } else {
                      _offsets = [..._offsets, val]..sort();
                    }
                  });
                },
              ),
          ],
        ),
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '免打扰时段',
                style: TextStyle(
                  color: theme.colors.text,
                  fontSize: theme.fontSize.sm,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '这段时间内不会投递通知，会在结束后顺延。',
                style: TextStyle(
                  color: theme.colors.textTertiary,
                  fontSize: theme.fontSize.xs,
                ),
              ),
              const SizedBox(height: 12),
              TimeOfDayField(
                label: '开始',
                value: _dndStart,
                onChanged: (v) => setState(() => _dndStart = v),
              ),
              const SizedBox(height: 12),
              TimeOfDayField(
                label: '结束',
                value: _dndEnd,
                onChanged: (v) => setState(() => _dndEnd = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '通知权限',
                style: TextStyle(
                  color: theme.colors.text,
                  fontSize: theme.fontSize.sm,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              if (_checkingPermission)
                Text(
                  '正在检查通知权限…',
                  style: TextStyle(
                    color: theme.colors.textSecondary,
                    fontSize: theme.fontSize.sm,
                  ),
                )
              else if (_permission?.granted == true) ...[
                Text(
                  '通知权限已开启。',
                  style: TextStyle(
                    color: theme.colors.success,
                    fontSize: theme.fontSize.sm,
                  ),
                ),
                if (_permission?.exactAlarm == false) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Android 可能无法精确到分钟，可在系统设置中允许精确闹钟。',
                    style: TextStyle(
                      color: theme.colors.warning,
                      fontSize: theme.fontSize.xs,
                    ),
                  ),
                ],
              ] else ...[
                Text(
                  '未获得通知权限，到点提醒可能不会出现。',
                  style: TextStyle(
                    color: theme.colors.warning,
                    fontSize: theme.fontSize.sm,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '可在系统设置 → 应用 → BioClock → 通知中手动开启。',
                  style: TextStyle(
                    color: theme.colors.textTertiary,
                    fontSize: theme.fontSize.xs,
                  ),
                ),
              ],
              if (_permissionError != null) ...[
                const SizedBox(height: 4),
                Text(
                  _permissionError!,
                  style: TextStyle(
                    color: theme.colors.danger,
                    fontSize: theme.fontSize.xs,
                  ),
                ),
              ],
              if (Platform.isAndroid) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: _permission?.granted == true ? '重新检查' : '允许通知',
                        onPressed: _requestPermission,
                        variant: AppButtonVariant.secondary,
                        loading: _checkingPermission,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AppButton(
                        label: '打开系统设置',
                        onPressed: () {
                          app_settings.AppSettings.openAppSettings(
                            type: app_settings.AppSettingsType.notification,
                          ).catchError((_) {
                            showToast('无法打开系统设置，请手动前往。', isError: true);
                          });
                        },
                        variant: AppButtonVariant.outline,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (_finishError != null) ...[
          const SizedBox(height: 12),
          InlineError(message: _finishError!),
        ],
        const SizedBox(height: 16),
        Text(
          Zh.disclaimer.short,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: theme.colors.textTertiary,
            fontSize: theme.fontSize.xs,
          ),
        ),
      ],
    );
  }
}

String _numText(double v) =>
    v == v.truncateToDouble() ? v.toInt().toString() : v.toString();

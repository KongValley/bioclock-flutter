import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:app_settings/app_settings.dart' as app_settings;
import 'package:bioclock/data/diseases.dart';
import 'package:bioclock/db/repo.dart';
import 'package:bioclock/domain/date_utils.dart';
import 'package:bioclock/export/export_service.dart';
import 'package:bioclock/i18n/zh.dart';
import 'package:bioclock/import/import_schema.dart';
import 'package:bioclock/import/import_service.dart';
import 'package:bioclock/import/spreadsheet_parser.dart';
import 'package:bioclock/import/transfer_restore.dart';
import 'package:bioclock/models/types.dart';
import 'package:bioclock/notify/notify_scheduler.dart';
import 'package:bioclock/screens/about_sheet.dart';
import 'package:bioclock/screens/settings_sheets.dart';
import 'package:bioclock/store/app_store.dart';
import 'package:bioclock/ui/components/app_icon.dart';
import 'package:bioclock/ui/components/app_layout.dart';
import 'package:bioclock/ui/components/app_lock_gate.dart';
import 'package:bioclock/ui/components/app_primitives.dart';
import 'package:bioclock/ui/components/app_scope.dart';
import 'package:bioclock/ui/components/medication_manager.dart';
import 'package:bioclock/ui/components/symptom_fields.dart';
import 'package:bioclock/ui/components/time_fields.dart';
import 'package:bioclock/ui/theme.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

const List<(int, String)> _offsetChoices = [
  (-3, '提前 3 天'),
  (-2, '提前 2 天'),
  (-1, '提前 1 天'),
  (0, '当天'),
];

const List<(int, String)> _snoozeChoices = [
  (15, '15 分钟'),
  (30, '30 分钟'),
  (60, '60 分钟'),
];

const List<(int, String)> _pdfRangeChoices = [
  (90, '近 90 天'),
  (180, '近 180 天'),
  (365, '近 1 年'),
  (3650, '全部历史'),
];

class SettingsTab extends StatefulWidget {
  const SettingsTab({
    super.key,
    required this.onOpenOnboarding,
  });

  final VoidCallback onOpenOnboarding;

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  String _appVersion = '1.1.2';
  String _buildNumber = '2';
  NotificationPermissionStatus? _permission;
  bool _checkingPermission = false;
  bool _busyExport = false;
  bool _busyImport = false;
  bool _busyLock = false;
  bool _busyClear = false;
  int _clearStage = 0;

  @override
  void initState() {
    super.initState();
    _loadPackageVersion();
    if (Platform.isAndroid) {
      _checkPermission();
    }
  }

  Future<void> _loadPackageVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted && info.version.isNotEmpty) {
        setState(() {
          _appVersion = info.version;
          if (info.buildNumber.isNotEmpty) {
            _buildNumber = info.buildNumber;
          }
        });
      }
    } catch (_) {
      // 测试环境或非原生构建下保留默认版本号
    }
  }

  Future<void> _checkPermission() async {
    if (!Platform.isAndroid) return;
    setState(() => _checkingPermission = true);
    try {
      final status = await NotifyScheduler.ensurePermissions();
      if (mounted) setState(() => _permission = status);
    } catch (_) {
      // 忽略权限检测异常，用户仍可手动打开系统设置
    } finally {
      if (mounted) setState(() => _checkingPermission = false);
    }
  }

  Future<void> _saveReminder({
    required AppStore store,
    required Treatment treatment,
    required ReminderRuleV5 current,
    List<int>? offsets,
    String? timeOfDay,
    int? snoozeMinutes,
    bool? enabled,
  }) async {
    try {
      final result = await store.updateReminder(
        ReminderRuleInput(
          treatmentId: treatment.id,
          offsets: offsets ?? current.offsets,
          timeOfDay: timeOfDay ?? current.timeOfDay,
          snoozeMinutes: snoozeMinutes ?? current.snoozeMinutes,
          enabled: enabled ?? current.enabled,
        ),
      );
      if (result.notifyWarning != null) {
        showToast(result.notifyWarning!, isError: true);
      }
    } catch (err) {
      showToast(friendlyErrorMessage(err), isError: true);
    }
  }

  Future<void> _toggleOffset(
    AppStore store,
    Treatment treatment,
    ReminderRuleV5 reminder,
    int val,
  ) async {
    final next = reminder.offsets.contains(val)
        ? reminder.offsets.where((o) => o != val).toList()
        : ([...reminder.offsets, val]..sort());
    if (next.isEmpty) {
      showToast('至少保留一个提醒时间点', isError: true);
      return;
    }
    await _saveReminder(
      store: store,
      treatment: treatment,
      current: reminder,
      offsets: next,
    );
  }

  Future<void> _updateSettingPatch(
    AppStore store,
    Map<String, String> patch,
  ) async {
    try {
      final result = await store.updateSettings(patch);
      if (result.notifyWarning != null) {
        showToast(result.notifyWarning!, isError: true);
      }
    } catch (err) {
      showToast(friendlyErrorMessage(err), isError: true);
    }
  }

  Future<void> _toggleAppLock(AppStore store, bool enable) async {
    if (_busyLock) return;
    setState(() => _busyLock = true);
    try {
      if (enable) {
        final verified = await authenticateBiometricOrDevice(
          reason: '验证身份以启用 BioClock 应用锁',
          requireEnrolledHardware: true,
        );
        if (!verified) {
          showToast('未完成身份验证，应用锁保持关闭', isError: true);
          return;
        }
        await _updateSettingPatch(store, {'app_lock': '1'});
        showToast('已开启应用锁');
      } else {
        final verified = await authenticateBiometricOrDevice(
          reason: '验证身份以关闭 BioClock 应用锁',
        );
        if (!verified) {
          showToast('验证未通过，应用锁保持开启', isError: true);
          return;
        }
        await _updateSettingPatch(store, {'app_lock': '0'});
        showToast('已关闭应用锁');
      }
    } catch (err) {
      showToast(friendlyErrorMessage(err), isError: true);
    } finally {
      if (mounted) setState(() => _busyLock = false);
    }
  }

  Future<void> _switchActiveTreatment(AppStore store, Treatment target) async {
    final ok = await showConfirmDialog(
      context,
      title: '切换当前方案？',
      message: '将切换为「${target.name}」，今日页与通知提醒会同步更新为该方案的计划。',
      confirmLabel: '确认切换',
    );
    if (!ok) return;
    try {
      final result = await store.setActiveTreatment(target.id, true);
      showToast('已启用「${target.name}」');
      if (result.notifyWarning != null) {
        showToast(result.notifyWarning!, isError: true);
      }
    } catch (err) {
      showToast(friendlyErrorMessage(err), isError: true);
    }
  }

  Future<void> _openChangeIntervalSheet(AppStore store) async {
    final activeLines = (store.treatment?.lines ?? const <TreatmentLine>[])
        .where((l) => l.kind == LineKind.injection && l.endedAt == null)
        .toList();
    if (activeLines.isEmpty) {
      showToast('当前方案中没有未停用的注射线', isError: true);
      return;
    }

    var selectedId = activeLines.first.id;
    var intervalDays = activeLines.first.phases.isNotEmpty
        ? activeLines.first.phases.last.intervalDays
        : 28;
    var saving = false;
    String? error;

    await showAppBottomSheet<void>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final theme = ctx.appTheme;
          return SheetScaffold(
            title: '从下一针起调整间隔',
            heightFactor: 0.62,
            body: ListView(
              padding: EdgeInsets.symmetric(horizontal: theme.spacing.lg),
              children: [
                Text(
                  '已记录的历史针次和当前这一针的基准保持不变，新的周期会在下次注射后开始生效。',
                  style: TextStyle(
                    color: theme.colors.textSecondary,
                    fontSize: theme.fontSize.sm,
                  ),
                ),
                const SizedBox(height: 14),
                if (activeLines.length > 1) ...[
                  Text(
                    '选择注射线',
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
                      for (final line in activeLines)
                        AppChip(
                          label: line.label,
                          selected: line.id == selectedId,
                          onPressed: () {
                            setSheetState(() {
                              selectedId = line.id;
                              if (line.phases.isNotEmpty) {
                                intervalDays = line.phases.last.intervalDays;
                              }
                            });
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
                StepperField(
                  label: '新间隔天数',
                  value: intervalDays,
                  onChanged: (v) => setSheetState(() => intervalDays = v),
                  min: 1,
                  max: 365,
                  suffix: Zh.common.unitDay,
                  decreaseLabel: '间隔减少一天',
                  increaseLabel: '间隔增加一天',
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  InlineError(message: error!),
                ],
              ],
            ),
            footer: AppButton(
              label: Zh.common.save,
              loading: saving,
              onPressed: () async {
                setSheetState(() {
                  saving = true;
                  error = null;
                });
                try {
                  final res =
                      await store.changeInjectionInterval(selectedId, intervalDays);
                  if (!ctx.mounted) return;
                  Navigator.of(ctx).pop();
                  showToast('已从下一针起调整为每 $intervalDays 天一次');
                  if (res.notifyWarning != null) {
                    showToast(res.notifyWarning!, isError: true);
                  }
                } catch (err) {
                  setSheetState(() {
                    saving = false;
                    error = friendlyErrorMessage(err);
                  });
                }
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _openDiseasesSheet(AppStore store) async {
    var selected = Set<String>.from(resolveDiseaseIds(store.settings));
    var saving = false;

    await showAppBottomSheet<void>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final theme = ctx.appTheme;
          return SheetScaffold(
            title: '选择适用病种',
            heightFactor: 0.78,
            body: ListView(
              padding: EdgeInsets.symmetric(horizontal: theme.spacing.lg),
              children: [
                Text(
                  '支持多选合并（例如同时关注克罗恩病与强直性脊柱炎），选药列表会优先展示相关生物制剂。',
                  style: TextStyle(
                    color: theme.colors.textSecondary,
                    fontSize: theme.fontSize.sm,
                  ),
                ),
                const SizedBox(height: 14),
                for (final group in diseaseGroups) ...[
                  Text(
                    group.name,
                    style: TextStyle(
                      color: theme.colors.textTertiary,
                      fontSize: theme.fontSize.xs,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final d in diseasesByGroup(group.id))
                        AppChip(
                          label: d.name,
                          selected: selected.contains(d.id),
                          onPressed: () {
                            setSheetState(() {
                              if (selected.contains(d.id)) {
                                if (selected.length == 1) {
                                  showToast('至少保留一个病种', isError: true);
                                  return;
                                }
                                selected.remove(d.id);
                              } else {
                                selected.add(d.id);
                              }
                            });
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            ),
            footer: AppButton(
              label: Zh.common.save,
              loading: saving,
              onPressed: () async {
                if (selected.isEmpty) {
                  showToast('请至少选择一个病种', isError: true);
                  return;
                }
                setSheetState(() => saving = true);
                final ordered = selected.toList();
                await _updateSettingPatch(store, {
                  'disease_ids': jsonEncode(ordered),
                  'disease_id': ordered.first,
                });
                if (!ctx.mounted) return;
                Navigator.of(ctx).pop();
                showToast('病种设置已更新');
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _openSimpleManagerSheet(String title, Widget child) {
    return showAppBottomSheet<void>(
      context,
      builder: (ctx) {
        final theme = ctx.appTheme;
        return SheetScaffold(
          title: title,
          heightFactor: 0.85,
          body: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              theme.spacing.lg,
              0,
              theme.spacing.lg,
              theme.spacing.xl,
            ),
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _runExport(
    Future<ExportDeliveryResult> Function() job,
  ) async {
    if (_busyExport) return;
    setState(() => _busyExport = true);
    try {
      final delivery = await job();
      if (!delivery.completed) {
        showToast('已取消保存');
        return;
      }
      final where = delivery.savedPath != null && Platform.isWindows
          ? '已保存：${delivery.filename}'
          : '已导出：${delivery.filename}';
      showToast(where);
    } catch (err) {
      showToast(friendlyErrorMessage(err), isError: true);
    } finally {
      if (mounted) setState(() => _busyExport = false);
    }
  }

  Future<void> _openPdfExportSheet() async {
    var patientName = '';
    var rangeDays = 180;
    var exporting = false;

    await showAppBottomSheet<void>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final theme = ctx.appTheme;
          return SheetScaffold(
            title: '导出就诊 PDF 报告',
            heightFactor: 0.62,
            body: ListView(
              padding: EdgeInsets.symmetric(horizontal: theme.spacing.lg),
              children: [
                Text(
                  Zh.disclaimer.exportWarning,
                  style: TextStyle(
                    color: theme.colors.textSecondary,
                    fontSize: theme.fontSize.sm,
                  ),
                ),
                const SizedBox(height: 14),
                AppTextField(
                  label: '姓名或称呼（${Zh.common.optional}）',
                  value: patientName,
                  onChanged: (v) => patientName = v,
                  placeholder: '仅用于报告页眉，不会上传任何数据',
                  semanticLabel: '报告称呼',
                  maxLength: 32,
                ),
                const SizedBox(height: 16),
                Text(
                  '统计范围',
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
                    for (final (days, label) in _pdfRangeChoices)
                      AppChip(
                        label: label,
                        selected: rangeDays == days,
                        onPressed: () => setSheetState(() => rangeDays = days),
                      ),
                  ],
                ),
              ],
            ),
            footer: AppButton(
              label: '生成 PDF',
              loading: exporting,
              onPressed: () async {
                setSheetState(() => exporting = true);
                try {
                  final trimmedName = patientName.trim();
                  final file = await exportPdf(
                    patientName: trimmedName.isEmpty ? null : trimmedName,
                    rangeDays: rangeDays,
                  );
                  final delivery = await shareOrSaveExportFile(
                    file,
                    mimeType: 'application/pdf',
                    dialogTitle: '保存就诊报告 PDF',
                  );
                  if (!ctx.mounted) return;
                  Navigator.of(ctx).pop();
                  showToast(
                    delivery.completed ? 'PDF 报告已导出' : '已取消保存 PDF',
                  );
                } catch (err) {
                  setSheetState(() => exporting = false);
                  showToast(friendlyErrorMessage(err), isError: true);
                }
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _handleImport(AppStore store) async {
    if (_busyImport) return;
    setState(() => _busyImport = true);
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['json', 'xlsx', 'xls'],
      );
      if (picked == null) return;

      final Uint8List bytes = await picked.readAsBytes();
      final lowerName = picked.name.toLowerCase();

      if (lowerName.endsWith('.json')) {
        final text = utf8.decode(bytes);
        if (isTransferFile(text)) {
          final summary = summarizeTransfer(text);
          if (!mounted) return;
          final ok = await showConfirmDialog(
            context,
            title: '确认换机恢复？',
            message: '检测到换机完整备份（v${summary.schemaVersion}），包含 ${summary.doses} 条打卡、${summary.symptoms} 条症状、${summary.efficacyEvents} 条疗效事件。\n\n恢复后将重建对应的激活方案和设置，是否继续？',
            confirmLabel: '开始恢复',
          );
          if (!ok) return;
          final outcome = await restoreTransferBackup(store, text);
          final r = outcome.result;
          showToast(
            '换机恢复完成：导入 ${r.injections + r.oralLogs} 条打卡、${r.symptoms} 条症状，跳过 ${r.skipped} 条重复记录',
          );
          if (outcome.notifyWarning != null) {
            showToast(outcome.notifyWarning!, isError: true);
          }
          return;
        }
      }

      final ImportPayload payload = lowerName.endsWith('.json')
          ? parseImportJson(utf8.decode(bytes))
          : parseSpreadsheet(bytes);
      final preview = await previewImport(payload);
      if (!mounted) return;

      final parts = <String>[
        '预计写入 ${preview.injections} 条注射、${preview.oralLogs} 条口服、${preview.symptoms} 条症状',
        if (preview.efficacyEvents > 0) '${preview.efficacyEvents} 条疗效事件',
        if (preview.linesCreated > 0) '将自动新建 ${preview.linesCreated} 条用药线',
        if (preview.medicationsCreated > 0)
          '将自动补充 ${preview.medicationsCreated} 种药物',
        if (preview.skipped > 0) '将跳过 ${preview.skipped} 条重复记录',
        if (preview.skippedNoLine > 0)
          '另有 ${preview.skippedNoLine} 条未匹配到用药线',
      ];
      final confirm = await showConfirmDialog(
        context,
        title: '确认导入「${picked.name}」？',
        message: parts.join('；'),
        confirmLabel: '确认导入',
      );
      if (!confirm) return;

      final outcome = await store.importRecords(payload);
      final res = outcome.result;
      showToast(
        '导入成功：注射 ${res.injections} 条、口服 ${res.oralLogs} 条、症状 ${res.symptoms} 条，跳过 ${res.skipped} 条',
      );
      if (outcome.notifyWarning != null) {
        showToast(outcome.notifyWarning!, isError: true);
      }
    } catch (err) {
      showToast(friendlyErrorMessage(err), isError: true);
    } finally {
      if (mounted) setState(() => _busyImport = false);
    }
  }

  Future<void> _confirmAndReset(AppStore store) async {
    if (_busyClear) return;
    final ok = await showConfirmDialog(
      context,
      title: '确定清空所有记录吗？',
      message: '将删除全部治疗方案、打卡记录、症状记录、疗效事件与个人设置，仅保留内置药物目录。清空前建议先导出一份换机备份。',
      confirmLabel: '全部清空',
      destructive: true,
    );
    if (!ok) {
      setState(() => _clearStage = 0);
      return;
    }
    setState(() => _busyClear = true);
    try {
      final res = await store.resetAllData();
      if (!mounted) return;
      setState(() => _clearStage = 0);
      showToast('所有个人数据已清空');
      if (res.notifyWarning != null) {
        showToast(res.notifyWarning!, isError: true);
      }
    } catch (err) {
      showToast(friendlyErrorMessage(err), isError: true);
    } finally {
      if (mounted) setState(() => _busyClear = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final store = context.store;
    final active = store.treatment;
    final reminder = store.reminder;
    final themeMode = AppThemeMode.parse(store.settings['theme_mode']);
    final dndStart = store.settings['dnd_start'] ?? defaultDndStart;
    final dndEnd = store.settings['dnd_end'] ?? defaultDndEnd;
    final appLockEnabled = store.settings['app_lock'] == '1';
    final acceptedRaw =
        int.tryParse(store.settings['disclaimer_accepted_at'] ?? '');
    final diseaseSummary = store.diseases.isEmpty
        ? '未选'
        : store.diseases.map((d) => d.name).join('、');

    return Column(
      children: [
        ScreenHeader(
          title: Zh.settings.title,
          subtitle: diseaseSummary == '未选' ? null : diseaseSummary,
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.only(bottom: theme.spacing.xxl),
            children: [
              ResponsiveContainer(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: theme.spacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SectionTitle(
                        title: '治疗方案',
                        hint: '可同时维护多套方案，任意时刻启用其中一套',
                      ),
                      const SizedBox(height: 10),
                      if (store.treatments.isEmpty)
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                '还没有建立治疗方案。',
                                style: TextStyle(
                                  color: theme.colors.textSecondary,
                                  fontSize: theme.fontSize.sm,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: AppButton(
                                      label: '新建方案',
                                      icon: AppIconName.plus,
                                      onPressed: () => showTreatmentEditorSheet(
                                        context,
                                        treatment: null,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: AppButton(
                                      label: '初始化向导',
                                      variant: AppButtonVariant.secondary,
                                      onPressed: widget.onOpenOnboarding,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        )
                      else ...[
                        for (final t in store.treatments)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: AppCard(
                              tone: t.isActive
                                  ? AppCardTone.primary
                                  : AppCardTone.defaultTone,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          t.name,
                                          style: TextStyle(
                                            color: theme.colors.text,
                                            fontSize: theme.fontSize.md,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      if (t.isActive)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: theme.colors.primary,
                                            borderRadius: BorderRadius.circular(
                                                theme.radius.pill),
                                          ),
                                          child: Text(
                                            '当前启用',
                                            style: TextStyle(
                                              color: theme.colors.onPrimary,
                                              fontSize: theme.fontSize.xs,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        )
                                      else
                                        AppButton(
                                          label: '启用',
                                          variant: AppButtonVariant.secondary,
                                          fullWidth: false,
                                          onPressed: () =>
                                              _switchActiveTreatment(store, t),
                                        ),
                                      const SizedBox(width: 6),
                                      Semantics(
                                        button: true,
                                        label: '编辑 ${t.name}',
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(
                                              theme.radius.pill),
                                          onTap: () => showTreatmentEditorSheet(
                                            context,
                                            treatment: t,
                                          ),
                                          child: SizedBox(
                                            width: 44,
                                            height: 44,
                                            child: Center(
                                              child: AppIcon(
                                                AppIconName.pencil,
                                                size: 18,
                                                color:
                                                    theme.colors.textSecondary,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  for (final line in t.lines)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 3),
                                      child: Text(
                                        describeLine(line, store.medications),
                                        style: TextStyle(
                                          color: theme.colors.textSecondary,
                                          fontSize: theme.fontSize.sm,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        AppButton(
                          label: '新建治疗方案',
                          icon: AppIconName.plus,
                          variant: AppButtonVariant.outline,
                          onPressed: () =>
                              showTreatmentEditorSheet(context, treatment: null),
                        ),
                      ],
                      const SizedBox(height: 12),
                      AppCard(
                        padding: false,
                        child: Column(
                          children: [
                            SettingRow(
                              label: '从下一针起调整间隔',
                              hint: '仅改未来周期，不影响过往记录',
                              onTap: active == null
                                  ? null
                                  : () => _openChangeIntervalSheet(store),
                            ),
                            SettingRow(
                              label: '疗效事件与停药管理',
                              hint: '记录疗效变化、暂停或恢复某条用药线',
                              value: '${store.efficacyEvents.length} 条',
                              onTap: active == null
                                  ? null
                                  : () => showEfficacyManagerSheet(context),
                            ),
                            SettingRow(
                              label: '适用病种',
                              value: diseaseSummary,
                              onTap: () => _openDiseasesSheet(store),
                            ),
                            SettingRow(
                              label: '药物管理',
                              hint: '调整内置药默认剂量，或增删自定义药物',
                              value: '${store.medications.length} 种',
                              last: true,
                              onTap: () => _openSimpleManagerSheet(
                                '药物管理',
                                const MedicationManager(),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      const SectionTitle(
                        title: '提醒设置',
                        hint: '纯本地排程通知，不会连接任何远程推送服务',
                      ),
                      const SizedBox(height: 10),
                      if (active == null || reminder == null)
                        AppCard(
                          child: Text(
                            '请先启用一个治疗方案后再配置提醒。',
                            style: TextStyle(
                              color: theme.colors.textSecondary,
                              fontSize: theme.fontSize.sm,
                            ),
                          ),
                        )
                      else
                        AppCard(
                          padding: false,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SwitchRow(
                                label: Zh.settings.reminderEnabled,
                                hint: '按当前方案在设备本地定时提醒',
                                value: reminder.enabled,
                                onChanged: (v) => _saveReminder(
                                  store: store,
                                  treatment: active,
                                  current: reminder,
                                  enabled: v,
                                ),
                                last: !reminder.enabled,
                              ),
                              if (reminder.enabled) ...[
                                Padding(
                                  padding: EdgeInsets.all(theme.spacing.lg),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      TimeOfDayField(
                                        label: Zh.settings.reminderTime,
                                        value: reminder.timeOfDay,
                                        onChanged: (v) => _saveReminder(
                                          store: store,
                                          treatment: active,
                                          current: reminder,
                                          timeOfDay: v,
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                      Text(
                                        Zh.settings.reminderOffsets,
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
                                          for (final (val, label)
                                              in _offsetChoices)
                                            AppChip(
                                              label: label,
                                              selected: reminder.offsets
                                                  .contains(val),
                                              onPressed: () => _toggleOffset(
                                                store,
                                                active,
                                                reminder,
                                                val,
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 14),
                                      Text(
                                        Zh.settings.snoozeMinutes,
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
                                          for (final (mins, label)
                                              in _snoozeChoices)
                                            AppChip(
                                              label: label,
                                              selected:
                                                  reminder.snoozeMinutes == mins,
                                              onPressed: () => _saveReminder(
                                                store: store,
                                                treatment: active,
                                                current: reminder,
                                                snoozeMinutes: mins,
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 14),
                                      Text(
                                        '免打扰时段（结束后自动顺延）',
                                        style: TextStyle(
                                          color: theme.colors.textSecondary,
                                          fontSize: theme.fontSize.sm,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: TimeOfDayField(
                                              label: '开始',
                                              value: dndStart,
                                              onChanged: (v) =>
                                                  _updateSettingPatch(
                                                store,
                                                {'dnd_start': v},
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: TimeOfDayField(
                                              label: '结束',
                                              value: dndEnd,
                                              onChanged: (v) =>
                                                  _updateSettingPatch(
                                                store,
                                                {'dnd_end': v},
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Divider(
                                  height: 1,
                                  color: theme.colors.border,
                                ),
                                Padding(
                                  padding: EdgeInsets.all(theme.spacing.lg),
                                  child: Platform.isAndroid
                                      ? Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            Text(
                                              _checkingPermission
                                                  ? '正在检查通知权限…'
                                                  : (_permission?.granted == true
                                                      ? (_permission!
                                                              .exactAlarm
                                                          ? '通知权限与精确闹钟已就绪'
                                                          : '通知权限已开启，但精确闹钟未授权，可能略有延迟')
                                                      : '通知权限未开启，请先授权后再依赖定时提醒'),
                                              style: TextStyle(
                                                color:
                                                    _permission?.granted == true
                                                        ? theme.colors.textSecondary
                                                        : theme.colors.danger,
                                                fontSize: theme.fontSize.sm,
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: AppButton(
                                                    label: '检查权限',
                                                    variant: AppButtonVariant
                                                        .secondary,
                                                    loading:
                                                        _checkingPermission,
                                                    onPressed: _checkPermission,
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: AppButton(
                                                    label: '打开系统设置',
                                                    variant:
                                                        AppButtonVariant.outline,
                                                    onPressed: () {
                                                      app_settings.AppSettings
                                                          .openAppSettings(
                                                        type: app_settings
                                                            .AppSettingsType
                                                            .notification,
                                                      ).catchError((_) {
                                                        showToast(
                                                          '无法打开系统设置，请手动前往',
                                                          isError: true,
                                                        );
                                                      });
                                                    },
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        )
                                      : Text(
                                          'Windows 桌面通知使用本地定时排程；系统睡眠时通知会在唤醒后触发。',
                                          style: TextStyle(
                                            color: theme.colors.textTertiary,
                                            fontSize: theme.fontSize.xs,
                                          ),
                                        ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      const SizedBox(height: 24),
                      const SectionTitle(title: '外观与偏好'),
                      const SizedBox(height: 10),
                      AppCard(
                        padding: false,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: EdgeInsets.all(theme.spacing.lg),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    '主题模式',
                                    style: TextStyle(
                                      color: theme.colors.text,
                                      fontSize: theme.fontSize.md,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  SegmentedControl<AppThemeMode>(
                                    options: const [
                                      SegmentOption(
                                        value: AppThemeMode.system,
                                        label: '跟随系统',
                                      ),
                                      SegmentOption(
                                        value: AppThemeMode.light,
                                        label: '浅色',
                                      ),
                                      SegmentOption(
                                        value: AppThemeMode.dark,
                                        label: '深色',
                                      ),
                                    ],
                                    value: themeMode,
                                    semanticLabel: '主题模式切换',
                                    onChange: (mode) => _updateSettingPatch(
                                      store,
                                      {'theme_mode': mode.wire},
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Divider(height: 1, color: theme.colors.border),
                            SwitchRow(
                              label: '应用锁（生物识别 / 系统凭据）',
                              hint: '冷启动或切回后台超过 30 秒时要求验证',
                              value: appLockEnabled,
                              disabled: _busyLock,
                              onChanged: (v) => _toggleAppLock(store, v),
                            ),
                            SettingRow(
                              label: '症状标签管理',
                              value: '${store.symptomTags.length} 个',
                              onTap: () => _openSimpleManagerSheet(
                                '症状标签管理',
                                const SymptomTagManager(),
                              ),
                            ),
                            SettingRow(
                              label: '重新打开初始化向导',
                              hint: '按四步流程重新配置方案和提醒',
                              last: true,
                              onTap: widget.onOpenOnboarding,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      SectionTitle(
                        title: '导出与导入',
                        hint: Zh.disclaimer.exportWarning,
                      ),
                      const SizedBox(height: 10),
                      AppCard(
                        padding: false,
                        child: Column(
                          children: [
                            SettingRow(
                              label: '生成就诊 PDF 报告',
                              hint: 'A4 排版，含依从性与症状趋势摘要',
                              onTap: _busyExport ? null : _openPdfExportSheet,
                            ),
                            SettingRow(
                              label: '导出 Excel (.xlsx)',
                              hint: '5 张工作表，含只读「用药线」概览',
                              onTap: _busyExport
                                  ? null
                                  : () => _runExport(() async {
                                        final file = await exportExcel();
                                        return shareOrSaveExportFile(
                                          file,
                                          mimeType:
                                              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                                          dialogTitle: '保存 Excel 导出文件',
                                        );
                                      }),
                            ),
                            SettingRow(
                              label: '导出 CSV (.csv)',
                              hint: '注射记录表格（UTF-8 BOM）',
                              onTap: _busyExport
                                  ? null
                                  : () => _runExport(() async {
                                        final file = await exportCsv();
                                        return shareOrSaveExportFile(
                                          file,
                                          mimeType: 'text/csv',
                                          dialogTitle: '保存 CSV 导出文件',
                                        );
                                      }),
                            ),
                            SettingRow(
                              label: '导出 JSON (v3)',
                              hint: '结构化记录，可再次导入恢复',
                              onTap: _busyExport
                                  ? null
                                  : () => _runExport(() async {
                                        final file = await exportJson();
                                        return shareOrSaveExportFile(
                                          file,
                                          mimeType: 'application/json',
                                          dialogTitle: '保存 JSON 导出文件',
                                        );
                                      }),
                            ),
                            SettingRow(
                              label: '换机导出（完整备份）',
                              hint: '含治疗方案、阶段时间、设置与提醒规则',
                              onTap: _busyExport
                                  ? null
                                  : () => _runExport(() async {
                                        final transfer =
                                            await exportTransferFile();
                                        return shareOrSaveTransferFile(transfer);
                                      }),
                            ),
                            SettingRow(
                              label: _busyImport ? '正在解析文件…' : '导入数据 / 换机恢复',
                              hint: '支持 .xlsx / .xls / .json（兼容 v1–v3 与换机包）',
                              last: true,
                              onTap: _busyImport
                                  ? null
                                  : () => _handleImport(store),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      const SectionTitle(
                        title: '危险区域',
                        hint: '清库前请先做好备份',
                      ),
                      const SizedBox(height: 10),
                      AppCard(
                        tone: _clearStage > 0
                            ? AppCardTone.danger
                            : AppCardTone.defaultTone,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_clearStage == 0)
                              AppButton(
                                label: '清空所有个人数据',
                                variant: AppButtonVariant.danger,
                                onPressed: () =>
                                    setState(() => _clearStage = 1),
                              )
                            else ...[
                              Text(
                                '二次确认：将删除所有个人记录，仅保留内置药物库。此操作不可撤销。',
                                style: TextStyle(
                                  color: theme.colors.danger,
                                  fontSize: theme.fontSize.sm,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: AppButton(
                                      label: Zh.common.cancel,
                                      variant: AppButtonVariant.secondary,
                                      onPressed: _busyClear
                                          ? null
                                          : () =>
                                              setState(() => _clearStage = 0),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: AppButton(
                                      label: '确认清空',
                                      variant: AppButtonVariant.danger,
                                      loading: _busyClear,
                                      onPressed: () => _confirmAndReset(store),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      SectionTitle(title: Zh.settings.aboutSection),
                      const SizedBox(height: 10),
                      AppCard(
                        padding: false,
                        child: Column(
                          children: [
                            SettingRow(
                              label: '关于 BioClock',
                              hint: '作者 宁波猪猪侠 · 功能介绍、本机数据与开源许可',
                              value: 'v$_appVersion',
                              onTap: () => showAboutBioClockSheet(
                                context,
                                appVersion: _appVersion,
                                buildNumber: _buildNumber,
                              ),
                            ),
                            SettingRow(
                              label: '免责声明与隐私说明',
                              hint: acceptedRaw != null
                                  ? '${Zh.disclaimer.acceptedAt}：${formatDateTime(acceptedRaw)}'
                                  : Zh.disclaimer.short,
                              last: true,
                              onTap: () => showDisclaimerSheet(
                                context,
                                acceptedAt: acceptedRaw,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

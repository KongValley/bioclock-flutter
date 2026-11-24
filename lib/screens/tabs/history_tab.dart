import 'package:bioclock/domain/date_utils.dart';
import 'package:bioclock/domain/rotation.dart';
import 'package:bioclock/i18n/zh.dart';
import 'package:bioclock/models/types.dart';
import 'package:bioclock/screens/modals/injection_modal.dart';
import 'package:bioclock/screens/modals/oral_modal.dart';
import 'package:bioclock/screens/modals/symptom_modal.dart';
import 'package:bioclock/store/app_store.dart';
import 'package:bioclock/ui/components/app_icon.dart';
import 'package:bioclock/ui/components/app_layout.dart';
import 'package:bioclock/ui/components/app_scope.dart';
import 'package:bioclock/ui/theme.dart';
import 'package:flutter/material.dart';

enum _HistoryTabKey { injection, oral, symptom }

sealed class _HistoryRow {}

class _HeaderRow extends _HistoryRow {
  _HeaderRow(this.title);
  final String title;
}

class _DoseRow extends _HistoryRow {
  _DoseRow(this.log, this.kind);
  final DoseLog log;
  final LineKind kind;
}

class _SymptomRow extends _HistoryRow {
  _SymptomRow(this.symptom);
  final SymptomLog symptom;
}

int _logTime(DoseLog log) => log.takenAt ?? log.scheduledAt ?? log.createdAt;

String _doseStatusText(DoseStatus status) => switch (status) {
      DoseStatus.done => '完成',
      DoseStatus.skipped => '跳过',
      DoseStatus.missed => '漏服',
    };

Color _severityColor(AppThemeData theme, int severity) {
  if (severity <= 1) return theme.colors.success;
  if (severity == 2) return theme.colors.primary;
  if (severity == 3) return theme.colors.warning;
  return theme.colors.danger;
}

class HistoryTab extends StatefulWidget {
  const HistoryTab({super.key});

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  _HistoryTabKey _tab = _HistoryTabKey.injection;

  Future<void> _refresh() async {
    try {
      await context.store.reload();
    } catch (err) {
      if (mounted) showToast(friendlyErrorMessage(err), isError: true);
    }
  }

  void _openNew(_HistoryTabKey target) {
    switch (target) {
      case _HistoryTabKey.injection:
        showInjectionModal(context);
      case _HistoryTabKey.oral:
        showOralModal(context);
      case _HistoryTabKey.symptom:
        showSymptomModal(context);
    }
  }

  Future<void> _showDoseMenu(
    DoseLog log,
    LineKind kind,
    String medName,
  ) async {
    await showActionSheet(
      context,
      title: '${formatDate(_logTime(log))} · $medName',
      actions: [
        SheetActionItem(
          label: Zh.common.edit,
          onTap: () {
            if (kind == LineKind.injection) {
              showInjectionModal(context, editingId: log.id);
            } else {
              showOralModal(context, editingId: log.id);
            }
          },
        ),
        SheetActionItem(
          label: Zh.common.delete,
          destructive: true,
          onTap: () => _confirmDeleteDose(log.id, kind),
        ),
      ],
    );
  }

  Future<void> _confirmDeleteDose(String id, LineKind kind) async {
    final confirmed = await showConfirmDialog(
      context,
      title: kind == LineKind.injection
          ? Zh.history.deleteInjectionTitle
          : '删除这条口服打卡？',
      message: kind == LineKind.injection
          ? Zh.history.deleteInjectionMessage
          : '删除后该次打卡会从时间线里移除，此操作不可恢复。',
      confirmLabel: Zh.common.delete,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      final res = await context.store.removeDoseLog(id);
      if (!mounted) return;
      showToast('已删除');
      if (res.notifyWarning != null) {
        showToast(res.notifyWarning!, isError: true);
      }
    } catch (err) {
      if (mounted) showToast(friendlyErrorMessage(err), isError: true);
    }
  }

  Future<void> _showSymptomMenu(SymptomLog symptom) async {
    await showActionSheet(
      context,
      title:
          '${formatDate(symptom.loggedAt)} ${formatTime(symptom.loggedAt)} · 严重度 ${symptom.severity}',
      actions: [
        SheetActionItem(
          label: Zh.common.edit,
          onTap: () => showSymptomModal(context, editingId: symptom.id),
        ),
        SheetActionItem(
          label: Zh.common.delete,
          destructive: true,
          onTap: () => _confirmDeleteSymptom(symptom.id),
        ),
      ],
    );
  }

  Future<void> _confirmDeleteSymptom(String id) async {
    final confirmed = await showConfirmDialog(
      context,
      title: Zh.history.deleteSymptomTitle,
      message: Zh.history.deleteSymptomMessage,
      confirmLabel: Zh.common.delete,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      final res = await context.store.removeSymptom(id);
      if (!mounted) return;
      showToast('已删除');
      if (res.notifyWarning != null) {
        showToast(res.notifyWarning!, isError: true);
      }
    } catch (err) {
      if (mounted) showToast(friendlyErrorMessage(err), isError: true);
    }
  }

  List<_HistoryRow> _buildDoseRows(
    LineKind kind,
    List<DoseLog> doseLogs,
    Map<String, TreatmentLine> lineById,
  ) {
    final sorted = doseLogs
        .where((l) => lineById[l.lineId]?.kind == kind)
        .toList()
      ..sort((a, b) => _logTime(b).compareTo(_logTime(a)));
    final rows = <_HistoryRow>[];
    var lastMonth = '';
    for (final log in sorted) {
      final at = _logTime(log);
      final mk = monthKey(at);
      if (mk != lastMonth) {
        lastMonth = mk;
        rows.add(_HeaderRow(formatMonth(at)));
      }
      rows.add(_DoseRow(log, kind));
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final store = context.store;
    if (!store.ready) return const LoadingView();

    final medNames = {for (final m in store.medications) m.id: m.name};
    final medRoutes = {for (final m in store.medications) m.id: m.route};
    final lineById = <String, TreatmentLine>{
      for (final t in store.treatments)
        for (final l in t.lines) l.id: l,
    };
    final doseLogById = {for (final l in store.doseLogs) l.id: l};

    String nameOfLine(String lineId) {
      final line = lineById[lineId];
      if (line == null) return Zh.common.unknown;
      return medNames[line.medicationId] ?? line.label;
    }

    final injRows = _buildDoseRows(LineKind.injection, store.doseLogs, lineById);
    final oralRows = _buildDoseRows(LineKind.oral, store.doseLogs, lineById);
    final symptomRows = [
      for (final s in [...store.symptoms]
        ..sort((a, b) => b.loggedAt.compareTo(a.loggedAt)))
        _SymptomRow(s),
    ];

    final rows = switch (_tab) {
      _HistoryTabKey.injection => injRows,
      _HistoryTabKey.oral => oralRows,
      _HistoryTabKey.symptom => symptomRows,
    };

    final subtitle = switch (_tab) {
      _HistoryTabKey.injection =>
        '共 ${injRows.whereType<_DoseRow>().length} 条注射记录',
      _HistoryTabKey.oral =>
        '共 ${oralRows.whereType<_DoseRow>().length} 条口服打卡',
      _HistoryTabKey.symptom => '共 ${store.symptoms.length} 条症状记录',
    };

    final (emptyIcon, emptyTitle, emptyMsg, emptyAction) = switch (_tab) {
      _HistoryTabKey.injection => (
          AppIconName.syringe,
          Zh.empty.historyNoInjection,
          '登记后，这里会按月展示你的注射时间线。',
          Zh.history.addInjection,
        ),
      _HistoryTabKey.oral => (
          AppIconName.smile,
          '暂无口服打卡',
          '在「今天」或这里记录口服用药的完成情况。',
          '新增口服打卡',
        ),
      _HistoryTabKey.symptom => (
          AppIconName.smile,
          Zh.empty.historyNoSymptom,
          '记录注射后出现的症状，方便复诊时回顾。',
          Zh.history.addSymptom,
        ),
    };

    final severityLabels = [
      Zh.form.severity1,
      Zh.form.severity2,
      Zh.form.severity3,
      Zh.form.severity4,
      Zh.form.severity5,
    ];

    return Scaffold(
      backgroundColor: theme.colors.background,
      floatingActionButton: Semantics(
        button: true,
        label: switch (_tab) {
          _HistoryTabKey.injection => '新增注射记录',
          _HistoryTabKey.oral => '新增口服打卡',
          _HistoryTabKey.symptom => '新增症状记录',
        },
        child: FloatingActionButton.extended(
          onPressed: () => _openNew(_tab),
          backgroundColor: theme.colors.primary,
          foregroundColor: theme.colors.onPrimary,
          icon: AppIcon(
            AppIconName.plus,
            size: 18,
            color: theme.colors.onPrimary,
            strokeWidth: 2.5,
          ),
          label: Text(
            emptyAction,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(title: Zh.history.title, subtitle: subtitle),
            ResponsiveContainer(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  theme.spacing.lg,
                  0,
                  theme.spacing.lg,
                  theme.spacing.sm,
                ),
                child: SegmentedControl<_HistoryTabKey>(
                  options: [
                    SegmentOption(
                      value: _HistoryTabKey.injection,
                      label: Zh.history.injectionTab,
                    ),
                    SegmentOption(
                      value: _HistoryTabKey.oral,
                      label: Zh.history.oralTab,
                    ),
                    SegmentOption(
                      value: _HistoryTabKey.symptom,
                      label: Zh.history.symptomTab,
                    ),
                  ],
                  value: _tab,
                  onChange: (next) => setState(() => _tab = next),
                  semanticLabel: '记录类型',
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: theme.colors.primary,
                onRefresh: _refresh,
                child: rows.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.only(bottom: 120),
                        children: [
                          ResponsiveContainer(
                            child: StateView(
                              icon: emptyIcon,
                              title: emptyTitle,
                              message: emptyMsg,
                              actionLabel: emptyAction,
                              onAction: () => _openNew(_tab),
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: EdgeInsets.fromLTRB(
                          theme.spacing.lg,
                          theme.spacing.xs,
                          theme.spacing.lg,
                          120,
                        ),
                        itemCount: rows.length,
                        itemBuilder: (context, index) {
                          final row = rows[index];
                          return ResponsiveContainer(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: switch (row) {
                                _HeaderRow() => Padding(
                                    padding: const EdgeInsets.only(
                                      top: 8,
                                      bottom: 2,
                                    ),
                                    child: Semantics(
                                      header: true,
                                      child: Text(
                                        row.title,
                                        style: TextStyle(
                                          color: theme.colors.textSecondary,
                                          fontSize: theme.fontSize.sm,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                _DoseRow() => _buildDoseCard(
                                    theme,
                                    row.log,
                                    row.kind,
                                    nameOfLine(row.log.lineId),
                                    medRoutes[lineById[row.log.lineId]
                                        ?.medicationId],
                                  ),
                                _SymptomRow() => _buildSymptomCard(
                                    theme,
                                    row.symptom,
                                    severityLabels,
                                    doseLogById,
                                    nameOfLine,
                                  ),
                              },
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDoseCard(
    AppThemeData theme,
    DoseLog log,
    LineKind kind,
    String medName,
    MedicationRoute? route,
  ) {
    final at = _logTime(log);
    final dt = DateTime.fromMillisecondsSinceEpoch(at);
    final doseText = log.dose != null
        ? '${log.dose! == log.dose!.truncateToDouble() ? log.dose!.toInt() : log.dose!} ${log.unit}'
            .trim()
        : '剂量未记录';
    final summary = kind == LineKind.injection ? '$medName · $doseText' : medName;

    final detailParts = <String>[
      if (kind == LineKind.injection) ...[
        if (log.site != null)
          siteLabels[log.site!] ?? ''
        else if (route == MedicationRoute.iv)
          '医院输注',
        if (log.lotNumber != null && log.lotNumber!.isNotEmpty)
          '批号 ${log.lotNumber}',
      ] else
        '${_doseStatusText(log.status)} · $doseText',
    ];
    final detail =
        detailParts.isEmpty && kind == LineKind.injection ? '注射' : detailParts.join(' · ');

    return Container(
      decoration: BoxDecoration(
        color: theme.colors.surface,
        borderRadius: BorderRadius.circular(theme.radius.md),
        border: Border.all(color: theme.colors.border, width: 0.6),
      ),
      padding: EdgeInsets.all(theme.spacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 58,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${dt.day} 日',
                  style: TextStyle(
                    color: theme.colors.text,
                    fontSize: theme.fontSize.lg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${formatWeekday(at)} ${formatTime(at)}',
                  style: TextStyle(
                    color: theme.colors.textTertiary,
                    fontSize: theme.fontSize.xs,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Semantics(
              button: true,
              label: '$summary，操作菜单',
              child: InkWell(
                onTap: () => _showDoseMenu(log, kind, medName),
                onLongPress: () => _showDoseMenu(log, kind, medName),
                borderRadius: BorderRadius.circular(theme.radius.sm),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        summary,
                        style: TextStyle(
                          color: theme.colors.text,
                          fontSize: theme.fontSize.md,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        style: TextStyle(
                          color: theme.colors.textSecondary,
                          fontSize: theme.fontSize.sm,
                        ),
                      ),
                      if (log.note != null && log.note!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          log.note!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.colors.textTertiary,
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
          Semantics(
            button: true,
            label: '用药记录操作',
            child: InkWell(
              onTap: () => _showDoseMenu(log, kind, medName),
              borderRadius: BorderRadius.circular(theme.radius.sm),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: AppIcon(
                    AppIconName.more,
                    size: 20,
                    color: theme.colors.textTertiary,
                    strokeWidth: 2.5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSymptomCard(
    AppThemeData theme,
    SymptomLog symptom,
    List<String> severityLabels,
    Map<String, DoseLog> doseLogById,
    String Function(String) nameOfLine,
  ) {
    final color = _severityColor(theme, symptom.severity);
    final related =
        symptom.injectionId != null ? doseLogById[symptom.injectionId!] : null;

    return Container(
      decoration: BoxDecoration(
        color: theme.colors.surface,
        borderRadius: BorderRadius.circular(theme.radius.md),
        border: Border.all(color: theme.colors.border, width: 0.6),
      ),
      padding: EdgeInsets.all(theme.spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: symptom.severity == 5
                      ? Border.all(color: theme.colors.text, width: 2)
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                severityLabels[(symptom.severity - 1).clamp(0, 4)],
                style: TextStyle(
                  color: theme.colors.text,
                  fontSize: theme.fontSize.md,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${formatRelativeDay(symptom.loggedAt)} ${formatTime(symptom.loggedAt)}',
                style: TextStyle(
                  color: theme.colors.textTertiary,
                  fontSize: theme.fontSize.xs,
                ),
              ),
              Semantics(
                button: true,
                label: '症状记录操作',
                child: InkWell(
                  onTap: () => _showSymptomMenu(symptom),
                  borderRadius: BorderRadius.circular(theme.radius.sm),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: AppIcon(
                        AppIconName.more,
                        size: 20,
                        color: theme.colors.textTertiary,
                        strokeWidth: 2.5,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (symptom.tags.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in symptom.tags)
                  Container(
                    decoration: BoxDecoration(
                      color: theme.colors.surfaceMuted,
                      borderRadius: BorderRadius.circular(theme.radius.pill),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    child: Text(
                      tag,
                      style: TextStyle(
                        color: theme.colors.textSecondary,
                        fontSize: theme.fontSize.xs,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              if (symptom.painScore != null)
                Text(
                  '${Zh.history.painLabel} ${symptom.painScore}/10',
                  style: TextStyle(
                    color: theme.colors.textSecondary,
                    fontSize: theme.fontSize.sm,
                  ),
                ),
              if (symptom.temperature != null)
                Text(
                  '体温 ${symptom.temperature}℃',
                  style: TextStyle(
                    color: theme.colors.textSecondary,
                    fontSize: theme.fontSize.sm,
                  ),
                ),
              if (related != null)
                Text(
                  '关联注射 ${formatDate(_logTime(related))} · ${nameOfLine(related.lineId)}',
                  style: TextStyle(
                    color: theme.colors.textTertiary,
                    fontSize: theme.fontSize.xs,
                  ),
                ),
            ],
          ),
          if (symptom.note != null && symptom.note!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              symptom.note!,
              style: TextStyle(
                color: theme.colors.textSecondary,
                fontSize: theme.fontSize.sm,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

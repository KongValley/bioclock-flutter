import 'dart:async';

import 'package:bioclock/db/repo.dart';
import 'package:bioclock/domain/date_utils.dart';
import 'package:bioclock/domain/rotation.dart';
import 'package:bioclock/domain/schedule.dart';
import 'package:bioclock/i18n/zh.dart';
import 'package:bioclock/models/types.dart';
import 'package:bioclock/notify/notify_content.dart';
import 'package:bioclock/screens/modals/injection_modal.dart';
import 'package:bioclock/screens/modals/oral_modal.dart';
import 'package:bioclock/screens/modals/symptom_modal.dart';
import 'package:bioclock/store/app_store.dart';
import 'package:bioclock/ui/components/app_icon.dart';
import 'package:bioclock/ui/components/app_layout.dart';
import 'package:bioclock/ui/components/app_primitives.dart';
import 'package:bioclock/ui/components/app_scope.dart';
import 'package:bioclock/ui/components/body_map.dart';
import 'package:bioclock/ui/theme.dart';
import 'package:flutter/material.dart';

enum _HeadlineTone { normal, primary, danger }

class _Headline {
  const _Headline(this.text, this.tone);
  final String text;
  final _HeadlineTone tone;
}

_Headline _injectionHeadline(SchedulePlan plan, int now) {
  final diff = calendarDayDiff(plan.plannedAt, now);
  if (diff < 0) return _Headline('${Zh.today.overduePrefix} ${-diff} 天', _HeadlineTone.danger);
  if (diff == 0) return _Headline(Zh.today.countdownToday, _HeadlineTone.primary);
  if (diff == 1) return const _Headline('明天该注射', _HeadlineTone.normal);
  return _Headline('还有 $diff 天', _HeadlineTone.normal);
}

_Headline _oralHeadline(SchedulePlan plan, int now) {
  final diff = calendarDayDiff(plan.plannedAt, now);
  if (diff < 0) return _Headline('${Zh.today.overduePrefix} ${-diff} 天', _HeadlineTone.danger);
  if (diff == 0) return const _Headline('今天该服用', _HeadlineTone.primary);
  if (diff == 1) return const _Headline('明天服用', _HeadlineTone.normal);
  return _Headline('下一剂 ${formatDateTime(plan.plannedAt)}', _HeadlineTone.normal);
}

Color _toneColor(AppThemeData theme, _HeadlineTone tone) => switch (tone) {
      _HeadlineTone.danger => theme.colors.danger,
      _HeadlineTone.primary => theme.colors.primary,
      _HeadlineTone.normal => theme.colors.text,
    };

class TodayTab extends StatefulWidget {
  const TodayTab({
    super.key,
    required this.onOpenOnboarding,
  });

  final VoidCallback onOpenOnboarding;

  @override
  State<TodayTab> createState() => _TodayTabState();
}

class _TodayTabState extends State<TodayTab> {
  int _now = DateTime.now().millisecondsSinceEpoch;
  Timer? _timer;
  String? _busyLineId;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now().millisecondsSinceEpoch);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      await context.store.reload();
    } catch (err) {
      if (mounted) showToast(friendlyErrorMessage(err), isError: true);
    }
  }

  Future<void> _markOral(SchedulePlan plan, DoseStatus status) async {
    setState(() => _busyLineId = plan.lineId);
    try {
      final res = await context.store.addDoseLog(
        DoseLogInput(
          lineId: plan.lineId,
          scheduledAt: plan.plannedAt,
          takenAt: DateTime.now().millisecondsSinceEpoch,
          status: status,
        ),
      );
      if (!mounted) return;
      showToast(status == DoseStatus.done ? '已记录服用' : '已跳过这次');
      if (res.notifyWarning != null) {
        showToast(res.notifyWarning!, isError: true);
      }
    } catch (err) {
      if (mounted) showToast(friendlyErrorMessage(err), isError: true);
    } finally {
      if (mounted) setState(() => _busyLineId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final store = context.store;
    if (!store.ready) return const LoadingView();

    final treatment = store.treatment;
    final medById = {for (final m in store.medications) m.id: m};
    final allLines = treatment?.lines ?? const <TreatmentLine>[];
    final lines = allLines.where((l) => l.endedAt == null).toList();
    final endedLines = allLines.where((l) => l.endedAt != null).toList();

    List<SchedulePlan> plans;
    try {
      plans = treatment == null
          ? const []
          : buildSchedule(
              lines: treatment.lines,
              logs: store.doseLogs,
              now: _now,
            );
    } catch (_) {
      plans = const [];
    }

    final nextByLine = <String, SchedulePlan>{};
    for (final line in lines) {
      final next =
          selectNextPlan(plans.where((p) => p.lineId == line.id).toList(), _now);
      if (next != null) nextByLine[line.id] = next;
    }

    final todoPlans = <SchedulePlan>[];
    for (final line in lines) {
      final plan = nextByLine[line.id];
      if (plan == null) continue;
      if (plan.status != PlanStatus.due && plan.status != PlanStatus.overdue) {
        continue;
      }
      if (calendarDayDiff(plan.plannedAt, _now) > 0) continue;
      todoPlans.add(plan);
    }

    final hostLine = lines.cast<TreatmentLine?>().firstWhere(
          (l) => l?.kind == LineKind.injection && l?.isHost == true,
          orElse: () => null,
        );
    final injectionLines =
        lines.where((l) => l.kind == LineKind.injection).toList();
    final hostMed = hostLine != null ? medById[hostLine.medicationId] : null;
    final showPrepHint = hostMed?.route == MedicationRoute.sc;

    InjectionSite? recommended;
    if (hostLine != null && hostMed?.route == MedicationRoute.sc) {
      recommended = recommendSite([
        for (final log in store.doseLogs)
          if (log.lineId == hostLine.id && log.site != null)
            SiteHistoryEntry(
              site: log.site!,
              injectedAt: log.takenAt ?? log.scheduledAt ?? log.createdAt,
            ),
      ]);
    }

    final subtitle = treatment != null
        ? (store.diseases.isNotEmpty
            ? store.diseases.map((d) => d.name).join('、')
            : '未选择病种')
        : '先把治疗方案设置好';

    return Scaffold(
      backgroundColor: theme.colors.background,
      floatingActionButton: treatment != null && injectionLines.isNotEmpty
          ? Semantics(
              button: true,
              label: '登记一次注射',
              child: FloatingActionButton.extended(
                onPressed: () => showInjectionModal(context),
                backgroundColor: theme.colors.primary,
                foregroundColor: theme.colors.onPrimary,
                icon: AppIcon(
                  AppIconName.plus,
                  size: 18,
                  color: theme.colors.onPrimary,
                  strokeWidth: 2.5,
                ),
                label: Text(
                  Zh.today.registerInjection,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: treatment?.name ?? Zh.today.title,
              subtitle: subtitle,
            ),
            if (store.error != null && store.doseLogs.isEmpty)
              ResponsiveContainer(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: theme.spacing.lg),
                  child: InlineError(
                    message: store.error!,
                    onRetry: _refresh,
                  ),
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                color: theme.colors.primary,
                onRefresh: _refresh,
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    ResponsiveContainer(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          theme.spacing.lg,
                          theme.spacing.xs,
                          theme.spacing.lg,
                          120,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (treatment == null)
                              AppCard(
                                child: StateView(
                                  icon: AppIconName.plus,
                                  title: '还没有治疗方案',
                                  message: '选择病种和药物，设置注射间隔后，这里会显示下一步计划。',
                                  actionLabel: '去设置方案',
                                  onAction: widget.onOpenOnboarding,
                                  compact: true,
                                ),
                              )
                            else if (lines.isEmpty && endedLines.isEmpty)
                              AppCard(
                                child: StateView(
                                  icon: AppIconName.syringe,
                                  title: Zh.today.noSchedule,
                                  compact: true,
                                ),
                              )
                            else ...[
                              const SectionTitle(title: '今天要做'),
                              const SizedBox(height: 10),
                              if (todoPlans.isEmpty)
                                AppCard(
                                  child: Text(
                                    lines.isEmpty
                                        ? '当前没有在用的用药线。'
                                        : '今天没有需要登记的项目，按计划进行即可。',
                                    style: TextStyle(
                                      color: theme.colors.textSecondary,
                                      fontSize: theme.fontSize.sm,
                                    ),
                                  ),
                                )
                              else
                                for (final plan in todoPlans) ...[
                                  _buildTodoCard(
                                    context,
                                    theme,
                                    plan,
                                    lines,
                                    medById,
                                  ),
                                  const SizedBox(height: 12),
                                ],
                              if (lines.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                const SectionTitle(
                                  title: '用药计划',
                                  hint: '每一条用药线的下一步',
                                ),
                                const SizedBox(height: 10),
                                for (final line in lines) ...[
                                  _buildLineCard(
                                    context,
                                    theme,
                                    line,
                                    nextByLine[line.id],
                                    medById,
                                  ),
                                  const SizedBox(height: 12),
                                ],
                              ],
                              if (endedLines.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                const SectionTitle(
                                  title: '已停用',
                                  hint: '历史记录保留，可在设置 → 疗效记录里恢复',
                                ),
                                const SizedBox(height: 10),
                                for (final line in endedLines) ...[
                                  AppCard(
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                medById[line.medicationId]
                                                        ?.name ??
                                                    line.label,
                                                style: TextStyle(
                                                  color: theme
                                                      .colors.textSecondary,
                                                  fontSize: theme.fontSize.md,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${line.kind == LineKind.injection ? '注射' : '口服'} · 已停用',
                                                style: TextStyle(
                                                  color:
                                                      theme.colors.textTertiary,
                                                  fontSize: theme.fontSize.xs,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (line.endedAt != null)
                                          Text(
                                            formatDate(line.endedAt!, _now),
                                            style: TextStyle(
                                              color: theme.colors.textTertiary,
                                              fontSize: theme.fontSize.sm,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                ],
                              ],
                            ],
                            if (recommended != null && hostLine != null) ...[
                              const SizedBox(height: 8),
                              AppCard(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    SectionTitle(
                                      title: Zh.today.recommendedSite,
                                      hint: Zh.today.rotateHint,
                                      right: Text(
                                        siteLabels[recommended] ?? '',
                                        style: TextStyle(
                                          color: theme.colors.primary,
                                          fontSize: theme.fontSize.sm,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    BodyMap(
                                      selected: recommended,
                                      recommended: recommended,
                                      height: 250,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '虚线椭圆是腹部建议注药区（脐周 5cm 以上），示意图只用于提示位置。',
                                      style: TextStyle(
                                        color: theme.colors.textTertiary,
                                        fontSize: theme.fontSize.xs,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (showPrepHint) ...[
                              const SizedBox(height: 16),
                              Container(
                                decoration: BoxDecoration(
                                  color: theme.colors.warningMuted,
                                  borderRadius: BorderRadius.circular(
                                    theme.radius.md,
                                  ),
                                ),
                                padding: EdgeInsets.all(theme.spacing.md),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    AppIcon(
                                      AppIconName.alert,
                                      size: 18,
                                      color: theme.colors.warning,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        notifyPrepHint,
                                        style: TextStyle(
                                          color: theme.colors.warning,
                                          fontSize: theme.fontSize.sm,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            AppButton(
                              label: Zh.today.quickLogSymptom,
                              onPressed: () => showSymptomModal(context),
                              variant: AppButtonVariant.secondary,
                              icon: AppIconName.pencil,
                            ),
                            const SizedBox(height: 16),
                            Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: theme.spacing.lg,
                              ),
                              child: Text(
                                Zh.disclaimer.short,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: theme.colors.textTertiary,
                                  fontSize: theme.fontSize.xs,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTodoCard(
    BuildContext context,
    AppThemeData theme,
    SchedulePlan plan,
    List<TreatmentLine> lines,
    Map<String, Medication> medById,
  ) {
    final line = lines.cast<TreatmentLine?>().firstWhere(
          (l) => l?.id == plan.lineId,
          orElse: () => null,
        );
    final med = line != null ? medById[line.medicationId] : null;
    final medName = med?.name ?? line?.label ?? '用药';
    final isInj = plan.kind == LineKind.injection;
    final headline =
        isInj ? _injectionHeadline(plan, _now) : _oralHeadline(plan, _now);
    final busy = _busyLineId == plan.lineId;
    final tone = switch (headline.tone) {
      _HeadlineTone.danger => AppCardTone.danger,
      _HeadlineTone.primary => AppCardTone.primary,
      _HeadlineTone.normal => AppCardTone.defaultTone,
    };

    return AppCard(
      tone: tone,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            medName,
            style: TextStyle(
              color: theme.colors.text,
              fontSize: theme.fontSize.md,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            headline.text,
            style: TextStyle(
              color: _toneColor(theme, headline.tone),
              fontSize: theme.fontSize.lg,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${isInj ? '注射' : '口服'} · ${formatDateTimeFull(plan.plannedAt)}',
            style: TextStyle(
              color: theme.colors.textSecondary,
              fontSize: theme.fontSize.xs,
            ),
          ),
          const SizedBox(height: 12),
          if (isInj)
            AppButton(
              label: '登记注射',
              onPressed: () =>
                  showInjectionModal(context, initialLineId: plan.lineId),
            )
          else
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: '完成',
                    onPressed: () => _markOral(plan, DoseStatus.done),
                    loading: busy,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    label: '跳过',
                    variant: AppButtonVariant.secondary,
                    disabled: busy,
                    onPressed: () => _markOral(plan, DoseStatus.skipped),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildLineCard(
    BuildContext context,
    AppThemeData theme,
    TreatmentLine line,
    SchedulePlan? plan,
    Map<String, Medication> medById,
  ) {
    final med = medById[line.medicationId];
    final isInj = line.kind == LineKind.injection;
    final headline = plan == null
        ? null
        : (isInj ? _injectionHeadline(plan, _now) : _oralHeadline(plan, _now));
    final dose = plan?.dose ?? med?.defaultDose;
    final unit =
        (plan?.unit.isNotEmpty == true ? plan!.unit : null) ?? med?.unit ?? 'mg';
    final routeText = med?.route == MedicationRoute.iv ? ' · 医院输注' : '';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      med?.name ?? line.label,
                      style: TextStyle(
                        color: theme.colors.text,
                        fontSize: theme.fontSize.md,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${isInj ? (line.isHost ? '注射 · 主药' : '注射') : '口服'}$routeText',
                      style: TextStyle(
                        color: theme.colors.textTertiary,
                        fontSize: theme.fontSize.xs,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (headline != null)
                    Text(
                      headline.text,
                      style: TextStyle(
                        color: _toneColor(theme, headline.tone),
                        fontSize: theme.fontSize.md,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  else
                    Text(
                      Zh.today.noSchedule,
                      style: TextStyle(
                        color: theme.colors.textTertiary,
                        fontSize: theme.fontSize.sm,
                      ),
                    ),
                  if (plan != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      formatDateTimeFull(plan.plannedAt),
                      style: TextStyle(
                        color: theme.colors.textTertiary,
                        fontSize: theme.fontSize.xs,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          if (isInj && dose != null) ...[
            const SizedBox(height: 8),
            Text(
              '剂量 ${dose == dose.truncateToDouble() ? dose.toInt() : dose} $unit',
              style: TextStyle(
                color: theme.colors.textSecondary,
                fontSize: theme.fontSize.sm,
              ),
            ),
          ],
          if (!isInj) ...[
            const SizedBox(height: 12),
            AppButton(
              label: '口服打卡',
              variant: AppButtonVariant.secondary,
              onPressed: () => showOralModal(
                context,
                initialLineId: line.id,
                scheduledAt:
                    plan != null && plan.status == PlanStatus.due ? plan.plannedAt : null,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:bioclock/domain/calendar.dart';
import 'package:bioclock/domain/date_utils.dart';
import 'package:bioclock/domain/schedule.dart';
import 'package:bioclock/i18n/zh.dart';
import 'package:bioclock/models/types.dart';
import 'package:bioclock/store/app_store.dart';
import 'package:bioclock/ui/components/app_icon.dart';
import 'package:bioclock/ui/components/app_layout.dart';
import 'package:bioclock/ui/components/app_primitives.dart';
import 'package:bioclock/ui/components/app_scope.dart';
import 'package:bioclock/ui/theme.dart';
import 'package:flutter/material.dart';

const int _calendarFutureDoseCount = 200;

String _statusLabel(PlanStatus status) => switch (status) {
      PlanStatus.done => Zh.calendar.statusDone,
      PlanStatus.due => Zh.calendar.statusDue,
      PlanStatus.overdue => Zh.calendar.statusOverdue,
      PlanStatus.missed => Zh.calendar.statusMissed,
      PlanStatus.upcoming => Zh.calendar.statusUpcoming,
    };

Color _statusColor(AppThemeData theme, PlanStatus status) => switch (status) {
      PlanStatus.done => theme.colors.success,
      PlanStatus.overdue => theme.colors.danger,
      PlanStatus.missed => theme.colors.textTertiary,
      PlanStatus.due || PlanStatus.upcoming => theme.colors.primary,
    };

class CalendarTab extends StatefulWidget {
  const CalendarTab({
    super.key,
    required this.onOpenOnboarding,
  });

  final VoidCallback onOpenOnboarding;

  @override
  State<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<CalendarTab> {
  late int _now;
  late MonthCursor _cursor;
  late int _selectedDay;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now().millisecondsSinceEpoch;
    _cursor = monthOf(_now);
    _selectedDay = dayStart(_now);
    _timer = Timer.periodic(const Duration(seconds: 60), (_) {
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

  void _goMonth(int delta) {
    final next = shiftMonth(_cursor, delta);
    setState(() {
      _cursor = next;
      if (!isSameMonth(next, _selectedDay)) {
        _selectedDay = DateTime(next.year, next.month + 1, 1).millisecondsSinceEpoch;
      }
    });
  }

  void _goToday() {
    final today = dayStart(DateTime.now().millisecondsSinceEpoch);
    setState(() {
      _cursor = monthOf(today);
      _selectedDay = today;
    });
  }

  void _selectDay(int day) {
    setState(() {
      _selectedDay = dayStart(day);
      if (!isSameMonth(_cursor, day)) _cursor = monthOf(day);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final store = context.store;
    if (!store.ready) return const LoadingView();

    final treatment = store.treatment;
    final lines = treatment?.lines ?? const <TreatmentLine>[];
    final injLines = lines.where((l) => l.kind == LineKind.injection).toList();
    final medById = {for (final m in store.medications) m.id: m};

    List<SchedulePlan> plans;
    try {
      plans = treatment == null
          ? const []
          : buildSchedule(
              lines: treatment.lines,
              logs: store.doseLogs,
              now: _now,
              futureDoseCount: _calendarFutureDoseCount,
            ).where((p) => p.kind == LineKind.injection).toList();
    } catch (_) {
      plans = const [];
    }

    final plansByDay = groupPlansByDay(plans);
    final cells = buildMonthCells(_cursor);
    final selectedPlans = plansByDay[dayStart(_selectedDay)] ?? const <SchedulePlan>[];
    final monthPlanCount =
        plans.where((p) => isSameMonth(_cursor, p.plannedAt)).length;
    final todayStart = dayStart(_now);

    return Scaffold(
      backgroundColor: theme.colors.background,
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: Zh.calendar.title,
              subtitle: treatment != null ? treatment.name : Zh.calendar.noTreatment,
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
                          0,
                          theme.spacing.lg,
                          40,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (treatment == null)
                              AppCard(
                                child: StateView(
                                  icon: AppIconName.calendar,
                                  title: Zh.calendar.noTreatment,
                                  message: '设置治疗方案后，这里会显示未来每一次注射安排。',
                                  actionLabel: '去设置方案',
                                  onAction: widget.onOpenOnboarding,
                                  compact: true,
                                ),
                              )
                            else if (injLines.isEmpty)
                              AppCard(
                                child: StateView(
                                  icon: AppIconName.calendar,
                                  title: Zh.calendar.noInjectionLines,
                                  compact: true,
                                ),
                              )
                            else ...[
                              AppCard(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        Semantics(
                                          button: true,
                                          label: Zh.calendar.prevMonth,
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(
                                              theme.radius.pill,
                                            ),
                                            onTap: () => _goMonth(-1),
                                            child: SizedBox(
                                              width: 44,
                                              height: 44,
                                              child: Center(
                                                child: AppIcon(
                                                  AppIconName.chevronLeft,
                                                  size: 22,
                                                  color: theme.colors.text,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Semantics(
                                            header: true,
                                            child: Text(
                                              monthTitle(_cursor),
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: theme.colors.text,
                                                fontSize: theme.fontSize.lg,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ),
                                        Semantics(
                                          button: true,
                                          label: Zh.calendar.nextMonth,
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(
                                              theme.radius.pill,
                                            ),
                                            onTap: () => _goMonth(1),
                                            child: SizedBox(
                                              width: 44,
                                              height: 44,
                                              child: Center(
                                                child: AppIcon(
                                                  AppIconName.chevronRight,
                                                  size: 22,
                                                  color: theme.colors.text,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        for (final label in Zh.calendar.weekdays)
                                          Expanded(
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                vertical: 6,
                                              ),
                                              child: Text(
                                                label,
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color:
                                                      theme.colors.textTertiary,
                                                  fontSize: theme.fontSize.xs,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    for (var week = 0; week < 6; week += 1)
                                      Row(
                                        children: [
                                          for (var col = 0; col < 7; col += 1)
                                            Expanded(
                                              child: _buildDayCell(
                                                theme,
                                                cells[week * 7 + col],
                                                plansByDay[
                                                        dayStart(cells[week * 7 + col])] ??
                                                    const [],
                                                todayStart,
                                              ),
                                            ),
                                        ],
                                      ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            Zh.calendar.legend,
                                            style: TextStyle(
                                              color: theme.colors.textTertiary,
                                              fontSize: theme.fontSize.xs,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Semantics(
                                          button: true,
                                          label: Zh.calendar.today,
                                          child: Material(
                                            color: theme.colors.surface,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(
                                                theme.radius.pill,
                                              ),
                                              side: BorderSide(
                                                color: theme.colors.border,
                                              ),
                                            ),
                                            child: InkWell(
                                              borderRadius: BorderRadius.circular(
                                                theme.radius.pill,
                                              ),
                                              onTap: _goToday,
                                              child: ConstrainedBox(
                                                constraints: const BoxConstraints(
                                                  minHeight: 44,
                                                  minWidth: 64,
                                                ),
                                                child: Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(horizontal: 12),
                                                  child: Center(
                                                    child: Text(
                                                      Zh.calendar.today,
                                                      style: TextStyle(
                                                        color: theme
                                                            .colors.primary,
                                                        fontSize:
                                                            theme.fontSize.sm,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              SectionTitle(
                                title: Zh.calendar.selectedDay,
                                hint:
                                    '${formatWeekday(_selectedDay)} · ${selectedPlans.isNotEmpty ? '${selectedPlans.length} ${Zh.calendar.countSuffix}' : Zh.calendar.emptyDay}',
                              ),
                              const SizedBox(height: 10),
                              if (selectedPlans.isEmpty)
                                AppCard(
                                  child: Text(
                                    monthPlanCount > 0
                                        ? Zh.calendar.emptyDay
                                        : Zh.calendar.emptyMonth,
                                    style: TextStyle(
                                      color: theme.colors.textSecondary,
                                      fontSize: theme.fontSize.sm,
                                    ),
                                  ),
                                )
                              else
                                for (final plan in selectedPlans) ...[
                                  _buildSelectedPlanCard(
                                    theme,
                                    plan,
                                    lines,
                                    medById,
                                  ),
                                  const SizedBox(height: 10),
                                ],
                              const SizedBox(height: 8),
                              Text(
                                Zh.calendar.footerNote,
                                textAlign: TextAlign.center,
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
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayCell(
    AppThemeData theme,
    int day,
    List<SchedulePlan> dayPlans,
    int todayStart,
  ) {
    final inMonth = isSameMonth(_cursor, day);
    final isToday = dayStart(day) == todayStart;
    final selected = dayStart(day) == dayStart(_selectedDay);
    final dt = DateTime.fromMillisecondsSinceEpoch(day);

    return Padding(
      padding: const EdgeInsets.all(2),
      child: Semantics(
        button: true,
        selected: selected,
        label: '${dt.month}月${dt.day}日，${dayPlans.length} ${Zh.calendar.countSuffix}',
        child: Opacity(
          opacity: inMonth ? 1.0 : 0.35,
          child: Material(
            color: selected ? theme.colors.primaryMuted : Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(theme.radius.md),
              side: BorderSide(
                color: isToday ? theme.colors.primary : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(theme.radius.md),
              onTap: () => _selectDay(day),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 52),
                child: Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 4),
                  child: Column(
                    children: [
                      Text(
                        '${dt.day}',
                        style: TextStyle(
                          color: selected
                              ? theme.colors.primary
                              : theme.colors.text,
                          fontSize: theme.fontSize.sm,
                          fontWeight: isToday || selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 8,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (final p in dayPlans.take(3))
                              Container(
                                width: 4,
                                height: 4,
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 1),
                                decoration: BoxDecoration(
                                  color: _statusColor(theme, p.status),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            if (dayPlans.length > 3)
                              Text(
                                '+${dayPlans.length - 3}',
                                style: TextStyle(
                                  color: theme.colors.textTertiary,
                                  fontSize: 8,
                                  height: 1.0,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedPlanCard(
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
    final name = med?.name ?? line?.label ?? '注射';
    final dose = plan.dose ?? med?.defaultDose;
    final unit =
        plan.unit.isNotEmpty ? plan.unit : (med?.unit ?? 'mg');
    final phase = switch (plan.phaseKind) {
      PhaseKind.loading => Zh.calendar.phaseLoading,
      PhaseKind.maintenance => Zh.calendar.phaseMaintenance,
      null => null,
    };
    final statusClr = _statusColor(theme, plan.status);

    return AppCard(
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: statusClr,
                borderRadius: BorderRadius.circular(theme.radius.pill),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: theme.colors.text,
                      fontSize: theme.fontSize.md,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      '第 ${plan.index + 1} 针',
                      ?phase,
                      if (line != null && line.label != name) line.label,
                    ].join(' · '),
                    style: TextStyle(
                      color: theme.colors.textTertiary,
                      fontSize: theme.fontSize.xs,
                    ),
                  ),
                  if (dose != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      '剂量 ${dose == dose.truncateToDouble() ? dose.toInt() : dose} $unit',
                      style: TextStyle(
                        color: theme.colors.textSecondary,
                        fontSize: theme.fontSize.sm,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _statusLabel(plan.status),
                  style: TextStyle(
                    color: statusClr,
                    fontSize: theme.fontSize.sm,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  formatDateTime(plan.plannedAt, _now),
                  style: TextStyle(
                    color: theme.colors.textTertiary,
                    fontSize: theme.fontSize.xs,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

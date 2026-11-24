import 'package:bioclock/domain/schedule.dart';
import 'package:bioclock/models/types.dart';

const int _missedAfterDays = 7;

sealed class LineAdherence {
  const LineAdherence({required this.lineId});
  final String lineId;
  LineKind get kind;
}

class InjectionLineAdherence extends LineAdherence {
  const InjectionLineAdherence({
    required super.lineId,
    required this.total,
    required this.onTime,
    required this.early,
    required this.late,
    required this.missed,
    required this.upcoming,
    required this.avgDeviationDays,
    required this.currentStreak,
  });

  @override
  LineKind get kind => LineKind.injection;

  final int total;
  final int onTime;
  final int early;
  final int late;
  final int missed;
  final int upcoming;
  final double avgDeviationDays;
  final int currentStreak;
}

class OralLineAdherence extends LineAdherence {
  const OralLineAdherence({
    required super.lineId,
    required this.total,
    required this.missed,
    required this.upcoming,
    required this.rate,
  });

  @override
  LineKind get kind => LineKind.oral;

  final int total;
  final int missed;
  final int upcoming;
  final double rate;
}

class AdherenceStats {
  const AdherenceStats({
    required this.total,
    required this.onTime,
    required this.early,
    required this.late,
    required this.missed,
    required this.upcoming,
    required this.avgDeviationDays,
    required this.currentStreak,
    required this.rate,
    required this.byLine,
  });

  final int total;
  final int onTime;
  final int early;
  final int late;
  final int missed;
  final int upcoming;
  final double avgDeviationDays;
  final int currentStreak;
  final double rate;
  final List<LineAdherence> byLine;
}

double _round1(double v) {
  final r = (v * 10 + 0.5).floor() / 10;
  return r == 0 ? 0.0 : r;
}

double _round2(double v) {
  final r = (v * 100 + 0.5).floor() / 100;
  return r == 0 ? 0.0 : r;
}

double _rateOf(int done, int missed) {
  final denom = done + missed;
  return denom > 0 ? _round2(done / denom) : 0.0;
}

bool _isMissedPlan(SchedulePlan plan, int now) {
  if (plan.status == PlanStatus.missed) return true;
  if (plan.status != PlanStatus.overdue) return false;
  return now - plan.plannedAt > _missedAfterDays * dayMs;
}

InjectionLineAdherence _injectionStats(
  String lineId,
  List<SchedulePlan> plans,
  int now,
) {
  final donePlans = plans.where((p) => p.status == PlanStatus.done).toList();
  final missed = plans.where((p) => _isMissedPlan(p, now)).length;
  final upcoming = plans
      .where((p) => p.status == PlanStatus.upcoming || p.status == PlanStatus.due)
      .length;

  var onTime = 0;
  var early = 0;
  var late = 0;
  var deviationSum = 0.0;

  for (final plan in donePlans) {
    if (plan.windowStatus == WindowStatus.onTime) {
      onTime += 1;
    } else if (plan.windowStatus == WindowStatus.early) {
      early += 1;
    } else if (plan.windowStatus == WindowStatus.late) {
      late += 1;
    }
    deviationSum += plan.deviationDays ?? 0;
  }

  var currentStreak = 0;
  for (var i = donePlans.length - 1; i >= 0; i -= 1) {
    if (donePlans[i].windowStatus != WindowStatus.onTime) break;
    currentStreak += 1;
  }

  return InjectionLineAdherence(
    lineId: lineId,
    total: donePlans.length,
    onTime: onTime,
    early: early,
    late: late,
    missed: missed,
    upcoming: upcoming,
    avgDeviationDays:
        donePlans.isNotEmpty ? _round1(deviationSum / donePlans.length) : 0.0,
    currentStreak: currentStreak,
  );
}

OralLineAdherence _oralStats(
  String lineId,
  List<SchedulePlan> plans,
  int now,
) {
  final total = plans.where((p) => p.status == PlanStatus.done).length;
  final missed = plans.where((p) => _isMissedPlan(p, now)).length;
  final upcoming = plans
      .where((p) => p.status == PlanStatus.upcoming || p.status == PlanStatus.due)
      .length;
  return OralLineAdherence(
    lineId: lineId,
    total: total,
    missed: missed,
    upcoming: upcoming,
    rate: _rateOf(total, missed),
  );
}

AdherenceStats computeAdherence(
  List<TreatmentLine> lines,
  List<DoseLog> logs,
  int now,
) {
  final plans = buildSchedule(lines: lines, logs: logs, now: now);

  final byLine = [
    for (final line in lines)
      line.kind == LineKind.oral
          ? _oralStats(
              line.id,
              plans.where((p) => p.lineId == line.id).toList(),
              now,
            )
          : _injectionStats(
              line.id,
              plans.where((p) => p.lineId == line.id).toList(),
              now,
            ),
  ];

  if (byLine.isEmpty) {
    return const AdherenceStats(
      total: 0,
      onTime: 0,
      early: 0,
      late: 0,
      missed: 0,
      upcoming: 0,
      avgDeviationDays: 0,
      currentStreak: 0,
      rate: 0,
      byLine: [],
    );
  }

  final injectionLineIds = lines
      .where((l) => l.kind != LineKind.oral)
      .map((l) => l.id)
      .toSet();

  var total = 0;
  var onTime = 0;
  var early = 0;
  var late = 0;
  var missed = 0;
  var upcoming = 0;
  var deviationSum = 0.0;
  var deviationCount = 0;
  var currentStreak = 0;

  for (final stats in byLine) {
    switch (stats) {
      case InjectionLineAdherence():
        total += stats.total;
        missed += stats.missed;
        upcoming += stats.upcoming;
        onTime += stats.onTime;
        early += stats.early;
        late += stats.late;
        if (stats.total > 0) currentStreak = stats.currentStreak;
      case OralLineAdherence():
        total += stats.total;
        missed += stats.missed;
        upcoming += stats.upcoming;
    }
  }

  for (final plan in plans) {
    if (plan.status != PlanStatus.done) continue;
    if (!injectionLineIds.contains(plan.lineId)) continue;
    deviationSum += plan.deviationDays ?? 0;
    deviationCount += 1;
  }

  return AdherenceStats(
    total: total,
    onTime: onTime,
    early: early,
    late: late,
    missed: missed,
    upcoming: upcoming,
    avgDeviationDays:
        deviationCount > 0 ? _round1(deviationSum / deviationCount) : 0.0,
    currentStreak: currentStreak,
    rate: _rateOf(total, missed),
    byLine: byLine,
  );
}

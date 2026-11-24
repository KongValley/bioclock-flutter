import 'dart:math' as math;

import 'package:bioclock/models/types.dart';

const int dayMs = 86400000;
const int _injectionFutureDoseCount = 2;
const int oralHorizonDays = 14;
const int _maxOralPlans = 20000;
const int _maxPlans = 100000;
const int _overdueActionableDays = 30;

enum PlanStatus {
  done('done'),
  due('due'),
  upcoming('upcoming'),
  overdue('overdue'),
  missed('missed');

  const PlanStatus(this.wire);
  final String wire;
}

class SchedulePlan {
  SchedulePlan({
    required this.index,
    required this.lineId,
    required this.treatmentId,
    required this.medicationId,
    required this.kind,
    required this.phaseId,
    required this.phaseKind,
    required this.plannedAt,
    required this.status,
    required this.dose,
    required this.unit,
    this.actualAt,
    this.deviationDays,
    this.windowStatus,
    this.doseLogId,
  });

  int index;
  final String lineId;
  final String treatmentId;
  final String medicationId;
  final LineKind kind;
  final String? phaseId;
  final PhaseKind? phaseKind;
  final int plannedAt;
  PlanStatus status;
  double? dose;
  String unit;
  int? actualAt;
  double? deviationDays;
  WindowStatus? windowStatus;
  String? doseLogId;
}

void _assertWindowDays(int windowDays) {
  if (windowDays < 0) {
    throw ArgumentError('允许偏差窗口不能小于 0 天');
  }
}

void _assertIntervalDays(int intervalDays) {
  if (intervalDays <= 0) {
    throw ArgumentError('给药间隔必须大于 0 天');
  }
}

int? _earliestEnd(int? a, int? b) {
  if (a == null) return b;
  if (b == null) return a;
  return math.min(a, b);
}

double _round1(double value) {
  final r = (value * 10 + 0.5).floor() / 10;
  return r == 0 ? 0.0 : r;
}

bool _isSyncedLine(TreatmentLine line) =>
    line.kind == LineKind.injection && line.syncWithHost;

int futureDoseCountForHorizon(List<TreatmentLine> lines, int horizonDays) {
  final intervals = <int>[];
  for (final line in lines) {
    if (line.kind != LineKind.injection) continue;
    for (final phase in line.phases) {
      if (phase.intervalDays > 0) intervals.add(phase.intervalDays);
    }
  }
  if (intervals.isEmpty) return _injectionFutureDoseCount;

  final days = math.max(1, horizonDays);
  final needed = (days / intervals.reduce(math.min)).ceil() + 2;
  return math.min(1000, math.max(_injectionFutureDoseCount, needed));
}

TreatmentLine? resolveHostLine(
  TreatmentLine line,
  List<TreatmentLine> lines,
) {
  final injectionLines = lines
      .where((item) => item.kind == LineKind.injection && item.id != line.id)
      .toList();
  for (final item in injectionLines) {
    if (item.isHost) return item;
  }
  for (final item in injectionLines) {
    if (!_isSyncedLine(item)) return item;
  }
  return null;
}

TreatmentPhase? _phaseAtByCount(List<TreatmentPhase> phases, int index) {
  var remaining = index;
  for (final phase in phases) {
    if (phase.repeatCount == 0) return phase;
    if (remaining < phase.repeatCount) return phase;
    remaining -= phase.repeatCount;
  }
  return null;
}

TreatmentPhase? _nextEffectivePhase(List<TreatmentPhase> phases, int after) {
  final candidates = phases
      .where((p) => p.effectiveFrom != null && p.effectiveFrom! > after)
      .toList();
  if (candidates.isEmpty) return null;
  candidates.sort((a, b) {
    final c = (a.effectiveFrom ?? 0).compareTo(b.effectiveFrom ?? 0);
    return c != 0 ? c : a.orderIdx.compareTo(b.orderIdx);
  });
  return candidates.first;
}

TreatmentPhase? _phaseAt(
  List<TreatmentPhase> phases,
  int index, [
  int? plannedAt,
]) {
  if (plannedAt != null) {
    final dated = phases
        .where(
            (p) => p.effectiveFrom != null && p.effectiveFrom! <= plannedAt)
        .toList();
    if (dated.isNotEmpty) {
      dated.sort((a, b) {
        final c = (a.effectiveFrom ?? 0).compareTo(b.effectiveFrom ?? 0);
        return c != 0 ? c : a.orderIdx.compareTo(b.orderIdx);
      });
      return dated.last;
    }
  }

  final undated = phases.where((p) => p.effectiveFrom == null).toList();
  final byCount = _phaseAtByCount(undated, index);
  if (byCount != null) return byCount;

  if (phases.any((p) => p.effectiveFrom != null)) {
    if (undated.isNotEmpty) return undated.last;
    return phases.isNotEmpty ? phases.first : null;
  }
  return null;
}

int _floorToDay(int timestamp) {
  final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
  return DateTime(dt.year, dt.month, dt.day).millisecondsSinceEpoch;
}

bool _sameLocalDay(int a, int b) => _floorToDay(a) == _floorToDay(b);

WindowStatus classifyWindow(int plannedAt, int actualAt, int windowDays) {
  _assertWindowDays(windowDays);
  if ((actualAt - plannedAt).abs() <= windowDays * dayMs) {
    return WindowStatus.onTime;
  }
  return actualAt < plannedAt ? WindowStatus.early : WindowStatus.late;
}

PlanStatus classifyStatus(int plannedAt, int now) {
  if (plannedAt < now - dayMs) return PlanStatus.overdue;
  if ((plannedAt - now).abs() <= dayMs) return PlanStatus.due;
  return PlanStatus.upcoming;
}

class _SortedLog {
  const _SortedLog(this.log, this.sortAt);
  final DoseLog log;
  final int sortAt;
}

int _logTime(DoseLog log) => log.takenAt ?? log.scheduledAt ?? log.createdAt;

List<_SortedLog> _sortLogs(List<DoseLog> logs) {
  final list = [for (var i = 0; i < logs.length; i += 1) (logs[i], i)];
  list.sort((a, b) {
    final cmp = _logTime(a.$1).compareTo(_logTime(b.$1));
    return cmp != 0 ? cmp : a.$2.compareTo(b.$2);
  });
  return [for (final item in list) _SortedLog(item.$1, _logTime(item.$1))];
}

List<DoseLog?> _pairLogs(
  List<SchedulePlan> plans,
  List<_SortedLog> sortedLogs,
  bool Function(int plannedAt, int logAt) samePeriod,
) {
  final assigned = List<DoseLog?>.filled(plans.length, null);
  final used = <String>{};

  for (var i = 0; i < plans.length; i += 1) {
    final plannedAt = plans[i].plannedAt;
    for (final item in sortedLogs) {
      if (!used.contains(item.log.id) && item.log.scheduledAt == plannedAt) {
        assigned[i] = item.log;
        used.add(item.log.id);
        break;
      }
    }
  }

  for (var i = 0; i < plans.length; i += 1) {
    if (assigned[i] != null) continue;
    final plannedAt = plans[i].plannedAt;
    for (final item in sortedLogs) {
      if (!used.contains(item.log.id) &&
          item.log.scheduledAt == null &&
          samePeriod(plannedAt, item.sortAt)) {
        assigned[i] = item.log;
        used.add(item.log.id);
        break;
      }
    }
  }

  return assigned;
}

DoseLog? _findNearestLog(
  List<_SortedLog> sortedLogs,
  Set<String> used,
  int plannedAt,
  int toleranceDays, [
  int? minAt,
]) {
  final tolerance = toleranceDays * dayMs;
  DoseLog? best;
  double bestDistance = double.infinity;

  for (final item in sortedLogs) {
    if (used.contains(item.log.id)) continue;
    if (minAt != null && item.sortAt < minAt) continue;
    final distance = item.log.scheduledAt == plannedAt
        ? 0.0
        : (item.sortAt - plannedAt).abs().toDouble();
    if (distance > tolerance) continue;
    if (distance < bestDistance) {
      best = item.log;
      bestDistance = distance;
    }
  }
  return best;
}

DoseLog? _takeNearestLog(
  List<_SortedLog> sortedLogs,
  Set<String> used,
  int plannedAt,
  int toleranceDays, [
  int? minAt,
]) {
  final best = _findNearestLog(sortedLogs, used, plannedAt, toleranceDays, minAt);
  if (best != null) used.add(best.id);
  return best;
}

PlanStatus _statusForLogged(DoseLog log, int plannedAt, int now) {
  if (log.status == DoseStatus.done) return PlanStatus.done;
  if (log.status == DoseStatus.skipped) {
    return plannedAt < now ? PlanStatus.missed : PlanStatus.upcoming;
  }
  return PlanStatus.missed;
}

void _applyLog(
  SchedulePlan plan,
  DoseLog log,
  int now,
  int? windowDays,
) {
  plan.status = _statusForLogged(log, plan.plannedAt, now);
  plan.doseLogId = log.id;
  if (log.dose != null) plan.dose = log.dose;
  if (log.unit.isNotEmpty) plan.unit = log.unit;

  final actualAt = log.takenAt;
  if (actualAt == null) return;

  plan.actualAt = actualAt;
  plan.deviationDays = _round1((actualAt - plan.plannedAt) / dayMs);
  if (windowDays != null) {
    plan.windowStatus = classifyWindow(plan.plannedAt, actualAt, windowDays);
  }
}

List<SchedulePlan> buildInjectionPlans({
  required TreatmentLine line,
  required List<DoseLog> logs,
  required int now,
  int? futureDoseCount,
}) {
  final futureDoseLimit = futureDoseCount ?? _injectionFutureDoseCount;
  if (line.kind != LineKind.injection) return const [];
  _assertWindowDays(line.windowDays);

  final phases = [...line.phases]
    ..sort((a, b) => a.orderIdx.compareTo(b.orderIdx));
  for (final phase in phases) {
    _assertIntervalDays(phase.intervalDays);
  }
  if (phases.isEmpty) return const [];

  final anchor = line.anchor;
  final windowDays = line.windowDays;
  final endedAt = line.endedAt;
  final sortedLogs = _sortLogs(logs);

  final plans = <SchedulePlan>[];
  final actualTimes = <int?>[];
  final usedLogIds = <String>{};
  var futureCount = 0;

  for (var index = 0;; index += 1) {
    int plannedAt;
    if (index == 0) {
      plannedAt = sortedLogs.isNotEmpty
          ? (sortedLogs.first.log.scheduledAt ?? sortedLogs.first.sortAt)
          : _floorToDay(now);
    } else {
      final previousPlanned = plans[index - 1].plannedAt;
      final previousActual = actualTimes[index - 1];
      final base = anchor == RegimenAnchor.actual && previousActual != null
          ? previousActual
          : previousPlanned;
      final previousPhase = _phaseAt(phases, index - 1, previousPlanned);
      plannedAt = base + (previousPhase?.intervalDays ?? 0) * dayMs;

      final nextPhase = _nextEffectivePhase(phases, previousPlanned);
      if (nextPhase?.effectiveFrom != null) {
        final effFrom = nextPhase!.effectiveFrom!;
        final oldTolerance = math.max(
          2,
          math.max(
            windowDays + 1,
            ((previousPhase?.intervalDays ?? 28) / 2).ceil(),
          ),
        );
        final oldLog =
            _findNearestLog(sortedLogs, usedLogIds, plannedAt, oldTolerance);
        final oldLogAt = oldLog == null ? null : _logTime(oldLog);
        if (oldLogAt == null || oldLogAt >= effFrom) {
          plannedAt = effFrom;
        }
      }
    }

    final phase = _phaseAt(phases, index, plannedAt);
    if (phase == null) break;

    final toleranceDays = math.max(
      2,
      math.max(windowDays + 1, (phase.intervalDays / 2).ceil()),
    );
    final afterEnd = endedAt != null && plannedAt > endedAt;
    if (afterEnd) {
      _SortedLog? nextPostEnd;
      for (final item in sortedLogs) {
        if (!usedLogIds.contains(item.log.id) && item.sortAt > endedAt) {
          nextPostEnd = item;
          break;
        }
      }
      if (nextPostEnd == null) break;
      plannedAt = nextPostEnd.sortAt;
    }

    final log = _takeNearestLog(
      sortedLogs,
      usedLogIds,
      plannedAt,
      toleranceDays,
      afterEnd ? endedAt : null,
    );
    if (afterEnd && log == null) break;

    if (log == null && plannedAt > now) {
      futureCount += 1;
      if (futureCount > futureDoseLimit) break;
    }
    if (plans.length >= _maxPlans) {
      throw StateError('排程长度超出上限，请检查给药间隔');
    }

    final plan = SchedulePlan(
      index: index,
      lineId: line.id,
      treatmentId: line.treatmentId,
      medicationId: line.medicationId,
      kind: line.kind,
      phaseId: phase.id,
      phaseKind: phase.kind,
      plannedAt: plannedAt,
      status: classifyStatus(plannedAt, now),
      dose: phase.dose,
      unit: phase.unit,
    );
    if (log != null) _applyLog(plan, log, now, windowDays);

    plans.add(plan);
    actualTimes.add(log?.takenAt);
  }

  return plans;
}

List<SchedulePlan> _buildSyncedPlans({
  required TreatmentLine line,
  required List<SchedulePlan> hostPlans,
  required List<DoseLog> logs,
  required int now,
  int? endAt,
  int? futureDoseCount,
}) {
  final futureDoseLimit = futureDoseCount ?? _injectionFutureDoseCount;
  final ownPhases = [...line.phases]
    ..sort((a, b) => a.orderIdx.compareTo(b.orderIdx));
  for (final phase in ownPhases) {
    _assertIntervalDays(phase.intervalDays);
  }
  if (ownPhases.isEmpty || hostPlans.isEmpty) return const [];

  _assertWindowDays(line.windowDays);
  final fallbackPhase = ownPhases.last;
  final step = fallbackPhase.intervalDays * dayMs;

  final timestamps = hostPlans
      .map((p) => p.plannedAt)
      .where((ts) => endAt == null || ts <= endAt)
      .toList();
  if (timestamps.isEmpty) return const [];

  var futureCount = timestamps.where((ts) => ts > now).length;
  var cursor = timestamps.last;
  while (futureCount < futureDoseLimit) {
    if (timestamps.length >= _maxPlans) {
      throw StateError('排程长度超出上限，请检查给药间隔');
    }
    final next = cursor + step;
    if (endAt != null && next > endAt) break;
    cursor = next;
    timestamps.add(cursor);
    if (cursor > now) futureCount += 1;
  }

  final plans = [
    for (var i = 0; i < timestamps.length; i += 1)
      () {
        final plannedAt = timestamps[i];
        final phase = _phaseAt(ownPhases, i, plannedAt) ?? fallbackPhase;
        return SchedulePlan(
          index: i,
          lineId: line.id,
          treatmentId: line.treatmentId,
          medicationId: line.medicationId,
          kind: line.kind,
          phaseId: phase.id,
          phaseKind: phase.kind,
          plannedAt: plannedAt,
          status: classifyStatus(plannedAt, now),
          dose: phase.dose,
          unit: phase.unit,
        );
      }(),
  ];

  final logTolerance =
      math.max(line.windowDays + 1, (fallbackPhase.intervalDays / 2).ceil()) *
          dayMs;
  final assigned = _pairLogs(
    plans,
    _sortLogs(logs),
    (plannedAt, logAt) => (logAt - plannedAt).abs() <= logTolerance,
  );
  for (var i = 0; i < plans.length; i += 1) {
    final log = assigned[i];
    if (log != null) _applyLog(plans[i], log, now, line.windowDays);
  }

  return plans;
}

List<int> _normalizeWeekdays(List<int> daysOfWeek) {
  final valid = daysOfWeek.where((d) => d >= 0 && d <= 6).toSet().toList()
    ..sort();
  if (valid.isEmpty) {
    throw ArgumentError('自定义服药频率至少要选择一周中的一天');
  }
  return valid;
}

List<int> _evenlySpacedWeekdays(int timesPerPeriod) {
  final count = timesPerPeriod.clamp(1, 7);
  const weekOrder = [1, 2, 3, 4, 5, 6, 0];
  final days = <int>[];
  for (var slot = 0; slot < count; slot += 1) {
    final day = weekOrder[((slot * 7) / count).round() % 7];
    if (!days.contains(day)) days.add(day);
  }
  days.sort();
  return days;
}

/// 口服线按哪几个（本地）周几打卡，0 = 周日 … 6 = 周六。
List<int> oralWeekdays(OralPlan oral) {
  if (oral.frequency == OralFrequency.daily) return _evenlySpacedWeekdays(7);
  if (oral.frequency == OralFrequency.custom) {
    return _normalizeWeekdays(oral.daysOfWeek);
  }
  return _evenlySpacedWeekdays(oral.timesPerPeriod);
}

List<SchedulePlan> buildOralPlans({
  required TreatmentLine line,
  required List<DoseLog> logs,
  required int now,
  int? horizonDays,
}) {
  if (line.kind != LineKind.oral || line.oral == null) return const [];
  final oral = line.oral!;
  final horizon = horizonDays ?? oralHorizonDays;
  final weekdays = oralWeekdays(oral);
  final startDay = _floorToDay(oral.startDate);
  final startDt = DateTime.fromMillisecondsSinceEpoch(startDay);
  final durationDays = oral.durationDays;
  final endedAt = line.endedAt;
  final endAt = _floorToDay(math.max(now, startDay)) + horizon * dayMs;

  final plannedTimes = <int>[];
  for (var day = 0;; day += 1) {
    if (durationDays != null && day >= durationDays) break;
    final cursor = DateTime(startDt.year, startDt.month, startDt.day + day);
    final timestamp = cursor.millisecondsSinceEpoch;
    if (timestamp > endAt) break;
    if (endedAt != null && timestamp > endedAt) break;
    if (plannedTimes.length >= _maxOralPlans) {
      throw StateError('排程长度超出上限，请检查口服频率');
    }
    final weekday = cursor.weekday % 7;
    if (weekdays.contains(weekday)) plannedTimes.add(timestamp);
  }

  final plans = [
    for (var i = 0; i < plannedTimes.length; i += 1)
      SchedulePlan(
        index: i,
        lineId: line.id,
        treatmentId: line.treatmentId,
        medicationId: line.medicationId,
        kind: line.kind,
        phaseId: null,
        phaseKind: null,
        plannedAt: plannedTimes[i],
        status: classifyStatus(plannedTimes[i], now),
        dose: null,
        unit: '',
      ),
  ];

  final sortedLogs = _sortLogs(logs);
  final assigned = _pairLogs(plans, sortedLogs, _sameLocalDay);
  final assignedIds = <String>{
    for (final l in assigned)
      if (l != null) l.id,
  };
  for (var i = 0; i < plans.length; i += 1) {
    final log = assigned[i];
    if (log != null) _applyLog(plans[i], log, now, null);
  }

  final boundary = _earliestEnd(
    endedAt,
    durationDays != null ? startDay + durationDays * dayMs - 1 : null,
  );
  if (boundary != null) {
    final seenDays = plans.map((p) => _floorToDay(p.plannedAt)).toSet();
    for (final item in sortedLogs) {
      if (assignedIds.contains(item.log.id)) continue;
      if (item.sortAt <= boundary) continue;
      final day = _floorToDay(item.sortAt);
      if (day < startDay) continue;
      if (!seenDays.add(day)) continue;
      if (plans.length >= _maxOralPlans) break;
      final plan = SchedulePlan(
        index: plans.length,
        lineId: line.id,
        treatmentId: line.treatmentId,
        medicationId: line.medicationId,
        kind: line.kind,
        phaseId: null,
        phaseKind: null,
        plannedAt: day,
        status: classifyStatus(day, now),
        dose: null,
        unit: '',
      );
      _applyLog(plan, item.log, now, null);
      plans.add(plan);
    }
    plans.sort((a, b) => a.plannedAt.compareTo(b.plannedAt));
    for (var i = 0; i < plans.length; i += 1) {
      plans[i].index = i;
    }
  }

  return plans;
}

List<SchedulePlan> buildLineSchedule({
  required TreatmentLine line,
  required List<DoseLog> logs,
  required int now,
  int? horizonDays,
  int? futureDoseCount,
  TreatmentLine? Function(TreatmentLine line)? resolveHost,
  List<DoseLog>? hostLogs,
}) {
  if (line.kind == LineKind.oral) {
    return buildOralPlans(
      line: line,
      logs: logs,
      now: now,
      horizonDays: horizonDays,
    );
  }

  if (_isSyncedLine(line)) {
    final host = resolveHost?.call(line);
    if (host == null) return const [];
    final hostPlans = buildInjectionPlans(
      line: host,
      logs: hostLogs ?? const [],
      now: now,
      futureDoseCount: futureDoseCount,
    );
    if (hostPlans.isEmpty) return const [];
    return _buildSyncedPlans(
      line: line,
      hostPlans: hostPlans,
      logs: logs,
      now: now,
      endAt: _earliestEnd(line.endedAt, host.endedAt),
      futureDoseCount: futureDoseCount,
    );
  }

  return buildInjectionPlans(
    line: line,
    logs: logs,
    now: now,
    futureDoseCount: futureDoseCount,
  );
}

List<SchedulePlan> buildSchedule({
  required List<TreatmentLine> lines,
  required List<DoseLog> logs,
  required int now,
  int? horizonDays,
  int? futureDoseCount,
}) {
  final logsByLine = <String, List<DoseLog>>{
    for (final line in lines)
      line.id: logs.where((l) => l.lineId == line.id).toList(),
  };

  final hostPlansById = <String, List<SchedulePlan>>{};
  for (final line in lines) {
    if (line.kind == LineKind.injection && !_isSyncedLine(line)) {
      hostPlansById[line.id] = buildInjectionPlans(
        line: line,
        logs: logsByLine[line.id] ?? const [],
        now: now,
        futureDoseCount: futureDoseCount,
      );
    }
  }

  final indexed = <(SchedulePlan, int)>[];
  var seq = 0;
  for (final line in lines) {
    final lineLogs = logsByLine[line.id] ?? const [];
    List<SchedulePlan> plans;
    if (line.kind == LineKind.oral) {
      plans = buildOralPlans(
        line: line,
        logs: lineLogs,
        now: now,
        horizonDays: horizonDays,
      );
    } else if (_isSyncedLine(line)) {
      final host = resolveHostLine(line, lines);
      if (host == null) continue;
      final hostPlans = hostPlansById[host.id] ?? const [];
      if (hostPlans.isEmpty) continue;
      plans = _buildSyncedPlans(
        line: line,
        hostPlans: hostPlans,
        logs: lineLogs,
        now: now,
        endAt: _earliestEnd(line.endedAt, host.endedAt),
        futureDoseCount: futureDoseCount,
      );
    } else {
      plans = hostPlansById[line.id] ??
          buildInjectionPlans(
            line: line,
            logs: lineLogs,
            now: now,
            futureDoseCount: futureDoseCount,
          );
    }
    for (final plan in plans) {
      indexed.add((plan, seq++));
    }
  }

  indexed.sort((a, b) {
    final c = a.$1.plannedAt.compareTo(b.$1.plannedAt);
    return c != 0 ? c : a.$2.compareTo(b.$2);
  });
  return [for (final item in indexed) item.$1];
}

SchedulePlan? selectNextPlan(List<SchedulePlan> plans, int now) {
  final actionable = plans
      .where((p) => p.status != PlanStatus.done && p.status != PlanStatus.missed)
      .toList();
  if (actionable.isEmpty) return null;

  final todayStart = _floorToDay(now);
  final todayEnd = todayStart + dayMs;

  for (final p in actionable) {
    if (p.plannedAt >= todayStart && p.plannedAt < todayEnd) return p;
  }

  final overdue = actionable.where((p) => p.plannedAt < todayStart).toList()
    ..sort((a, b) => b.plannedAt.compareTo(a.plannedAt));
  for (final p in overdue) {
    if (now - p.plannedAt <= _overdueActionableDays * dayMs) return p;
  }

  final upcoming = actionable.where((p) => p.plannedAt >= todayEnd).toList()
    ..sort((a, b) => a.plannedAt.compareTo(b.plannedAt));
  if (upcoming.isNotEmpty) return upcoming.first;

  return null;
}

SchedulePlan? nextDose({
  required List<TreatmentLine> lines,
  required List<DoseLog> logs,
  required int now,
  int? horizonDays,
  int? futureDoseCount,
}) =>
    selectNextPlan(
      buildSchedule(
        lines: lines,
        logs: logs,
        now: now,
        horizonDays: horizonDays,
        futureDoseCount: futureDoseCount,
      ),
      now,
    );

SchedulePlan? nextDoseForLine({
  required TreatmentLine line,
  required List<DoseLog> logs,
  required int now,
  int? horizonDays,
  int? futureDoseCount,
  TreatmentLine? Function(TreatmentLine line)? resolveHost,
  List<DoseLog>? hostLogs,
}) =>
    selectNextPlan(
      buildLineSchedule(
        line: line,
        logs: logs,
        now: now,
        horizonDays: horizonDays,
        futureDoseCount: futureDoseCount,
        resolveHost: resolveHost,
        hostLogs: hostLogs,
      ),
      now,
    );

double totalPlannedDoses(List<TreatmentPhase> phases) {
  for (final phase in phases) {
    _assertIntervalDays(phase.intervalDays);
  }
  var total = 0.0;
  for (final phase in phases) {
    if (phase.repeatCount == 0) return double.infinity;
    total += phase.repeatCount;
  }
  return total;
}

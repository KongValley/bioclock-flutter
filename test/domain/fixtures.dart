import 'package:bioclock/domain/schedule.dart';
import 'package:bioclock/models/types.dart';

const int day = dayMs;

/// 本地时区周一 00:00（2026-01-05 周一），避免跨时区测试偏移。
final int t0 = DateTime(2026, 1, 5).millisecondsSinceEpoch;

var _idSeq = 0;
String _nextId(String prefix) {
  _idSeq += 1;
  return '$prefix-$_idSeq';
}

TreatmentPhase makePhase({
  String? id,
  String lineId = 'line-host',
  required int orderIdx,
  PhaseKind kind = PhaseKind.maintenance,
  int intervalDays = 14,
  int repeatCount = 0,
  double? dose = 40,
  String unit = 'mg',
  int? effectiveFrom,
}) {
  return TreatmentPhase(
    id: id ?? _nextId('phase'),
    lineId: lineId,
    orderIdx: orderIdx,
    kind: kind,
    intervalDays: intervalDays,
    repeatCount: repeatCount,
    dose: dose,
    unit: unit,
    effectiveFrom: effectiveFrom,
  );
}

TreatmentLine makeInjectionLine({
  String id = 'line-host',
  String treatmentId = 'treat-1',
  String medicationId = 'med-1',
  String label = '阿达木单抗',
  bool isHost = true,
  bool syncWithHost = false,
  RegimenAnchor anchor = RegimenAnchor.actual,
  int windowDays = 2,
  int? endedAt,
  List<TreatmentPhase>? phases,
}) {
  return TreatmentLine(
    id: id,
    treatmentId: treatmentId,
    medicationId: medicationId,
    kind: LineKind.injection,
    label: label,
    isHost: isHost,
    syncWithHost: syncWithHost,
    anchor: anchor,
    windowDays: windowDays,
    endedAt: endedAt,
    phases: phases ?? [makePhase(lineId: id, orderIdx: 0)],
    oral: null,
  );
}

TreatmentLine makeOralLine({
  String id = 'line-oral',
  String treatmentId = 'treat-1',
  String medicationId = 'med-oral',
  String label = '甲氨蝶呤',
  int? endedAt,
  int? startDate,
  int? durationDays,
  OralFrequency frequency = OralFrequency.weekly,
  int timesPerPeriod = 1,
  List<int> daysOfWeek = const [1],
  String remindTime = '09:00',
}) {
  return TreatmentLine(
    id: id,
    treatmentId: treatmentId,
    medicationId: medicationId,
    kind: LineKind.oral,
    label: label,
    isHost: false,
    syncWithHost: false,
    anchor: RegimenAnchor.planned,
    windowDays: 0,
    endedAt: endedAt,
    phases: const [],
    oral: OralPlan(
      startDate: startDate ?? t0,
      durationDays: durationDays,
      frequency: frequency,
      timesPerPeriod: timesPerPeriod,
      daysOfWeek: daysOfWeek,
      remindTime: remindTime,
    ),
  );
}

DoseLog makeLog({
  String? id,
  String lineId = 'line-host',
  int? scheduledAt,
  int? takenAt,
  DoseStatus status = DoseStatus.done,
  double? dose = 40,
  String unit = 'mg',
  InjectionSite? site = InjectionSite.abdomenUl,
  int? createdAt,
}) {
  final ts = createdAt ?? takenAt ?? scheduledAt ?? t0;
  return DoseLog(
    id: id ?? _nextId('log'),
    lineId: lineId,
    scheduledAt: scheduledAt,
    takenAt: takenAt,
    status: status,
    dose: dose,
    unit: unit,
    site: site,
    lotNumber: null,
    note: null,
    createdAt: ts,
    updatedAt: ts,
  );
}

DoseLog injectionLog(double dayOffset, [String lineId = 'line-host']) {
  final ts = t0 + (dayOffset * day).round();
  return makeLog(lineId: lineId, scheduledAt: ts, takenAt: ts);
}

List<double> offsets(List<SchedulePlan> plans) =>
    [for (final p in plans) (p.plannedAt - t0) / day];

List<int> intOffsets(List<SchedulePlan> plans) =>
    [for (final p in plans) ((p.plannedAt - t0) / day).round()];

import 'package:bioclock/models/types.dart';

class PhaseDraft {
  const PhaseDraft({
    required this.orderIdx,
    required this.kind,
    required this.intervalDays,
    required this.repeatCount,
    required this.dose,
    required this.unit,
    required this.effectiveFrom,
  });

  final int orderIdx;
  final PhaseKind kind;
  final int intervalDays;
  final int repeatCount;
  final double? dose;
  final String unit;
  final int? effectiveFrom;

  TreatmentPhaseInput toInput() => TreatmentPhaseInput(
        orderIdx: orderIdx,
        kind: kind,
        intervalDays: intervalDays,
        repeatCount: repeatCount,
        dose: dose,
        unit: unit,
        effectiveFrom: effectiveFrom,
      );
}

void _assertInterval(int intervalDays) {
  if (intervalDays < 1 || intervalDays > 365) {
    throw ArgumentError('注射间隔必须是 1 到 365 之间的整数天');
  }
}

/// 从 `effectiveFrom` 起追加一个新的维持阶段；保留旧阶段以支持事后补录按旧间隔计算。
List<PhaseDraft> buildIntervalChangePhases(
  List<TreatmentPhase> phases,
  int newIntervalDays,
  int effectiveFrom,
) {
  _assertInterval(newIntervalDays);
  if (effectiveFrom <= 0) {
    throw ArgumentError('新间隔的生效时间不合法');
  }

  final sorted = [...phases]
    ..sort((a, b) => a.orderIdx.compareTo(b.orderIdx));
  if (sorted.isEmpty) throw StateError('这条用药线还没有阶段');
  if (sorted.any(
      (phase) => phase.kind != PhaseKind.maintenance && phase.effectiveFrom != null)) {
    throw StateError('负荷阶段不能设置生效时间');
  }

  final last = sorted.last;
  if (last.kind != PhaseKind.maintenance) {
    throw StateError('当前还在负荷阶段，请等进入维持阶段后再调整间隔');
  }

  final kept = sorted
      .where((phase) =>
          phase.effectiveFrom == null || phase.effectiveFrom! < effectiveFrom)
      .toList();
  final base = kept.isNotEmpty ? kept.last : sorted.first;

  return [
    for (var i = 0; i < kept.length; i += 1)
      PhaseDraft(
        orderIdx: i,
        kind: kept[i].kind,
        intervalDays: kept[i].intervalDays,
        repeatCount: kept[i].repeatCount,
        dose: kept[i].dose,
        unit: kept[i].unit,
        effectiveFrom: kept[i].effectiveFrom,
      ),
    PhaseDraft(
      orderIdx: kept.length,
      kind: PhaseKind.maintenance,
      intervalDays: newIntervalDays,
      repeatCount: 0,
      dose: base.dose,
      unit: base.unit,
      effectiveFrom: effectiveFrom,
    ),
  ];
}

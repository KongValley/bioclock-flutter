import 'package:bioclock/models/types.dart';

class PreviewPhase {
  const PreviewPhase({
    required this.kind,
    required this.intervalDays,
    required this.repeatCount,
    required this.dose,
    required this.unit,
  });

  final PhaseKind kind;
  final int intervalDays;
  final int repeatCount;
  final double? dose;
  final String unit;
}

class PhasePreviewDose {
  const PhasePreviewDose({
    required this.index,
    required this.dayOffset,
    required this.kind,
    required this.dose,
    required this.unit,
  });

  final int index;
  final int dayOffset;
  final PhaseKind kind;
  final double? dose;
  final String unit;
}

PreviewPhase? _phaseAt(List<PreviewPhase> phases, int index) {
  var remaining = index;
  for (final phase in phases) {
    if (phase.repeatCount == 0) return phase;
    if (remaining < phase.repeatCount) return phase;
    remaining -= phase.repeatCount;
  }
  return null;
}

List<PhasePreviewDose> buildPhasePreview(
  List<PreviewPhase> phases, {
  int max = 5,
}) {
  if (phases.isEmpty || max <= 0) return const [];

  final result = <PhasePreviewDose>[];
  var dayOffset = 0;
  for (var index = 0; result.length < max && index < 1000; index += 1) {
    final phase = _phaseAt(phases, index);
    if (phase == null) break;
    result.add(PhasePreviewDose(
      index: index,
      dayOffset: dayOffset,
      kind: phase.kind,
      dose: phase.dose,
      unit: phase.unit,
    ));
    final interval = phase.intervalDays > 0 ? phase.intervalDays : 1;
    dayOffset += interval;
  }
  return result;
}

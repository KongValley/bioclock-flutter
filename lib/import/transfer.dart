import 'package:bioclock/db/repo.dart';
import 'package:bioclock/domain/medication.dart';
import 'package:bioclock/export/transfer_schema.dart';
import 'package:bioclock/models/types.dart';

/// 全新设备导入换机文件时，先根据快照里的方案结构建出激活方案和用药线。
/// 若当前已有激活方案则跳过建线，交给常规导入合并记录。
Future<bool> ensureTreatmentFromTransfer(String text) async {
  final active = await TreatmentsRepo.getActive();
  if (active != null) return false;

  final transfer = parseTransferFile(text);
  TransferTreatment? template;
  for (final item in transfer.treatments) {
    if (item.isActive) {
      template = item;
      break;
    }
  }
  template ??= transfer.treatments.isNotEmpty ? transfer.treatments.first : null;
  if (template == null || template.lines.isEmpty) return false;

  var medications = await MedicationsRepo.list();
  Future<String?> resolveMedicationId(String medicationId) async {
    TransferMedication? source;
    for (final m in transfer.medications) {
      if (m.id == medicationId) {
        source = m;
        break;
      }
    }
    if (source == null) return null;

    final existing = findMedicationByName(medications, source.name);
    if (existing != null) return existing.id;

    final created = await MedicationsRepo.create(
      MedicationInput(
        name: source.name,
        genericName: source.genericName,
        brandNames: source.brandNames,
        defaultDose: source.defaultDose,
        unit: source.unit,
        color: source.color,
        route: source.route,
        diseaseIds: source.diseaseIds,
        catalogKey: source.catalogKey,
        isBuiltin: source.isBuiltin,
        extra: source.extra,
      ),
    );
    medications = [...medications, created];
    return created.id;
  }

  final lines = <TreatmentLineInput>[];
  for (final line in template.lines) {
    final medicationId = await resolveMedicationId(line.medicationId);
    if (medicationId == null) continue;
    final kind = line.kind == 'oral' ? LineKind.oral : LineKind.injection;
    lines.add(
      TreatmentLineInput(
        medicationId: medicationId,
        kind: kind,
        label: line.label,
        isHost: line.isHost,
        syncWithHost: line.syncWithHost,
        anchor:
            line.anchor == 'planned' ? RegimenAnchor.planned : RegimenAnchor.actual,
        windowDays: line.windowDays,
        endedAt: line.endedAt,
        phases: kind == LineKind.oral
            ? const []
            : [
                for (final phase in line.phases)
                  TreatmentPhaseInput(
                    orderIdx: phase.orderIdx,
                    kind: phase.kind == 'loading'
                        ? PhaseKind.loading
                        : PhaseKind.maintenance,
                    intervalDays: phase.intervalDays,
                    repeatCount: phase.repeatCount,
                    dose: phase.dose,
                    unit: phase.unit,
                    effectiveFrom: phase.effectiveFrom,
                  ),
              ],
        oral: kind == LineKind.oral && line.oral != null
            ? OralPlan(
                startDate: line.oral!.startDate,
                durationDays: line.oral!.durationDays,
                frequency: line.oral!.frequency == 'weekly'
                    ? OralFrequency.weekly
                    : line.oral!.frequency == 'custom'
                        ? OralFrequency.custom
                        : OralFrequency.daily,
                timesPerPeriod: line.oral!.timesPerPeriod,
                daysOfWeek: line.oral!.daysOfWeek,
                remindTime: line.oral!.remindTime,
              )
            : null,
      ),
    );
  }

  if (lines.isEmpty) return false;
  final created = await TreatmentsRepo.create(
    TreatmentInput(name: template.name, lines: lines),
  );
  await TreatmentsRepo.setActive(created.id, true);
  return true;
}

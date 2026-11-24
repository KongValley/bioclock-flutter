import 'dart:convert';
import 'dart:io';

import 'package:bioclock/db/repo.dart';
import 'package:bioclock/db/schema.dart';
import 'package:bioclock/domain/date_utils.dart';
import 'package:bioclock/export/transfer_schema.dart';
import 'package:bioclock/models/types.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class TransferExportCounts {
  const TransferExportCounts({
    required this.treatments,
    required this.lines,
    required this.doses,
    required this.symptoms,
    required this.efficacyEvents,
  });

  final int treatments;
  final int lines;
  final int doses;
  final int symptoms;
  final int efficacyEvents;
}

class TransferExportResult {
  const TransferExportResult({
    required this.path,
    required this.filename,
    required this.counts,
  });

  final String path;
  final String filename;
  final TransferExportCounts counts;
}

TransferLine _lineToTransfer(TreatmentLine line) {
  final phases = [...line.phases]
    ..sort((a, b) => a.orderIdx.compareTo(b.orderIdx));
  return TransferLine(
    id: line.id,
    medicationId: line.medicationId,
    kind: line.kind.wire,
    label: line.label,
    isHost: line.isHost,
    syncWithHost: line.syncWithHost,
    anchor: line.anchor.wire,
    windowDays: line.windowDays,
    endedAt: line.endedAt,
    phases: [
      for (final phase in phases)
        TransferPhase(
          orderIdx: phase.orderIdx,
          kind: phase.kind.wire,
          intervalDays: phase.intervalDays,
          repeatCount: phase.repeatCount,
          dose: phase.dose,
          unit: phase.unit,
          effectiveFrom: phase.effectiveFrom,
        ),
    ],
    oral: line.oral == null
        ? null
        : TransferOralPlan(
            startDate: line.oral!.startDate,
            durationDays: line.oral!.durationDays,
            frequency: line.oral!.frequency.wire,
            timesPerPeriod: line.oral!.timesPerPeriod,
            daysOfWeek: line.oral!.daysOfWeek,
            remindTime: line.oral!.remindTime,
          ),
  );
}

Future<TransferExportResult> exportTransferFile() async {
  final results = await Future.wait([
    TreatmentsRepo.list(),
    MedicationsRepo.list(),
    DoseLogsRepo.list(),
    SymptomsRepo.list(),
    EfficacyEventsRepo.list(),
    SymptomTagsRepo.list(),
    SettingsRepo.all(),
  ]);

  final allTreatments = results[0] as List<Treatment>;
  final allMedications = results[1] as List<Medication>;
  final allDoses = results[2] as List<DoseLog>;
  final allSymptoms = results[3] as List<SymptomLog>;
  final allEvents = results[4] as List<EfficacyEvent>;
  final allTags = results[5] as List<SymptomTag>;
  final allSettings = Map<String, String>.from(results[6] as AppSettings);

  final lineIds = <String>{};
  final transferTreatments = <TransferTreatment>[];
  for (final t in allTreatments) {
    for (final line in t.lines) {
      lineIds.add(line.id);
    }
    transferTreatments.add(
      TransferTreatment(
        id: t.id,
        name: t.name,
        isActive: t.isActive,
        createdAt: t.createdAt,
        lines: [for (final line in t.lines) _lineToTransfer(line)],
      ),
    );
  }

  final scopedDoses =
      allDoses.where((d) => lineIds.contains(d.lineId)).toList();
  final doseIndexById = <String, int>{};
  final transferDoses = <TransferDose>[];
  for (var i = 0; i < scopedDoses.length; i += 1) {
    final dose = scopedDoses[i];
    doseIndexById[dose.id] = i;
    transferDoses.add(
      TransferDose(
        lineId: dose.lineId,
        scheduledAt: dose.scheduledAt,
        takenAt: dose.takenAt,
        status: dose.status.wire,
        dose: dose.dose,
        unit: dose.unit.isEmpty ? null : dose.unit,
        site: dose.site?.wire,
        lotNumber: dose.lotNumber,
        note: dose.note,
        createdAt: dose.createdAt,
        updatedAt: dose.updatedAt,
      ),
    );
  }

  final reminders = <TransferReminder>[];
  for (final t in allTreatments) {
    final rule = await ReminderRulesRepo.getFor(t.id);
    if (rule != null) {
      reminders.add(
        TransferReminder(
          treatmentId: t.id,
          offsets: rule.offsets,
          timeOfDay: rule.timeOfDay,
          snoozeMinutes: rule.snoozeMinutes,
          enabled: rule.enabled,
        ),
      );
    }
  }

  // 换机不继承应用锁，避免新机无生物识别时被锁在门外
  allSettings.remove('app_lock');

  final scopedEvents = allEvents
      .where((e) => lineIds.contains(e.lineId))
      .map(
        (e) => TransferEfficacy(
          lineId: e.lineId,
          kind: e.kind.wire,
          occurredAt: e.occurredAt,
          dosesCount: e.dosesCount,
          note: e.note,
          createdAt: e.createdAt,
        ),
      )
      .toList();

  final transfer = TransferFile(
    format: transferFormat,
    version: transferVersion,
    schemaVersion: schemaVersion,
    exportedAt: DateTime.now().millisecondsSinceEpoch,
    app: 'BioClock',
    medications: [
      for (final m in allMedications)
        TransferMedication(
          id: m.id,
          name: m.name,
          genericName: m.genericName,
          brandNames: m.brandNames,
          defaultDose: m.defaultDose,
          unit: m.unit,
          color: m.color,
          route: m.route,
          diseaseIds: m.diseaseIds,
          catalogKey: m.catalogKey,
          isBuiltin: m.isBuiltin,
          extra: m.extra,
        ),
    ],
    treatments: transferTreatments,
    doseLogs: transferDoses,
    symptoms: [
      for (final s in allSymptoms)
        TransferSymptom(
          loggedAt: s.loggedAt,
          severity: s.severity,
          painScore: s.painScore,
          tags: s.tags,
          note: s.note,
          temperature: s.temperature,
          doseIndex:
              s.injectionId != null ? doseIndexById[s.injectionId!] : null,
        ),
    ],
    efficacyEvents: scopedEvents,
    symptomTags: [
      for (final tag in allTags)
        TransferTag(
          name: tag.name,
          isBuiltin: tag.isBuiltin,
          sortOrder: tag.sortOrder,
        ),
    ],
    reminders: reminders,
    settings: allSettings,
  );

  final dir = await getTemporaryDirectory();
  final filename =
      'bioclock-transfer-${formatLocalDate(DateTime.now().millisecondsSinceEpoch)}.json';
  final file = File(p.join(dir.path, filename));
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(transfer.toJson()),
    flush: true,
  );

  return TransferExportResult(
    path: file.path,
    filename: filename,
    counts: TransferExportCounts(
      treatments: transferTreatments.length,
      lines: lineIds.length,
      doses: transferDoses.length,
      symptoms: allSymptoms.length,
      efficacyEvents: scopedEvents.length,
    ),
  );
}

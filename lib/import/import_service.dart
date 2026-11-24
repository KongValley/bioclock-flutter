import 'dart:math' as math;

import 'package:bioclock/db/database.dart';
import 'package:bioclock/db/repo.dart';
import 'package:bioclock/domain/medication.dart';
import 'package:bioclock/import/import_schema.dart';
import 'package:bioclock/models/types.dart';

class ImportResult {
  const ImportResult({
    required this.injections,
    required this.oralLogs,
    required this.symptoms,
    required this.skipped,
    required this.skippedNoLine,
    required this.tags,
    required this.medicationsCreated,
    required this.linesCreated,
    required this.efficacyEvents,
  });

  final int injections;
  final int oralLogs;
  final int symptoms;
  final int skipped;
  final int skippedNoLine;
  final int tags;
  final int medicationsCreated;
  final int linesCreated;
  final int efficacyEvents;
}

const int _dayMs = 24 * 60 * 60 * 1000;

const List<String> _importMedicationColors = [
  '#2B6CB0',
  '#2C5282',
  '#C53030',
  '#2F855A',
  '#6B46C1',
  '#B7791F',
  '#4A5568',
];

class _PendingDoseLog {
  const _PendingDoseLog({
    required this.input,
    required this.time,
    required this.lineKey,
  });

  final DoseLogInput input;
  final int time;
  final String lineKey;
}

class _PendingLine {
  const _PendingLine({
    required this.key,
    required this.kind,
    required this.medicationId,
    required this.input,
  });

  final String key;
  final LineKind kind;
  final String medicationId;
  final TreatmentLineInput input;
}

class _TargetLine {
  const _TargetLine({
    required this.label,
    required this.kind,
    required this.medicationId,
    required this.key,
  });

  final String label;
  final LineKind kind;
  final String medicationId;
  final String key;
}

int _minuteKey(int timestamp) => (timestamp / 60000).floor();

int _logTimeOf(DoseLog log) => log.takenAt ?? log.scheduledAt ?? log.createdAt;

String _symptomKey(int loggedAt, int severity, List<String> tags) {
  final sorted = [...tags]..sort();
  return '${_minuteKey(loggedAt)}|$severity|${sorted.join('|')}';
}

MedicationInput _medicationCreateInput(ImportMedication entry, int index) {
  final color = _importMedicationColors[index % _importMedicationColors.length];
  final unit =
      (entry.unit != null && entry.unit!.trim().isNotEmpty) ? entry.unit! : 'mg';
  return MedicationInput(
    name: entry.name,
    genericName: entry.genericName,
    brandNames: entry.brandNames,
    defaultDose: entry.defaultDose,
    unit: unit,
    color: color,
    route: entry.route,
    diseaseIds: const [],
    catalogKey: entry.catalogKey,
    isBuiltin: false,
    extra: entry.extra,
  );
}

List<String> _mergeNames(List<String> current, List<String> incoming) {
  final result = [...current];
  for (final name in incoming) {
    if (!result.contains(name)) result.add(name);
  }
  return result;
}

MedicationPatch? _buildMergePatch(
  Medication existing,
  ImportMedication entry,
) {
  PatchValue<String?>? genericName;
  List<String>? brandNames;
  PatchValue<double?>? defaultDose;
  String? unit;
  var changed = false;

  if (!existing.isBuiltin) {
    if ((existing.genericName == null || existing.genericName!.isEmpty) &&
        entry.genericName != null) {
      genericName = PatchValue(entry.genericName);
      changed = true;
    }
    final mergedBrands = _mergeNames(existing.brandNames, entry.brandNames);
    if (mergedBrands.length != existing.brandNames.length) {
      brandNames = mergedBrands;
      changed = true;
    }
  }
  if (existing.defaultDose == null && entry.defaultDose != null) {
    defaultDose = PatchValue(entry.defaultDose);
    changed = true;
  }
  if (existing.unit.trim().isEmpty &&
      entry.unit != null &&
      entry.unit!.trim().isNotEmpty) {
    unit = entry.unit;
    changed = true;
  }

  if (!changed) return null;
  return MedicationPatch(
    genericName: genericName,
    brandNames: brandNames,
    defaultDose: defaultDose,
    unit: unit,
  );
}

Medication? _findById(List<Medication> medications, String id) {
  for (final m in medications) {
    if (m.id == id) return m;
  }
  return null;
}

int _dayStart(int timestamp) {
  final d = DateTime.fromMillisecondsSinceEpoch(timestamp);
  return DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
}

int _inferInterval(List<int> times) {
  if (times.length < 2) return 28;
  final sorted = [...times]..sort();
  final gaps = <double>[];
  for (var i = 1; i < sorted.length; i += 1) {
    final days = (sorted[i] - sorted[i - 1]) / _dayMs;
    if (days >= 0.5 && days <= 365) gaps.add(days);
  }
  if (gaps.isEmpty) return 28;
  gaps.sort();
  return math.max(1, gaps[gaps.length ~/ 2].round());
}

Future<ImportResult> _executeImport(
  ImportPayload payload, {
  required bool dryRun,
}) async {
  final hasDoseRecords =
      payload.injections.isNotEmpty || payload.oralLogs.isNotEmpty;

  final results = await Future.wait([
    MedicationsRepo.list(),
    TreatmentsRepo.list(),
    DoseLogsRepo.list(),
    SymptomsRepo.list(),
    SymptomTagsRepo.list(),
    EfficacyEventsRepo.list(),
  ]);

  final allMedications = results[0] as List<Medication>;
  final allTreatments = results[1] as List<Treatment>;
  final allLogs = results[2] as List<DoseLog>;
  final allSymptoms = results[3] as List<SymptomLog>;
  final allTags = results[4] as List<SymptomTag>;
  final allEvents = results[5] as List<EfficacyEvent>;

  Treatment? active;
  for (final t in allTreatments) {
    if (t.isActive) {
      active = t;
      break;
    }
  }
  if (hasDoseRecords && active == null) {
    throw const ImportValidationException(
      '还没有治疗方案：请先完成设置（病种 / 药物 / 方案），再导入注射或口服记录',
    );
  }

  // ---- 合并药物 ----
  var workingMedications = List<Medication>.from(allMedications);
  final medicationPatches = <({String id, MedicationPatch patch})>[];
  final medicationCreates = <MedicationInput>[];
  final pendingMedicationIndex = <String, int>{};

  for (final entry in payload.medications) {
    final existing = findMedicationByName(workingMedications, entry.name);
    if (existing != null) {
      if (existing.id.startsWith('__import_')) {
        final idx = pendingMedicationIndex[existing.id];
        if (idx != null) {
          final current = medicationCreates[idx];
          final merged = MedicationInput(
            name: current.name,
            genericName: current.genericName ?? entry.genericName,
            brandNames: _mergeNames(current.brandNames, entry.brandNames),
            defaultDose: current.defaultDose ?? entry.defaultDose,
            unit: current.unit.isNotEmpty
                ? current.unit
                : (entry.unit ?? 'mg'),
            color: current.color,
            route: current.route,
            diseaseIds: current.diseaseIds,
            catalogKey: current.catalogKey,
            isBuiltin: false,
            extra: {...current.extra, ...entry.extra},
          );
          medicationCreates[idx] = merged;
          workingMedications = [
            for (final m in workingMedications)
              if (m.id == existing.id)
                Medication(
                  id: m.id,
                  name: merged.name,
                  genericName: merged.genericName,
                  brandNames: merged.brandNames,
                  defaultDose: merged.defaultDose,
                  unit: merged.unit,
                  color: merged.color,
                  route: merged.route,
                  diseaseIds: merged.diseaseIds,
                  catalogKey: merged.catalogKey,
                  isBuiltin: false,
                  extra: merged.extra,
                  createdAt: 0,
                )
              else
                m,
          ];
        }
        continue;
      }

      final patch = _buildMergePatch(existing, entry);
      if (patch != null) {
        medicationPatches.add((id: existing.id, patch: patch));
        workingMedications = [
          for (final m in workingMedications)
            if (m.id == existing.id)
              Medication(
                id: m.id,
                name: m.name,
                genericName:
                    patch.genericName != null ? patch.genericName!.value : m.genericName,
                brandNames: patch.brandNames ?? m.brandNames,
                defaultDose:
                    patch.defaultDose != null ? patch.defaultDose!.value : m.defaultDose,
                unit: patch.unit ?? m.unit,
                color: m.color,
                route: m.route,
                diseaseIds: m.diseaseIds,
                catalogKey: m.catalogKey,
                isBuiltin: m.isBuiltin,
                extra: m.extra,
                createdAt: m.createdAt,
              )
            else
              m,
        ];
      }
    } else {
      final input = _medicationCreateInput(entry, medicationCreates.length);
      medicationCreates.add(input);
      final placeholderId = '__import_${medicationCreates.length}';
      pendingMedicationIndex[placeholderId] = medicationCreates.length - 1;
      workingMedications.add(
        Medication(
          id: placeholderId,
          name: input.name,
          genericName: input.genericName,
          brandNames: input.brandNames,
          defaultDose: input.defaultDose,
          unit: input.unit,
          color: input.color,
          route: input.route,
          diseaseIds: input.diseaseIds,
          catalogKey: input.catalogKey,
          isBuiltin: false,
          extra: input.extra,
          createdAt: 0,
        ),
      );
    }
  }

  // ---- 用药线 ----
  final existingLines = active?.lines ?? const <TreatmentLine>[];
  final existingInjectionLines =
      existingLines.where((l) => l.kind == LineKind.injection).toList();
  final existingOralLines =
      existingLines.where((l) => l.kind == LineKind.oral).toList();

  final lineByMedication = <String, TreatmentLine>{
    for (final line in existingLines)
      '${line.kind.wire}:${line.medicationId}': line,
  };

  final pendingLines = <_PendingLine>[];
  final pendingLineByKey = <String, _PendingLine>{};

  bool hasHost() =>
      existingInjectionLines.any((l) => l.isHost) ||
      pendingLines.any((l) => l.kind == LineKind.injection && l.input.isHost);

  List<int> injectionTimesFor(String medicationId) => payload.injections
      .where((row) =>
          row.medicationName != null &&
          findMedicationByName(workingMedications, row.medicationName!)?.id ==
              medicationId)
      .map((row) => row.injectedAt)
      .toList();

  List<int> oralTimesFor(String medicationId) => payload.oralLogs
      .where((row) =>
          row.medicationName != null &&
          findMedicationByName(workingMedications, row.medicationName!)?.id ==
              medicationId)
      .map((row) => row.takenAt)
      .toList();

  void assertRecordAllowed(
    TreatmentLine line, {
    required DoseStatus status,
    required int eventAt,
    int? scheduledAt,
  }) {
    final time = resolveImportLogTime(
      status: status,
      eventAt: eventAt,
      scheduledAt: scheduledAt,
    );
    if (!payload.preserveEndedLines &&
        line.endedAt != null &&
        time > line.endedAt!) {
      throw ImportValidationException(
        '用药线「${line.label}」已停用，停用后的记录请先恢复该用药线再导入',
      );
    }
  }

  String ensureLine(
    LineKind kind,
    Medication medication, {
    required DoseStatus status,
    required int eventAt,
    int? scheduledAt,
  }) {
    final key = '${kind.wire}:${medication.id}';
    final existing = lineByMedication[key];
    if (existing != null) {
      assertRecordAllowed(
        existing,
        status: status,
        eventAt: eventAt,
        scheduledAt: scheduledAt,
      );
      return 'existing:${existing.id}';
    }

    final pending = pendingLineByKey[key];
    if (pending != null) return pending.key;

    final TreatmentLineInput input;
    if (kind == LineKind.injection) {
      final times = injectionTimesFor(medication.id);
      final interval = _inferInterval(times);
      final matching = payload.injections
          .where((row) =>
              row.medicationName != null &&
              findMedicationByName(workingMedications, row.medicationName!)
                      ?.id ==
                  medication.id)
          .toList()
        ..sort((a, b) => b.injectedAt.compareTo(a.injectedAt));
      final latest = matching.isEmpty ? null : matching.first;
      final isHost = !hasHost();
      input = TreatmentLineInput(
        medicationId: medication.id,
        kind: LineKind.injection,
        label: medication.name,
        isHost: isHost,
        syncWithHost: false,
        anchor: RegimenAnchor.actual,
        windowDays: 2,
        phases: [
          TreatmentPhaseInput(
            orderIdx: 0,
            kind: PhaseKind.maintenance,
            intervalDays: interval,
            repeatCount: 0,
            dose: latest?.dose ?? medication.defaultDose,
            unit: latest?.unit ?? medication.unit,
          ),
        ],
        oral: null,
      );
    } else {
      final times = oralTimesFor(medication.id)..sort();
      final earliest =
          times.isNotEmpty ? times.first : DateTime.now().millisecondsSinceEpoch;
      input = TreatmentLineInput(
        medicationId: medication.id,
        kind: LineKind.oral,
        label: medication.name,
        isHost: false,
        syncWithHost: false,
        anchor: RegimenAnchor.actual,
        windowDays: 2,
        phases: const [],
        oral: OralPlan(
          startDate: _dayStart(earliest),
          durationDays: null,
          frequency: OralFrequency.daily,
          timesPerPeriod: 1,
          daysOfWeek: const [],
          remindTime: '09:00',
        ),
      );
    }

    final created = _PendingLine(
      key: 'new:${kind.wire}:${medication.id}',
      kind: kind,
      medicationId: medication.id,
      input: input,
    );
    pendingLines.add(created);
    pendingLineByKey[key] = created;
    return created.key;
  }

  ({String? lineKey, Medication? medication}) resolveLine(
    LineKind kind, {
    required String? lineLabel,
    required String? medicationName,
    required DoseStatus status,
    required int eventAt,
    int? scheduledAt,
  }) {
    final lines =
        kind == LineKind.injection ? existingInjectionLines : existingOralLines;
    if (lineLabel != null) {
      for (final line in lines) {
        if (line.label == lineLabel) {
          assertRecordAllowed(
            line,
            status: status,
            eventAt: eventAt,
            scheduledAt: scheduledAt,
          );
          return (
            lineKey: 'existing:${line.id}',
            medication: _findById(workingMedications, line.medicationId),
          );
        }
      }
    }

    if (medicationName != null) {
      final medication =
          findMedicationByName(workingMedications, medicationName);
      if (medication == null) return (lineKey: null, medication: null);
      final key = ensureLine(
        kind,
        medication,
        status: status,
        eventAt: eventAt,
        scheduledAt: scheduledAt,
      );
      return (lineKey: key, medication: medication);
    }

    final running = lines.where((l) => l.endedAt == null).toList();
    TreatmentLine? host;
    if (kind == LineKind.injection) {
      for (final l in running) {
        if (l.isHost) {
          host = l;
          break;
        }
      }
      host ??= running.isNotEmpty ? running.first : null;
    } else {
      host = running.isNotEmpty ? running.first : null;
    }
    return host != null
        ? (
            lineKey: 'existing:${host.id}',
            medication: _findById(workingMedications, host.medicationId),
          )
        : (lineKey: null, medication: null);
  }

  // ---- 记录去重 ----
  final existingLogKeys = {
    for (final log in allLogs) '${_minuteKey(_logTimeOf(log))}|${log.lineId}',
  };
  final existingLogIdByTime = {
    for (final log in allLogs) _minuteKey(_logTimeOf(log)): log.id,
  };

  final pendingLogs = <_PendingDoseLog>[];
  var injections = 0;
  var oralLogs = 0;
  var skipped = 0;
  var skippedNoLine = 0;

  for (final row in payload.injections) {
    final resolved = resolveLine(
      LineKind.injection,
      lineLabel: row.lineLabel,
      medicationName: row.medicationName,
      status: row.status,
      eventAt: row.injectedAt,
      scheduledAt: row.scheduledAt,
    );
    if (resolved.lineKey == null) {
      skippedNoLine += 1;
      continue;
    }
    final lineKey = resolved.lineKey!;
    final storedAt = resolveImportLogTime(
      status: row.status,
      eventAt: row.injectedAt,
      scheduledAt: row.scheduledAt,
    );
    final rawId = lineKey.startsWith('existing:')
        ? lineKey.substring('existing:'.length)
        : lineKey;
    final key = '${_minuteKey(storedAt)}|$rawId';
    if (!existingLogKeys.add(key)) {
      skipped += 1;
      continue;
    }

    pendingLogs.add(_PendingDoseLog(
      time: storedAt,
      lineKey: lineKey,
      input: DoseLogInput(
        lineId: lineKey,
        scheduledAt:
            row.scheduledAt ?? (row.status == DoseStatus.done ? null : row.injectedAt),
        takenAt: row.status == DoseStatus.done ? row.injectedAt : null,
        status: row.status,
        dose: row.dose,
        unit: row.unit ?? resolved.medication?.unit ?? 'mg',
        site: row.site,
        lotNumber: row.lotNumber,
        note: row.note,
      ),
    ));
    injections += 1;
  }

  for (final row in payload.oralLogs) {
    final resolved = resolveLine(
      LineKind.oral,
      lineLabel: row.lineLabel,
      medicationName: row.medicationName,
      status: row.status,
      eventAt: row.takenAt,
      scheduledAt: row.scheduledAt,
    );
    if (resolved.lineKey == null) {
      skippedNoLine += 1;
      continue;
    }
    final lineKey = resolved.lineKey!;
    final storedAt = resolveImportLogTime(
      status: row.status,
      eventAt: row.takenAt,
      scheduledAt: row.scheduledAt,
    );
    final rawId = lineKey.startsWith('existing:')
        ? lineKey.substring('existing:'.length)
        : lineKey;
    final key = '${_minuteKey(storedAt)}|$rawId';
    if (!existingLogKeys.add(key)) {
      skipped += 1;
      continue;
    }

    pendingLogs.add(_PendingDoseLog(
      time: storedAt,
      lineKey: lineKey,
      input: DoseLogInput(
        lineId: lineKey,
        scheduledAt:
            row.scheduledAt ?? (row.status == DoseStatus.done ? null : row.takenAt),
        takenAt: row.status == DoseStatus.done ? row.takenAt : null,
        status: row.status,
        dose: row.dose,
        unit: row.unit ?? resolved.medication?.unit,
        site: null,
        lotNumber: null,
        note: row.note,
      ),
    ));
    oralLogs += 1;
  }

  // ---- 症状 & 标签 ----
  final existingSymptomKeys = {
    for (final s in allSymptoms) _symptomKey(s.loggedAt, s.severity, s.tags),
  };
  final pendingSymptoms = <ImportSymptom>[];
  for (final row in payload.symptoms) {
    final key = _symptomKey(row.loggedAt, row.severity, row.tags);
    if (!existingSymptomKeys.add(key)) {
      skipped += 1;
      continue;
    }
    pendingSymptoms.add(row);
  }

  final tagSet = {for (final t in allTags) t.name.toLowerCase()};
  var tags = 0;
  for (final row in payload.symptoms) {
    for (final tag in row.tags) {
      if (tagSet.add(tag.toLowerCase())) tags += 1;
    }
  }
  for (final name in payload.symptomTags ?? const <String>[]) {
    if (tagSet.add(name.toLowerCase())) tags += 1;
  }

  // ---- 用药线状态 & 疗效事件 ----
  final targets = <_TargetLine>[
    for (final l in existingLines)
      _TargetLine(
        label: l.label,
        kind: l.kind,
        medicationId: l.medicationId,
        key: 'existing:${l.id}',
      ),
    for (final p in pendingLines)
      _TargetLine(
        label: p.input.label,
        kind: p.input.kind,
        medicationId: p.input.medicationId,
        key: p.key,
      ),
  ];

  _TargetLine? findTarget(
    String? lineLabel,
    String? medicationName, [
    LineKind? kind,
  ]) {
    final candidates = targets
        .where((line) => kind == null || line.kind == kind)
        .toList();
    final medication = medicationName != null
        ? findMedicationByName(workingMedications, medicationName)
        : null;
    if (lineLabel != null) {
      for (final c in candidates) {
        if (c.label == lineLabel) return c;
      }
    }
    if (medication != null) {
      for (final c in candidates) {
        if (c.medicationId == medication.id) return c;
      }
    }
    return null;
  }

  final pendingStates = <({String key, int? endedAt})>[];
  for (final state in payload.lineStates) {
    final target =
        findTarget(state.lineLabel, state.medicationName, state.kind);
    if (target != null) {
      pendingStates.add((key: target.key, endedAt: state.endedAt));
    }
  }

  final seenEvents = {
    for (final e in allEvents)
      'existing:${e.lineId}|${e.kind.wire}|${_minuteKey(e.occurredAt)}',
  };
  final pendingEvents = <({ImportEfficacyEvent event, String key})>[];
  for (final event in payload.efficacyEvents) {
    final target = findTarget(event.lineLabel, event.medicationName);
    if (target == null) continue;
    final key =
        '${target.key}|${event.kind.wire}|${_minuteKey(event.occurredAt)}';
    if (!seenEvents.add(key)) continue;
    pendingEvents.add((event: event, key: target.key));
  }

  if (!dryRun) {
    final logIdByTime = <int, String>{};
    final lineIdByKey = <String, String>{
      for (final line in existingLines) 'existing:${line.id}': line.id,
    };

    await AppDatabase.runInTransaction((txn) async {
      for (final input in medicationCreates) {
        await MedicationsRepo.create(input, executor: txn);
      }

      final createdMedications = await MedicationsRepo.list(executor: txn);
      final createdMedByName = <String, String>{
        for (final m in createdMedications)
          normalizeMedicationName(m.name): m.id,
      };
      String resolveMedicationId(String medicationId) {
        if (!medicationId.startsWith('__import_')) return medicationId;
        final idx = pendingMedicationIndex[medicationId];
        if (idx == null) return medicationId;
        final name = medicationCreates[idx].name;
        return createdMedByName[normalizeMedicationName(name)] ?? medicationId;
      }

      for (final item in medicationPatches) {
        await MedicationsRepo.update(item.id, item.patch, executor: txn);
      }

      if (pendingLines.isNotEmpty && active != null) {
        for (final pending in pendingLines) {
          final created = await TreatmentsRepo.addLine(
            active.id,
            TreatmentLineInput(
              medicationId: resolveMedicationId(pending.input.medicationId),
              kind: pending.input.kind,
              label: pending.input.label,
              isHost: pending.input.isHost,
              syncWithHost: pending.input.syncWithHost,
              anchor: pending.input.anchor,
              windowDays: pending.input.windowDays,
              endedAt: pending.input.endedAt,
              phases: pending.input.phases,
              oral: pending.input.oral,
            ),
            executor: txn,
          );
          lineIdByKey[pending.key] = created.id;
        }
      }

      for (final pending in pendingLogs) {
        final lineId = lineIdByKey[pending.lineKey];
        if (lineId == null) {
          throw const ImportValidationException('导入时找不到对应的用药线');
        }
        final created = await DoseLogsRepo.create(
          DoseLogInput(
            lineId: lineId,
            scheduledAt: pending.input.scheduledAt,
            takenAt: pending.input.takenAt,
            status: pending.input.status,
            dose: pending.input.dose,
            unit: pending.input.unit,
            site: pending.input.site,
            lotNumber: pending.input.lotNumber,
            note: pending.input.note,
          ),
          executor: txn,
        );
        logIdByTime[_minuteKey(pending.time)] = created.id;
      }

      for (final row in pendingSymptoms) {
        final injectionId = row.injectionAt == null
            ? null
            : (logIdByTime[_minuteKey(row.injectionAt!)] ??
                existingLogIdByTime[_minuteKey(row.injectionAt!)]);
        await SymptomsRepo.create(
          SymptomLogInput(
            loggedAt: row.loggedAt,
            severity: row.severity,
            painScore: row.painScore,
            tags: row.tags,
            temperature: row.temperature,
            note: row.note,
            injectionId: injectionId,
          ),
          executor: txn,
        );
      }

      for (final row in payload.symptoms) {
        for (final tag in row.tags) {
          await SymptomTagsRepo.ensure(tag, executor: txn);
        }
      }
      for (final name in payload.symptomTags ?? const <String>[]) {
        await SymptomTagsRepo.ensure(name, executor: txn);
      }

      for (final state in pendingStates) {
        final lineId = lineIdByKey[state.key];
        if (lineId == null) {
          throw const ImportValidationException('导入时找不到对应的用药线');
        }
        await txn.rawUpdate(
          'UPDATE treatment_line SET ended_at = ? WHERE id = ?',
          [state.endedAt, lineId],
        );
      }

      for (final item in pendingEvents) {
        final lineId = lineIdByKey[item.key];
        if (lineId == null) {
          throw const ImportValidationException('导入时找不到对应的用药线');
        }
        await EfficacyEventsRepo.create(
          EfficacyEventInput(
            lineId: lineId,
            kind: item.event.kind,
            occurredAt: item.event.occurredAt,
            note: item.event.note,
            stopLine: false,
          ),
          executor: txn,
        );
      }
    });
  }

  return ImportResult(
    injections: injections,
    oralLogs: oralLogs,
    symptoms: pendingSymptoms.length,
    skipped: skipped,
    skippedNoLine: skippedNoLine,
    tags: tags,
    medicationsCreated: medicationCreates.length,
    linesCreated: pendingLines.length,
    efficacyEvents: pendingEvents.length,
  );
}

Future<ImportResult> importPayload(ImportPayload payload) =>
    _executeImport(payload, dryRun: false);

Future<ImportResult> previewImport(ImportPayload payload) =>
    _executeImport(payload, dryRun: true);

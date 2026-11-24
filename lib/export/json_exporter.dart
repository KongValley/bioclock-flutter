import 'dart:convert';
import 'dart:io';

import 'package:bioclock/db/repo.dart';
import 'package:bioclock/domain/date_utils.dart';
import 'package:bioclock/domain/rotation.dart';
import 'package:bioclock/export/csv_exporter.dart';
import 'package:bioclock/import/import_schema.dart';
import 'package:bioclock/models/types.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

int _logTime(DoseLog log) => log.takenAt ?? log.scheduledAt ?? log.createdAt;

/// 纯函数构建可再次导入的 v3 JSON 字符串。
String buildExportJsonString({
  required List<Treatment> treatments,
  required List<Medication> medications,
  required List<SymptomLog> symptoms,
  required List<DoseLog> doseLogs,
  required List<EfficacyEvent> efficacyEvents,
  int? nowMs,
}) {
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final medById = {for (final m in medications) m.id: m};
  final lineById = <String, TreatmentLine>{
    for (final t in treatments)
      for (final l in t.lines) l.id: l,
  };
  final scopedLogs =
      doseLogs.where((log) => lineById.containsKey(log.lineId)).toList();
  final logById = {for (final l in scopedLogs) l.id: l};
  final sortedLogs = [...scopedLogs]
    ..sort((a, b) => _logTime(a).compareTo(_logTime(b)));

  final medicationsPayload = [
    for (final m in medications)
      {
        'name': m.name,
        'genericName': m.genericName,
        'brandNames': m.brandNames,
        'route': m.route.wire,
        'defaultDose': m.defaultDose,
        'unit': m.unit,
        'catalogKey': m.catalogKey,
        'extra': m.extra,
      },
  ];

  final injections = [
    for (final log in sortedLogs)
      if (lineById[log.lineId]?.kind == LineKind.injection)
        () {
          final line = lineById[log.lineId]!;
          final med = medById[line.medicationId];
          final map = <String, dynamic>{
            'injectedAt': formatLocalDateTime(_logTime(log)),
            'medication': med?.name ?? line.label,
            'dose': log.dose,
            'unit': log.unit.isNotEmpty ? log.unit : med?.unit,
            'lotNumber': log.lotNumber,
            'note': log.note,
            'status': log.status.wire,
            'lineLabel': line.label,
          };
          if (log.site != null) {
            map['site'] = siteLabels[log.site!];
          }
          return map;
        }(),
  ];

  final oralLogs = [
    for (final log in sortedLogs)
      if (lineById[log.lineId]?.kind == LineKind.oral)
        () {
          final line = lineById[log.lineId]!;
          final med = medById[line.medicationId];
          return {
            'takenAt': formatLocalDateTime(_logTime(log)),
            'medication': med?.name ?? line.label,
            'status': log.status.wire,
            'dose': log.dose,
            'unit': log.unit.isNotEmpty ? log.unit : null,
            'note': log.note,
            'lineLabel': line.label,
          };
        }(),
  ];

  final sortedSymptoms = [...symptoms]
    ..sort((a, b) => a.loggedAt.compareTo(b.loggedAt));
  final symptomsPayload = [
    for (final symptom in sortedSymptoms)
      () {
        final linked = symptom.injectionId != null
            ? logById[symptom.injectionId!]
            : null;
        return {
          'loggedAt': formatLocalDateTime(symptom.loggedAt),
          'severity': symptom.severity,
          'painScore': symptom.painScore,
          'tags': symptom.tags,
          'temperature': symptom.temperature,
          'note': symptom.note,
          'injectionAt':
              linked != null ? formatLocalDateTime(_logTime(linked)) : null,
        };
      }(),
  ];

  final lineStates = [
    for (final line in lineById.values)
      {
        'lineLabel': line.label,
        'medication': medById[line.medicationId]?.name ?? line.label,
        'kind': line.kind.wire,
        'endedAt': line.endedAt == null ? null : formatLocalDateTime(line.endedAt!),
      },
  ];

  final efficacyPayload = [
    for (final event in efficacyEvents)
      if (lineById.containsKey(event.lineId))
        () {
          final line = lineById[event.lineId]!;
          final med = medById[line.medicationId];
          return {
            'lineLabel': line.label,
            'medication': med?.name ?? line.label,
            'kind': event.kind.wire,
            'occurredAt': formatLocalDateTime(event.occurredAt),
            'note': event.note,
          };
        }(),
  ];

  final payload = {
    'format': importFormat,
    'version': importVersion,
    'exportedAt': formatLocalDateTime(now),
    'medications': medicationsPayload,
    'injections': injections,
    'symptoms': symptomsPayload,
    'oralLogs': oralLogs,
    'lineStates': lineStates,
    'efficacyEvents': efficacyPayload,
  };
  return const JsonEncoder.withIndent('  ').convert(payload);
}

Future<ExportFileOutput> exportJson() async {
  final results = await Future.wait([
    TreatmentsRepo.list(),
    MedicationsRepo.list(),
    SymptomsRepo.list(),
    DoseLogsRepo.list(),
    EfficacyEventsRepo.list(),
  ]);
  final content = buildExportJsonString(
    treatments: results[0] as List<Treatment>,
    medications: results[1] as List<Medication>,
    symptoms: results[2] as List<SymptomLog>,
    doseLogs: results[3] as List<DoseLog>,
    efficacyEvents: results[4] as List<EfficacyEvent>,
  );

  final dir = await getTemporaryDirectory();
  final filename =
      'bioclock-${formatLocalDate(DateTime.now().millisecondsSinceEpoch)}.json';
  final file = File(p.join(dir.path, filename));
  await file.writeAsString(content, flush: true);
  return ExportFileOutput(path: file.path, filename: filename);
}

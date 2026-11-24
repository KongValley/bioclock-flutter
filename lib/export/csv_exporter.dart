import 'dart:convert';
import 'dart:io';

import 'package:bioclock/db/repo.dart';
import 'package:bioclock/domain/date_utils.dart';
import 'package:bioclock/domain/rotation.dart';
import 'package:bioclock/domain/schedule.dart';
import 'package:bioclock/i18n/zh.dart';
import 'package:bioclock/models/types.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ExportFileOutput {
  const ExportFileOutput({required this.path, required this.filename});
  final String path;
  final String filename;
}

int _logTime(DoseLog log) => log.takenAt ?? log.scheduledAt ?? log.createdAt;

String _escapeCsvField(String value) {
  if (value.contains('"') ||
      value.contains(',') ||
      value.contains('\r') ||
      value.contains('\n')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

/// 纯函数构建 CSV 文本（带 UTF-8 BOM）。
String buildCsvContent({
  required List<Treatment> treatments,
  required List<Medication> medications,
  required List<DoseLog> doseLogs,
  int? nowMs,
}) {
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final medById = {for (final m in medications) m.id: m};
  final lineById = <String, TreatmentLine>{
    for (final t in treatments)
      for (final l in t.lines) l.id: l,
  };

  final planByLogId = <String, SchedulePlan>{};
  for (final t in treatments) {
    final plans = buildSchedule(lines: t.lines, logs: doseLogs, now: now);
    for (final plan in plans) {
      if (plan.doseLogId != null) {
        planByLogId[plan.doseLogId!] = plan;
      }
    }
  }

  final rows = doseLogs
      .where((log) => lineById[log.lineId]?.kind == LineKind.injection)
      .toList()
    ..sort((a, b) => _logTime(a).compareTo(_logTime(b)));

  final lines = <List<String>>[
    [
      '注射日期时间',
      '药名',
      '通用名',
      '剂量',
      '单位',
      '部位',
      '批号',
      '备注',
      '计划时间',
      '偏差天数',
      Zh.report.status,
    ],
  ];

  for (final log in rows) {
    final line = lineById[log.lineId];
    final med = line != null ? medById[line.medicationId] : null;
    final plan = planByLogId[log.id];
    final isInfusion = med?.route == MedicationRoute.iv;
    lines.add([
      formatLocalDateTime(_logTime(log)),
      med?.name ?? line?.label ?? '',
      med?.genericName ?? '',
      log.dose == null ? '' : _formatNum(log.dose!),
      log.unit.isNotEmpty ? log.unit : (med?.unit ?? ''),
      isInfusion || log.site == null ? '' : (siteLabels[log.site!] ?? ''),
      log.lotNumber ?? '',
      log.note ?? '',
      plan != null ? formatLocalDateTime(plan.plannedAt) : '',
      plan?.deviationDays != null ? plan!.deviationDays!.toStringAsFixed(1) : '',
      Zh.doseStatusLabel(log.status),
    ]);
  }

  final csv =
      lines.map((row) => row.map(_escapeCsvField).join(',')).join('\r\n');
  return '\uFEFF$csv';
}

String _formatNum(double v) =>
    v == v.truncateToDouble() ? v.toInt().toString() : v.toString();

Future<ExportFileOutput> exportCsv() async {
  final results = await Future.wait([
    TreatmentsRepo.list(),
    MedicationsRepo.list(),
    DoseLogsRepo.list(),
  ]);
  final content = buildCsvContent(
    treatments: results[0] as List<Treatment>,
    medications: results[1] as List<Medication>,
    doseLogs: results[2] as List<DoseLog>,
  );

  final dir = await getTemporaryDirectory();
  final filename = 'bioclock-${formatLocalDate(DateTime.now().millisecondsSinceEpoch)}.csv';
  final file = File(p.join(dir.path, filename));
  await file.writeAsBytes(utf8.encode(content), flush: true);
  return ExportFileOutput(path: file.path, filename: filename);
}

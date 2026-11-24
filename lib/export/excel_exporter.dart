import 'dart:io';
import 'dart:typed_data';

import 'package:bioclock/db/repo.dart';
import 'package:bioclock/domain/date_utils.dart';
import 'package:bioclock/domain/rotation.dart';
import 'package:bioclock/export/csv_exporter.dart';
import 'package:bioclock/models/types.dart';
import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const Map<MedicationRoute, String> _routeLabels = {
  MedicationRoute.sc: '皮下注射',
  MedicationRoute.iv: '静脉输注',
  MedicationRoute.oral: '口服',
};

const Map<DoseStatus, String> _statusLabels = {
  DoseStatus.done: '已用',
  DoseStatus.skipped: '跳过',
  DoseStatus.missed: '漏用',
};

const Map<LineKind, String> _kindLabels = {
  LineKind.injection: '注射',
  LineKind.oral: '口服',
};

int _logTime(DoseLog log) => log.takenAt ?? log.scheduledAt ?? log.createdAt;

String _describeOral(TreatmentLine line) {
  if (line.kind != LineKind.oral || line.oral == null) return '';
  final oral = line.oral!;
  const dayNames = ['日', '一', '二', '三', '四', '五', '六'];
  final freq = oral.frequency == OralFrequency.daily
      ? '每天'
      : oral.frequency == OralFrequency.weekly
          ? '每周 ${oral.timesPerPeriod} 次'
          : '每周 ${oral.daysOfWeek.map((d) => dayNames[d]).join('、')}';
  final duration =
      oral.durationDays == null ? '长期' : '${oral.durationDays} 天';
  return '$freq ${oral.remindTime}（$duration）';
}

CellValue? _textOrNull(String? v) =>
    v == null || v.isEmpty ? null : TextCellValue(v);
CellValue? _numOrNull(double? v) => v == null ? null : DoubleCellValue(v);

/// 纯函数构建 5 张工作表的 `.xlsx` 字节，便于单测往返解析。
Uint8List buildExcelBytes({
  required List<Treatment> treatments,
  required List<Medication> medications,
  required List<SymptomLog> symptoms,
  required List<DoseLog> doseLogs,
}) {
  final medById = {for (final m in medications) m.id: m};
  final lineById = <String, TreatmentLine>{
    for (final t in treatments)
      for (final l in t.lines) l.id: l,
  };

  final scopedLogs =
      doseLogs.where((log) => lineById.containsKey(log.lineId)).toList();
  final sortedLogs = [...scopedLogs]
    ..sort((a, b) => _logTime(a).compareTo(_logTime(b)));
  final injectionLogs = sortedLogs
      .where((log) => lineById[log.lineId]?.kind == LineKind.injection)
      .toList();
  final oralLogs = sortedLogs
      .where((log) => lineById[log.lineId]?.kind == LineKind.oral)
      .toList();
  final logById = {for (final log in scopedLogs) log.id: log};

  final excel = Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
  excel.rename(defaultSheet, '注射记录');

  void appendRows(String sheetName, List<List<CellValue?>> rows) {
    final sheet = excel[sheetName];
    for (final row in rows) {
      sheet.appendRow(row);
    }
  }

  appendRows('注射记录', [
    [
      TextCellValue('注射时间'),
      TextCellValue('药物'),
      TextCellValue('剂量'),
      TextCellValue('单位'),
      TextCellValue('部位'),
      TextCellValue('批号'),
      TextCellValue('备注'),
      TextCellValue('状态'),
      TextCellValue('用药线'),
    ],
    for (final log in injectionLogs)
      () {
        final line = lineById[log.lineId];
        final med = line != null ? medById[line.medicationId] : null;
        final isIv = med?.route == MedicationRoute.iv;
        return [
          TextCellValue(formatLocalDateTime(_logTime(log))),
          TextCellValue(med?.name ?? line?.label ?? ''),
          _numOrNull(log.dose),
          TextCellValue(log.unit.isNotEmpty ? log.unit : (med?.unit ?? '')),
          TextCellValue(
              isIv || log.site == null ? '' : (siteLabels[log.site!] ?? '')),
          TextCellValue(log.lotNumber ?? ''),
          TextCellValue(log.note ?? ''),
          TextCellValue(_statusLabels[log.status] ?? log.status.wire),
          TextCellValue(line?.label ?? ''),
        ];
      }(),
  ]);

  appendRows('症状记录', [
    [
      TextCellValue('记录时间'),
      TextCellValue('严重程度'),
      TextCellValue('疼痛评分'),
      TextCellValue('症状'),
      TextCellValue('体温'),
      TextCellValue('备注'),
      TextCellValue('关联注射时间'),
    ],
    for (final s in symptoms)
      () {
        final linked =
            s.injectionId != null ? logById[s.injectionId!] : null;
        return [
          TextCellValue(formatLocalDateTime(s.loggedAt)),
          IntCellValue(s.severity),
          s.painScore == null ? null : IntCellValue(s.painScore!),
          TextCellValue(s.tags.join('、')),
          _numOrNull(s.temperature),
          TextCellValue(s.note ?? ''),
          _textOrNull(linked != null ? formatLocalDateTime(_logTime(linked)) : ''),
        ];
      }(),
  ]);

  appendRows('药物', [
    [
      TextCellValue('药名'),
      TextCellValue('通用名'),
      TextCellValue('商品名'),
      TextCellValue('给药途径'),
      TextCellValue('默认剂量'),
      TextCellValue('单位'),
      TextCellValue('目录标识'),
    ],
    for (final m in medications)
      [
        TextCellValue(m.name),
        TextCellValue(m.genericName ?? ''),
        TextCellValue(m.brandNames.join('、')),
        TextCellValue(_routeLabels[m.route] ?? m.route.wire),
        _numOrNull(m.defaultDose),
        TextCellValue(m.unit),
        TextCellValue(m.catalogKey ?? ''),
      ],
  ]);

  appendRows('口服打卡', [
    [
      TextCellValue('记录时间'),
      TextCellValue('药物'),
      TextCellValue('状态'),
      TextCellValue('剂量'),
      TextCellValue('单位'),
      TextCellValue('备注'),
      TextCellValue('用药线'),
    ],
    for (final log in oralLogs)
      () {
        final line = lineById[log.lineId];
        final med = line != null ? medById[line.medicationId] : null;
        return [
          TextCellValue(formatLocalDateTime(_logTime(log))),
          TextCellValue(med?.name ?? line?.label ?? ''),
          TextCellValue(_statusLabels[log.status] ?? log.status.wire),
          _numOrNull(log.dose),
          TextCellValue(log.unit),
          TextCellValue(log.note ?? ''),
          TextCellValue(line?.label ?? ''),
        ];
      }(),
  ]);

  appendRows('用药线', [
    [
      TextCellValue('方案'),
      TextCellValue('用药线'),
      TextCellValue('药物'),
      TextCellValue('方式'),
      TextCellValue('锚点'),
      TextCellValue('窗口天数'),
      TextCellValue('口服计划'),
    ],
    for (final t in treatments)
      for (final line in t.lines)
        [
          TextCellValue(t.name),
          TextCellValue(line.label),
          TextCellValue(medById[line.medicationId]?.name ?? ''),
          TextCellValue(_kindLabels[line.kind] ?? line.kind.wire),
          TextCellValue(line.anchor.wire),
          IntCellValue(line.windowDays),
          TextCellValue(_describeOral(line)),
        ],
  ]);

  final encoded = excel.encode();
  if (encoded == null) {
    throw StateError('生成 Excel 文件失败');
  }
  return Uint8List.fromList(encoded);
}

Future<ExportFileOutput> exportExcel() async {
  final results = await Future.wait([
    TreatmentsRepo.list(),
    MedicationsRepo.list(),
    SymptomsRepo.list(),
    DoseLogsRepo.list(),
  ]);
  final bytes = buildExcelBytes(
    treatments: results[0] as List<Treatment>,
    medications: results[1] as List<Medication>,
    symptoms: results[2] as List<SymptomLog>,
    doseLogs: results[3] as List<DoseLog>,
  );

  final dir = await getTemporaryDirectory();
  final filename =
      'bioclock-${formatLocalDate(DateTime.now().millisecondsSinceEpoch)}.xlsx';
  final file = File(p.join(dir.path, filename));
  await file.writeAsBytes(bytes, flush: true);
  return ExportFileOutput(path: file.path, filename: filename);
}

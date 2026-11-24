import 'dart:io';
import 'dart:typed_data';

import 'package:bioclock/db/repo.dart';
import 'package:bioclock/domain/adherence.dart';
import 'package:bioclock/domain/date_utils.dart';
import 'package:bioclock/domain/rotation.dart';
import 'package:bioclock/domain/schedule.dart';
import 'package:bioclock/export/csv_exporter.dart';
import 'package:bioclock/i18n/zh.dart';
import 'package:bioclock/models/types.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

const int _defaultRangeDays = 180;
const String _pdfDisclaimer =
    '本报告由患者自行记录生成，仅用于就诊沟通，不构成医疗诊断或用药建议。';

class LineSummary {
  const LineSummary({
    required this.label,
    required this.kind,
    required this.done,
    required this.onTime,
    required this.missed,
    required this.avgDeviationDays,
    required this.rate,
  });

  final String label;
  final LineKind kind;
  final int done;
  final int? onTime;
  final int missed;
  final double? avgDeviationDays;
  final double rate;
}

class SymptomSummary {
  const SymptomSummary({
    required this.count,
    required this.avgSeverity,
    required this.avgPain,
    required this.mostCommonTag,
  });

  final int count;
  final double avgSeverity;
  final double? avgPain;
  final String mostCommonTag;
}

int _logTime(DoseLog log) => log.takenAt ?? log.scheduledAt ?? log.createdAt;

double _round1(double v) {
  final r = (v * 10 + 0.5).floor() / 10;
  return r == 0 ? 0.0 : r;
}

double _round2(double v) {
  final r = (v * 100 + 0.5).floor() / 100;
  return r == 0 ? 0.0 : r;
}

int resolveReportRangeDays([int? value]) {
  if (value == null) return _defaultRangeDays;
  if (value < 1) throw ArgumentError('统计范围必须是大于 0 的天数');
  return value;
}

({AdherenceStats stats, List<LineSummary> rows}) summarizeReportAdherence({
  required List<Treatment> treatments,
  required List<DoseLog> allLogs,
  required Map<String, TreatmentLine> lineById,
  required int now,
}) {
  final lines = [for (final t in treatments) ...t.lines];
  final stats = computeAdherence(lines, allLogs, now);
  final rows = <LineSummary>[];
  for (final entry in stats.byLine) {
    final label = lineById[entry.lineId]?.label ?? entry.lineId;
    switch (entry) {
      case OralLineAdherence():
        rows.add(LineSummary(
          label: label,
          kind: LineKind.oral,
          done: entry.total,
          onTime: null,
          missed: entry.missed,
          avgDeviationDays: null,
          rate: entry.rate,
        ));
      case InjectionLineAdherence():
        final denom = entry.total + entry.missed;
        rows.add(LineSummary(
          label: label,
          kind: LineKind.injection,
          done: entry.total,
          onTime: entry.onTime,
          missed: entry.missed,
          avgDeviationDays: entry.avgDeviationDays,
          rate: denom > 0 ? _round2(entry.total / denom) : 0.0,
        ));
    }
  }
  return (stats: stats, rows: rows);
}

SymptomSummary summarizeReportSymptoms(List<SymptomLog> logs) {
  if (logs.isEmpty) {
    return const SymptomSummary(
      count: 0,
      avgSeverity: 0,
      avgPain: null,
      mostCommonTag: '暂无记录',
    );
  }

  var severitySum = 0;
  var painSum = 0;
  var painCount = 0;
  final tagCounts = <String, int>{};

  for (final log in logs) {
    severitySum += log.severity;
    if (log.painScore != null) {
      painSum += log.painScore!;
      painCount += 1;
    }
    for (final tag in log.tags) {
      tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
    }
  }

  var mostCommonTag = '暂无记录';
  var maxCount = 0;
  for (final e in tagCounts.entries) {
    if (e.value > maxCount) {
      mostCommonTag = e.key;
      maxCount = e.value;
    }
  }

  return SymptomSummary(
    count: logs.length,
    avgSeverity: _round1(severitySum / logs.length),
    avgPain: painCount == 0 ? null : _round1(painSum / painCount),
    mostCommonTag: mostCommonTag,
  );
}

String _formatDose(DoseLog log, Medication? med) {
  if (log.dose == null) return '—';
  final unit = log.unit.isNotEmpty ? log.unit : (med?.unit ?? '');
  final doseText = log.dose == log.dose!.truncateToDouble()
      ? log.dose!.toInt().toString()
      : log.dose.toString();
  return '$doseText $unit'.trim();
}

String _escapeHtml(String v) => v
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

String buildReportHtml({
  required String patientName,
  required int rangeDays,
  required int since,
  required int now,
  required List<DoseLog> logs,
  required Map<String, TreatmentLine> lineById,
  required Map<String, Medication> medicationById,
  required AdherenceStats adherence,
  required List<LineSummary> lineSummaries,
  required SymptomSummary symptomSummary,
}) {
  final injectionRows = logs.isEmpty
      ? '<tr><td class="empty" colspan="8">该时间范围内暂无注射记录</td></tr>'
      : logs.map((log) {
          final line = lineById[log.lineId];
          final med = line != null ? medicationById[line.medicationId] : null;
          final isIv = med?.route == MedicationRoute.iv;
          final site = isIv
              ? '—'
              : (log.site != null ? (siteLabels[log.site!] ?? '—') : '—');
          return '<tr>'
              '<td class="nowrap">${_escapeHtml(formatLocalDateTime(_logTime(log)))}</td>'
              '<td>${Zh.doseStatusLabel(log.status)}</td>'
              '<td>${_escapeHtml(med?.name ?? line?.label ?? '—')}</td>'
              '<td>${_escapeHtml(med?.genericName ?? '—')}</td>'
              '<td class="nowrap">${_escapeHtml(_formatDose(log, med))}</td>'
              '<td>${_escapeHtml(site)}</td>'
              '<td>${_escapeHtml(log.lotNumber ?? '—')}</td>'
              '<td class="note">${_escapeHtml(log.note ?? '—')}</td>'
              '</tr>';
        }).join();

  final lineRows = lineSummaries.isEmpty
      ? '<tr><td class="empty" colspan="7">暂无用药线</td></tr>'
      : lineSummaries.map((row) {
          final kindLabel = row.kind == LineKind.oral ? '口服' : '注射';
          final onTime =
              row.kind == LineKind.injection ? '${row.onTime ?? 0}' : '—';
          final deviation = row.avgDeviationDays == null
              ? '—'
              : '${row.avgDeviationDays! > 0 ? '+' : ''}${row.avgDeviationDays!.toStringAsFixed(1)} 天';
          return '<tr>'
              '<td>${_escapeHtml(row.label)}</td>'
              '<td class="nowrap">$kindLabel</td>'
              '<td>${row.done}</td>'
              '<td>$onTime</td>'
              '<td>${row.missed}</td>'
              '<td class="nowrap">$deviation</td>'
              '<td>${(row.rate * 100).round()}%</td>'
              '</tr>';
        }).join();

  final patientRow = patientName.isNotEmpty
      ? '<div class="meta-item"><span class="meta-label">患者姓名</span><span>${_escapeHtml(patientName)}</span></div>'
      : '';
  final deviationLabel = adherence.total == 0
      ? '—'
      : '${adherence.avgDeviationDays > 0 ? '+' : ''}${adherence.avgDeviationDays.toStringAsFixed(1)} 天';

  return '''<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8" />
<style>
  @page { size: A4; margin: 16mm 14mm; }
  * { box-sizing: border-box; }
  body {
    margin: 0; color: #1a202c;
    font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", "Hiragino Sans GB",
      "Microsoft YaHei", "Noto Sans CJK SC", "Source Han Sans SC", sans-serif;
    font-size: 11px; line-height: 1.55;
  }
  h1 { margin: 0 0 4px; font-size: 22px; letter-spacing: 1px; }
  h2 { margin: 22px 0 8px; padding-left: 8px; border-left: 3px solid #2b6cb0; font-size: 14px; }
  .generated { margin: 0; color: #718096; font-size: 10px; }
  .meta { display: flex; flex-wrap: wrap; gap: 6px 24px; margin-top: 14px; padding: 10px 12px; background: #f7fafc; border: 1px solid #e2e8f0; border-radius: 4px; }
  .meta-item { display: flex; gap: 8px; }
  .meta-label { color: #718096; }
  table { width: 100%; border-collapse: collapse; table-layout: fixed; }
  th, td { padding: 6px 6px; border: 1px solid #cbd5e0; text-align: left; vertical-align: top; word-break: break-word; }
  th { background: #edf2f7; font-weight: 600; white-space: nowrap; }
  tbody tr:nth-child(even) { background: #fbfdff; }
  .nowrap { white-space: nowrap; }
  .note { white-space: pre-wrap; }
  .empty { padding: 18px; text-align: center; color: #718096; }
  .stats { display: flex; flex-wrap: wrap; gap: 8px; }
  .stat { flex: 1 1 90px; min-width: 90px; padding: 9px 10px; background: #f7fafc; border: 1px solid #e2e8f0; border-radius: 4px; }
  .stat-label { display: block; color: #718096; font-size: 10px; }
  .stat-value { display: block; margin-top: 2px; font-size: 15px; font-weight: 600; color: #2b6cb0; }
  .hint { margin: 7px 0 0; color: #718096; font-size: 9.5px; }
  footer { margin-top: 26px; padding-top: 10px; border-top: 1px solid #e2e8f0; color: #4a5568; font-size: 10px; page-break-inside: avoid; }
</style>
</head>
<body>
  <header>
    <h1>用药记录</h1>
    <p class="generated">生成时间：${_escapeHtml(formatLocalDateTime(now))}</p>
  </header>
  <div class="meta">
    $patientRow
    <div class="meta-item"><span class="meta-label">统计范围</span><span>${_escapeHtml(formatLocalDate(since))} 至 ${_escapeHtml(formatLocalDate(now))}（近 $rangeDays 天）</span></div>
    <div class="meta-item"><span class="meta-label">注射记录</span><span>${logs.length} 条</span></div>
  </div>
  <section>
    <h2>注射记录</h2>
    <table>
      <colgroup>
        <col style="width: 19%" /><col style="width: 7%" /><col style="width: 13%" /><col style="width: 13%" />
        <col style="width: 11%" /><col style="width: 10%" /><col style="width: 10%" /><col style="width: 17%" />
      </colgroup>
      <thead><tr><th>日期时间</th><th>${Zh.report.status}</th><th>药名</th><th>通用名</th><th>剂量</th><th>部位</th><th>批号</th><th>备注</th></tr></thead>
      <tbody>$injectionRows</tbody>
    </table>
  </section>
  <section>
    <h2>症状摘要</h2>
    <div class="stats">
      <div class="stat"><span class="stat-label">记录次数</span><span class="stat-value">${symptomSummary.count}</span></div>
      <div class="stat"><span class="stat-label">平均严重度（1–5）</span><span class="stat-value">${symptomSummary.count == 0 ? '—' : symptomSummary.avgSeverity.toStringAsFixed(1)}</span></div>
      <div class="stat"><span class="stat-label">平均疼痛（NRS 0–10）</span><span class="stat-value">${symptomSummary.avgPain == null ? '—' : symptomSummary.avgPain!.toStringAsFixed(1)}</span></div>
      <div class="stat"><span class="stat-label">最常见标签</span><span class="stat-value">${_escapeHtml(symptomSummary.mostCommonTag)}</span></div>
    </div>
    <p class="hint">症状记录仅用于自我观察，不构成因果判断。</p>
  </section>
  <section>
    <h2>${Zh.report.adherenceAllHistory}</h2>
    <div class="stats">
      <div class="stat"><span class="stat-label">已记录</span><span class="stat-value">${adherence.total}</span></div>
      <div class="stat"><span class="stat-label">按时</span><span class="stat-value">${adherence.onTime}</span></div>
      <div class="stat"><span class="stat-label">提前</span><span class="stat-value">${adherence.early}</span></div>
      <div class="stat"><span class="stat-label">延迟</span><span class="stat-value">${adherence.late}</span></div>
      <div class="stat"><span class="stat-label">平均偏差</span><span class="stat-value">$deviationLabel</span></div>
      <div class="stat"><span class="stat-label">整体完成率</span><span class="stat-value">${(adherence.rate * 100).round()}%</span></div>
    </div>
    <table style="margin-top: 12px;">
      <colgroup><col style="width: 26%" /><col style="width: 10%" /><col style="width: 12%" /><col style="width: 10%" /><col style="width: 10%" /><col style="width: 16%" /><col style="width: 16%" /></colgroup>
      <thead><tr><th>用药线</th><th>方式</th><th>已完成</th><th>按时</th><th>漏用</th><th>平均偏差</th><th>完成率</th></tr></thead>
      <tbody>$lineRows</tbody>
    </table>
    <p class="hint">按时指实际注射时间与计划时间的偏差不超过方案设定的窗口天数；偏差为负数表示提前。口服线按打卡完成率统计。</p>
  </section>
  <footer>$_pdfDisclaimer</footer>
</body>
</html>''';
}

Future<pw.Font?> _loadDesktopCjkFont() async {
  const candidates = [
    r'C:\Windows\Fonts\simhei.ttf',
    r'C:\Windows\Fonts\Deng.ttf',
    r'C:\Windows\Fonts\NotoSansSC-VF.ttf',
    '/System/Library/Fonts/Supplemental/Songti.ttc',
    '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
    '/usr/share/fonts/truetype/noto/NotoSansSC-Regular.ttf',
  ];
  for (final fontPath in candidates) {
    try {
      final f = File(fontPath);
      if (!await f.exists()) continue;
      final bytes = await f.readAsBytes();
      return pw.Font.ttf(ByteData.sublistView(bytes));
    } catch (_) {}
  }
  return null;
}

/// 桌面端及回退用的离线 PDF 排版，避免依赖网络字体或 WebView。
Future<Uint8List> buildVectorPdfBytes({
  required String patientName,
  required int rangeDays,
  required int since,
  required int now,
  required List<DoseLog> logs,
  required Map<String, TreatmentLine> lineById,
  required Map<String, Medication> medicationById,
  required AdherenceStats adherence,
  required List<LineSummary> lineSummaries,
  required SymptomSummary symptomSummary,
}) async {
  final font = await _loadDesktopCjkFont();
  final theme = font != null
      ? pw.ThemeData.withFont(base: font, bold: font)
      : pw.ThemeData.base();

  final doc = pw.Document(theme: theme);
  final primary = PdfColor.fromInt(0xFF2B6CB0);
  final borderColor = PdfColor.fromInt(0xFFCBD5E0);
  final headerBg = PdfColor.fromInt(0xFFEDF2F7);
  final mutedText = PdfColor.fromInt(0xFF718096);

  pw.Widget sectionTitle(String title) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 14, bottom: 6),
        padding: const pw.EdgeInsets.only(left: 6),
        decoration: pw.BoxDecoration(
          border: pw.Border(left: pw.BorderSide(color: primary, width: 3)),
        ),
        child: pw.Text(
          title,
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
      );

  pw.Widget statBox(String label, String value) => pw.Container(
        padding: const pw.EdgeInsets.all(6),
        decoration: pw.BoxDecoration(
          color: PdfColor.fromInt(0xFFF7FAFC),
          border: pw.Border.all(color: PdfColor.fromInt(0xFFE2E8F0)),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label, style: pw.TextStyle(fontSize: 8.5, color: mutedText)),
            pw.SizedBox(height: 2),
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: primary,
              ),
            ),
          ],
        ),
      );

  final deviationLabel = adherence.total == 0
      ? '—'
      : '${adherence.avgDeviationDays > 0 ? '+' : ''}${adherence.avgDeviationDays.toStringAsFixed(1)} 天';

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 32, vertical: 34),
      build: (ctx) => [
        pw.Text('用药记录',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 3),
        pw.Text('生成时间：${formatLocalDateTime(now)}',
            style: pw.TextStyle(fontSize: 9, color: mutedText)),
        pw.SizedBox(height: 8),
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            color: PdfColor.fromInt(0xFFF7FAFC),
            border: pw.Border.all(color: PdfColor.fromInt(0xFFE2E8F0)),
          ),
          child: pw.Wrap(
            spacing: 18,
            runSpacing: 4,
            children: [
              if (patientName.isNotEmpty) pw.Text('患者姓名：$patientName', style: const pw.TextStyle(fontSize: 9.5)),
              pw.Text(
                '统计范围：${formatLocalDate(since)} 至 ${formatLocalDate(now)}（近 $rangeDays 天）',
                style: const pw.TextStyle(fontSize: 9.5),
              ),
              pw.Text('注射记录：${logs.length} 条',
                  style: const pw.TextStyle(fontSize: 9.5)),
            ],
          ),
        ),
        sectionTitle('注射记录'),
        if (logs.isEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.all(10),
            child: pw.Text('该时间范围内暂无注射记录',
                style: pw.TextStyle(fontSize: 10, color: mutedText)),
          )
        else
          pw.TableHelper.fromTextArray(
            border: pw.TableBorder.all(color: borderColor, width: 0.6),
            headerDecoration: pw.BoxDecoration(color: headerBg),
            headerStyle:
                pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 8.5),
            headers: [
              '日期时间',
              Zh.report.status,
              '药名',
              '通用名',
              '剂量',
              '部位',
              '批号',
              '备注',
            ],
            data: [
              for (final log in logs)
                () {
                  final line = lineById[log.lineId];
                  final med =
                      line != null ? medicationById[line.medicationId] : null;
                  final isIv = med?.route == MedicationRoute.iv;
                  final site = isIv
                      ? '—'
                      : (log.site != null ? (siteLabels[log.site!] ?? '—') : '—');
                  return [
                    formatLocalDateTime(_logTime(log)),
                    Zh.doseStatusLabel(log.status),
                    med?.name ?? line?.label ?? '—',
                    med?.genericName ?? '—',
                    _formatDose(log, med),
                    site,
                    log.lotNumber ?? '—',
                    log.note ?? '—',
                  ];
                }(),
            ],
          ),
        sectionTitle('症状摘要'),
        pw.Row(
          children: [
            pw.Expanded(child: statBox('记录次数', '${symptomSummary.count}')),
            pw.SizedBox(width: 6),
            pw.Expanded(
              child: statBox(
                '平均严重度（1–5）',
                symptomSummary.count == 0
                    ? '—'
                    : symptomSummary.avgSeverity.toStringAsFixed(1),
              ),
            ),
            pw.SizedBox(width: 6),
            pw.Expanded(
              child: statBox(
                '平均疼痛（NRS 0–10）',
                symptomSummary.avgPain == null
                    ? '—'
                    : symptomSummary.avgPain!.toStringAsFixed(1),
              ),
            ),
            pw.SizedBox(width: 6),
            pw.Expanded(child: statBox('最常见标签', symptomSummary.mostCommonTag)),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Text('症状记录仅用于自我观察，不构成因果判断。',
            style: pw.TextStyle(fontSize: 8, color: mutedText)),
        sectionTitle(Zh.report.adherenceAllHistory),
        pw.Row(
          children: [
            pw.Expanded(child: statBox('已记录', '${adherence.total}')),
            pw.SizedBox(width: 4),
            pw.Expanded(child: statBox('按时', '${adherence.onTime}')),
            pw.SizedBox(width: 4),
            pw.Expanded(child: statBox('提前', '${adherence.early}')),
            pw.SizedBox(width: 4),
            pw.Expanded(child: statBox('延迟', '${adherence.late}')),
            pw.SizedBox(width: 4),
            pw.Expanded(child: statBox('平均偏差', deviationLabel)),
            pw.SizedBox(width: 4),
            pw.Expanded(
              child: statBox('整体完成率', '${(adherence.rate * 100).round()}%'),
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        if (lineSummaries.isNotEmpty)
          pw.TableHelper.fromTextArray(
            border: pw.TableBorder.all(color: borderColor, width: 0.6),
            headerDecoration: pw.BoxDecoration(color: headerBg),
            headerStyle:
                pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 8.5),
            headers: ['用药线', '方式', '已完成', '按时', '漏用', '平均偏差', '完成率'],
            data: [
              for (final row in lineSummaries)
                [
                  row.label,
                  row.kind == LineKind.oral ? '口服' : '注射',
                  '${row.done}',
                  row.kind == LineKind.injection ? '${row.onTime ?? 0}' : '—',
                  '${row.missed}',
                  row.avgDeviationDays == null
                      ? '—'
                      : '${row.avgDeviationDays! > 0 ? '+' : ''}${row.avgDeviationDays!.toStringAsFixed(1)} 天',
                  '${(row.rate * 100).round()}%',
                ],
            ],
          ),
        pw.SizedBox(height: 4),
        pw.Text(
          '按时指实际注射时间与计划时间的偏差不超过方案设定的窗口天数；偏差为负数表示提前。口服线按打卡完成率统计。',
          style: pw.TextStyle(fontSize: 8, color: mutedText),
        ),
        pw.SizedBox(height: 16),
        pw.Divider(color: PdfColor.fromInt(0xFFE2E8F0)),
        pw.Text(_pdfDisclaimer,
            style: pw.TextStyle(fontSize: 8.5, color: mutedText)),
      ],
    ),
  );

  return doc.save();
}

Future<ExportFileOutput> exportPdf({
  String? patientName,
  int? rangeDays,
}) async {
  final days = resolveReportRangeDays(rangeDays);
  final now = DateTime.now().millisecondsSinceEpoch;
  final since = now - days * dayMs;

  final results = await Future.wait([
    TreatmentsRepo.list(),
    MedicationsRepo.list(),
    SymptomsRepo.list(),
    DoseLogsRepo.list(),
    SettingsRepo.all(),
  ]);

  final allTreatments = results[0] as List<Treatment>;
  final allMedications = results[1] as List<Medication>;
  final allSymptoms = results[2] as List<SymptomLog>;
  final allLogs = results[3] as List<DoseLog>;
  final appSettings = results[4] as AppSettings;

  final resolvedName =
      (patientName?.trim().isNotEmpty == true ? patientName!.trim() : null) ??
          appSettings['patient_name']?.trim() ??
          '';
  final medById = {for (final m in allMedications) m.id: m};
  final lineById = <String, TreatmentLine>{
    for (final t in allTreatments)
      for (final l in t.lines) l.id: l,
  };

  final reportLogs = allLogs
      .where((log) => lineById[log.lineId]?.kind == LineKind.injection)
      .where((log) {
    final t = _logTime(log);
    return t >= since && t <= now;
  }).toList()
    ..sort((a, b) => _logTime(a).compareTo(_logTime(b)));

  final rangeSymptoms = allSymptoms
      .where((s) => s.loggedAt >= since && s.loggedAt <= now)
      .toList();

  final adherenceSummary = summarizeReportAdherence(
    treatments: allTreatments,
    allLogs: allLogs,
    lineById: lineById,
    now: now,
  );
  final symptomSummary = summarizeReportSymptoms(rangeSymptoms);

  final Uint8List pdfBytes;
  if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
    final html = buildReportHtml(
      patientName: resolvedName,
      rangeDays: days,
      since: since,
      now: now,
      logs: reportLogs,
      lineById: lineById,
      medicationById: medById,
      adherence: adherenceSummary.stats,
      lineSummaries: adherenceSummary.rows,
      symptomSummary: symptomSummary,
    );
    // Android/iOS 原生 WebView HTML 转 A4 PDF 自带系统 CJK 字体，离线零额外字体资产
    // ignore: deprecated_member_use
    pdfBytes = await Printing.convertHtml(html: html, format: PdfPageFormat.a4);
  } else {
    pdfBytes = await buildVectorPdfBytes(
      patientName: resolvedName,
      rangeDays: days,
      since: since,
      now: now,
      logs: reportLogs,
      lineById: lineById,
      medicationById: medById,
      adherence: adherenceSummary.stats,
      lineSummaries: adherenceSummary.rows,
      symptomSummary: symptomSummary,
    );
  }

  final dir = await getTemporaryDirectory();
  final filename = 'bioclock-${formatLocalDate(now)}.pdf';
  final target = File(p.join(dir.path, filename));
  await target.writeAsBytes(pdfBytes, flush: true);
  return ExportFileOutput(path: target.path, filename: filename);
}

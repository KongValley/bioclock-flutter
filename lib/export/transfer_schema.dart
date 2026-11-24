import 'dart:convert';

import 'package:bioclock/db/schema.dart';
import 'package:bioclock/import/import_schema.dart';
import 'package:bioclock/models/types.dart';

const String transferFormat = 'bioclock-transfer';
const int transferVersion = 1;

class TransferMedication {
  const TransferMedication({
    required this.id,
    required this.name,
    required this.genericName,
    required this.brandNames,
    required this.defaultDose,
    required this.unit,
    required this.color,
    required this.route,
    required this.diseaseIds,
    required this.catalogKey,
    required this.isBuiltin,
    required this.extra,
  });

  final String id;
  final String name;
  final String? genericName;
  final List<String> brandNames;
  final double? defaultDose;
  final String unit;
  final String color;
  final MedicationRoute route;
  final List<String> diseaseIds;
  final String? catalogKey;
  final bool isBuiltin;
  final Map<String, dynamic> extra;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'genericName': genericName,
        'brandNames': brandNames,
        'defaultDose': defaultDose,
        'unit': unit,
        'color': color,
        'route': route.wire,
        'diseaseIds': diseaseIds,
        'catalogKey': catalogKey,
        'isBuiltin': isBuiltin,
        'extra': extra,
      };
}

class TransferPhase {
  const TransferPhase({
    required this.orderIdx,
    required this.kind,
    required this.intervalDays,
    required this.repeatCount,
    required this.dose,
    required this.unit,
    required this.effectiveFrom,
  });

  final int orderIdx;
  final String kind;
  final int intervalDays;
  final int repeatCount;
  final double? dose;
  final String unit;
  final int? effectiveFrom;

  Map<String, dynamic> toJson() => {
        'orderIdx': orderIdx,
        'kind': kind,
        'intervalDays': intervalDays,
        'repeatCount': repeatCount,
        'dose': dose,
        'unit': unit,
        'effectiveFrom': effectiveFrom,
      };
}

class TransferOralPlan {
  const TransferOralPlan({
    required this.startDate,
    required this.durationDays,
    required this.frequency,
    required this.timesPerPeriod,
    required this.daysOfWeek,
    required this.remindTime,
  });

  final int startDate;
  final int? durationDays;
  final String frequency;
  final int timesPerPeriod;
  final List<int> daysOfWeek;
  final String remindTime;

  Map<String, dynamic> toJson() => {
        'startDate': startDate,
        'durationDays': durationDays,
        'frequency': frequency,
        'timesPerPeriod': timesPerPeriod,
        'daysOfWeek': daysOfWeek,
        'remindTime': remindTime,
      };
}

class TransferLine {
  const TransferLine({
    required this.id,
    required this.medicationId,
    required this.kind,
    required this.label,
    required this.isHost,
    required this.syncWithHost,
    required this.anchor,
    required this.windowDays,
    required this.endedAt,
    required this.phases,
    required this.oral,
  });

  final String id;
  final String medicationId;
  final String kind;
  final String label;
  final bool isHost;
  final bool syncWithHost;
  final String anchor;
  final int windowDays;
  final int? endedAt;
  final List<TransferPhase> phases;
  final TransferOralPlan? oral;

  Map<String, dynamic> toJson() => {
        'id': id,
        'medicationId': medicationId,
        'kind': kind,
        'label': label,
        'isHost': isHost,
        'syncWithHost': syncWithHost,
        'anchor': anchor,
        'windowDays': windowDays,
        'endedAt': endedAt,
        'phases': [for (final p in phases) p.toJson()],
        'oral': oral?.toJson(),
      };
}

class TransferTreatment {
  const TransferTreatment({
    required this.id,
    required this.name,
    required this.isActive,
    required this.createdAt,
    required this.lines,
  });

  final String id;
  final String name;
  final bool isActive;
  final int createdAt;
  final List<TransferLine> lines;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isActive': isActive,
        'createdAt': createdAt,
        'lines': [for (final l in lines) l.toJson()],
      };
}

class TransferDose {
  const TransferDose({
    required this.lineId,
    required this.scheduledAt,
    required this.takenAt,
    required this.status,
    required this.dose,
    required this.unit,
    required this.site,
    required this.lotNumber,
    required this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  final String lineId;
  final int? scheduledAt;
  final int? takenAt;
  final String status;
  final double? dose;
  final String? unit;
  final String? site;
  final String? lotNumber;
  final String? note;
  final int createdAt;
  final int updatedAt;

  Map<String, dynamic> toJson() => {
        'lineId': lineId,
        'scheduledAt': scheduledAt,
        'takenAt': takenAt,
        'status': status,
        'dose': dose,
        'unit': unit,
        'site': site,
        'lotNumber': lotNumber,
        'note': note,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };
}

class TransferSymptom {
  const TransferSymptom({
    required this.loggedAt,
    required this.severity,
    required this.painScore,
    required this.tags,
    required this.note,
    required this.temperature,
    required this.doseIndex,
  });

  final int loggedAt;
  final int severity;
  final int? painScore;
  final List<String> tags;
  final String? note;
  final double? temperature;
  final int? doseIndex;

  Map<String, dynamic> toJson() => {
        'loggedAt': loggedAt,
        'severity': severity,
        'painScore': painScore,
        'tags': tags,
        'note': note,
        'temperature': temperature,
        'doseIndex': doseIndex,
      };
}

class TransferEfficacy {
  const TransferEfficacy({
    required this.lineId,
    required this.kind,
    required this.occurredAt,
    required this.dosesCount,
    required this.note,
    required this.createdAt,
  });

  final String lineId;
  final String kind;
  final int occurredAt;
  final int dosesCount;
  final String? note;
  final int createdAt;

  Map<String, dynamic> toJson() => {
        'lineId': lineId,
        'kind': kind,
        'occurredAt': occurredAt,
        'dosesCount': dosesCount,
        'note': note,
        'createdAt': createdAt,
      };
}

class TransferTag {
  const TransferTag({
    required this.name,
    required this.isBuiltin,
    required this.sortOrder,
  });

  final String name;
  final bool isBuiltin;
  final int sortOrder;

  Map<String, dynamic> toJson() => {
        'name': name,
        'isBuiltin': isBuiltin,
        'sortOrder': sortOrder,
      };
}

class TransferReminder {
  const TransferReminder({
    required this.treatmentId,
    required this.offsets,
    required this.timeOfDay,
    required this.snoozeMinutes,
    required this.enabled,
  });

  final String treatmentId;
  final List<int> offsets;
  final String timeOfDay;
  final int snoozeMinutes;
  final bool enabled;

  Map<String, dynamic> toJson() => {
        'treatmentId': treatmentId,
        'offsets': offsets,
        'timeOfDay': timeOfDay,
        'snoozeMinutes': snoozeMinutes,
        'enabled': enabled,
      };
}

class TransferFile {
  const TransferFile({
    required this.format,
    required this.version,
    required this.schemaVersion,
    required this.exportedAt,
    required this.app,
    required this.medications,
    required this.treatments,
    required this.doseLogs,
    required this.symptoms,
    required this.efficacyEvents,
    required this.symptomTags,
    required this.reminders,
    required this.settings,
  });

  final String format;
  final int version;
  final int schemaVersion;
  final int exportedAt;
  final String app;
  final List<TransferMedication> medications;
  final List<TransferTreatment> treatments;
  final List<TransferDose> doseLogs;
  final List<TransferSymptom> symptoms;
  final List<TransferEfficacy> efficacyEvents;
  final List<TransferTag> symptomTags;
  final List<TransferReminder> reminders;
  final Map<String, String> settings;

  Map<String, dynamic> toJson() => {
        'format': format,
        'version': version,
        'schemaVersion': schemaVersion,
        'exportedAt': exportedAt,
        'app': app,
        'medications': [for (final m in medications) m.toJson()],
        'treatments': [for (final t in treatments) t.toJson()],
        'doseLogs': [for (final d in doseLogs) d.toJson()],
        'symptoms': [for (final s in symptoms) s.toJson()],
        'efficacyEvents': [for (final e in efficacyEvents) e.toJson()],
        'symptomTags': [for (final tag in symptomTags) tag.toJson()],
        'reminders': [for (final r in reminders) r.toJson()],
        'settings': settings,
      };
}

class TransferSummary {
  const TransferSummary({
    required this.doses,
    required this.symptoms,
    required this.efficacyEvents,
    required this.schemaVersion,
    required this.settings,
    required this.reminder,
  });

  final int doses;
  final int symptoms;
  final int efficacyEvents;
  final int schemaVersion;
  final Map<String, String> settings;
  final TransferReminder? reminder;
}

String _stripBom(String text) => text.replaceFirst(RegExp(r'^\uFEFF'), '');

bool isTransferFile(String text) {
  try {
    final parsed = jsonDecode(_stripBom(text));
    return parsed is Map && parsed['format'] == transferFormat;
  } catch (_) {
    return false;
  }
}

TransferFile parseTransferFile(String text) {
  final Object? parsed;
  try {
    parsed = jsonDecode(_stripBom(text));
  } catch (_) {
    throw const ImportValidationException('不是有效的 JSON 换机文件');
  }
  if (parsed is! Map || parsed['format'] != transferFormat) {
    throw const ImportValidationException('不是 BioClock 的换机文件');
  }
  if (parsed['version'] != transferVersion) {
    throw ImportValidationException('不支持的换机文件版本：${parsed['version']}');
  }
  final sv = parsed['schemaVersion'];
  if (sv is! num || sv.isNaN || sv.isInfinite) {
    throw const ImportValidationException('换机文件缺少数据库版本');
  }
  if (sv > schemaVersion) {
    throw ImportValidationException(
      '备份来自更新版本的 BioClock（数据库 v${sv.toInt()}），请先升级 App 再导入',
    );
  }

  for (final pair in [
    ('medications', '药物'),
    ('treatments', '治疗方案'),
    ('doseLogs', '打卡记录'),
    ('symptoms', '症状记录'),
    ('efficacyEvents', '疗效记录'),
    ('symptomTags', '症状标签'),
    ('reminders', '提醒规则'),
  ]) {
    if (parsed[pair.$1] is! List) {
      throw ImportValidationException('换机文件缺少${pair.$2}');
    }
  }

  final rawSettings = parsed['settings'];
  final settingsMap = <String, String>{};
  if (rawSettings is Map) {
    for (final e in rawSettings.entries) {
      if (e.value != null) settingsMap[e.key.toString()] = e.value.toString();
    }
  }

  final meds = (parsed['medications'] as List).map((item) {
    final m = Map<String, dynamic>.from(item as Map);
    return TransferMedication(
      id: m['id'] as String,
      name: m['name'] as String,
      genericName: m['genericName'] as String?,
      brandNames: [
        for (final b in (m['brandNames'] as List? ?? const [])) b.toString(),
      ],
      defaultDose: (m['defaultDose'] as num?)?.toDouble(),
      unit: (m['unit'] as String?) ?? 'mg',
      color: (m['color'] as String?) ?? '#2B6CB0',
      route: MedicationRoute.tryParse(m['route'] as String?) ??
          MedicationRoute.sc,
      diseaseIds: [
        for (final id in (m['diseaseIds'] as List? ?? const [])) id.toString(),
      ],
      catalogKey: m['catalogKey'] as String?,
      isBuiltin: m['isBuiltin'] == true,
      extra: m['extra'] is Map
          ? Map<String, dynamic>.from(m['extra'] as Map)
          : const {},
    );
  }).toList();

  final treatmentList = (parsed['treatments'] as List).map((item) {
    final t = Map<String, dynamic>.from(item as Map);
    final lines = (t['lines'] as List? ?? const []).map((lItem) {
      final l = Map<String, dynamic>.from(lItem as Map);
      final phases = (l['phases'] as List? ?? const []).map((pItem) {
        final p = Map<String, dynamic>.from(pItem as Map);
        return TransferPhase(
          orderIdx: (p['orderIdx'] as num).toInt(),
          kind: p['kind'] as String,
          intervalDays: (p['intervalDays'] as num).toInt(),
          repeatCount: (p['repeatCount'] as num).toInt(),
          dose: (p['dose'] as num?)?.toDouble(),
          unit: p['unit'] as String,
          effectiveFrom: (p['effectiveFrom'] as num?)?.toInt(),
        );
      }).toList();
      final oralRaw = l['oral'];
      TransferOralPlan? oral;
      if (oralRaw is Map) {
        final o = Map<String, dynamic>.from(oralRaw);
        oral = TransferOralPlan(
          startDate: (o['startDate'] as num).toInt(),
          durationDays: (o['durationDays'] as num?)?.toInt(),
          frequency: o['frequency'] as String,
          timesPerPeriod: (o['timesPerPeriod'] as num?)?.toInt() ?? 0,
          daysOfWeek: [
            for (final d in (o['daysOfWeek'] as List? ?? const []))
              (d as num).toInt(),
          ],
          remindTime: (o['remindTime'] as String?) ?? '09:00',
        );
      }
      return TransferLine(
        id: l['id'] as String,
        medicationId: l['medicationId'] as String,
        kind: l['kind'] as String,
        label: l['label'] as String,
        isHost: l['isHost'] == true,
        syncWithHost: l['syncWithHost'] == true,
        anchor: (l['anchor'] as String?) ?? 'actual',
        windowDays: (l['windowDays'] as num?)?.toInt() ?? 2,
        endedAt: (l['endedAt'] as num?)?.toInt(),
        phases: phases,
        oral: oral,
      );
    }).toList();
    return TransferTreatment(
      id: t['id'] as String,
      name: t['name'] as String,
      isActive: t['isActive'] == true,
      createdAt: (t['createdAt'] as num?)?.toInt() ?? 0,
      lines: lines,
    );
  }).toList();

  final doses = (parsed['doseLogs'] as List).map((item) {
    final d = Map<String, dynamic>.from(item as Map);
    return TransferDose(
      lineId: d['lineId'] as String,
      scheduledAt: (d['scheduledAt'] as num?)?.toInt(),
      takenAt: (d['takenAt'] as num?)?.toInt(),
      status: d['status'] as String,
      dose: (d['dose'] as num?)?.toDouble(),
      unit: d['unit'] as String?,
      site: d['site'] as String?,
      lotNumber: d['lotNumber'] as String?,
      note: d['note'] as String?,
      createdAt: (d['createdAt'] as num).toInt(),
      updatedAt: (d['updatedAt'] as num).toInt(),
    );
  }).toList();

  final symptomsList = (parsed['symptoms'] as List).map((item) {
    final s = Map<String, dynamic>.from(item as Map);
    return TransferSymptom(
      loggedAt: (s['loggedAt'] as num).toInt(),
      severity: (s['severity'] as num).toInt(),
      painScore: (s['painScore'] as num?)?.toInt(),
      tags: [
        for (final tag in (s['tags'] as List? ?? const [])) tag.toString(),
      ],
      note: s['note'] as String?,
      temperature: (s['temperature'] as num?)?.toDouble(),
      doseIndex: (s['doseIndex'] as num?)?.toInt(),
    );
  }).toList();

  final events = (parsed['efficacyEvents'] as List).map((item) {
    final e = Map<String, dynamic>.from(item as Map);
    return TransferEfficacy(
      lineId: e['lineId'] as String,
      kind: e['kind'] as String,
      occurredAt: (e['occurredAt'] as num).toInt(),
      dosesCount: (e['dosesCount'] as num?)?.toInt() ?? 0,
      note: e['note'] as String?,
      createdAt: (e['createdAt'] as num?)?.toInt() ?? 0,
    );
  }).toList();

  final tagsList = (parsed['symptomTags'] as List).map((item) {
    final tag = Map<String, dynamic>.from(item as Map);
    return TransferTag(
      name: tag['name'] as String,
      isBuiltin: tag['isBuiltin'] == true,
      sortOrder: (tag['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }).toList();

  final remindersList = (parsed['reminders'] as List).map((item) {
    final r = Map<String, dynamic>.from(item as Map);
    return TransferReminder(
      treatmentId: r['treatmentId'] as String,
      offsets: [
        for (final o in (r['offsets'] as List? ?? const [])) (o as num).toInt(),
      ],
      timeOfDay: (r['timeOfDay'] as String?) ?? '09:00',
      snoozeMinutes: (r['snoozeMinutes'] as num?)?.toInt() ?? 10,
      enabled: r['enabled'] != false,
    );
  }).toList();

  return TransferFile(
    format: parsed['format'] as String,
    version: (parsed['version'] as num).toInt(),
    schemaVersion: sv.toInt(),
    exportedAt: (parsed['exportedAt'] as num?)?.toInt() ?? 0,
    app: (parsed['app'] as String?) ?? 'BioClock',
    medications: meds,
    treatments: treatmentList,
    doseLogs: doses,
    symptoms: symptomsList,
    efficacyEvents: events,
    symptomTags: tagsList,
    reminders: remindersList,
    settings: settingsMap,
  );
}

ImportPayload transferToImportPayload(String text) {
  final parsed = parseTransferFile(text);
  final medById = {for (final m in parsed.medications) m.id: m};
  final lineById = <String, TransferLine>{
    for (final t in parsed.treatments)
      for (final l in t.lines) l.id: l,
  };

  int eventTime(TransferDose dose) =>
      dose.takenAt ?? dose.scheduledAt ?? dose.createdAt;

  int storedTime(TransferDose dose) => resolveImportLogTime(
        status: DoseStatus.tryParse(dose.status) ?? DoseStatus.done,
        eventAt: eventTime(dose),
        scheduledAt: dose.scheduledAt,
      );

  final injections = parsed.doseLogs
      .where((d) => lineById[d.lineId]?.kind == 'injection')
      .map((dose) {
    final line = lineById[dose.lineId];
    final med = line != null ? medById[line.medicationId] : null;
    final status = DoseStatus.tryParse(dose.status) ?? DoseStatus.done;
    return ImportInjection(
      injectedAt: storedTime(dose),
      scheduledAt:
          dose.scheduledAt ?? (status == DoseStatus.done ? null : eventTime(dose)),
      medicationName: med?.name ?? line?.label,
      dose: dose.dose,
      unit: dose.unit,
      site: InjectionSite.tryParse(dose.site),
      lotNumber: dose.lotNumber,
      note: dose.note,
      status: status,
      lineLabel: line?.label,
    );
  }).toList();

  final oralLogs = parsed.doseLogs
      .where((d) => lineById[d.lineId]?.kind == 'oral')
      .map((dose) {
    final line = lineById[dose.lineId];
    final med = line != null ? medById[line.medicationId] : null;
    final status = DoseStatus.tryParse(dose.status) ?? DoseStatus.done;
    return ImportOralLog(
      takenAt: storedTime(dose),
      scheduledAt:
          dose.scheduledAt ?? (status == DoseStatus.done ? null : eventTime(dose)),
      medicationName: med?.name ?? line?.label,
      status: status,
      dose: dose.dose,
      unit: dose.unit,
      note: dose.note,
      lineLabel: line?.label,
    );
  }).toList();

  final lineStates = [
    for (final t in parsed.treatments)
      for (final line in t.lines)
        ImportLineState(
          lineLabel: line.label,
          medicationName: medById[line.medicationId]?.name ?? line.label,
          kind: line.kind == 'oral' ? LineKind.oral : LineKind.injection,
          endedAt: line.endedAt,
        ),
  ];

  final efficacyEvents = parsed.efficacyEvents.map((event) {
    final line = lineById[event.lineId];
    return ImportEfficacyEvent(
      lineLabel: line?.label,
      medicationName:
          line != null ? (medById[line.medicationId]?.name ?? line.label) : null,
      kind: EfficacyKind.tryParse(event.kind) ?? EfficacyKind.other,
      occurredAt: event.occurredAt,
      note: event.note,
    );
  }).toList();

  final symptoms = parsed.symptoms.map((symptom) {
    int? injectionAt;
    if (symptom.doseIndex != null &&
        symptom.doseIndex! >= 0 &&
        symptom.doseIndex! < parsed.doseLogs.length) {
      injectionAt = storedTime(parsed.doseLogs[symptom.doseIndex!]);
    }
    return ImportSymptom(
      loggedAt: symptom.loggedAt,
      severity: symptom.severity.clamp(1, 5),
      painScore: symptom.painScore,
      tags: symptom.tags,
      temperature: symptom.temperature,
      note: symptom.note,
      injectionAt: injectionAt,
    );
  }).toList();

  return ImportPayload(
    medications: [
      for (final m in parsed.medications)
        ImportMedication(
          name: m.name,
          genericName: m.genericName,
          brandNames: m.brandNames,
          route: m.route,
          defaultDose: m.defaultDose,
          unit: m.unit,
          catalogKey: m.catalogKey,
          extra: m.extra,
        ),
    ],
    injections: injections,
    oralLogs: oralLogs,
    symptoms: symptoms,
    lineStates: lineStates,
    efficacyEvents: efficacyEvents,
    symptomTags: [for (final tag in parsed.symptomTags) tag.name],
    preserveEndedLines: true,
  );
}

TransferSummary summarizeTransfer(String text) {
  final parsed = parseTransferFile(text);
  final payload = transferToImportPayload(text);
  TransferTreatment? activeTreatment;
  for (final t in parsed.treatments) {
    if (t.isActive) {
      activeTreatment = t;
      break;
    }
  }
  TransferReminder? reminder;
  for (final r in parsed.reminders) {
    if (r.treatmentId == activeTreatment?.id) {
      reminder = r;
      break;
    }
  }
  reminder ??= parsed.reminders.isNotEmpty ? parsed.reminders.first : null;

  return TransferSummary(
    doses: payload.injections.length + payload.oralLogs.length,
    symptoms: payload.symptoms.length,
    efficacyEvents: payload.efficacyEvents.length,
    schemaVersion: parsed.schemaVersion,
    settings: parsed.settings,
    reminder: reminder,
  );
}

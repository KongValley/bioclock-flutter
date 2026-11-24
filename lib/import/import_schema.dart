import 'dart:convert';

import 'package:bioclock/domain/rotation.dart';
import 'package:bioclock/models/types.dart';

const String importFormat = 'bioclock-import';
const int importVersion = 3;
const int importMinVersion = 1;
const int importMaxRows = 2000;

class ImportValidationException implements Exception {
  const ImportValidationException(this.message);
  final String message;

  @override
  String toString() => message;
}

Never _fail(String message) => throw ImportValidationException(message);

class ImportMedication {
  const ImportMedication({
    required this.name,
    required this.genericName,
    required this.brandNames,
    required this.route,
    required this.defaultDose,
    required this.unit,
    required this.catalogKey,
    required this.extra,
  });

  final String name;
  final String? genericName;
  final List<String> brandNames;
  final MedicationRoute route;
  final double? defaultDose;
  final String? unit;
  final String? catalogKey;
  final Map<String, dynamic> extra;
}

class ImportInjection {
  const ImportInjection({
    required this.injectedAt,
    this.scheduledAt,
    required this.medicationName,
    required this.dose,
    required this.unit,
    required this.site,
    required this.lotNumber,
    required this.note,
    required this.status,
    required this.lineLabel,
  });

  final int injectedAt;
  final int? scheduledAt;
  final String? medicationName;
  final double? dose;
  final String? unit;
  final InjectionSite? site;
  final String? lotNumber;
  final String? note;
  final DoseStatus status;
  final String? lineLabel;
}

class ImportOralLog {
  const ImportOralLog({
    required this.takenAt,
    this.scheduledAt,
    required this.medicationName,
    required this.status,
    required this.dose,
    required this.unit,
    required this.note,
    required this.lineLabel,
  });

  final int takenAt;
  final int? scheduledAt;
  final String? medicationName;
  final DoseStatus status;
  final double? dose;
  final String? unit;
  final String? note;
  final String? lineLabel;
}

class ImportSymptom {
  const ImportSymptom({
    required this.loggedAt,
    required this.severity,
    required this.painScore,
    required this.tags,
    required this.temperature,
    required this.note,
    required this.injectionAt,
  });

  final int loggedAt;
  final int severity;
  final int? painScore;
  final List<String> tags;
  final double? temperature;
  final String? note;
  final int? injectionAt;
}

class ImportLineState {
  const ImportLineState({
    required this.lineLabel,
    required this.medicationName,
    required this.kind,
    required this.endedAt,
  });

  final String? lineLabel;
  final String? medicationName;
  final LineKind kind;
  final int? endedAt;
}

class ImportEfficacyEvent {
  const ImportEfficacyEvent({
    required this.lineLabel,
    required this.medicationName,
    required this.kind,
    required this.occurredAt,
    required this.note,
  });

  final String? lineLabel;
  final String? medicationName;
  final EfficacyKind kind;
  final int occurredAt;
  final String? note;
}

class ImportPayload {
  const ImportPayload({
    required this.medications,
    required this.injections,
    required this.oralLogs,
    required this.symptoms,
    required this.lineStates,
    required this.efficacyEvents,
    this.symptomTags,
    this.preserveEndedLines = false,
  });

  final List<ImportMedication> medications;
  final List<ImportInjection> injections;
  final List<ImportOralLog> oralLogs;
  final List<ImportSymptom> symptoms;
  final List<ImportLineState> lineStates;
  final List<ImportEfficacyEvent> efficacyEvents;
  final List<String>? symptomTags;
  final bool preserveEndedLines;
}

/// 导入记录最终用于落库/去重的时间。
int resolveImportLogTime({
  required DoseStatus status,
  required int eventAt,
  int? scheduledAt,
}) {
  if (status == DoseStatus.done) return eventAt;
  return scheduledAt ?? eventAt;
}

final Map<String, InjectionSite> _siteAliases = {
  for (final entry in siteLabels.entries) ...{
    entry.key.wire: entry.key,
    entry.value: entry.key,
  },
};

const Map<String, MedicationRoute> _routeAliases = {
  'sc': MedicationRoute.sc,
  '皮下': MedicationRoute.sc,
  '皮下注射': MedicationRoute.sc,
  'subcutaneous': MedicationRoute.sc,
  'iv': MedicationRoute.iv,
  '静脉': MedicationRoute.iv,
  '静脉输注': MedicationRoute.iv,
  '输注': MedicationRoute.iv,
  'intravenous': MedicationRoute.iv,
  'oral': MedicationRoute.oral,
  '口服': MedicationRoute.oral,
  'po': MedicationRoute.oral,
};

const Map<String, DoseStatus> _statusAliases = {
  'done': DoseStatus.done,
  '已用': DoseStatus.done,
  '已完成': DoseStatus.done,
  '完成': DoseStatus.done,
  '已注射': DoseStatus.done,
  '已服用': DoseStatus.done,
  'skipped': DoseStatus.skipped,
  '跳过': DoseStatus.skipped,
  '取消': DoseStatus.skipped,
  'missed': DoseStatus.missed,
  '漏用': DoseStatus.missed,
  '漏服': DoseStatus.missed,
  '未用': DoseStatus.missed,
};

const Map<String, EfficacyKind> _efficacyKindAliases = {
  'reduced': EfficacyKind.reduced,
  '疗效下降': EfficacyKind.reduced,
  '下降': EfficacyKind.reduced,
  'failed': EfficacyKind.failed,
  '疗效失效': EfficacyKind.failed,
  '失效': EfficacyKind.failed,
  'intolerance': EfficacyKind.intolerance,
  '不耐受': EfficacyKind.intolerance,
  'antibody': EfficacyKind.antibody,
  '抗药抗体': EfficacyKind.antibody,
  'other': EfficacyKind.other,
  '其他': EfficacyKind.other,
};

final RegExp _dateTimeRe = RegExp(
  r'^(\d{4})-(\d{1,2})-(\d{1,2}) (\d{1,2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?$',
);

/// 解析本地时间字符串 `YYYY-MM-DD HH:mm`（也兼容 `/` 分隔、`T` 分隔及可选秒/毫秒）。
int parseLocalDateTime(Object? value, String label) {
  if (value is! String) _fail('$label必须是文本时间，例如 2026-03-01 09:00');
  final text = value.trim().replaceAll('/', '-').replaceFirst('T', ' ');
  final match = _dateTimeRe.firstMatch(text);
  if (match == null) _fail('$label格式不正确，应为 2026-03-01 09:00');

  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final hour = int.parse(match.group(4)!);
  final minute = int.parse(match.group(5)!);
  final second = match.group(6) == null ? 0 : int.parse(match.group(6)!);

  if (month < 1 || month > 12) _fail('$label的月份不合法');
  if (day < 1 || day > 31) _fail('$label的日期不合法');
  if (hour > 23 || minute > 59 || second > 59) _fail('$label的时间不合法');

  final date = DateTime(year, month, day, hour, minute, second);
  if (date.year != year || date.month != month || date.day != day) {
    _fail('$label不是一个真实存在的日期');
  }
  return date.millisecondsSinceEpoch;
}

String? _optionalText(Object? value, String label, [int maxLength = 200]) {
  if (value == null) return null;
  if (value is! String) _fail('$label必须是文本');
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.length > maxLength) _fail('$label最多 $maxLength 个字');
  return trimmed;
}

String _requireText(Object? value, String label, [int maxLength = 200]) {
  final text = _optionalText(value, label, maxLength);
  if (text == null) _fail('$label不能为空');
  return text;
}

double? _optionalNumber(Object? value, String label) {
  if (value == null || value == '') return null;
  final num? numVal =
      value is num ? value : (value is String ? num.tryParse(value) : null);
  if (numVal == null || numVal.isNaN || numVal.isInfinite) {
    _fail('$label必须是数字');
  }
  return numVal.toDouble();
}

int? _optionalInt(Object? value, String label, int min, int max) {
  final numVal = _optionalNumber(value, label);
  if (numVal == null) return null;
  final asInt = numVal.toInt();
  if (numVal != asInt.toDouble() || asInt < min || asInt > max) {
    _fail('$label必须是 $min 到 $max 之间的整数');
  }
  return asInt;
}

InjectionSite _parseSite(Object? value, String label) {
  if (value == null || value == '') return InjectionSite.abdomenUl;
  if (value is! String) _fail('$label必须是文本');
  final site = _siteAliases[value.trim()];
  if (site == null) {
    _fail('$label不认识「$value」，可选：${siteLabels.values.join('、')}');
  }
  return site;
}

MedicationRoute _parseRoute(Object? value, String label) {
  if (value == null || value == '') return MedicationRoute.sc;
  if (value is! String) _fail('$label必须是文本');
  final trimmed = value.trim();
  final route = _routeAliases[trimmed.toLowerCase()] ?? _routeAliases[trimmed];
  if (route == null) _fail('$label不认识「$value」，可选：sc、iv、oral');
  return route;
}

DoseStatus _parseStatus(Object? value, String label) {
  if (value == null || value == '') return DoseStatus.done;
  if (value is! String) _fail('$label必须是文本');
  final trimmed = value.trim();
  final status =
      _statusAliases[trimmed.toLowerCase()] ?? _statusAliases[trimmed];
  if (status == null) _fail('$label不认识「$value」，可选：done、skipped、missed');
  return status;
}

LineKind _parseLineKind(Object? value, String label) {
  if (value == 'injection' || value == '注射') return LineKind.injection;
  if (value == 'oral' || value == '口服') return LineKind.oral;
  _fail('$label必须是注射或口服');
}

EfficacyKind _parseEfficacyKind(Object? value, String label) {
  if (value is! String) _fail('$label必须是文本');
  final trimmed = value.trim();
  final kind = _efficacyKindAliases[trimmed.toLowerCase()] ??
      _efficacyKindAliases[trimmed];
  if (kind == null) _fail('$label不认识「$value」');
  return kind;
}

List<String> _parseTags(Object? value, String label) {
  if (value == null) return const [];
  if (value is! List) _fail('$label必须是数组');
  final seen = <String>{};
  final result = <String>[];
  for (final item in value) {
    if (item is! String) _fail('$label里的每一项都必须是文本');
    final tag = item.trim();
    if (tag.isEmpty) continue;
    if (tag.length > 20) _fail('$label里的单个症状最多 20 个字');
    if (seen.add(tag)) result.add(tag);
  }
  return result;
}

final RegExp _splitNamesRe = RegExp(r'[、,，;；/\n]+');

List<String> _parseNameList(Object? value, String label) {
  if (value == null || value == '') return const [];
  List<Object?> raw;
  if (value is List) {
    raw = value;
  } else if (value is String) {
    raw = value.split(_splitNamesRe);
  } else {
    _fail('$label必须是数组或文本');
  }
  final seen = <String>{};
  final result = <String>[];
  for (final item in raw) {
    if (item is! String) _fail('$label里的每一项都必须是文本');
    final name = item.trim();
    if (name.isEmpty) continue;
    if (name.length > 40) _fail('$label里的单个名称最多 40 个字');
    if (seen.add(name)) result.add(name);
  }
  return result;
}

Map<String, dynamic> _parseExtra(Object? value, String label) {
  if (value == null) return const {};
  if (value is! Map) _fail('$label必须是对象');
  return Map<String, dynamic>.from(value);
}

List<Object?> _readArray(Object? value, String label) {
  if (value == null) return const [];
  if (value is! List) _fail('$label 必须是数组');
  return value;
}

Map<String, Object?> _asRecord(Object? value, String label) {
  if (value is! Map) _fail('$label必须是对象');
  return {
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}

ImportMedication _parseMedication(Object? value, int index) {
  final label = '第 ${index + 1} 条药物';
  final map = _asRecord(value, label);
  final defaultDose = _optionalNumber(map['defaultDose'], '$label的默认剂量');
  if (defaultDose != null && defaultDose < 0) {
    _fail('$label的默认剂量不能为负数');
  }
  return ImportMedication(
    name: _requireText(map['name'], '$label的药名', 40),
    genericName: _optionalText(map['genericName'], '$label的通用名', 40),
    brandNames: _parseNameList(map['brandNames'], '$label的商品名'),
    route: _parseRoute(map['route'], '$label的给药途径'),
    defaultDose: defaultDose,
    unit: _optionalText(map['unit'], '$label的单位', 20),
    catalogKey: _optionalText(map['catalogKey'], '$label的目录标识', 60),
    extra: _parseExtra(map['extra'], '$label的扩展字段'),
  );
}

ImportInjection _parseInjection(Object? value, int index) {
  final label = '第 ${index + 1} 条注射记录';
  final map = _asRecord(value, label);
  final injectedAt = parseLocalDateTime(map['injectedAt'], '$label的注射时间');
  final dose = _optionalNumber(map['dose'], '$label的剂量');
  if (dose != null && dose < 0) _fail('$label的剂量不能为负数');
  return ImportInjection(
    injectedAt: injectedAt,
    medicationName: _optionalText(map['medication'], '$label的药名'),
    dose: dose,
    unit: _optionalText(map['unit'], '$label的单位', 20),
    site: _parseSite(map['site'], '$label的注射部位'),
    lotNumber: _optionalText(map['lotNumber'], '$label的批号', 60),
    note: _optionalText(map['note'], '$label的备注'),
    status: _parseStatus(map['status'], '$label的状态'),
    lineLabel: _optionalText(map['lineLabel'], '$label的用药线名称', 60),
  );
}

ImportOralLog _parseOralLog(Object? value, int index) {
  final label = '第 ${index + 1} 条口服打卡';
  final map = _asRecord(value, label);
  final timeValue = map['takenAt'] ?? map['loggedAt'];
  final dose = _optionalNumber(map['dose'], '$label的剂量');
  if (dose != null && dose < 0) _fail('$label的剂量不能为负数');
  return ImportOralLog(
    takenAt: parseLocalDateTime(timeValue, '$label的记录时间'),
    medicationName: _optionalText(map['medication'], '$label的药名'),
    status: _parseStatus(map['status'], '$label的状态'),
    dose: dose,
    unit: _optionalText(map['unit'], '$label的单位', 20),
    note: _optionalText(map['note'], '$label的备注'),
    lineLabel: _optionalText(map['lineLabel'], '$label的用药线名称', 60),
  );
}

ImportSymptom _parseSymptom(Object? value, int index) {
  final label = '第 ${index + 1} 条症状记录';
  final map = _asRecord(value, label);
  final severity = _optionalInt(map['severity'], '$label的严重程度', 1, 5) ?? 3;
  final painScore = _optionalInt(map['painScore'], '$label的疼痛评分', 0, 10);
  final temperature = _optionalNumber(map['temperature'], '$label的体温');
  if (temperature != null && (temperature < 30 || temperature > 45)) {
    _fail('$label的体温应在 30℃ 到 45℃ 之间');
  }
  return ImportSymptom(
    loggedAt: parseLocalDateTime(map['loggedAt'], '$label的记录时间'),
    severity: severity,
    painScore: painScore,
    tags: _parseTags(map['tags'], '$label的症状'),
    temperature: temperature,
    note: _optionalText(map['note'], '$label的备注'),
    injectionAt: map['injectionAt'] == null
        ? null
        : parseLocalDateTime(map['injectionAt'], '$label的关联注射时间'),
  );
}

ImportLineState _parseLineState(Object? value, int index) {
  final label = '第 ${index + 1} 条用药线状态';
  final map = _asRecord(value, label);
  final endedAt = map['endedAt'] == null
      ? null
      : parseLocalDateTime(map['endedAt'], '$label的停用时间');
  if (endedAt != null &&
      endedAt > DateTime.now().millisecondsSinceEpoch + 24 * 60 * 60 * 1000) {
    _fail('$label的停用时间不能晚于今天');
  }
  return ImportLineState(
    lineLabel: _optionalText(map['lineLabel'], '$label的用药线名称', 60),
    medicationName: _optionalText(map['medication'], '$label的药名'),
    kind: _parseLineKind(map['kind'], '$label的类型'),
    endedAt: endedAt,
  );
}

ImportEfficacyEvent _parseEfficacyEvent(Object? value, int index) {
  final label = '第 ${index + 1} 条疗效记录';
  final map = _asRecord(value, label);
  return ImportEfficacyEvent(
    lineLabel: _optionalText(map['lineLabel'], '$label的用药线名称', 60),
    medicationName: _optionalText(map['medication'], '$label的药名'),
    kind: _parseEfficacyKind(map['kind'], '$label的类型'),
    occurredAt: parseLocalDateTime(map['occurredAt'], '$label的发生时间'),
    note: _optionalText(map['note'], '$label的备注'),
  );
}

ImportPayload parseImportRows(
  List<Object?> medicationRows,
  List<Object?> injectionRows,
  List<Object?> oralLogRows,
  List<Object?> symptomRows, [
  List<Object?> lineStateRows = const [],
  List<Object?> efficacyRows = const [],
]) {
  final total = medicationRows.length +
      injectionRows.length +
      oralLogRows.length +
      symptomRows.length +
      lineStateRows.length +
      efficacyRows.length;
  if (total == 0) _fail('文件里没有任何记录');

  for (final pair in [
    (medicationRows, '药物'),
    (injectionRows, '注射记录'),
    (oralLogRows, '口服打卡'),
    (symptomRows, '症状记录'),
    (lineStateRows, '用药线状态'),
    (efficacyRows, '疗效记录'),
  ]) {
    if (pair.$1.length > importMaxRows) {
      _fail('${pair.$2}最多 $importMaxRows 条，请拆分成多个文件');
    }
  }

  return ImportPayload(
    medications: [
      for (var i = 0; i < medicationRows.length; i += 1)
        _parseMedication(medicationRows[i], i),
    ],
    injections: [
      for (var i = 0; i < injectionRows.length; i += 1)
        _parseInjection(injectionRows[i], i),
    ],
    oralLogs: [
      for (var i = 0; i < oralLogRows.length; i += 1)
        _parseOralLog(oralLogRows[i], i),
    ],
    symptoms: [
      for (var i = 0; i < symptomRows.length; i += 1)
        _parseSymptom(symptomRows[i], i),
    ],
    lineStates: [
      for (var i = 0; i < lineStateRows.length; i += 1)
        _parseLineState(lineStateRows[i], i),
    ],
    efficacyEvents: [
      for (var i = 0; i < efficacyRows.length; i += 1)
        _parseEfficacyEvent(efficacyRows[i], i),
    ],
  );
}

ImportPayload parseImportJson(String text) {
  final cleaned = text.replaceFirst(RegExp(r'^\uFEFF'), '').trim();
  if (cleaned.isEmpty) _fail('文件是空的');

  Object? raw;
  try {
    raw = jsonDecode(cleaned);
  } catch (_) {
    _fail('文件不是有效的 JSON，请检查是否导出完整');
  }
  if (raw is! Map) _fail('文件格式不对：顶层必须是一个对象');

  if (raw['format'] != importFormat) {
    _fail('这不是 BioClock 的导入文件（缺少 format: "bioclock-import"）');
  }

  final version = raw['version'];
  if (version is! int ||
      version < importMinVersion ||
      version > importVersion) {
    _fail(
      '不支持的导入文件版本：$version，当前支持版本 $importMinVersion 到 $importVersion',
    );
  }

  return parseImportRows(
    _readArray(raw['medications'], 'medications'),
    _readArray(raw['injections'], 'injections'),
    _readArray(raw['oralLogs'], 'oralLogs'),
    _readArray(raw['symptoms'], 'symptoms'),
    _readArray(raw['lineStates'], 'lineStates'),
    _readArray(raw['efficacyEvents'], 'efficacyEvents'),
  );
}

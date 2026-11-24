import 'dart:convert';

import 'package:bioclock/db/database.dart';
import 'package:bioclock/models/types.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();
const int _oneDayMs = 24 * 60 * 60 * 1000;

/// 用于 Partial 更新中区分「未传入」与「显式设为 null」。
class PatchValue<T> {
  const PatchValue(this.value);
  final T value;
}

Never _fail(String message) => throw RepoValidationException(message);

Future<DatabaseExecutor> _resolveDb(DatabaseExecutor? executor) async {
  return executor ?? await AppDatabase.database;
}

// ---------------------------------------------------------------------------
// Input / Patch types
// ---------------------------------------------------------------------------

class MedicationInput {
  const MedicationInput({
    required this.name,
    this.genericName,
    this.brandNames = const [],
    this.defaultDose,
    required this.unit,
    required this.color,
    this.route = MedicationRoute.sc,
    this.diseaseIds = const [],
    this.catalogKey,
    this.isBuiltin = false,
    this.extra = const {},
  });

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
}

class MedicationPatch {
  const MedicationPatch({
    this.name,
    this.genericName,
    this.brandNames,
    this.defaultDose,
    this.unit,
    this.route,
    this.extra,
  });

  final String? name;
  final PatchValue<String?>? genericName;
  final List<String>? brandNames;
  final PatchValue<double?>? defaultDose;
  final String? unit;
  final MedicationRoute? route;
  final Map<String, dynamic>? extra;
}

class TreatmentLineInput {
  const TreatmentLineInput({
    required this.medicationId,
    required this.kind,
    required this.label,
    this.isHost = false,
    this.syncWithHost = false,
    this.anchor = RegimenAnchor.actual,
    this.windowDays = 2,
    this.endedAt,
    this.phases,
    this.oral,
  });

  final String medicationId;
  final LineKind kind;
  final String label;
  final bool isHost;
  final bool syncWithHost;
  final RegimenAnchor anchor;
  final int windowDays;
  final int? endedAt;
  final List<TreatmentPhaseInput>? phases;
  final OralPlan? oral;
}

class TreatmentInput {
  const TreatmentInput({required this.name, required this.lines});

  final String name;
  final List<TreatmentLineInput> lines;
}

class TreatmentLinePatch {
  const TreatmentLinePatch({
    required this.id,
    this.medicationId,
    this.label,
    this.isHost,
    this.syncWithHost,
    this.anchor,
    this.windowDays,
    this.endedAt,
    this.phases,
    this.oral,
  });

  final String id;
  final String? medicationId;
  final String? label;
  final bool? isHost;
  final bool? syncWithHost;
  final RegimenAnchor? anchor;
  final int? windowDays;
  final PatchValue<int?>? endedAt;
  final List<TreatmentPhaseInput>? phases;
  final OralPlan? oral;
}

class TreatmentPatch {
  const TreatmentPatch({
    this.name,
    this.lines,
    this.removeLines,
    this.addLines,
  });

  final String? name;
  final List<TreatmentLinePatch>? lines;
  final List<String>? removeLines;
  final List<TreatmentLineInput>? addLines;
}

class EfficacyEventInput {
  const EfficacyEventInput({
    required this.lineId,
    required this.kind,
    required this.occurredAt,
    this.note,
    this.stopLine = false,
  });

  final String lineId;
  final EfficacyKind kind;
  final int occurredAt;
  final String? note;
  final bool stopLine;
}

class DoseLogInput {
  const DoseLogInput({
    required this.lineId,
    required this.scheduledAt,
    required this.takenAt,
    required this.status,
    this.dose,
    this.unit,
    this.site,
    this.lotNumber,
    this.note,
  });

  final String lineId;
  final int? scheduledAt;
  final int? takenAt;
  final DoseStatus status;
  final double? dose;
  final String? unit;
  final InjectionSite? site;
  final String? lotNumber;
  final String? note;
}

class DoseLogPatch {
  const DoseLogPatch({
    this.scheduledAt,
    this.takenAt,
    this.status,
    this.dose,
    this.unit,
    this.site,
    this.lotNumber,
    this.note,
  });

  final PatchValue<int?>? scheduledAt;
  final PatchValue<int?>? takenAt;
  final DoseStatus? status;
  final PatchValue<double?>? dose;
  final PatchValue<String?>? unit;
  final PatchValue<InjectionSite?>? site;
  final PatchValue<String?>? lotNumber;
  final PatchValue<String?>? note;
}

class SymptomLogInput {
  const SymptomLogInput({
    required this.loggedAt,
    required this.severity,
    this.painScore,
    required this.tags,
    this.note,
    this.temperature,
    this.injectionId,
  });

  final int loggedAt;
  final int severity;
  final int? painScore;
  final List<String> tags;
  final String? note;
  final double? temperature;
  final String? injectionId;
}

class SymptomLogPatch {
  const SymptomLogPatch({
    this.loggedAt,
    this.severity,
    this.painScore,
    this.tags,
    this.note,
    this.temperature,
    this.injectionId,
  });

  final int? loggedAt;
  final int? severity;
  final PatchValue<int?>? painScore;
  final List<String>? tags;
  final PatchValue<String?>? note;
  final PatchValue<double?>? temperature;
  final PatchValue<String?>? injectionId;
}

class ReminderRuleInput {
  const ReminderRuleInput({
    required this.treatmentId,
    required this.offsets,
    required this.timeOfDay,
    required this.snoozeMinutes,
    required this.enabled,
    this.id,
  });

  final String treatmentId;
  final List<int> offsets;
  final String timeOfDay;
  final int snoozeMinutes;
  final bool enabled;
  final String? id;
}

// ---------------------------------------------------------------------------
// Row Mappers
// ---------------------------------------------------------------------------

int? _asInt(Object? v) => v == null ? null : (v as num).toInt();
double? _asDouble(Object? v) => v == null ? null : (v as num).toDouble();

Map<String, dynamic> _parseExtra(String? raw) {
  if (raw == null || raw.isEmpty) return const {};
  try {
    final parsed = jsonDecode(raw);
    if (parsed is Map<String, dynamic>) return parsed;
    if (parsed is Map) return Map<String, dynamic>.from(parsed);
  } catch (_) {}
  return const {};
}

List<String> _parseStringArray(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final parsed = jsonDecode(raw);
    if (parsed is List) {
      return parsed.whereType<String>().toList();
    }
  } catch (_) {}
  return const [];
}

List<int> _parseDaysOfWeek(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final parsed = jsonDecode(raw);
    if (parsed is List) {
      return parsed
          .whereType<num>()
          .map((e) => e.toInt())
          .where((d) => d >= 0 && d <= 6)
          .toList();
    }
  } catch (_) {}
  return const [];
}

List<int> _parseOffsets(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final parsed = jsonDecode(raw);
    if (parsed is List) {
      return parsed.whereType<num>().map((e) => e.toInt()).toList();
    }
  } catch (_) {}
  return const [];
}

Medication _mapMedication(Map<String, Object?> row) {
  return Medication(
    id: row['id'] as String,
    name: row['name'] as String,
    genericName: row['generic_name'] as String?,
    brandNames: _parseStringArray(row['brand_names'] as String?),
    defaultDose: _asDouble(row['default_dose']),
    unit: row['unit'] as String,
    color: row['color'] as String,
    route: MedicationRoute.tryParse(row['route'] as String?) ??
        MedicationRoute.sc,
    diseaseIds: _parseStringArray(row['disease_ids'] as String?),
    catalogKey: row['catalog_key'] as String?,
    isBuiltin: _asInt(row['is_builtin']) == 1,
    extra: _parseExtra(row['extra'] as String?),
    createdAt: _asInt(row['created_at']) ?? 0,
  );
}

TreatmentPhase _mapTreatmentPhase(Map<String, Object?> row) {
  return TreatmentPhase(
    id: row['id'] as String,
    lineId: row['line_id'] as String,
    orderIdx: _asInt(row['order_idx']) ?? 0,
    kind: PhaseKind.tryParse(row['kind'] as String?) ?? PhaseKind.maintenance,
    intervalDays: _asInt(row['interval_days']) ?? 1,
    repeatCount: _asInt(row['repeat_count']) ?? 0,
    dose: _asDouble(row['dose']),
    unit: row['unit'] as String,
    effectiveFrom: _asInt(row['effective_from']),
  );
}

OralPlan? _mapOralPlan(Map<String, Object?> row) {
  if (row['kind'] != 'oral') return null;
  final oralStart = _asInt(row['oral_start']);
  final oralFreq = OralFrequency.tryParse(row['oral_frequency'] as String?);
  if (oralStart == null || oralFreq == null) return null;
  return OralPlan(
    startDate: oralStart,
    durationDays: _asInt(row['oral_duration_days']),
    frequency: oralFreq,
    timesPerPeriod: _asInt(row['oral_times_per_period']) ?? 0,
    daysOfWeek: _parseDaysOfWeek(row['oral_days_of_week'] as String?),
    remindTime: (row['oral_remind_time'] as String?) ?? '09:00',
  );
}

TreatmentLine _mapTreatmentLine(
  Map<String, Object?> row,
  List<TreatmentPhase> phases,
) {
  return TreatmentLine(
    id: row['id'] as String,
    treatmentId: row['treatment_id'] as String,
    medicationId: row['medication_id'] as String,
    kind: LineKind.tryParse(row['kind'] as String?) ?? LineKind.injection,
    label: row['label'] as String,
    isHost: _asInt(row['is_host']) == 1,
    syncWithHost: _asInt(row['sync_with_host']) == 1,
    anchor:
        RegimenAnchor.tryParse(row['anchor'] as String?) ?? RegimenAnchor.actual,
    windowDays: _asInt(row['window_days']) ?? 2,
    endedAt: _asInt(row['ended_at']),
    phases: phases,
    oral: _mapOralPlan(row),
  );
}

Treatment _mapTreatment(Map<String, Object?> row, List<TreatmentLine> lines) {
  return Treatment(
    id: row['id'] as String,
    name: row['name'] as String,
    isActive: _asInt(row['is_active']) == 1,
    createdAt: _asInt(row['created_at']) ?? 0,
    lines: lines,
  );
}

DoseLog _mapDoseLog(Map<String, Object?> row) {
  return DoseLog(
    id: row['id'] as String,
    lineId: row['line_id'] as String,
    scheduledAt: _asInt(row['scheduled_at']),
    takenAt: _asInt(row['taken_at']),
    status: DoseStatus.tryParse(row['status'] as String?) ?? DoseStatus.done,
    dose: _asDouble(row['dose']),
    unit: (row['unit'] as String?) ?? '',
    site: InjectionSite.tryParse(row['site'] as String?),
    lotNumber: row['lot_number'] as String?,
    note: row['note'] as String?,
    createdAt: _asInt(row['created_at']) ?? 0,
    updatedAt: _asInt(row['updated_at']) ?? 0,
  );
}

EfficacyEvent _mapEfficacyEvent(Map<String, Object?> row) {
  return EfficacyEvent(
    id: row['id'] as String,
    lineId: row['line_id'] as String,
    kind: EfficacyKind.tryParse(row['kind'] as String?) ?? EfficacyKind.other,
    occurredAt: _asInt(row['occurred_at']) ?? 0,
    dosesCount: _asInt(row['doses_count']) ?? 0,
    note: row['note'] as String?,
    createdAt: _asInt(row['created_at']) ?? 0,
  );
}

SymptomLog _mapSymptom(Map<String, Object?> row) {
  final rawPain = _asDouble(row['pain_score']);
  return SymptomLog(
    id: row['id'] as String,
    loggedAt: _asInt(row['logged_at']) ?? 0,
    severity: (_asInt(row['severity']) ?? 1).clamp(1, 5),
    painScore: rawPain?.round(),
    tags: _parseStringArray(row['tags'] as String?),
    note: row['note'] as String?,
    temperature: _asDouble(row['temperature']),
    injectionId: row['dose_log_id'] as String?,
  );
}

SymptomTag _mapSymptomTag(Map<String, Object?> row) {
  return SymptomTag(
    id: row['id'] as String,
    name: row['name'] as String,
    isBuiltin: _asInt(row['is_builtin']) == 1,
    sortOrder: _asInt(row['sort_order']) ?? 0,
    createdAt: _asInt(row['created_at']) ?? 0,
  );
}

ReminderRuleV5 _mapReminderRule(Map<String, Object?> row) {
  return ReminderRuleV5(
    id: row['id'] as String,
    treatmentId: row['treatment_id'] as String,
    offsets: _parseOffsets(row['offsets'] as String?),
    timeOfDay: row['time_of_day'] as String,
    snoozeMinutes: _asInt(row['snooze_minutes']) ?? 10,
    enabled: _asInt(row['enabled']) == 1,
  );
}

// ---------------------------------------------------------------------------
// Validations
// ---------------------------------------------------------------------------

String _requireNonEmptyString(String? value, String label) {
  if (value == null || value.trim().isEmpty) {
    _fail('$label不能为空');
  }
  return value.trim();
}

int _requireTimestamp(int? value, String label) {
  if (value == null || value <= 0) {
    _fail('$label必须是有效时间戳');
  }
  return value;
}

int? _normalizeEndedAt(int? value) {
  if (value == null) return null;
  final ts = _requireTimestamp(value, '停用时间');
  final now = DateTime.now().millisecondsSinceEpoch;
  if (ts > now + _oneDayMs) {
    _fail('停用时间不能晚于今天');
  }
  return ts;
}

double? _requireNullableDose(double? value, String label) {
  if (value == null) return null;
  if (value.isNaN || value.isInfinite) {
    _fail('$label必须是有效数字');
  }
  if (value < 0) {
    _fail('$label不能为负数');
  }
  return value;
}

int _requireInteger(int value, String label, [int? min]) {
  if (min != null && value < min) {
    _fail('$label不能小于 $min');
  }
  return value;
}

final RegExp _timeOfDayRe = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

String _requireTimeOfDay(String value, String label) {
  if (!_timeOfDayRe.hasMatch(value)) {
    _fail('$label格式必须为 HH:mm');
  }
  return value;
}

List<int> _normalizeDaysOfWeek(List<int> days) {
  final seen = <int>{};
  for (final d in days) {
    if (d < 0 || d > 6) _fail('服药星期必须在 0 到 6 之间');
    seen.add(d);
  }
  final list = seen.toList()..sort();
  return list;
}

List<String> _normalizeNames(List<String> values, String label) {
  final seen = <String>{};
  final result = <String>[];
  for (final raw in values) {
    final name = _requireNonEmptyString(raw, label);
    if (name.length > 40) _fail('$label单项最多 40 个字');
    if (seen.add(name)) result.add(name);
  }
  return result;
}

String? _normalizeOptionalText(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? _normalizeOptionalId(String? value, String label) {
  if (value == null) return null;
  return _requireNonEmptyString(value, label);
}

double? _normalizeTemperature(double? value) {
  if (value == null) return null;
  if (value.isNaN || value.isInfinite) _fail('体温必须是有效数字');
  if (value < 30 || value > 45) _fail('体温必须在 30℃ 到 45℃ 之间');
  return value;
}

int? _normalizePainScore(int? value) {
  if (value == null) return null;
  if (value < 0 || value > 10) _fail('疼痛评分必须在 0 到 10 之间');
  return value;
}

List<String> _normalizeTags(List<String> tags) {
  final seen = <String>{};
  final result = <String>[];
  for (final tag in tags) {
    final name = _requireNonEmptyString(tag, '症状标签');
    if (name.length > 20) _fail('症状名称最多 20 个字');
    if (seen.add(name)) result.add(name);
  }
  return result;
}

// ---------------------------------------------------------------------------
// Internal queries
// ---------------------------------------------------------------------------

Future<Map<String, Object?>?> _getMedicationRow(
    DatabaseExecutor db, String id) async {
  final rows = await db.rawQuery(
    'SELECT * FROM medication WHERE id = ? LIMIT 1',
    [id],
  );
  return rows.isEmpty ? null : rows.first;
}

Future<Map<String, Object?>?> _getTreatmentRow(
    DatabaseExecutor db, String id) async {
  final rows = await db.rawQuery(
    'SELECT * FROM treatment WHERE id = ? LIMIT 1',
    [id],
  );
  return rows.isEmpty ? null : rows.first;
}

Future<Map<String, Object?>?> _getTreatmentLineRow(
    DatabaseExecutor db, String id) async {
  final rows = await db.rawQuery(
    'SELECT * FROM treatment_line WHERE id = ? LIMIT 1',
    [id],
  );
  return rows.isEmpty ? null : rows.first;
}

Future<Map<String, Object?>?> _getDoseLogRow(
    DatabaseExecutor db, String id) async {
  final rows = await db.rawQuery(
    'SELECT * FROM dose_log WHERE id = ? LIMIT 1',
    [id],
  );
  return rows.isEmpty ? null : rows.first;
}

Future<Map<String, Object?>?> _getSymptomRow(
    DatabaseExecutor db, String id) async {
  final rows = await db.rawQuery(
    'SELECT * FROM symptom_log WHERE id = ? LIMIT 1',
    [id],
  );
  return rows.isEmpty ? null : rows.first;
}

Future<Map<String, Object?>?> _getReminderRowFor(
    DatabaseExecutor db, String treatmentId) async {
  final rows = await db.rawQuery(
    'SELECT * FROM reminder_rule WHERE treatment_id = ? LIMIT 1',
    [treatmentId],
  );
  return rows.isEmpty ? null : rows.first;
}

Future<Map<String, Object?>> _requireMedicationExists(
    DatabaseExecutor db, String id) async {
  final row = await _getMedicationRow(db, id);
  if (row == null) _fail('所选药物不存在');
  return row;
}

Future<Map<String, Object?>> _requireTreatmentExists(
    DatabaseExecutor db, String id) async {
  final row = await _getTreatmentRow(db, id);
  if (row == null) _fail('治疗方案不存在');
  return row;
}

Future<Map<String, Object?>> _requireTreatmentLineExists(
    DatabaseExecutor db, String id) async {
  final row = await _getTreatmentLineRow(db, id);
  if (row == null) _fail('治疗方案里的用药条目不存在');
  return row;
}

Future<List<Treatment>> _loadTreatments(
  DatabaseExecutor db,
  List<Map<String, Object?>> rows,
) async {
  if (rows.isEmpty) return const [];

  final treatmentIds = rows.map((r) => r['id'] as String).toList();
  final placeholders = List.filled(treatmentIds.length, '?').join(', ');
  final lineRows = await db.rawQuery(
    '''SELECT * FROM treatment_line
        WHERE treatment_id IN ($placeholders)
        ORDER BY is_host DESC, rowid ASC''',
    treatmentIds,
  );

  final phasesByLine = <String, List<TreatmentPhase>>{};
  if (lineRows.isNotEmpty) {
    final lineIds = lineRows.map((r) => r['id'] as String).toList();
    final linePlaceholders = List.filled(lineIds.length, '?').join(', ');
    final phaseRows = await db.rawQuery(
      '''SELECT * FROM treatment_phase
          WHERE line_id IN ($linePlaceholders)
          ORDER BY order_idx ASC''',
      lineIds,
    );
    for (final phase in phaseRows) {
      final lineId = phase['line_id'] as String;
      (phasesByLine[lineId] ??= []).add(_mapTreatmentPhase(phase));
    }
  }

  final linesByTreatment = <String, List<TreatmentLine>>{};
  for (final lineRow in lineRows) {
    final tid = lineRow['treatment_id'] as String;
    final lid = lineRow['id'] as String;
    final line = _mapTreatmentLine(lineRow, phasesByLine[lid] ?? const []);
    (linesByTreatment[tid] ??= []).add(line);
  }

  return rows
      .map((row) =>
          _mapTreatment(row, linesByTreatment[row['id'] as String] ?? const []))
      .toList();
}

// ---------------------------------------------------------------------------
// Repositories
// ---------------------------------------------------------------------------

abstract final class MedicationsRepo {
  static Future<List<Medication>> list({DatabaseExecutor? executor}) async {
    final db = await _resolveDb(executor);
    final rows = await db.rawQuery(
      'SELECT * FROM medication ORDER BY is_builtin DESC, created_at ASC, name ASC',
    );
    return rows.map(_mapMedication).toList();
  }

  static Future<List<Medication>> listForDisease(
    String diseaseId, {
    DatabaseExecutor? executor,
  }) async {
    final safeId = _requireNonEmptyString(diseaseId, '病种 ID');
    final all = await list(executor: executor);
    return all
        .where((med) => med.isBuiltin && med.diseaseIds.contains(safeId))
        .toList();
  }

  static Future<Medication?> get(
    String id, {
    DatabaseExecutor? executor,
  }) async {
    final safeId = _requireNonEmptyString(id, '药物 ID');
    final db = await _resolveDb(executor);
    final row = await _getMedicationRow(db, safeId);
    return row == null ? null : _mapMedication(row);
  }

  static Future<Medication> create(
    MedicationInput input, {
    DatabaseExecutor? executor,
  }) async {
    final name = _requireNonEmptyString(input.name, '药物名称');
    final unit = _requireNonEmptyString(input.unit, '单位');
    final color = _requireNonEmptyString(input.color, '颜色');
    final defaultDose = _requireNullableDose(input.defaultDose, '默认剂量');
    final genericName = input.genericName == null
        ? null
        : _requireNonEmptyString(input.genericName, '通用名');
    final catalogKey = input.catalogKey == null
        ? null
        : _requireNonEmptyString(input.catalogKey, '目录标识');
    final brandNames = _normalizeNames(input.brandNames, '商品名');
    final diseaseIds = input.diseaseIds.where((id) => id.isNotEmpty).toList();

    final db = await _resolveDb(executor);
    if (catalogKey != null) {
      final duplicate = await db.rawQuery(
        'SELECT id FROM medication WHERE catalog_key = ? LIMIT 1',
        [catalogKey],
      );
      if (duplicate.isNotEmpty) {
        _fail('目录标识已存在，不能重复创建药物');
      }
    }

    final row = <String, Object?>{
      'id': _uuid.v4(),
      'name': name,
      'generic_name': genericName,
      'brand_names': jsonEncode(brandNames),
      'default_dose': defaultDose,
      'unit': unit,
      'color': color,
      'route': input.route.wire,
      'disease_ids': jsonEncode(diseaseIds),
      'catalog_key': catalogKey,
      'is_builtin': input.isBuiltin ? 1 : 0,
      'extra': jsonEncode(input.extra),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    };

    await db.rawInsert(
      '''INSERT INTO medication
          (id, name, generic_name, brand_names, default_dose, unit, color, route,
           disease_ids, catalog_key, is_builtin, extra, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        row['id'],
        row['name'],
        row['generic_name'],
        row['brand_names'],
        row['default_dose'],
        row['unit'],
        row['color'],
        row['route'],
        row['disease_ids'],
        row['catalog_key'],
        row['is_builtin'],
        row['extra'],
        row['created_at'],
      ],
    );
    return _mapMedication(row);
  }

  static Future<Medication> update(
    String id,
    MedicationPatch patch, {
    DatabaseExecutor? executor,
  }) async {
    final safeId = _requireNonEmptyString(id, '药物 ID');
    final db = await _resolveDb(executor);
    final row = await _getMedicationRow(db, safeId);
    if (row == null) _fail('药物不存在');

    final builtin = _asInt(row['is_builtin']) == 1;
    if (builtin) {
      if (patch.name != null ||
          patch.genericName != null ||
          patch.brandNames != null ||
          patch.route != null) {
        _fail('内置药物的名称与给药途径来自目录，不能修改');
      }
    }

    final sets = <String>[];
    final values = <Object?>[];

    if (patch.name != null) {
      sets.add('name = ?');
      values.add(_requireNonEmptyString(patch.name, '药物名称'));
    }
    if (patch.genericName != null) {
      sets.add('generic_name = ?');
      final g = patch.genericName!.value;
      values.add(g == null ? null : _requireNonEmptyString(g, '通用名'));
    }
    if (patch.brandNames != null) {
      sets.add('brand_names = ?');
      values.add(jsonEncode(_normalizeNames(patch.brandNames!, '商品名')));
    }
    if (patch.defaultDose != null) {
      sets.add('default_dose = ?');
      values.add(_requireNullableDose(patch.defaultDose!.value, '默认剂量'));
    }
    if (patch.unit != null) {
      sets.add('unit = ?');
      values.add(_requireNonEmptyString(patch.unit, '单位'));
    }
    if (patch.route != null) {
      sets.add('route = ?');
      values.add(patch.route!.wire);
    }
    if (patch.extra != null) {
      sets.add('extra = ?');
      values.add(jsonEncode(patch.extra));
    }

    if (sets.isEmpty) return _mapMedication(row);

    values.add(safeId);
    await db.rawUpdate(
      'UPDATE medication SET ${sets.join(', ')} WHERE id = ?',
      values,
    );

    final updated = await _getMedicationRow(db, safeId);
    if (updated == null) _fail('药物不存在');
    return _mapMedication(updated);
  }

  static Future<void> remove(
    String id, {
    DatabaseExecutor? executor,
  }) async {
    final safeId = _requireNonEmptyString(id, '药物 ID');
    final db = await _resolveDb(executor);
    final row = await _getMedicationRow(db, safeId);
    if (row == null) _fail('药物不存在');
    if (_asInt(row['is_builtin']) == 1) _fail('内置药物不可删除');

    final used = await db.rawQuery(
      'SELECT id FROM treatment_line WHERE medication_id = ? LIMIT 1',
      [safeId],
    );
    if (used.isNotEmpty) _fail('该药物已被治疗方案使用，请先删除相关方案');

    await db.rawDelete('DELETE FROM medication WHERE id = ?', [safeId]);
  }
}

class _NormalizedLine {
  const _NormalizedLine({required this.row, required this.phases});
  final Map<String, Object?> row;
  final List<Map<String, Object?>> phases;
}

OralPlan _normalizeOralPlan(OralPlan? plan) {
  if (plan == null) _fail('口服计划不能为空');
  final startDate = _requireTimestamp(plan.startDate, '开始服药时间');
  final durationDays = plan.durationDays == null
      ? null
      : _requireInteger(plan.durationDays!, '服药天数', 1);
  var timesPerPeriod = 0;
  var daysOfWeek = <int>[];
  if (plan.frequency == OralFrequency.weekly) {
    timesPerPeriod = _requireInteger(plan.timesPerPeriod, '每周服药次数', 1);
    if (timesPerPeriod > 7) _fail('每周服药次数不能超过 7');
  } else if (plan.frequency == OralFrequency.custom) {
    daysOfWeek = _normalizeDaysOfWeek(plan.daysOfWeek);
    if (daysOfWeek.isEmpty) _fail('请至少选择一天服药');
  }
  final remindTime = _requireTimeOfDay(plan.remindTime, '服药提醒时间');
  return OralPlan(
    startDate: startDate,
    durationDays: durationDays,
    frequency: plan.frequency,
    timesPerPeriod: timesPerPeriod,
    daysOfWeek: daysOfWeek,
    remindTime: remindTime,
  );
}

List<Map<String, Object?>> _normalizePhases(
  String lineId,
  List<TreatmentPhaseInput>? phases,
) {
  if (phases == null || phases.isEmpty) {
    _fail('注射用药至少需要一个阶段');
  }

  final rows = phases.map((phase) {
    final orderIdx = _requireInteger(phase.orderIdx, '阶段顺序', 0);
    final intervalDays = _requireInteger(phase.intervalDays, '间隔天数', 1);
    final repeatCount = _requireInteger(phase.repeatCount, '重复次数', 0);
    final dose = _requireNullableDose(phase.dose, '阶段剂量');
    final unit = _requireNonEmptyString(phase.unit, '阶段单位');
    final effectiveFrom = phase.effectiveFrom == null
        ? null
        : _requireTimestamp(phase.effectiveFrom, '阶段生效时间');
    return <String, Object?>{
      'id': _uuid.v4(),
      'line_id': lineId,
      'order_idx': orderIdx,
      'kind': phase.kind.wire,
      'interval_days': intervalDays,
      'repeat_count': repeatCount,
      'dose': dose,
      'unit': unit,
      'effective_from': effectiveFrom,
    };
  }).toList();

  final seen = <int>{};
  for (final phase in rows) {
    final idx = phase['order_idx'] as int;
    if (!seen.add(idx)) _fail('阶段顺序不能重复');
  }
  rows.sort((a, b) => (a['order_idx'] as int) - (b['order_idx'] as int));
  return rows;
}

_NormalizedLine _normalizeLine(String treatmentId, TreatmentLineInput input) {
  final medicationId = _requireNonEmptyString(input.medicationId, '药物 ID');
  final label = _requireNonEmptyString(input.label, '用药条目名称');
  final windowDays = _requireInteger(input.windowDays, '按时窗口', 0);
  if (input.isHost && input.syncWithHost) _fail('主药不能同时跟随其他主药');
  if (input.kind == LineKind.oral && input.isHost) _fail('口服用药不能设为主药');
  if (input.kind == LineKind.oral && input.syncWithHost) {
    _fail('口服用药不参与跟随主药');
  }

  final lineId = _uuid.v4();
  final row = <String, Object?>{
    'id': lineId,
    'treatment_id': treatmentId,
    'medication_id': medicationId,
    'kind': input.kind.wire,
    'label': label,
    'is_host': input.isHost ? 1 : 0,
    'sync_with_host': input.syncWithHost ? 1 : 0,
    'anchor': input.anchor.wire,
    'window_days': windowDays,
    'ended_at': _normalizeEndedAt(input.endedAt),
    'oral_start': null,
    'oral_duration_days': null,
    'oral_frequency': null,
    'oral_times_per_period': null,
    'oral_days_of_week': null,
    'oral_remind_time': null,
  };

  if (input.kind == LineKind.oral) {
    final oral = _normalizeOralPlan(input.oral);
    row['oral_start'] = oral.startDate;
    row['oral_duration_days'] = oral.durationDays;
    row['oral_frequency'] = oral.frequency.wire;
    row['oral_times_per_period'] = oral.timesPerPeriod;
    row['oral_days_of_week'] = jsonEncode(oral.daysOfWeek);
    row['oral_remind_time'] = oral.remindTime;
    return _NormalizedLine(row: row, phases: const []);
  }

  final phases = _normalizePhases(lineId, input.phases);
  return _NormalizedLine(row: row, phases: phases);
}

Future<void> _insertLine(DatabaseExecutor db, _NormalizedLine line) async {
  final row = line.row;
  await db.rawInsert(
    '''INSERT INTO treatment_line
        (id, treatment_id, medication_id, kind, label, is_host, sync_with_host, anchor,
         window_days, ended_at, oral_start, oral_duration_days, oral_frequency,
         oral_times_per_period, oral_days_of_week, oral_remind_time)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
    [
      row['id'],
      row['treatment_id'],
      row['medication_id'],
      row['kind'],
      row['label'],
      row['is_host'],
      row['sync_with_host'],
      row['anchor'],
      row['window_days'],
      row['ended_at'],
      row['oral_start'],
      row['oral_duration_days'],
      row['oral_frequency'],
      row['oral_times_per_period'],
      row['oral_days_of_week'],
      row['oral_remind_time'],
    ],
  );
  for (final phase in line.phases) {
    await db.rawInsert(
      '''INSERT INTO treatment_phase
          (id, line_id, order_idx, kind, interval_days, repeat_count, dose, unit, effective_from)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        phase['id'],
        phase['line_id'],
        phase['order_idx'],
        phase['kind'],
        phase['interval_days'],
        phase['repeat_count'],
        phase['dose'],
        phase['unit'],
        phase['effective_from'],
      ],
    );
  }
}

class _PreparedLineUpdate {
  const _PreparedLineUpdate({
    required this.id,
    required this.sets,
    required this.values,
    required this.phases,
    required this.isHost,
    required this.medicationId,
  });

  final String id;
  final List<String> sets;
  final List<Object?> values;
  final List<Map<String, Object?>>? phases;
  final int? isHost;
  final String? medicationId;
}

class _FinalLineState {
  _FinalLineState({
    required this.medicationId,
    required this.kind,
    required this.isHost,
  });
  String medicationId;
  final String kind;
  bool isHost;
}

abstract final class TreatmentsRepo {
  static Future<List<Treatment>> list({DatabaseExecutor? executor}) async {
    final db = await _resolveDb(executor);
    final rows = await db.rawQuery(
      'SELECT * FROM treatment ORDER BY created_at ASC',
    );
    return _loadTreatments(db, rows);
  }

  static Future<Treatment?> getActive({DatabaseExecutor? executor}) async {
    final db = await _resolveDb(executor);
    final rows = await db.rawQuery(
      'SELECT * FROM treatment WHERE is_active = 1 ORDER BY created_at DESC LIMIT 1',
    );
    if (rows.isEmpty) return null;
    final loaded = await _loadTreatments(db, rows);
    return loaded.first;
  }

  static Future<Treatment?> get(
    String id, {
    DatabaseExecutor? executor,
  }) async {
    final safeId = _requireNonEmptyString(id, '治疗方案 ID');
    final db = await _resolveDb(executor);
    final row = await _getTreatmentRow(db, safeId);
    if (row == null) return null;
    final loaded = await _loadTreatments(db, [row]);
    return loaded.first;
  }

  static Future<Treatment> create(
    TreatmentInput input, {
    DatabaseExecutor? executor,
  }) async {
    final name = _requireNonEmptyString(input.name, '治疗方案名称');
    if (input.lines.isEmpty) _fail('治疗方案至少需要一种药');

    Future<Treatment> run(DatabaseExecutor db) async {
      final treatmentId = _uuid.v4();
      final createdAt = DateTime.now().millisecondsSinceEpoch;
      final lineKeys = <String>{};
      final lines = <_NormalizedLine>[];

      for (final lineInput in input.lines) {
        final medicationId =
            _requireNonEmptyString(lineInput.medicationId, '药物 ID');
        await _requireMedicationExists(db, medicationId);
        final normalized = _normalizeLine(treatmentId, lineInput);
        final key =
            '${normalized.row['kind']}:${normalized.row['medication_id']}';
        if (!lineKeys.add(key)) {
          _fail('同一个治疗方案里不能重复添加同一种药');
        }
        lines.add(normalized);
      }

      final hosts = lines.where((l) => l.row['is_host'] == 1).length;
      if (hosts > 1) _fail('一个治疗方案只能有一个主药');

      final row = <String, Object?>{
        'id': treatmentId,
        'name': name,
        'is_active': 0,
        'created_at': createdAt,
      };

      await db.rawInsert(
        'INSERT INTO treatment (id, name, is_active, created_at) VALUES (?, ?, ?, ?)',
        [row['id'], row['name'], row['is_active'], row['created_at']],
      );
      for (final line in lines) {
        await _insertLine(db, line);
      }

      final loaded = await _loadTreatments(db, [row]);
      return loaded.first;
    }

    if (executor != null) return run(executor);
    return AppDatabase.runInTransaction((txn) => run(txn));
  }

  static Future<TreatmentLine> addLine(
    String treatmentId,
    TreatmentLineInput input, {
    DatabaseExecutor? executor,
  }) async {
    final tid = _requireNonEmptyString(treatmentId, '治疗方案 ID');
    final db = await _resolveDb(executor);
    await _requireTreatmentExists(db, tid);

    final medicationId = _requireNonEmptyString(input.medicationId, '药物 ID');
    await _requireMedicationExists(db, medicationId);

    final duplicate = await db.rawQuery(
      'SELECT id FROM treatment_line WHERE treatment_id = ? AND medication_id = ? AND kind = ? LIMIT 1',
      [tid, medicationId, input.kind.wire],
    );
    if (duplicate.isNotEmpty) {
      _fail('同一个治疗方案里不能重复添加同一种药');
    }

    final normalized = _normalizeLine(tid, input);
    if (normalized.row['is_host'] == 1) {
      final host = await db.rawQuery(
        'SELECT id FROM treatment_line WHERE treatment_id = ? AND is_host = 1 LIMIT 1',
        [tid],
      );
      if (host.isNotEmpty) _fail('一个治疗方案只能有一个主药');
    }

    await _insertLine(db, normalized);
    return _mapTreatmentLine(
      normalized.row,
      normalized.phases.map(_mapTreatmentPhase).toList(),
    );
  }

  static Future<void> removeLine(
    String lineId, {
    DatabaseExecutor? executor,
  }) async {
    final safeId = _requireNonEmptyString(lineId, '用药线 ID');
    final db = await _resolveDb(executor);
    final row = await db.rawQuery(
      'SELECT id FROM treatment_line WHERE id = ? LIMIT 1',
      [safeId],
    );
    if (row.isEmpty) _fail('用药线不存在');
    await db.rawDelete('DELETE FROM treatment_line WHERE id = ?', [safeId]);
  }

  static Future<TreatmentLine> setLineEnded(
    String lineId,
    int? endedAt, {
    DatabaseExecutor? executor,
  }) async {
    final safeId = _requireNonEmptyString(lineId, '用药线 ID');
    final db = await _resolveDb(executor);
    await _requireTreatmentLineExists(db, safeId);
    final value = _normalizeEndedAt(endedAt);
    await db.rawUpdate(
      '''UPDATE treatment_line
          SET ended_at = CASE
            WHEN ? IS NULL THEN NULL
            WHEN ended_at IS NULL OR ended_at > ? THEN ?
            ELSE ended_at
          END
          WHERE id = ?''',
      [value, value, value, safeId],
    );
    final updated = await _getTreatmentLineRow(db, safeId);
    if (updated == null) _fail('用药线不存在');
    final phaseRows = await db.rawQuery(
      'SELECT * FROM treatment_phase WHERE line_id = ? ORDER BY order_idx ASC',
      [safeId],
    );
    return _mapTreatmentLine(
      updated,
      phaseRows.map(_mapTreatmentPhase).toList(),
    );
  }

  static Future<void> setActive(
    String id,
    bool active, {
    DatabaseExecutor? executor,
  }) async {
    final safeId = _requireNonEmptyString(id, '治疗方案 ID');
    Future<void> run(DatabaseExecutor db) async {
      await _requireTreatmentExists(db, safeId);
      if (active) {
        await db.rawUpdate(
          'UPDATE treatment SET is_active = 0 WHERE id <> ?',
          [safeId],
        );
      }
      await db.rawUpdate(
        'UPDATE treatment SET is_active = ? WHERE id = ?',
        [active ? 1 : 0, safeId],
      );
    }

    if (executor != null) {
      await run(executor);
    } else {
      await AppDatabase.runInTransaction((txn) => run(txn));
    }
  }

  static Future<Treatment> update(
    String id,
    TreatmentPatch patch, {
    DatabaseExecutor? executor,
  }) async {
    final safeId = _requireNonEmptyString(id, '治疗方案 ID');

    Future<Treatment> run(DatabaseExecutor db) async {
      final existing = await _requireTreatmentExists(db, safeId);
      final newName =
          patch.name != null ? _requireNonEmptyString(patch.name, '治疗方案名称') : null;

      final linePatches = patch.lines ?? const [];
      final prepared = <_PreparedLineUpdate>[];
      final seenLines = <String>{};

      for (final linePatch in linePatches) {
        final lineId = _requireNonEmptyString(linePatch.id, '用药条目 ID');
        if (!seenLines.add(lineId)) _fail('同一条用药条目不能重复修改');
        final lineRow = await _requireTreatmentLineExists(db, lineId);
        if (lineRow['treatment_id'] != safeId) _fail('用药条目不属于该治疗方案');

        final sets = <String>[];
        final values = <Object?>[];
        int? isHost;
        String? medicationId;
        final kind = lineRow['kind'] as String;

        if (linePatch.medicationId != null) {
          medicationId =
              _requireNonEmptyString(linePatch.medicationId, '药物 ID');
          await _requireMedicationExists(db, medicationId);
          if (medicationId != lineRow['medication_id']) {
            final logs = await db.rawQuery(
              'SELECT COUNT(*) AS n FROM dose_log WHERE line_id = ?',
              [lineId],
            );
            final count = _asInt(logs.first['n']) ?? 0;
            if (count > 0) {
              _fail('已有打卡记录的用药线不能更换药物，请新建一条用药线');
            }
          }
          sets.add('medication_id = ?');
          values.add(medicationId);
        }
        if (linePatch.label != null) {
          sets.add('label = ?');
          values.add(_requireNonEmptyString(linePatch.label, '用药条目名称'));
        }
        if (linePatch.anchor != null) {
          sets.add('anchor = ?');
          values.add(linePatch.anchor!.wire);
        }
        if (linePatch.windowDays != null) {
          sets.add('window_days = ?');
          values.add(_requireInteger(linePatch.windowDays!, '按时窗口', 0));
        }
        if (linePatch.endedAt != null) {
          final endedAt = _normalizeEndedAt(linePatch.endedAt!.value);
          if (endedAt != null) {
            sets.add('ended_at = ?');
            values.add(endedAt);
          } else {
            sets.add('ended_at = NULL');
          }
        }
        if (linePatch.isHost != null) {
          isHost = linePatch.isHost! ? 1 : 0;
          if (isHost == 1 && kind == 'oral') _fail('口服用药不能设为主药');
          sets.add('is_host = ?');
          values.add(isHost);
        }
        if (linePatch.syncWithHost != null) {
          final sync = linePatch.syncWithHost!;
          final willBeHost = linePatch.isHost ?? (_asInt(lineRow['is_host']) == 1);
          if (sync && willBeHost) _fail('主药不能同时跟随其他主药');
          if (sync && kind == 'oral') _fail('口服用药不参与跟随主药');
          sets.add('sync_with_host = ?');
          values.add(sync ? 1 : 0);
        }

        List<Map<String, Object?>>? phases;
        if (linePatch.phases != null) {
          if (kind != 'injection') _fail('口服用药没有注射阶段');
          phases = _normalizePhases(lineId, linePatch.phases);
        }

        if (kind == 'oral' && linePatch.oral != null) {
          final oral = _normalizeOralPlan(linePatch.oral);
          sets.addAll([
            'oral_start = ?',
            'oral_duration_days = ?',
            'oral_frequency = ?',
            'oral_times_per_period = ?',
            'oral_days_of_week = ?',
            'oral_remind_time = ?',
          ]);
          values.addAll([
            oral.startDate,
            oral.durationDays,
            oral.frequency.wire,
            oral.timesPerPeriod,
            jsonEncode(oral.daysOfWeek),
            oral.remindTime,
          ]);
        }

        prepared.add(_PreparedLineUpdate(
          id: lineId,
          sets: sets,
          values: values,
          phases: phases,
          isHost: isHost,
          medicationId: medicationId,
        ));
      }

      final newHosts = prepared.where((e) => e.isHost == 1).length;
      if (newHosts > 1) _fail('一个治疗方案只能有一个主药');

      final removeLineIds = patch.removeLines ?? const [];
      final addLineInputs = patch.addLines ?? const [];
      final normalizedAdds = <_NormalizedLine>[];
      for (final addInput in addLineInputs) {
        final medicationId =
            _requireNonEmptyString(addInput.medicationId, '药物 ID');
        await _requireMedicationExists(db, medicationId);
        normalizedAdds.add(_normalizeLine(safeId, addInput));
      }

      final currentRows = await db.rawQuery(
        'SELECT id, medication_id, kind, is_host FROM treatment_line WHERE treatment_id = ?',
        [safeId],
      );
      final finalLines = <String, _FinalLineState>{
        for (final row in currentRows)
          row['id'] as String: _FinalLineState(
            medicationId: row['medication_id'] as String,
            kind: row['kind'] as String,
            isHost: _asInt(row['is_host']) == 1,
          ),
      };

      for (final entry in prepared) {
        final current = finalLines[entry.id];
        if (current == null) continue;
        if (entry.medicationId != null) current.medicationId = entry.medicationId!;
        if (entry.isHost != null) current.isHost = entry.isHost == 1;
      }

      final removed = <String>{};
      for (final removeId in removeLineIds) {
        final lineId = _requireNonEmptyString(removeId, '用药线 ID');
        if (!removed.add(lineId)) _fail('同一条用药线不能重复删除');
        if (seenLines.contains(lineId)) _fail('同一条用药线不能同时修改和删除');
        final lineRow = await _requireTreatmentLineExists(db, lineId);
        if (lineRow['treatment_id'] != safeId) _fail('用药线不属于该治疗方案');
        finalLines.remove(lineId);
      }

      for (final normalized in normalizedAdds) {
        final key =
            '${normalized.row['kind']}:${normalized.row['medication_id']}';
        final duplicate = finalLines.values
            .any((l) => '${l.kind}:${l.medicationId}' == key);
        if (duplicate) _fail('同一个治疗方案里不能重复添加同一种药');
        if (normalized.row['is_host'] == 1) {
          final hasHost = finalLines.values.any((l) => l.isHost);
          if (hasHost) _fail('一个治疗方案只能有一个主药');
        }
        finalLines[normalized.row['id'] as String] = _FinalLineState(
          medicationId: normalized.row['medication_id'] as String,
          kind: normalized.row['kind'] as String,
          isHost: normalized.row['is_host'] == 1,
        );
      }

      if (finalLines.values.where((l) => l.isHost).length > 1) {
        _fail('一个治疗方案只能有一个主药');
      }

      final usedLineKeys = <String>{};
      for (final line in finalLines.values) {
        final lineKey = '${line.kind}:${line.medicationId}';
        if (!usedLineKeys.add(lineKey)) {
          _fail('同一个治疗方案里不能重复添加同一种药');
        }
      }

      final clearHosts =
          newHosts > 0 || normalizedAdds.any((l) => l.row['is_host'] == 1);
      final touched = prepared
          .where((e) => e.sets.isNotEmpty || e.phases != null)
          .toList();

      if (newName == null &&
          touched.isEmpty &&
          removed.isEmpty &&
          normalizedAdds.isEmpty) {
        return (await _loadTreatments(db, [existing])).first;
      }

      if (newName != null) {
        await db.rawUpdate(
          'UPDATE treatment SET name = ? WHERE id = ?',
          [newName, safeId],
        );
      }
      if (clearHosts) {
        await db.rawUpdate(
          'UPDATE treatment_line SET is_host = 0 WHERE treatment_id = ?',
          [safeId],
        );
      }
      for (final entry in touched) {
        if (entry.sets.isNotEmpty) {
          await db.rawUpdate(
            'UPDATE treatment_line SET ${entry.sets.join(', ')} WHERE id = ?',
            [...entry.values, entry.id],
          );
        }
        if (entry.phases != null) {
          await db.rawDelete(
            'DELETE FROM treatment_phase WHERE line_id = ?',
            [entry.id],
          );
          for (final phase in entry.phases!) {
            await db.rawInsert(
              '''INSERT INTO treatment_phase
                  (id, line_id, order_idx, kind, interval_days, repeat_count, dose, unit, effective_from)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
              [
                phase['id'],
                phase['line_id'],
                phase['order_idx'],
                phase['kind'],
                phase['interval_days'],
                phase['repeat_count'],
                phase['dose'],
                phase['unit'],
                phase['effective_from'],
              ],
            );
          }
        }
      }
      for (final removeId in removed) {
        await db.rawDelete(
          'DELETE FROM treatment_line WHERE id = ?',
          [removeId],
        );
      }
      for (final normalized in normalizedAdds) {
        await _insertLine(db, normalized);
      }

      final updated = await _getTreatmentRow(db, safeId);
      if (updated == null) _fail('治疗方案不存在');
      return (await _loadTreatments(db, [updated])).first;
    }

    if (executor != null) return run(executor);
    return AppDatabase.runInTransaction((txn) => run(txn));
  }

  static Future<void> remove(
    String id, {
    DatabaseExecutor? executor,
  }) async {
    final safeId = _requireNonEmptyString(id, '治疗方案 ID');
    final db = await _resolveDb(executor);
    await _requireTreatmentExists(db, safeId);
    await db.rawDelete('DELETE FROM treatment WHERE id = ?', [safeId]);
  }
}

abstract final class EfficacyEventsRepo {
  static Future<List<EfficacyEvent>> list({
    String? lineId,
    DatabaseExecutor? executor,
  }) async {
    final db = await _resolveDb(executor);
    if (lineId != null) {
      final safeId = _requireNonEmptyString(lineId, '用药线 ID');
      final rows = await db.rawQuery(
        'SELECT * FROM efficacy_event WHERE line_id = ? ORDER BY occurred_at DESC, created_at DESC',
        [safeId],
      );
      return rows.map(_mapEfficacyEvent).toList();
    }
    final rows = await db.rawQuery(
      'SELECT * FROM efficacy_event ORDER BY occurred_at DESC, created_at DESC',
    );
    return rows.map(_mapEfficacyEvent).toList();
  }

  static Future<EfficacyEvent> create(
    EfficacyEventInput input, {
    DatabaseExecutor? executor,
  }) async {
    final lineId = _requireNonEmptyString(input.lineId, '用药线 ID');
    final occurredAt = _requireTimestamp(input.occurredAt, '发生时间');
    if (occurredAt > DateTime.now().millisecondsSinceEpoch + _oneDayMs) {
      _fail('发生时间不能晚于今天');
    }
    final note = _normalizeOptionalText(input.note);

    Future<EfficacyEvent> write(DatabaseExecutor db) async {
      await _requireTreatmentLineExists(db, lineId);
      final counted = await db.rawQuery(
        '''SELECT COUNT(*) AS n FROM dose_log
            WHERE line_id = ? AND status = 'done'
              AND COALESCE(taken_at, scheduled_at, created_at) <= ?''',
        [lineId, occurredAt],
      );
      final dosesCount = _asInt(counted.first['n']) ?? 0;
      final row = <String, Object?>{
        'id': _uuid.v4(),
        'line_id': lineId,
        'kind': input.kind.wire,
        'occurred_at': occurredAt,
        'doses_count': dosesCount,
        'note': note,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      };
      await db.rawInsert(
        '''INSERT INTO efficacy_event
            (id, line_id, kind, occurred_at, doses_count, note, created_at)
           VALUES (?, ?, ?, ?, ?, ?, ?)''',
        [
          row['id'],
          row['line_id'],
          row['kind'],
          row['occurred_at'],
          row['doses_count'],
          row['note'],
          row['created_at'],
        ],
      );
      if (input.stopLine) {
        await db.rawUpdate(
          '''UPDATE treatment_line
              SET ended_at = MIN(COALESCE(ended_at, ?), ?)
              WHERE id = ?''',
          [occurredAt, occurredAt, lineId],
        );
      }
      return _mapEfficacyEvent(row);
    }

    if (executor != null) return write(executor);
    return AppDatabase.runInTransaction((txn) => write(txn));
  }

  static Future<void> remove(
    String id, {
    DatabaseExecutor? executor,
  }) async {
    final eventId = _requireNonEmptyString(id, '疗效事件 ID');
    final db = await _resolveDb(executor);
    final rows = await db.rawQuery(
      'SELECT id FROM efficacy_event WHERE id = ? LIMIT 1',
      [eventId],
    );
    if (rows.isEmpty) _fail('疗效事件不存在');
    await db.rawDelete('DELETE FROM efficacy_event WHERE id = ?', [eventId]);
  }
}

abstract final class DoseLogsRepo {
  static Future<List<DoseLog>> list({
    String? lineId,
    DatabaseExecutor? executor,
  }) async {
    final db = await _resolveDb(executor);
    if (lineId != null) {
      final safeId = _requireNonEmptyString(lineId, '用药条目 ID');
      final rows = await db.rawQuery(
        '''SELECT * FROM dose_log WHERE line_id = ?
            ORDER BY scheduled_at IS NULL, scheduled_at ASC, created_at ASC''',
        [safeId],
      );
      return rows.map(_mapDoseLog).toList();
    }
    final rows = await db.rawQuery(
      'SELECT * FROM dose_log ORDER BY scheduled_at IS NULL, scheduled_at ASC, created_at ASC',
    );
    return rows.map(_mapDoseLog).toList();
  }

  static Future<List<DoseLog>> listBetween(
    int from,
    int to, {
    DatabaseExecutor? executor,
  }) async {
    final start = _requireTimestamp(from, '起始时间');
    final end = _requireTimestamp(to, '结束时间');
    if (end < start) _fail('结束时间不能早于起始时间');
    final db = await _resolveDb(executor);
    final rows = await db.rawQuery(
      '''SELECT * FROM dose_log
          WHERE scheduled_at IS NOT NULL AND scheduled_at BETWEEN ? AND ?
          ORDER BY scheduled_at ASC, created_at ASC''',
      [start, end],
    );
    return rows.map(_mapDoseLog).toList();
  }

  static Future<DoseLog> create(
    DoseLogInput input, {
    DatabaseExecutor? executor,
  }) async {
    final lineId = _requireNonEmptyString(input.lineId, '用药条目 ID');
    final scheduledAt = input.scheduledAt == null
        ? null
        : _requireTimestamp(input.scheduledAt, '计划时间');
    final takenAt =
        input.takenAt == null ? null : _requireTimestamp(input.takenAt, '打卡时间');
    if (input.status == DoseStatus.done && takenAt == null) {
      _fail('已完成的记录需要填写打卡时间');
    }
    final dose = _requireNullableDose(input.dose, '剂量');
    final unit =
        input.unit == null ? null : _requireNonEmptyString(input.unit, '单位');
    final lotNumber = _normalizeOptionalText(input.lotNumber);
    final note = _normalizeOptionalText(input.note);

    final db = await _resolveDb(executor);
    await _requireTreatmentLineExists(db, lineId);

    final now = DateTime.now().millisecondsSinceEpoch;
    final row = <String, Object?>{
      'id': _uuid.v4(),
      'line_id': lineId,
      'scheduled_at': scheduledAt,
      'taken_at': takenAt,
      'status': input.status.wire,
      'dose': dose,
      'unit': unit,
      'site': input.site?.wire,
      'lot_number': lotNumber,
      'note': note,
      'created_at': now,
      'updated_at': now,
    };

    await db.rawInsert(
      '''INSERT INTO dose_log
          (id, line_id, scheduled_at, taken_at, status, dose, unit, site,
           lot_number, note, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        row['id'],
        row['line_id'],
        row['scheduled_at'],
        row['taken_at'],
        row['status'],
        row['dose'],
        row['unit'],
        row['site'],
        row['lot_number'],
        row['note'],
        row['created_at'],
        row['updated_at'],
      ],
    );
    return _mapDoseLog(row);
  }

  static Future<DoseLog> update(
    String id,
    DoseLogPatch patch, {
    DatabaseExecutor? executor,
  }) async {
    final safeId = _requireNonEmptyString(id, '打卡记录 ID');
    final db = await _resolveDb(executor);
    final existing = await _getDoseLogRow(db, safeId);
    if (existing == null) _fail('打卡记录不存在');

    final sets = <String>[];
    final values = <Object?>[];

    if (patch.scheduledAt != null) {
      sets.add('scheduled_at = ?');
      final v = patch.scheduledAt!.value;
      values.add(v == null ? null : _requireTimestamp(v, '计划时间'));
    }
    if (patch.takenAt != null) {
      sets.add('taken_at = ?');
      final v = patch.takenAt!.value;
      values.add(v == null ? null : _requireTimestamp(v, '打卡时间'));
    }
    if (patch.status != null) {
      sets.add('status = ?');
      values.add(patch.status!.wire);
    }
    if (patch.dose != null) {
      sets.add('dose = ?');
      values.add(_requireNullableDose(patch.dose!.value, '剂量'));
    }
    if (patch.unit != null) {
      sets.add('unit = ?');
      final v = patch.unit!.value;
      values.add(v == null ? null : _requireNonEmptyString(v, '单位'));
    }
    if (patch.site != null) {
      sets.add('site = ?');
      values.add(patch.site!.value?.wire);
    }
    if (patch.lotNumber != null) {
      sets.add('lot_number = ?');
      values.add(_normalizeOptionalText(patch.lotNumber!.value));
    }
    if (patch.note != null) {
      sets.add('note = ?');
      values.add(_normalizeOptionalText(patch.note!.value));
    }

    if (sets.isEmpty) return _mapDoseLog(existing);

    final nextStatus =
        patch.status ?? DoseStatus.tryParse(existing['status'] as String?)!;
    final nextTakenAt = patch.takenAt != null
        ? patch.takenAt!.value
        : _asInt(existing['taken_at']);
    if (nextStatus == DoseStatus.done && nextTakenAt == null) {
      _fail('已完成的记录需要填写打卡时间');
    }

    sets.add('updated_at = ?');
    values.add(DateTime.now().millisecondsSinceEpoch);
    values.add(safeId);

    await db.rawUpdate(
      'UPDATE dose_log SET ${sets.join(', ')} WHERE id = ?',
      values,
    );
    final updated = await _getDoseLogRow(db, safeId);
    if (updated == null) _fail('打卡记录不存在');
    return _mapDoseLog(updated);
  }

  static Future<void> remove(
    String id, {
    DatabaseExecutor? executor,
  }) async {
    final safeId = _requireNonEmptyString(id, '打卡记录 ID');
    final db = await _resolveDb(executor);
    final changes =
        await db.rawDelete('DELETE FROM dose_log WHERE id = ?', [safeId]);
    if (changes == 0) _fail('打卡记录不存在');
  }
}

abstract final class SymptomsRepo {
  static Future<List<SymptomLog>> list({DatabaseExecutor? executor}) async {
    final db = await _resolveDb(executor);
    final rows = await db.rawQuery(
      'SELECT * FROM symptom_log ORDER BY logged_at ASC',
    );
    return rows.map(_mapSymptom).toList();
  }

  static Future<SymptomLog?> get(
    String id, {
    DatabaseExecutor? executor,
  }) async {
    final safeId = _requireNonEmptyString(id, '症状记录 ID');
    final db = await _resolveDb(executor);
    final row = await _getSymptomRow(db, safeId);
    return row == null ? null : _mapSymptom(row);
  }

  static Future<SymptomLog> create(
    SymptomLogInput input, {
    DatabaseExecutor? executor,
  }) async {
    final loggedAt = _requireTimestamp(input.loggedAt, '记录时间');
    final severity = _requireInteger(input.severity, '严重程度', 1);
    if (severity > 5) _fail('严重程度必须在 1 到 5 之间');

    final tags = _normalizeTags(input.tags);
    final painScore = _normalizePainScore(input.painScore);
    final note = _normalizeOptionalText(input.note);
    final temperature = _normalizeTemperature(input.temperature);
    final doseLogId = _normalizeOptionalId(input.injectionId, '关联记录 ID');

    final db = await _resolveDb(executor);
    if (doseLogId != null) {
      final log = await _getDoseLogRow(db, doseLogId);
      if (log == null) _fail('关联的打卡记录不存在');
    }

    final row = <String, Object?>{
      'id': _uuid.v4(),
      'logged_at': loggedAt,
      'severity': severity,
      'pain_score': painScore,
      'tags': jsonEncode(tags),
      'note': note,
      'temperature': temperature,
      'dose_log_id': doseLogId,
    };

    await db.rawInsert(
      '''INSERT INTO symptom_log
          (id, logged_at, severity, pain_score, tags, note, temperature, dose_log_id)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        row['id'],
        row['logged_at'],
        row['severity'],
        row['pain_score'],
        row['tags'],
        row['note'],
        row['temperature'],
        row['dose_log_id'],
      ],
    );
    return _mapSymptom(row);
  }

  static Future<SymptomLog> update(
    String id,
    SymptomLogPatch patch, {
    DatabaseExecutor? executor,
  }) async {
    final safeId = _requireNonEmptyString(id, '症状记录 ID');
    final db = await _resolveDb(executor);
    final existing = await _getSymptomRow(db, safeId);
    if (existing == null) _fail('症状记录不存在');

    final sets = <String>[];
    final values = <Object?>[];

    if (patch.loggedAt != null) {
      sets.add('logged_at = ?');
      values.add(_requireTimestamp(patch.loggedAt, '记录时间'));
    }
    if (patch.severity != null) {
      final s = _requireInteger(patch.severity!, '严重程度', 1);
      if (s > 5) _fail('严重程度必须在 1 到 5 之间');
      sets.add('severity = ?');
      values.add(s);
    }
    if (patch.painScore != null) {
      sets.add('pain_score = ?');
      values.add(_normalizePainScore(patch.painScore!.value));
    }
    if (patch.tags != null) {
      sets.add('tags = ?');
      values.add(jsonEncode(_normalizeTags(patch.tags!)));
    }
    if (patch.note != null) {
      sets.add('note = ?');
      values.add(_normalizeOptionalText(patch.note!.value));
    }
    if (patch.temperature != null) {
      sets.add('temperature = ?');
      values.add(_normalizeTemperature(patch.temperature!.value));
    }
    if (patch.injectionId != null) {
      final doseLogId =
          _normalizeOptionalId(patch.injectionId!.value, '关联记录 ID');
      if (doseLogId != null) {
        final log = await _getDoseLogRow(db, doseLogId);
        if (log == null) _fail('关联的打卡记录不存在');
      }
      sets.add('dose_log_id = ?');
      values.add(doseLogId);
    }

    if (sets.isEmpty) return _mapSymptom(existing);

    values.add(safeId);
    await db.rawUpdate(
      'UPDATE symptom_log SET ${sets.join(', ')} WHERE id = ?',
      values,
    );
    final updated = await _getSymptomRow(db, safeId);
    if (updated == null) _fail('症状记录不存在');
    return _mapSymptom(updated);
  }

  static Future<void> remove(
    String id, {
    DatabaseExecutor? executor,
  }) async {
    final safeId = _requireNonEmptyString(id, '症状记录 ID');
    final db = await _resolveDb(executor);
    final changes =
        await db.rawDelete('DELETE FROM symptom_log WHERE id = ?', [safeId]);
    if (changes == 0) _fail('症状记录不存在');
  }
}

Future<Map<String, Object?>> _insertSymptomTag(
  DatabaseExecutor db,
  String safeName,
) async {
  final maxRows = await db.rawQuery(
    'SELECT MAX(sort_order) AS max_order FROM symptom_tag',
  );
  final maxOrder =
      maxRows.isEmpty ? null : _asInt(maxRows.first['max_order']);
  final row = <String, Object?>{
    'id': _uuid.v4(),
    'name': safeName,
    'is_builtin': 0,
    'sort_order': (maxOrder ?? -1) + 1,
    'created_at': DateTime.now().millisecondsSinceEpoch,
  };
  await db.rawInsert(
    '''INSERT INTO symptom_tag (id, name, is_builtin, sort_order, created_at)
       VALUES (?, ?, ?, ?, ?)''',
    [
      row['id'],
      row['name'],
      row['is_builtin'],
      row['sort_order'],
      row['created_at'],
    ],
  );
  return row;
}

abstract final class SymptomTagsRepo {
  static Future<List<SymptomTag>> list({DatabaseExecutor? executor}) async {
    final db = await _resolveDb(executor);
    final rows = await db.rawQuery(
      'SELECT * FROM symptom_tag ORDER BY sort_order ASC, created_at ASC',
    );
    return rows.map(_mapSymptomTag).toList();
  }

  static Future<SymptomTag> create(
    String name, {
    DatabaseExecutor? executor,
  }) async {
    final safeName = _requireNonEmptyString(name, '症状名称');
    if (safeName.length > 20) _fail('症状名称最多 20 个字');

    final db = await _resolveDb(executor);
    final duplicate = await db.rawQuery(
      'SELECT id FROM symptom_tag WHERE name = ? COLLATE NOCASE LIMIT 1',
      [safeName],
    );
    if (duplicate.isNotEmpty) _fail('这个症状已经存在');

    return _mapSymptomTag(await _insertSymptomTag(db, safeName));
  }

  static Future<void> remove(
    String id, {
    DatabaseExecutor? executor,
  }) async {
    final safeId = _requireNonEmptyString(id, '症状标签 ID');
    final db = await _resolveDb(executor);
    final rows = await db.rawQuery(
      'SELECT is_builtin FROM symptom_tag WHERE id = ? LIMIT 1',
      [safeId],
    );
    if (rows.isEmpty) _fail('症状标签不存在');
    if (_asInt(rows.first['is_builtin']) == 1) _fail('内置症状标签不能删除');
    await db.rawDelete('DELETE FROM symptom_tag WHERE id = ?', [safeId]);
  }

  static Future<({SymptomTag tag, bool created})> ensure(
    String name, {
    DatabaseExecutor? executor,
  }) async {
    final safeName = _requireNonEmptyString(name, '症状名称');
    if (safeName.length > 20) _fail('症状名称最多 20 个字');

    final db = await _resolveDb(executor);
    final existing = await db.rawQuery(
      'SELECT * FROM symptom_tag WHERE name = ? COLLATE NOCASE LIMIT 1',
      [safeName],
    );
    if (existing.isNotEmpty) {
      return (tag: _mapSymptomTag(existing.first), created: false);
    }
    return (
      tag: _mapSymptomTag(await _insertSymptomTag(db, safeName)),
      created: true,
    );
  }
}

abstract final class ReminderRulesRepo {
  static Future<ReminderRuleV5?> getFor(
    String treatmentId, {
    DatabaseExecutor? executor,
  }) async {
    final safeId = _requireNonEmptyString(treatmentId, '治疗方案 ID');
    final db = await _resolveDb(executor);
    final row = await _getReminderRowFor(db, safeId);
    return row == null ? null : _mapReminderRule(row);
  }

  static Future<ReminderRuleV5> upsert(
    ReminderRuleInput input, {
    DatabaseExecutor? executor,
  }) async {
    final treatmentId = _requireNonEmptyString(input.treatmentId, '治疗方案 ID');
    if (input.offsets.isEmpty) _fail('提醒偏移不能为空');
    final offsets = input.offsets;
    final timeOfDay = _requireTimeOfDay(input.timeOfDay, '提醒时间');
    final snoozeMinutes = _requireInteger(input.snoozeMinutes, '稍后提醒分钟数', 0);

    final db = await _resolveDb(executor);
    await _requireTreatmentExists(db, treatmentId);

    Map<String, Object?>? byId;
    if (input.id != null) {
      final rows = await db.rawQuery(
        'SELECT * FROM reminder_rule WHERE id = ? LIMIT 1',
        [input.id],
      );
      byId = rows.isEmpty ? null : rows.first;
      if (byId != null && byId['treatment_id'] != treatmentId) {
        _fail('提醒规则不属于该治疗方案');
      }
    }

    final existing = (await _getReminderRowFor(db, treatmentId)) ?? byId;
    final offsetsJson = jsonEncode(offsets);
    final enabledInt = input.enabled ? 1 : 0;

    if (existing != null) {
      final existingId = existing['id'] as String;
      await db.rawUpdate(
        '''UPDATE reminder_rule
              SET treatment_id = ?, offsets = ?, time_of_day = ?, snooze_minutes = ?, enabled = ?
            WHERE id = ?''',
        [
          treatmentId,
          offsetsJson,
          timeOfDay,
          snoozeMinutes,
          enabledInt,
          existingId,
        ],
      );
      return ReminderRuleV5(
        id: existingId,
        treatmentId: treatmentId,
        offsets: List<int>.from(offsets),
        timeOfDay: timeOfDay,
        snoozeMinutes: snoozeMinutes,
        enabled: input.enabled,
      );
    }

    final newId = input.id ?? _uuid.v4();
    await db.rawInsert(
      '''INSERT INTO reminder_rule
          (id, treatment_id, offsets, time_of_day, snooze_minutes, enabled)
         VALUES (?, ?, ?, ?, ?, ?)''',
      [
        newId,
        treatmentId,
        offsetsJson,
        timeOfDay,
        snoozeMinutes,
        enabledInt,
      ],
    );
    return ReminderRuleV5(
      id: newId,
      treatmentId: treatmentId,
      offsets: List<int>.from(offsets),
      timeOfDay: timeOfDay,
      snoozeMinutes: snoozeMinutes,
      enabled: input.enabled,
    );
  }
}

abstract final class SettingsRepo {
  static Future<AppSettings> all({DatabaseExecutor? executor}) async {
    final db = await _resolveDb(executor);
    final rows = await db.rawQuery('SELECT key, value FROM app_setting');
    return {
      for (final row in rows) row['key'] as String: row['value'] as String,
    };
  }

  static Future<String?> get(
    String key, {
    DatabaseExecutor? executor,
  }) async {
    final safeKey = _requireNonEmptyString(key, '设置项 key');
    final db = await _resolveDb(executor);
    final rows = await db.rawQuery(
      'SELECT value FROM app_setting WHERE key = ? LIMIT 1',
      [safeKey],
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  static Future<void> set(
    String key,
    String value, {
    DatabaseExecutor? executor,
  }) async {
    final safeKey = _requireNonEmptyString(key, '设置项 key');
    final db = await _resolveDb(executor);
    await db.rawInsert(
      '''INSERT INTO app_setting (key, value) VALUES (?, ?)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value''',
      [safeKey, value],
    );
  }
}

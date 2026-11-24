/// 领域与数据库共用数据类型。
///
/// 时间字段统一使用 UTC 毫秒时间戳（`int`），仅在导入/导出文本里转换为本地 `YYYY-MM-DD HH:mm`。
library;

enum RegimenAnchor {
  actual('actual'),
  planned('planned');

  const RegimenAnchor(this.wire);
  final String wire;

  static RegimenAnchor? tryParse(String? raw) => switch (raw) {
        'actual' => actual,
        'planned' => planned,
        _ => null,
      };
}

enum PhaseKind {
  loading('loading'),
  maintenance('maintenance');

  const PhaseKind(this.wire);
  final String wire;

  static PhaseKind? tryParse(String? raw) => switch (raw) {
        'loading' => loading,
        'maintenance' => maintenance,
        _ => null,
      };
}

enum WindowStatus {
  early('early'),
  onTime('on_time'),
  late('late');

  const WindowStatus(this.wire);
  final String wire;
}

enum InjectionSite {
  abdomenUl('abdomen_ul'),
  abdomenUr('abdomen_ur'),
  abdomenLl('abdomen_ll'),
  abdomenLr('abdomen_lr'),
  thighL('thigh_l'),
  thighR('thigh_r'),
  armL('arm_l'),
  armR('arm_r');

  const InjectionSite(this.wire);
  final String wire;

  static InjectionSite? tryParse(String? raw) => switch (raw) {
        'abdomen_ul' => abdomenUl,
        'abdomen_ur' => abdomenUr,
        'abdomen_ll' => abdomenLl,
        'abdomen_lr' => abdomenLr,
        'thigh_l' => thighL,
        'thigh_r' => thighR,
        'arm_l' => armL,
        'arm_r' => armR,
        _ => null,
      };
}

/// 给药途径：皮下（可自行注射）/ 静脉输注（需到医院）/ 口服。
enum MedicationRoute {
  sc('sc'),
  iv('iv'),
  oral('oral');

  const MedicationRoute(this.wire);
  final String wire;

  static MedicationRoute? tryParse(String? raw) => switch (raw) {
        'sc' => sc,
        'iv' => iv,
        'oral' => oral,
        _ => null,
      };
}

enum DiseaseGroup {
  ibd('ibd'),
  skin('skin'),
  joint('joint'),
  other('other');

  const DiseaseGroup(this.wire);
  final String wire;
}

enum LineKind {
  injection('injection'),
  oral('oral');

  const LineKind(this.wire);
  final String wire;

  static LineKind? tryParse(String? raw) => switch (raw) {
        'injection' => injection,
        'oral' => oral,
        _ => null,
      };
}

enum OralFrequency {
  daily('daily'),
  weekly('weekly'),
  custom('custom');

  const OralFrequency(this.wire);
  final String wire;

  static OralFrequency? tryParse(String? raw) => switch (raw) {
        'daily' => daily,
        'weekly' => weekly,
        'custom' => custom,
        _ => null,
      };
}

/// 打卡状态：已用 / 跳过 / 漏用。
enum DoseStatus {
  done('done'),
  skipped('skipped'),
  missed('missed');

  const DoseStatus(this.wire);
  final String wire;

  static DoseStatus? tryParse(String? raw) => switch (raw) {
        'done' => done,
        'skipped' => skipped,
        'missed' => missed,
        _ => null,
      };
}

/// 疗效事件类型：下降 / 失效 / 不耐受 / 抗药抗体 / 其他。
enum EfficacyKind {
  reduced('reduced'),
  failed('failed'),
  intolerance('intolerance'),
  antibody('antibody'),
  other('other');

  const EfficacyKind(this.wire);
  final String wire;

  static EfficacyKind? tryParse(String? raw) => switch (raw) {
        'reduced' => reduced,
        'failed' => failed,
        'intolerance' => intolerance,
        'antibody' => antibody,
        'other' => other,
        _ => null,
      };
}

typedef AppSettings = Map<String, String>;

class Disease {
  const Disease({
    required this.id,
    required this.name,
    required this.aliases,
    required this.group,
    required this.summary,
  });

  final String id;
  final String name;
  final List<String> aliases;
  final DiseaseGroup group;
  final String summary;
}

class Medication {
  const Medication({
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
    required this.createdAt,
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
  final int createdAt;
}

/// 方案模板里的单个阶段（未入库，仅用于预填）。
class RegimenPhaseTemplate {
  const RegimenPhaseTemplate({
    required this.kind,
    required this.intervalDays,
    required this.repeatCount,
    required this.dose,
    required this.unit,
  });

  final PhaseKind kind;
  final int intervalDays;
  final int repeatCount;
  final double? dose;
  final String unit;
}

class RegimenTemplate {
  const RegimenTemplate({
    required this.name,
    required this.anchor,
    required this.windowDays,
    required this.phases,
  });

  final String name;
  final RegimenAnchor anchor;
  final int windowDays;
  final List<RegimenPhaseTemplate> phases;
}

class CatalogDrug {
  const CatalogDrug({
    required this.key,
    required this.name,
    required this.genericName,
    required this.brandNames,
    required this.route,
    required this.defaultDose,
    required this.unit,
    required this.color,
    this.note,
  });

  final String key;
  final String name;
  final String genericName;
  final List<String> brandNames;
  final MedicationRoute route;
  final double? defaultDose;
  final String unit;
  final String color;
  final String? note;
}

class DiseaseDrug {
  const DiseaseDrug({
    required this.diseaseId,
    required this.drugKey,
    required this.firstLine,
    this.doseNote,
    required this.regimen,
  });

  final String diseaseId;
  final String drugKey;
  final bool firstLine;
  final String? doseNote;
  final RegimenTemplate regimen;
}

class SymptomLog {
  const SymptomLog({
    required this.id,
    required this.loggedAt,
    required this.severity,
    required this.painScore,
    required this.tags,
    required this.note,
    required this.temperature,
    required this.injectionId,
  });

  final String id;
  final int loggedAt;
  final int severity;

  /// 临床疼痛评分 NRS 0–10，0 表示无痛；未填写为 null。
  final int? painScore;
  final List<String> tags;
  final String? note;
  final double? temperature;
  final String? injectionId;
}

class SymptomTag {
  const SymptomTag({
    required this.id,
    required this.name,
    required this.isBuiltin,
    required this.sortOrder,
    required this.createdAt,
  });

  final String id;
  final String name;
  final bool isBuiltin;
  final int sortOrder;
  final int createdAt;
}

class TreatmentPhase {
  const TreatmentPhase({
    required this.id,
    required this.lineId,
    required this.orderIdx,
    required this.kind,
    required this.intervalDays,
    required this.repeatCount,
    required this.dose,
    required this.unit,
    required this.effectiveFrom,
  });

  final String id;
  final String lineId;
  final int orderIdx;
  final PhaseKind kind;
  final int intervalDays;
  final int repeatCount;
  final double? dose;
  final String unit;
  final int? effectiveFrom;

  TreatmentPhase copyWith({
    String? id,
    String? lineId,
    int? orderIdx,
    PhaseKind? kind,
    int? intervalDays,
    int? repeatCount,
    double? Function()? dose,
    String? unit,
    int? Function()? effectiveFrom,
  }) {
    return TreatmentPhase(
      id: id ?? this.id,
      lineId: lineId ?? this.lineId,
      orderIdx: orderIdx ?? this.orderIdx,
      kind: kind ?? this.kind,
      intervalDays: intervalDays ?? this.intervalDays,
      repeatCount: repeatCount ?? this.repeatCount,
      dose: dose != null ? dose() : this.dose,
      unit: unit ?? this.unit,
      effectiveFrom: effectiveFrom != null ? effectiveFrom() : this.effectiveFrom,
    );
  }
}

class TreatmentPhaseInput {
  const TreatmentPhaseInput({
    required this.orderIdx,
    required this.kind,
    required this.intervalDays,
    required this.repeatCount,
    required this.dose,
    required this.unit,
    this.effectiveFrom,
  });

  final int orderIdx;
  final PhaseKind kind;
  final int intervalDays;
  final int repeatCount;
  final double? dose;
  final String unit;
  final int? effectiveFrom;

  factory TreatmentPhaseInput.fromPhase(TreatmentPhase phase) {
    return TreatmentPhaseInput(
      orderIdx: phase.orderIdx,
      kind: phase.kind,
      intervalDays: phase.intervalDays,
      repeatCount: phase.repeatCount,
      dose: phase.dose,
      unit: phase.unit,
      effectiveFrom: phase.effectiveFrom,
    );
  }
}

/// 口服计划：注射线的 `oral` 为 null。
class OralPlan {
  const OralPlan({
    required this.startDate,
    required this.durationDays,
    required this.frequency,
    required this.timesPerPeriod,
    required this.daysOfWeek,
    required this.remindTime,
  });

  final int startDate;
  final int? durationDays;
  final OralFrequency frequency;
  final int timesPerPeriod;
  final List<int> daysOfWeek;
  final String remindTime;
}

class TreatmentLine {
  const TreatmentLine({
    required this.id,
    required this.treatmentId,
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
  final String treatmentId;
  final String medicationId;
  final LineKind kind;
  final String label;
  final bool isHost;
  final bool syncWithHost;
  final RegimenAnchor anchor;
  final int windowDays;
  final int? endedAt;
  final List<TreatmentPhase> phases;
  final OralPlan? oral;
}

class EfficacyEvent {
  const EfficacyEvent({
    required this.id,
    required this.lineId,
    required this.kind,
    required this.occurredAt,
    required this.dosesCount,
    required this.note,
    required this.createdAt,
  });

  final String id;
  final String lineId;
  final EfficacyKind kind;
  final int occurredAt;
  final int dosesCount;
  final String? note;
  final int createdAt;
}

class Treatment {
  const Treatment({
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
  final List<TreatmentLine> lines;
}

class DoseLog {
  const DoseLog({
    required this.id,
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

  final String id;
  final String lineId;
  final int? scheduledAt;
  final int? takenAt;
  final DoseStatus status;
  final double? dose;
  final String unit;
  final InjectionSite? site;
  final String? lotNumber;
  final String? note;
  final int createdAt;
  final int updatedAt;
}

class ReminderRuleV5 {
  const ReminderRuleV5({
    required this.id,
    required this.treatmentId,
    required this.offsets,
    required this.timeOfDay,
    required this.snoozeMinutes,
    required this.enabled,
  });

  final String id;
  final String treatmentId;
  final List<int> offsets;
  final String timeOfDay;
  final int snoozeMinutes;
  final bool enabled;
}

class RepoValidationException implements Exception {
  const RepoValidationException(this.message);
  final String message;

  @override
  String toString() => message;
}

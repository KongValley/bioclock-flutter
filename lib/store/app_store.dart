import 'dart:async';
import 'dart:convert';

import 'package:bioclock/data/diseases.dart';
import 'package:bioclock/db/database.dart';
import 'package:bioclock/db/repo.dart';
import 'package:bioclock/domain/interval.dart';
import 'package:bioclock/domain/schedule.dart';
import 'package:bioclock/import/import_schema.dart';
import 'package:bioclock/import/import_service.dart';
import 'package:bioclock/models/types.dart';
import 'package:bioclock/notify/notify_scheduler.dart';
import 'package:flutter/foundation.dart';

class MutationResult {
  const MutationResult({this.notifyWarning});

  final String? notifyWarning;
}

class ImportOutcome {
  const ImportOutcome({
    required this.result,
    this.notifyWarning,
  });

  final ImportResult result;
  final String? notifyWarning;
}

class TreatmentLineDraft extends TreatmentLineInput {
  const TreatmentLineDraft({
    this.id,
    required super.medicationId,
    required super.kind,
    required super.label,
    super.isHost = false,
    super.syncWithHost = false,
    super.anchor = RegimenAnchor.actual,
    super.windowDays = 2,
    super.endedAt,
    super.phases = const [],
    super.oral,
  });

  final String? id;
}

class SaveTreatmentInput {
  const SaveTreatmentInput({
    this.id,
    required this.name,
    required this.lines,
  });

  final String? id;
  final String name;
  final List<TreatmentLineDraft> lines;
}

class DoseNotificationRoute {
  const DoseNotificationRoute({
    required this.kind,
    this.lineId,
    this.scheduledAt,
  });

  final LineKind kind;
  final String? lineId;
  final int? scheduledAt;
}

class ToastMessage {
  const ToastMessage({
    required this.id,
    required this.text,
    required this.isError,
  });

  final int id;
  final String text;
  final bool isError;
}

class ToastController extends ChangeNotifier {
  ToastController._();

  static final ToastController instance = ToastController._();

  ToastMessage? _current;
  Timer? _timer;
  int _nextId = 0;

  ToastMessage? get current => _current;

  void show(String text, {bool isError = false}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _timer?.cancel();
    final msg = ToastMessage(
      id: ++_nextId,
      text: trimmed,
      isError: isError,
    );
    _current = msg;
    notifyListeners();
    _timer = Timer(Duration(milliseconds: isError ? 3600 : 2600), () {
      if (_current?.id == msg.id) {
        _current = null;
        notifyListeners();
      }
    });
  }

  void clear() {
    _timer?.cancel();
    _current = null;
    notifyListeners();
  }
}

void showToast(String text, {bool isError = false}) {
  ToastController.instance.show(text, isError: isError);
}

String friendlyErrorMessage(Object error) {
  final msg = error.toString().trim();
  if (error is RepoValidationException) return error.message;
  if (error is StateError) return error.message;
  if (error is ArgumentError && error.message != null) {
    return error.message.toString();
  }
  if (msg.startsWith('Exception: ')) return msg.substring(11);
  if (msg.startsWith('Bad state: ')) return msg.substring(11);
  return msg.isEmpty ? '操作失败，请稍后再试' : msg;
}

class AppStore extends ChangeNotifier {
  bool _ready = false;
  bool _refreshing = false;
  String? _error;
  Treatment? _treatment;
  List<Treatment> _treatments = const [];
  List<DoseLog> _doseLogs = const [];
  List<EfficacyEvent> _efficacyEvents = const [];
  List<Medication> _medications = const [];
  List<SymptomLog> _symptoms = const [];
  List<SymptomTag> _symptomTags = const [];
  ReminderRuleV5? _reminder;
  AppSettings _settings = const {};
  List<Disease> _diseases = const [];
  Disease? _disease;

  DoseNotificationRoute? _pendingNotification;
  String? _lastHandledPayload;
  int _lastHandledAt = 0;

  bool get ready => _ready;
  bool get refreshing => _refreshing;
  String? get error => _error;
  Treatment? get treatment => _treatment;
  List<Treatment> get treatments => _treatments;
  List<DoseLog> get doseLogs => _doseLogs;
  List<EfficacyEvent> get efficacyEvents => _efficacyEvents;
  List<Medication> get medications => _medications;
  List<SymptomLog> get symptoms => _symptoms;
  List<SymptomTag> get symptomTags => _symptomTags;
  ReminderRuleV5? get reminder => _reminder;
  AppSettings get settings => _settings;
  List<Disease> get diseases => _diseases;
  Disease? get disease => _disease;
  DoseNotificationRoute? get pendingNotification => _pendingNotification;

  bool get isOnboarded => (_settings['onboarded_at'] ?? '').isNotEmpty;

  Future<void> reload() async {
    _refreshing = _ready;
    _error = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        TreatmentsRepo.getActive(),
        TreatmentsRepo.list(),
        SettingsRepo.all(),
        MedicationsRepo.list(),
        SymptomsRepo.list(),
        SymptomTagsRepo.list(),
        DoseLogsRepo.list(),
        EfficacyEventsRepo.list(),
      ]);
      final active = results[0] as Treatment?;
      final allTreatments = results[1] as List<Treatment>;
      final allSettings = results[2] as AppSettings;
      final allMedications = results[3] as List<Medication>;
      final allSymptoms = results[4] as List<SymptomLog>;
      final allSymptomTags = results[5] as List<SymptomTag>;
      final allDoseLogs = results[6] as List<DoseLog>;
      final allEfficacyEvents = results[7] as List<EfficacyEvent>;

      final rem =
          active != null ? await ReminderRulesRepo.getFor(active.id) : null;
      final disList = findDiseases(resolveDiseaseIds(allSettings));

      _ready = true;
      _refreshing = false;
      _error = null;
      _treatment = active;
      _treatments = allTreatments;
      _doseLogs = allDoseLogs;
      _efficacyEvents = allEfficacyEvents;
      _medications = allMedications;
      _symptoms = allSymptoms;
      _symptomTags = allSymptomTags;
      _reminder = rem;
      _settings = allSettings;
      _diseases = disList;
      _disease = disList.isNotEmpty ? disList.first : null;
      notifyListeners();
    } catch (err) {
      _ready = true;
      _refreshing = false;
      _error = friendlyErrorMessage(err);
      notifyListeners();
      rethrow;
    }
  }

  Future<String?> _rescheduleOrWarning() async {
    try {
      await NotifyScheduler.rescheduleAll();
      return null;
    } catch (err) {
      return '提醒更新失败：${friendlyErrorMessage(err)}';
    }
  }

  Future<String?> _afterWrite() async {
    final warnings = <String>[];
    try {
      await reload();
    } catch (err) {
      warnings.add('数据刷新失败：${friendlyErrorMessage(err)}');
    }
    final scheduleWarning = await _rescheduleOrWarning();
    if (scheduleWarning != null) warnings.add(scheduleWarning);
    return warnings.isNotEmpty ? warnings.join('；') : null;
  }

  void handleNotificationPayload(String? payload) {
    if (payload == null || payload.trim().isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastHandledPayload == payload && now - _lastHandledAt < 5000) {
      return;
    }

    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) return;
      if (decoded['type'] != 'dose') return;

      _lastHandledPayload = payload;
      _lastHandledAt = now;
      final lineId =
          decoded['lineId'] is String ? decoded['lineId'] as String : null;
      final plannedAt = decoded['plannedAt'] is num
          ? (decoded['plannedAt'] as num).toInt()
          : null;
      final kind = decoded['kind'] == 'oral' ? LineKind.oral : LineKind.injection;
      _pendingNotification = DoseNotificationRoute(
        kind: kind,
        lineId: lineId,
        scheduledAt: plannedAt,
      );
      notifyListeners();
    } catch (_) {
      // 忽略畸形通知负载
    }
  }

  DoseNotificationRoute? consumePendingNotification() {
    if (!isOnboarded) return null;
    final pending = _pendingNotification;
    if (pending == null) return null;
    _pendingNotification = null;
    return pending;
  }

  Future<MutationResult> addDoseLog(DoseLogInput input) async {
    await DoseLogsRepo.create(input);
    return MutationResult(notifyWarning: await _afterWrite());
  }

  Future<MutationResult> updateDoseLog(String id, DoseLogPatch patch) async {
    await DoseLogsRepo.update(id, patch);
    return MutationResult(notifyWarning: await _afterWrite());
  }

  Future<MutationResult> removeDoseLog(String id) async {
    await DoseLogsRepo.remove(id);
    return MutationResult(notifyWarning: await _afterWrite());
  }

  Future<MutationResult> addEfficacyEvent(EfficacyEventInput input) async {
    await EfficacyEventsRepo.create(input);
    return MutationResult(notifyWarning: await _afterWrite());
  }

  Future<MutationResult> removeEfficacyEvent(String id) async {
    await EfficacyEventsRepo.remove(id);
    return MutationResult(notifyWarning: await _afterWrite());
  }

  Future<MutationResult> setLineEnded(String lineId, int? endedAt) async {
    await TreatmentsRepo.setLineEnded(lineId, endedAt);
    return MutationResult(notifyWarning: await _afterWrite());
  }

  Future<MutationResult> changeInjectionInterval(
    String lineId,
    int intervalDays, {
    int? nowMs,
  }) async {
    final active = await TreatmentsRepo.getActive();
    if (active == null) throw StateError('还没有治疗方案');
    final line = active.lines.cast<TreatmentLine?>().firstWhere(
          (item) => item?.id == lineId,
          orElse: () => null,
        );
    if (line == null || line.kind != LineKind.injection) {
      throw StateError('找不到要调整的注射线');
    }
    if (line.endedAt != null) {
      throw StateError('这条用药线已停用，请先恢复');
    }

    final logs = await DoseLogsRepo.list(lineId: lineId);
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final plans = buildInjectionPlans(
      line: line,
      logs: logs,
      now: now,
      futureDoseCount: 4,
    );
    final next = selectNextPlan(plans, now);
    if (next == null) throw StateError('这条用药线没有可调整的下一针');

    final prior = plans.where((p) => p.index < next.index).toList()
      ..sort((a, b) => b.index.compareTo(a.index));
    final previous = prior.isNotEmpty ? prior.first : null;
    final base = line.anchor == RegimenAnchor.actual
        ? (previous?.actualAt ?? previous?.plannedAt ?? now)
        : (previous?.plannedAt ?? now);
    final effectiveFrom = base + intervalDays * dayMs;

    final phases = [
      for (final p in buildIntervalChangePhases(
        line.phases,
        intervalDays,
        effectiveFrom,
      ))
        p.toInput(),
    ];
    await TreatmentsRepo.update(
      line.treatmentId,
      TreatmentPatch(
        lines: [TreatmentLinePatch(id: line.id, phases: phases)],
      ),
    );
    return MutationResult(notifyWarning: await _afterWrite());
  }

  Future<MutationResult> saveTreatment(SaveTreatmentInput input) async {
    if (input.id == null) {
      final created = await TreatmentsRepo.create(
        TreatmentInput(
          name: input.name,
          lines: input.lines,
        ),
      );
      if (_treatment == null) {
        await TreatmentsRepo.setActive(created.id, true);
      }
    } else {
      final current = await TreatmentsRepo.get(input.id!);
      if (current == null) throw StateError('治疗方案不存在');
      final linePatches = <TreatmentLinePatch>[
        for (final line in input.lines)
          if (line.id != null && line.id!.isNotEmpty)
            TreatmentLinePatch(
              id: line.id!,
              medicationId: line.medicationId,
              label: line.label,
              isHost: line.isHost,
              syncWithHost: line.syncWithHost,
              anchor: line.anchor,
              windowDays: line.windowDays,
              phases: line.phases,
              oral: line.oral,
            ),
      ];
      final keptIds = {
        for (final line in input.lines)
          if (line.id != null && line.id!.isNotEmpty) line.id!,
      };
      final removeLines = [
        for (final line in current.lines)
          if (!keptIds.contains(line.id)) line.id,
      ];
      final addLines = [
        for (final line in input.lines)
          if (line.id == null) line,
      ];
      await TreatmentsRepo.update(
        input.id!,
        TreatmentPatch(
          name: input.name,
          lines: linePatches,
          removeLines: removeLines,
          addLines: addLines,
        ),
      );
    }
    return MutationResult(notifyWarning: await _afterWrite());
  }

  Future<MutationResult> setActiveTreatment(String id, bool active) async {
    await TreatmentsRepo.setActive(id, active);
    return MutationResult(notifyWarning: await _afterWrite());
  }

  Future<MutationResult> updateReminder(ReminderRuleInput input) async {
    await ReminderRulesRepo.upsert(input);
    return MutationResult(notifyWarning: await _afterWrite());
  }

  Future<MutationResult> addMedication(MedicationInput input) async {
    await MedicationsRepo.create(input);
    return MutationResult(notifyWarning: await _afterWrite());
  }

  Future<MutationResult> updateMedication(
    String id,
    MedicationPatch patch,
  ) async {
    await MedicationsRepo.update(id, patch);
    return MutationResult(notifyWarning: await _afterWrite());
  }

  Future<MutationResult> removeMedication(String id) async {
    await MedicationsRepo.remove(id);
    return MutationResult(notifyWarning: await _afterWrite());
  }

  Future<MutationResult> addSymptom(SymptomLogInput input) async {
    await SymptomsRepo.create(input);
    return MutationResult(notifyWarning: await _afterWrite());
  }

  Future<MutationResult> updateSymptom(String id, SymptomLogPatch patch) async {
    await SymptomsRepo.update(id, patch);
    return MutationResult(notifyWarning: await _afterWrite());
  }

  Future<MutationResult> removeSymptom(String id) async {
    await SymptomsRepo.remove(id);
    return MutationResult(notifyWarning: await _afterWrite());
  }

  Future<MutationResult> addSymptomTag(String name) async {
    await SymptomTagsRepo.create(name);
    return MutationResult(notifyWarning: await _afterWrite());
  }

  Future<MutationResult> removeSymptomTag(String id) async {
    await SymptomTagsRepo.remove(id);
    return MutationResult(notifyWarning: await _afterWrite());
  }

  Future<MutationResult> updateSettings(Map<String, String> patch) async {
    for (final entry in patch.entries) {
      await SettingsRepo.set(entry.key, entry.value);
    }
    return MutationResult(notifyWarning: await _afterWrite());
  }

  Future<ImportOutcome> importRecords(ImportPayload payload) async {
    final result = await importPayload(payload);
    return ImportOutcome(
      result: result,
      notifyWarning: await _afterWrite(),
    );
  }

  Future<MutationResult> resetAllData() async {
    await AppDatabase.resetDatabase();
    return MutationResult(notifyWarning: await _afterWrite());
  }
}

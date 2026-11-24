import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:bioclock/db/repo.dart';
import 'package:bioclock/domain/schedule.dart';
import 'package:bioclock/i18n/zh.dart';
import 'package:bioclock/models/types.dart';
import 'package:bioclock/notify/notify_content.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

const String reminderChannelId = 'bioclock-reminders';
const int scheduleWindowDays = 56;
const int maxScheduledNotifications = 60;
const int eveningCatchUpMinutes = 20 * 60;
const int defaultReminderMinutes = 9 * 60;
const String defaultDndStart = '22:00';
const String defaultDndEnd = '08:00';

const String _windowsAppName = 'BioClock';
const String _windowsAppUserModelId = 'Com.BioClock.BioClockApp';
const String _windowsGuid = 'a6e8d4f2-4b3c-4e1a-9f8d-2c5e7a1b3d9f';

class DndWindow {
  const DndWindow({
    required this.startMinutes,
    required this.endMinutes,
  });

  final int startMinutes;
  final int endMinutes;
}

class ReminderDraft {
  const ReminderDraft({
    required this.lineId,
    required this.kind,
    required this.plannedAt,
    required this.triggerAt,
    required this.title,
    required this.body,
  });

  final String lineId;
  final LineKind kind;
  final int plannedAt;
  final int triggerAt;
  final String title;
  final String body;

  String get payloadJson => jsonEncode({
        'type': 'dose',
        'kind': kind.wire,
        'lineId': lineId,
        'plannedAt': plannedAt,
      });
}

class NotificationPermissionStatus {
  const NotificationPermissionStatus({
    required this.granted,
    required this.exactAlarm,
  });

  final bool granted;
  final bool exactAlarm;
}

class _OralDayGroup {
  _OralDayGroup({
    required this.day,
    required this.lineIds,
    required this.names,
    required this.remindMinutes,
  });

  final int day;
  final List<String> lineIds;
  final List<String> names;
  final int remindMinutes;
}

final RegExp _hhmmRe = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$');

int parseMinutesOfDay(String value, int fallbackMinutes) {
  final match = _hhmmRe.firstMatch(value.trim());
  if (match == null) return fallbackMinutes;
  return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
}

DndWindow resolveDndWindow(AppSettings appSettings) {
  return DndWindow(
    startMinutes: parseMinutesOfDay(
      appSettings['dnd_start'] ?? defaultDndStart,
      22 * 60,
    ),
    endMinutes: parseMinutesOfDay(
      appSettings['dnd_end'] ?? defaultDndEnd,
      8 * 60,
    ),
  );
}

/// 落在免打扰区间内的提醒顺延到区间结束；跨午夜的区间按两段处理。
int shiftOutOfDnd(int timestamp, DndWindow dnd) {
  final start = dnd.startMinutes;
  final end = dnd.endMinutes;
  if (start == end) return timestamp;

  final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
  final minutes = dt.hour * 60 + dt.minute;

  if (start < end) {
    if (minutes >= start && minutes < end) {
      return _atLocalMinutes(timestamp, end);
    }
    return timestamp;
  }

  if (minutes >= start) {
    return _atLocalMinutes(_addLocalDays(timestamp, 1), end);
  }
  if (minutes < end) {
    return _atLocalMinutes(timestamp, end);
  }
  return timestamp;
}

int _atLocalMinutes(int timestamp, int minutesOfDay) {
  final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
  return DateTime(
    dt.year,
    dt.month,
    dt.day,
    minutesOfDay ~/ 60,
    minutesOfDay % 60,
  ).millisecondsSinceEpoch;
}

int _addLocalDays(int timestamp, int days) {
  final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
  return DateTime(dt.year, dt.month, dt.day + days, dt.hour, dt.minute,
          dt.second, dt.millisecond)
      .millisecondsSinceEpoch;
}

int _startOfLocalDay(int timestamp) {
  final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
  return DateTime(dt.year, dt.month, dt.day).millisecondsSinceEpoch;
}

bool _sameLocalDay(int a, int b) => _startOfLocalDay(a) == _startOfLocalDay(b);

bool _claimDraftKey(
  Set<String> seen,
  String lineId,
  int plannedAt,
  int triggerAt,
) {
  final key = '$lineId|$plannedAt|$triggerAt';
  if (seen.contains(key)) return false;
  seen.add(key);
  return true;
}

List<SchedulePlan> _collectPlansThrough(
  Treatment treatment,
  List<DoseLog> logs,
  int now,
  int horizon,
) {
  final horizonDays = math.max(
    oralHorizonDays,
    ((horizon - now) / dayMs).ceil() + oralHorizonDays,
  );
  return buildSchedule(
    lines: treatment.lines,
    logs: logs,
    now: now,
    horizonDays: oralHorizonDays - 1,
    futureDoseCount: futureDoseCountForHorizon(treatment.lines, horizonDays),
  );
}

List<ReminderDraft> _buildInjectionDrafts({
  required List<SchedulePlan> plans,
  required Map<String, TreatmentLine> lines,
  required ReminderRuleV5 reminder,
  required Map<String, Medication> medicationById,
  required String treatmentName,
  required int now,
  required int horizon,
  required DndWindow dnd,
}) {
  final reminderMinutes =
      parseMinutesOfDay(reminder.timeOfDay, defaultReminderMinutes);
  final offsets = reminder.offsets.toSet().toList()..sort();

  final drafts = <ReminderDraft>[];
  final seen = <String>{};

  for (final plan in plans) {
    if (plan.kind != LineKind.injection) continue;
    if (plan.doseLogId != null ||
        plan.status == PlanStatus.done ||
        plan.status == PlanStatus.missed) {
      continue;
    }
    if (plan.plannedAt > horizon) continue;

    final line = lines[plan.lineId];
    if (line?.endedAt != null) continue;
    final medication = line != null ? medicationById[line.medicationId] : null;
    final medicationName = medication?.name ?? line?.label ?? treatmentName;
    final route =
        medication?.route == MedicationRoute.iv ? MedicationRoute.iv : MedicationRoute.sc;

    for (final offset in offsets) {
      final day = _addLocalDays(plan.plannedAt, offset);
      final rawTriggerAt = _atLocalMinutes(day, reminderMinutes);
      if (rawTriggerAt > horizon) continue;
      final triggerAt = shiftOutOfDnd(rawTriggerAt, dnd);
      if (!_sameLocalDay(triggerAt, rawTriggerAt)) continue;
      if (triggerAt <= now ||
          !_claimDraftKey(seen, plan.lineId, plan.plannedAt, triggerAt)) {
        continue;
      }

      final content = buildReminderContent(
        medicationName: medicationName,
        dose: plan.dose,
        unit: plan.unit,
        offsetDays: offset.abs(),
        route: route,
      );
      drafts.add(ReminderDraft(
        lineId: plan.lineId,
        kind: LineKind.injection,
        plannedAt: plan.plannedAt,
        triggerAt: triggerAt,
        title: content.title,
        body: content.body,
      ));
    }

    if (offsets.contains(0)) {
      final rawTriggerAt = _atLocalMinutes(plan.plannedAt, eveningCatchUpMinutes);
      if (rawTriggerAt > horizon) continue;
      final triggerAt = shiftOutOfDnd(rawTriggerAt, dnd);
      if (_sameLocalDay(triggerAt, rawTriggerAt) &&
          triggerAt > now &&
          _claimDraftKey(seen, plan.lineId, plan.plannedAt, triggerAt)) {
        final content = buildReminderContent(
          medicationName: medicationName,
          dose: plan.dose,
          unit: plan.unit,
          offsetDays: 0,
          isSameDayEvening: true,
          route: route,
        );
        drafts.add(ReminderDraft(
          lineId: plan.lineId,
          kind: LineKind.injection,
          plannedAt: plan.plannedAt,
          triggerAt: triggerAt,
          title: content.title,
          body: content.body,
        ));
      }
    }
  }

  return drafts;
}

List<ReminderDraft> _buildOralDrafts({
  required List<SchedulePlan> plans,
  required Map<String, TreatmentLine> lines,
  required Map<String, Medication> medicationById,
  required int now,
  required int horizon,
  required DndWindow dnd,
}) {
  final byDay = <String, _OralDayGroup>{};

  for (final plan in plans) {
    if (plan.kind != LineKind.oral) continue;
    if (plan.doseLogId != null ||
        plan.status == PlanStatus.done ||
        plan.status == PlanStatus.missed) {
      continue;
    }
    if (plan.plannedAt > horizon) continue;

    final line = lines[plan.lineId];
    if (line == null || line.oral == null || line.endedAt != null) continue;

    final day = _startOfLocalDay(plan.plannedAt);
    final remindMinutes =
        parseMinutesOfDay(line.oral!.remindTime, defaultReminderMinutes);
    final key = '$day|$remindMinutes';
    final medication = medicationById[line.medicationId];
    final name = medication?.name ?? line.label;

    final existing = byDay[key];
    if (existing != null) {
      if (!existing.lineIds.contains(plan.lineId)) existing.lineIds.add(plan.lineId);
      if (!existing.names.contains(name)) existing.names.add(name);
    } else {
      byDay[key] = _OralDayGroup(
        day: day,
        lineIds: [plan.lineId],
        names: [name],
        remindMinutes: remindMinutes,
      );
    }
  }

  final drafts = <ReminderDraft>[];
  for (final group in byDay.values) {
    final rawTriggerAt = _atLocalMinutes(group.day, group.remindMinutes);
    final triggerAt = shiftOutOfDnd(rawTriggerAt, dnd);
    if (!_sameLocalDay(triggerAt, rawTriggerAt)) continue;
    if (triggerAt <= now) continue;

    final content = buildOralReminderContent(group.names);
    drafts.add(ReminderDraft(
      lineId: group.lineIds.first,
      kind: LineKind.oral,
      plannedAt: group.day,
      triggerAt: triggerAt,
      title: content.title,
      body: content.body,
    ));
  }
  return drafts;
}

/// 纯函数构建未来 8 周的提醒草稿，优先保证注射提醒并在超出上限时裁剪口服提醒。
List<ReminderDraft> buildNotificationDrafts({
  required Treatment? treatment,
  required List<DoseLog> logs,
  required ReminderRuleV5? reminder,
  required AppSettings appSettings,
  required List<Medication> medications,
  required int now,
}) {
  if (treatment == null) return const [];

  final horizon = now + scheduleWindowDays * dayMs;
  final plans = _collectPlansThrough(treatment, logs, now, horizon);
  final medicationById = {for (final m in medications) m.id: m};
  final lineById = {for (final l in treatment.lines) l.id: l};
  final dnd = resolveDndWindow(appSettings);

  final injectionDrafts =
      reminder != null && reminder.enabled && reminder.offsets.isNotEmpty
          ? _buildInjectionDrafts(
              plans: plans,
              lines: lineById,
              reminder: reminder,
              medicationById: medicationById,
              treatmentName: treatment.name,
              now: now,
              horizon: horizon,
              dnd: dnd,
            )
          : <ReminderDraft>[];

  final oralDrafts = reminder?.enabled == false
      ? <ReminderDraft>[]
      : _buildOralDrafts(
          plans: plans,
          lines: lineById,
          medicationById: medicationById,
          now: now,
          horizon: horizon,
          dnd: dnd,
        );

  injectionDrafts.sort((a, b) => a.triggerAt.compareTo(b.triggerAt));
  oralDrafts.sort((a, b) => a.triggerAt.compareTo(b.triggerAt));

  final limitedInjections =
      injectionDrafts.take(maxScheduledNotifications).toList();
  final remaining =
      math.max(0, maxScheduledNotifications - limitedInjections.length);
  final merged = <ReminderDraft>[
    ...limitedInjections,
    ...oralDrafts.take(remaining),
  ];
  merged.sort((a, b) {
    final t = a.triggerAt.compareTo(b.triggerAt);
    return t != 0 ? t : a.plannedAt.compareTo(b.plannedAt);
  });
  return merged;
}

/// 抽象系统通知操作，便于纯 Dart 单测与多平台降级处理。
abstract class NotificationGateway {
  Future<void> initialize({
    required void Function(String? payload) onTap,
  });

  Future<String?> getLaunchPayload();

  Future<void> ensureChannel();

  Future<NotificationPermissionStatus> ensurePermissions();

  Future<void> cancelAll();

  Future<void> schedule(int id, ReminderDraft draft);
}

class PluginNotificationGateway implements NotificationGateway {
  PluginNotificationGateway([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;
  bool _timezoneInitialized = false;
  void Function(String? payload)? _onTap;

  Future<void> _ensureTimezoneInitialized() async {
    if (_timezoneInitialized) return;
    tz_data.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      // 某些精简 ROM 或桌面区域名称不在 IANA 表中时回退 UTC+8 / 默认时区，不阻断启动。
      try {
        tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
      } catch (_) {}
    }
    _timezoneInitialized = true;
  }

  @override
  Future<void> initialize({
    required void Function(String? payload) onTap,
  }) async {
    _onTap = onTap;
    if (_initialized) return;
    await _ensureTimezoneInitialized();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const windowsSettings = WindowsInitializationSettings(
      appName: _windowsAppName,
      appUserModelId: _windowsAppUserModelId,
      guid: _windowsGuid,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      windows: windowsSettings,
    );
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) {
        _onTap?.call(response.payload);
      },
    );
    _initialized = true;
  }

  @override
  Future<String?> getLaunchPayload() async {
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details != null && details.didNotificationLaunchApp) {
        return details.notificationResponse?.payload;
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<void> ensureChannel() async {
    if (!Platform.isAndroid) return;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    await android.createNotificationChannel(
      AndroidNotificationChannel(
        reminderChannelId,
        Zh.notify.channelName,
        importance: Importance.high,
      ),
    );
  }

  @override
  Future<NotificationPermissionStatus> ensurePermissions() async {
    await initialize(onTap: _onTap ?? (_) {});
    await ensureChannel();

    if (!Platform.isAndroid) {
      return const NotificationPermissionStatus(granted: true, exactAlarm: true);
    }

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) {
      return const NotificationPermissionStatus(granted: false, exactAlarm: false);
    }

    var granted = await android.areNotificationsEnabled() ?? false;
    if (!granted) {
      granted = await android.requestNotificationsPermission() ?? false;
    }

    var exactAlarm = await android.canScheduleExactNotifications() ?? false;
    if (!exactAlarm) {
      try {
        exactAlarm = await android.requestExactAlarmsPermission() ?? false;
      } catch (_) {
        exactAlarm = false;
      }
    }
    return NotificationPermissionStatus(granted: granted, exactAlarm: exactAlarm);
  }

  @override
  Future<void> cancelAll() async {
    if (!_initialized) return;
    await _plugin.cancelAll();
  }

  @override
  Future<void> schedule(int id, ReminderDraft draft) async {
    await _ensureTimezoneInitialized();
    final now = tz.TZDateTime.now(tz.local);
    final triggerDate = tz.TZDateTime.fromMillisecondsSinceEpoch(
      tz.local,
      draft.triggerAt,
    );
    if (!triggerDate.isAfter(now.add(const Duration(seconds: 2)))) {
      return;
    }

    var scheduleMode = AndroidScheduleMode.exactAllowWhileIdle;
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final canExact = await android?.canScheduleExactNotifications() ?? false;
      if (!canExact) {
        scheduleMode = AndroidScheduleMode.inexactAllowWhileIdle;
      }
    }

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        reminderChannelId,
        Zh.notify.channelName,
        importance: Importance.high,
        priority: Priority.high,
      ),
      windows: const WindowsNotificationDetails(),
    );

    await _plugin.zonedSchedule(
      id: id,
      scheduledDate: triggerDate,
      notificationDetails: details,
      androidScheduleMode: scheduleMode,
      title: draft.title,
      body: draft.body,
      payload: draft.payloadJson,
    );
  }
}

class NotifyScheduler {
  NotifyScheduler._();

  static NotificationGateway _gateway = PluginNotificationGateway();
  static Future<void> _queue = Future<void>.value();
  static int _generation = 0;
  static void Function(String? payload)? _tapHandler;

  @visibleForTesting
  static void configureGatewayForTesting(NotificationGateway gateway) {
    _gateway = gateway;
    _queue = Future<void>.value();
    _generation = 0;
  }

  @visibleForTesting
  static void resetGateway() {
    _gateway = PluginNotificationGateway();
    _queue = Future<void>.value();
    _generation = 0;
    _tapHandler = null;
  }

  static Future<void> initialize({
    required void Function(String? payload) onTap,
  }) async {
    _tapHandler = onTap;
    await _gateway.initialize(onTap: (payload) => _tapHandler?.call(payload));
  }

  static Future<String?> getLaunchPayload() => _gateway.getLaunchPayload();

  static Future<NotificationPermissionStatus> ensurePermissions() =>
      _gateway.ensurePermissions();

  static Future<void> cancelAll() => _gateway.cancelAll();

  static Future<int> rescheduleAll({int? nowMs}) {
    final generation = ++_generation;
    final run = _queue.catchError((Object _) {}).then(
          (_) => _runReschedule(generation, nowMs: nowMs),
        );
    _queue = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  static Future<int> _runReschedule(int generation, {int? nowMs}) async {
    if (generation != _generation) return 0;

    final treatment = await TreatmentsRepo.getActive();
    if (treatment == null) {
      if (generation == _generation) {
        await cancelAll();
      }
      return 0;
    }

    final results = await Future.wait([
      DoseLogsRepo.list(),
      ReminderRulesRepo.getFor(treatment.id),
      SettingsRepo.all(),
      MedicationsRepo.list(),
    ]);
    final logs = results[0] as List<DoseLog>;
    final reminder = results[1] as ReminderRuleV5?;
    final appSettings = results[2] as AppSettings;
    final allMedications = results[3] as List<Medication>;

    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final drafts = buildNotificationDrafts(
      treatment: treatment,
      logs: logs,
      reminder: reminder,
      appSettings: appSettings,
      medications: allMedications,
      now: now,
    );

    if (drafts.isNotEmpty) {
      await _gateway.ensureChannel();
    }
    if (generation != _generation) return 0;
    await cancelAll();

    var failed = 0;
    for (var i = 0; i < drafts.length; i++) {
      if (generation != _generation) return 0;
      try {
        await _gateway.schedule(i + 1, drafts[i]);
      } catch (_) {
        failed += 1;
      }
    }

    if (failed > 0) {
      throw StateError('有 $failed 条提醒未能排程，请检查系统通知权限');
    }
    return drafts.length;
  }
}

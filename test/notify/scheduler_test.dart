import 'package:bioclock/db/database.dart';
import 'package:bioclock/db/repo.dart';
import 'package:bioclock/domain/schedule.dart';
import 'package:bioclock/models/types.dart';
import 'package:bioclock/notify/notify_content.dart';
import 'package:bioclock/notify/notify_scheduler.dart';
import 'package:bioclock/store/app_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeNotificationGateway implements NotificationGateway {
  int initCount = 0;
  int channelCount = 0;
  int cancelAllCount = 0;
  final List<(int, ReminderDraft)> scheduled = [];
  bool throwOnSchedule = false;

  @override
  Future<void> initialize({
    required void Function(String? payload) onTap,
  }) async {
    initCount += 1;
  }

  @override
  Future<String?> getLaunchPayload() async => null;

  @override
  Future<void> ensureChannel() async {
    channelCount += 1;
  }

  @override
  Future<NotificationPermissionStatus> ensurePermissions() async {
    return const NotificationPermissionStatus(granted: true, exactAlarm: true);
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCount += 1;
    scheduled.clear();
  }

  @override
  Future<void> schedule(int id, ReminderDraft draft) async {
    if (throwOnSchedule) {
      throw StateError('模拟系统拒绝排程');
    }
    scheduled.add((id, draft));
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    NotifyScheduler.resetGateway();
    await AppDatabase.closeForTesting();
  });

  group('notify_content & shiftOutOfDnd', () {
    test('皮下与输注文案区分清晰且包含回温提示', () {
      final scSameDay = buildReminderContent(
        medicationName: '阿达木单抗',
        dose: 40,
        unit: 'mg',
        offsetDays: 0,
        route: MedicationRoute.sc,
      );
      expect(scSameDay.title, '今天该注射了');
      expect(scSameDay.body, contains(notifyPrepHint));

      final ivAhead = buildReminderContent(
        medicationName: '英夫利西单抗',
        dose: 300,
        unit: 'mg',
        offsetDays: -1,
        route: MedicationRoute.iv,
      );
      expect(ivAhead.title, '明天该去医院输注了');
      expect(ivAhead.body, isNot(contains(notifyPrepHint)));

      final oralMulti = buildOralReminderContent(['甲氨蝶呤', '叶酸']);
      expect(oralMulti.title, '今天有 2 种口服药');
      expect(oralMulti.body, contains('甲氨蝶呤、叶酸'));
    });

    test('免打扰顺延支持日间区间与跨午夜区间', () {
      final nightTs = DateTime(2026, 3, 1, 23, 0).millisecondsSinceEpoch;
      final shifted = shiftOutOfDnd(
        nightTs,
        const DndWindow(startMinutes: 22 * 60, endMinutes: 8 * 60),
      );
      final expected = DateTime(2026, 3, 2, 8, 0).millisecondsSinceEpoch;
      expect(shifted, expected);

      final daytimeTs = DateTime(2026, 3, 1, 13, 30).millisecondsSinceEpoch;
      final shiftedDay = shiftOutOfDnd(
        daytimeTs,
        const DndWindow(startMinutes: 12 * 60, endMinutes: 14 * 60),
      );
      expect(
        shiftedDay,
        DateTime(2026, 3, 1, 14, 0).millisecondsSinceEpoch,
      );
    });
  });

  group('buildNotificationDrafts', () {
    test('生成注射提前/当天/晚8点补提醒，免打扰顺延且优先级不超60条', () {
      final day0 = DateTime(2026, 3, 10, 0, 0).millisecondsSinceEpoch;
      final now = DateTime(2026, 3, 1, 7, 0).millisecondsSinceEpoch;

      const medInj = Medication(
        id: 'med-1',
        name: '司库奇尤单抗',
        genericName: null,
        brandNames: [],
        defaultDose: 150,
        unit: 'mg',
        color: '#2B6CB0',
        route: MedicationRoute.sc,
        diseaseIds: [],
        catalogKey: null,
        isBuiltin: true,
        extra: {},
        createdAt: 0,
      );
      const medOral = Medication(
        id: 'med-2',
        name: '甲氨蝶呤',
        genericName: null,
        brandNames: [],
        defaultDose: 10,
        unit: 'mg',
        color: '#2B6CB0',
        route: MedicationRoute.oral,
        diseaseIds: [],
        catalogKey: null,
        isBuiltin: true,
        extra: {},
        createdAt: 0,
      );

      final injLine = TreatmentLine(
        id: 'line-inj',
        treatmentId: 't1',
        medicationId: 'med-1',
        kind: LineKind.injection,
        label: '司库奇尤单抗',
        isHost: true,
        syncWithHost: false,
        anchor: RegimenAnchor.actual,
        windowDays: 2,
        endedAt: null,
        phases: const [
          TreatmentPhase(
            id: 'p1',
            lineId: 'line-inj',
            orderIdx: 0,
            kind: PhaseKind.maintenance,
            intervalDays: 1,
            repeatCount: 0,
            dose: 150,
            unit: 'mg',
            effectiveFrom: null,
          ),
        ],
        oral: null,
      );
      final oralLine = TreatmentLine(
        id: 'line-oral',
        treatmentId: 't1',
        medicationId: 'med-2',
        kind: LineKind.oral,
        label: '甲氨蝶呤',
        isHost: false,
        syncWithHost: false,
        anchor: RegimenAnchor.planned,
        windowDays: 0,
        endedAt: null,
        phases: const [],
        oral: OralPlan(
          startDate: DateTime(2026, 3, 1).millisecondsSinceEpoch,
          durationDays: null,
          frequency: OralFrequency.daily,
          timesPerPeriod: 1,
          daysOfWeek: const [],
          remindTime: '08:30',
        ),
      );

      final treatment = Treatment(
        id: 't1',
        name: '方案1',
        isActive: true,
        createdAt: day0,
        lines: [injLine, oralLine],
      );

      final drafts = buildNotificationDrafts(
        treatment: treatment,
        logs: [
          DoseLog(
            id: 'l0',
            lineId: 'line-inj',
            scheduledAt: day0,
            takenAt: day0,
            status: DoseStatus.done,
            dose: 150,
            unit: 'mg',
            site: InjectionSite.abdomenUl,
            lotNumber: null,
            note: null,
            createdAt: day0,
            updatedAt: day0,
          ),
        ],
        reminder: const ReminderRuleV5(
          id: 'r1',
          treatmentId: 't1',
          offsets: [-1, 0],
          timeOfDay: '07:00',
          snoozeMinutes: 10,
          enabled: true,
        ),
        appSettings: const {'dnd_start': '22:00', 'dnd_end': '08:00'},
        medications: const [medInj, medOral],
        now: now,
      );

      expect(drafts.length, maxScheduledNotifications);
      // 注射在 07:00 会被 22:00-08:00 免打扰顺延到 08:00
      final firstInj = drafts.firstWhere((d) => d.kind == LineKind.injection);
      final dt = DateTime.fromMillisecondsSinceEpoch(firstInj.triggerAt);
      expect(dt.hour, 8);
      expect(dt.minute, 0);
      expect(drafts.any((d) => d.title == '今天还没登记注射'), isTrue);
    });

    test('总开关关闭时不排口服也不排注射', () {
      final t0 = DateTime(2026, 3, 1, 8, 0).millisecondsSinceEpoch;
      final oralLine = TreatmentLine(
        id: 'line-oral',
        treatmentId: 't1',
        medicationId: 'm1',
        kind: LineKind.oral,
        label: '口服',
        isHost: false,
        syncWithHost: false,
        anchor: RegimenAnchor.planned,
        windowDays: 0,
        endedAt: null,
        phases: const [],
        oral: OralPlan(
          startDate: DateTime(2026, 3, 1).millisecondsSinceEpoch,
          durationDays: null,
          frequency: OralFrequency.daily,
          timesPerPeriod: 1,
          daysOfWeek: const [],
          remindTime: '09:00',
        ),
      );
      final drafts = buildNotificationDrafts(
        treatment: Treatment(
          id: 't1',
          name: '方案',
          isActive: true,
          createdAt: t0,
          lines: [oralLine],
        ),
        logs: const [],
        reminder: const ReminderRuleV5(
          id: 'r1',
          treatmentId: 't1',
          offsets: [0],
          timeOfDay: '09:00',
          snoozeMinutes: 10,
          enabled: false,
        ),
        appSettings: const {},
        medications: const [],
        now: t0,
      );
      expect(drafts, isEmpty);
    });
  });

  group('AppStore & NotifyScheduler integration', () {
    test('写入遵循 repo -> reload -> rescheduleAll，排程失败不回滚数据', () async {
      await AppDatabase.configureForTesting(path: inMemoryDatabasePath);
      final fake = _FakeNotificationGateway();
      NotifyScheduler.configureGatewayForTesting(fake);

      final store = AppStore();
      await store.reload();
      expect(store.ready, isTrue);

      final adalimumab =
          store.medications.firstWhere((m) => m.catalogKey == 'adalimumab');
      await store.saveTreatment(
        SaveTreatmentInput(
          name: '生物制剂方案',
          lines: [
            TreatmentLineDraft(
              medicationId: adalimumab.id,
              kind: LineKind.injection,
              label: adalimumab.name,
              isHost: true,
              phases: const [
                TreatmentPhaseInput(
                  orderIdx: 0,
                  kind: PhaseKind.maintenance,
                  intervalDays: 14,
                  repeatCount: 0,
                  dose: 40,
                  unit: 'mg',
                ),
              ],
            ),
          ],
        ),
      );
      await store.updateReminder(
        ReminderRuleInput(
          treatmentId: store.treatment!.id,
          offsets: const [-1, 0],
          timeOfDay: '09:00',
          snoozeMinutes: 10,
          enabled: true,
        ),
      );

      expect(fake.scheduled, isNotEmpty);

      // 测试排程失败时依然保留数据并返回 notifyWarning
      fake.throwOnSchedule = true;
      final now = DateTime.now().millisecondsSinceEpoch;
      final outcome = await store.addDoseLog(
        DoseLogInput(
          lineId: store.treatment!.lines.first.id,
          scheduledAt: null,
          takenAt: now - 3 * dayMs,
          status: DoseStatus.done,
          dose: 40,
          unit: 'mg',
          site: InjectionSite.abdomenUl,
        ),
      );
      expect(outcome.notifyWarning, isNotNull);
      expect(store.doseLogs.length, 1);

      // 测试「从下一针起」调整间隔
      fake.throwOnSchedule = false;
      final intervalOutcome = await store.changeInjectionInterval(
        store.treatment!.lines.first.id,
        28,
      );
      expect(intervalOutcome.notifyWarning, isNull);
      expect(store.treatment!.lines.first.phases.last.intervalDays, 28);
      expect(
        store.treatment!.lines.first.phases.last.effectiveFrom,
        isNotNull,
      );

      // 清空恢复内置药
      await store.resetAllData();
      expect(store.treatment, isNull);
      expect(store.doseLogs, isEmpty);
      expect(store.medications, isNotEmpty);
    });
  });
}

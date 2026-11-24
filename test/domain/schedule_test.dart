import 'package:bioclock/domain/schedule.dart';
import 'package:bioclock/models/types.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

TreatmentLine _crohnLine() => makeInjectionLine(
      id: 'line-host',
      phases: [
        makePhase(
            orderIdx: 0,
            kind: PhaseKind.loading,
            intervalDays: 14,
            repeatCount: 1,
            dose: 160),
        makePhase(
            orderIdx: 1,
            kind: PhaseKind.loading,
            intervalDays: 14,
            repeatCount: 1,
            dose: 80),
        makePhase(
            orderIdx: 2,
            kind: PhaseKind.maintenance,
            intervalDays: 14,
            repeatCount: 0,
            dose: 40),
      ],
    );

void main() {
  group('classifyWindow', () {
    test('窗口内（含边界）为 on_time', () {
      expect(classifyWindow(0, 2 * day, 2), WindowStatus.onTime);
      expect(classifyWindow(0, -2 * day, 2), WindowStatus.onTime);
      expect(classifyWindow(0, 0, 0), WindowStatus.onTime);
    });

    test('早于窗口为 early，晚于窗口为 late', () {
      expect(classifyWindow(0, -3 * day, 2), WindowStatus.early);
      expect(classifyWindow(0, 3 * day, 2), WindowStatus.late);
      expect(classifyWindow(0, -1 * day, 0), WindowStatus.early);
      expect(classifyWindow(0, 1 * day, 0), WindowStatus.late);
    });

    test('负窗口抛中文错误', () {
      expect(
        () => classifyWindow(0, 0, -1),
        throwsA(predicate((e) => e.toString().contains('允许偏差窗口不能小于 0 天'))),
      );
    });
  });

  group('classifyStatus', () {
    test('按 1 天边界判定 due / overdue / upcoming', () {
      expect(classifyStatus(t0, t0 + day), PlanStatus.due);
      expect(classifyStatus(t0, t0 - day), PlanStatus.due);
      expect(classifyStatus(t0, t0 + day + 1), PlanStatus.overdue);
      expect(classifyStatus(t0, t0 - day - 1), PlanStatus.upcoming);
    });
  });

  group('注射线：负荷 + 维持推进', () {
    test('无记录时首针计划时间 = 当日零点', () {
      final plans =
          buildInjectionPlans(line: _crohnLine(), logs: const [], now: t0);

      expect(plans[0].plannedAt, t0);
      expect(plans[0].status, PlanStatus.due);
      expect(plans[0].kind, LineKind.injection);
      expect(plans[0].lineId, 'line-host');
      expect(plans[0].medicationId, 'med-1');
      expect(plans[0].actualAt, isNull);
      expect(plans[0].deviationDays, isNull);
      expect(plans[0].windowStatus, isNull);
    });

    test('负荷 → 维持的剂量、阶段与时间正确推进', () {
      final plans = buildInjectionPlans(
        line: _crohnLine(),
        logs: [
          makeLog(scheduledAt: t0, takenAt: t0, dose: 160),
          makeLog(scheduledAt: t0 + 14 * day, takenAt: t0 + 14 * day, dose: 80),
        ],
        now: t0 + 35 * day,
      );

      expect(plans.map((p) => p.dose).toList(), [160, 80, 40, 40, 40]);
      expect(plans.map((p) => p.phaseKind).toList(), [
        PhaseKind.loading,
        PhaseKind.loading,
        PhaseKind.maintenance,
        PhaseKind.maintenance,
        PhaseKind.maintenance,
      ]);
      expect(intOffsets(plans), [0, 14, 28, 42, 56]);
      expect(plans.map((p) => p.status).toList(), [
        PlanStatus.done,
        PlanStatus.done,
        PlanStatus.overdue,
        PlanStatus.upcoming,
        PlanStatus.upcoming,
      ]);
    });

    test('无记录时从当天起算，只输出当次 + 未来 2 针', () {
      final plans = buildInjectionPlans(
        line: _crohnLine(),
        logs: const [],
        now: t0 + 35 * day,
      );

      expect(intOffsets(plans), [35, 49, 63]);
      expect(plans.map((p) => p.dose).toList(), [160, 80, 40]);
      expect(plans.map((p) => p.status).toList(),
          [PlanStatus.due, PlanStatus.upcoming, PlanStatus.upcoming]);
    });

    test("anchor: 'actual' 迟到会让后续顺延", () {
      final line = makeInjectionLine(anchor: RegimenAnchor.actual);
      final plans = buildInjectionPlans(
        line: line,
        logs: [injectionLog(0), injectionLog(16)],
        now: t0 + 16 * day,
      );

      expect(intOffsets(plans), [0, 14, 30, 44]);
      expect(plans[1].actualAt, t0 + 16 * day);
      expect(plans[1].deviationDays, 2);
      expect(plans[1].windowStatus, WindowStatus.onTime);
      expect(plans.map((p) => p.status).toList(), [
        PlanStatus.done,
        PlanStatus.done,
        PlanStatus.upcoming,
        PlanStatus.upcoming,
      ]);
    });

    test("anchor: 'planned' 下迟到不影响后续计划日", () {
      final line = makeInjectionLine(anchor: RegimenAnchor.planned);
      final plans = buildInjectionPlans(
        line: line,
        logs: [injectionLog(0), injectionLog(16)],
        now: t0 + 16 * day,
      );

      expect(intOffsets(plans), [0, 14, 28, 42]);
      expect(plans[1].windowStatus, WindowStatus.onTime);
    });

    test('超过窗口的迟到判定为 late，并记录一位小数的偏差', () {
      final line =
          makeInjectionLine(anchor: RegimenAnchor.planned, windowDays: 2);
      final plans = buildInjectionPlans(
        line: line,
        logs: [injectionLog(0), injectionLog(16.34)],
        now: t0 + 17 * day,
      );

      expect(plans[1].deviationDays, 2.3);
      expect(plans[1].windowStatus, WindowStatus.late);
    });

    test('缺少记录时退回上一针计划时间', () {
      final plans = buildInjectionPlans(
        line: makeInjectionLine(anchor: RegimenAnchor.actual),
        logs: [injectionLog(0)],
        now: t0 + 40 * day,
      );

      expect(intOffsets(plans), [0, 14, 28, 42, 56]);
      expect(plans[1].status, PlanStatus.overdue);
      expect(plans[0].doseLogId, isNotNull);
    });

    test('记录里的剂量与单位覆盖到计划项上', () {
      final plans = buildInjectionPlans(
        line: makeInjectionLine(),
        logs: [makeLog(scheduledAt: t0, takenAt: t0, dose: 80, unit: 'mg')],
        now: t0,
      );

      expect(plans[0].dose, 80);
      expect(plans[0].unit, 'mg');
    });

    test('记录按 scheduledAt 认领对应计划，即使实际时间乱序', () {
      final first = t0;
      final second = t0 + 14 * day;
      final plans = buildInjectionPlans(
        line: makeInjectionLine(anchor: RegimenAnchor.planned),
        logs: [
          makeLog(scheduledAt: second, takenAt: second + 2 * day),
          makeLog(scheduledAt: first, takenAt: first),
        ],
        now: second,
      );

      expect(plans[0].actualAt, first);
      expect(plans[1].actualAt, second + 2 * day);
      expect(plans[1].deviationDays, 2);
    });

    test('有限方案阶段耗尽后不再生成计划', () {
      final line = makeInjectionLine(
        phases: [
          makePhase(
              orderIdx: 0,
              kind: PhaseKind.loading,
              intervalDays: 7,
              repeatCount: 1,
              dose: 160),
        ],
      );
      final plans = buildInjectionPlans(
        line: line,
        logs: [injectionLog(0)],
        now: t0 + 10 * day,
      );

      expect(plans.length, 1);
      expect(plans[0].status, PlanStatus.done);
    });

    test('无限维持阶段只输出未来 2 针', () {
      final now = t0 + 100 * day;
      final plans = buildInjectionPlans(
          line: makeInjectionLine(), logs: const [], now: now);

      expect(intOffsets(plans), [100, 114, 128]);
      expect(plans.where((p) => p.plannedAt > now).length, 2);
    });

    test('爽约（skipped）且计划日已过 → missed；未来爽约 → upcoming', () {
      final line = makeInjectionLine(anchor: RegimenAnchor.planned);
      final plans = buildInjectionPlans(
        line: line,
        logs: [
          makeLog(scheduledAt: t0, takenAt: null, status: DoseStatus.skipped),
        ],
        now: t0 + 2 * day,
      );

      expect(plans[0].status, PlanStatus.missed);
      expect(plans[0].actualAt, isNull);
      expect(plans[1].status, PlanStatus.upcoming);
    });

    test('非法间隔与窗口抛中文错误', () {
      expect(
        () => buildInjectionPlans(
          line: makeInjectionLine(
              phases: [makePhase(orderIdx: 0, intervalDays: 0)]),
          logs: const [],
          now: t0,
        ),
        throwsA(predicate((e) => e.toString().contains('给药间隔必须大于 0 天'))),
      );
      expect(
        () => buildInjectionPlans(
          line: makeInjectionLine(windowDays: -1),
          logs: const [],
          now: t0,
        ),
        throwsA(predicate((e) => e.toString().contains('允许偏差窗口不能小于 0 天'))),
      );
    });

    test('空 phases 返回 []', () {
      expect(
        buildInjectionPlans(
          line: makeInjectionLine(phases: const []),
          logs: const [],
          now: t0,
        ),
        isEmpty,
      );
    });
  });

  group('同步线与错开线', () {
    test('同步线针日跟随宿主线，不自己累加', () {
      final host = makeInjectionLine(
        id: 'line-host',
        isHost: true,
        phases: [
          makePhase(lineId: 'line-host', orderIdx: 0, intervalDays: 14)
        ],
      );
      final synced = makeInjectionLine(
        id: 'line-synced',
        medicationId: 'med-2',
        isHost: false,
        syncWithHost: true,
        phases: [
          makePhase(
              lineId: 'line-synced', orderIdx: 0, intervalDays: 30, dose: 20)
        ],
      );

      final plans = buildSchedule(
        lines: [host, synced],
        logs: [
          injectionLog(0, 'line-host'),
          injectionLog(17, 'line-host'),
        ],
        now: t0 + 17 * day,
      );

      final hostPlans = plans.where((p) => p.lineId == 'line-host').toList();
      final syncedPlans =
          plans.where((p) => p.lineId == 'line-synced').toList();
      final hostDaySet = hostPlans.map((p) => p.plannedAt).toSet();

      expect(syncedPlans, isNotEmpty);
      expect(syncedPlans.every((p) => hostDaySet.contains(p.plannedAt)), isTrue);
      expect(intOffsets(hostPlans).sublist(0, 4), [0, 14, 31, 45]);
      expect(intOffsets(syncedPlans).sublist(0, 4), [0, 14, 31, 45]);
      expect(syncedPlans[0].dose, 20);
      expect(syncedPlans[0].kind, LineKind.injection);
    });

    test('resolveHostLine 优先返回 isHost 的注射线', () {
      final host = makeInjectionLine(id: 'line-host', isHost: true);
      final other = makeInjectionLine(
          id: 'line-other', isHost: false, anchor: RegimenAnchor.planned);
      final synced = makeInjectionLine(
          id: 'line-synced', isHost: false, syncWithHost: true);

      expect(resolveHostLine(synced, [synced, other, host])?.id, 'line-host');
      expect(resolveHostLine(synced, [synced, other])?.id, 'line-other');
      expect(resolveHostLine(synced, [synced]), isNull);
    });

    test('没有宿主可跟随时返回空', () {
      final synced = makeInjectionLine(
          id: 'line-synced', isHost: false, syncWithHost: true);
      expect(
          buildLineSchedule(line: synced, logs: const [], now: t0), isEmpty);
    });

    test('错开线按自己间隔推进且记录不串线', () {
      final host = makeInjectionLine(
        id: 'line-host',
        isHost: true,
        anchor: RegimenAnchor.planned,
      );
      final staggered = makeInjectionLine(
        id: 'line-staggered',
        isHost: false,
        anchor: RegimenAnchor.planned,
        phases: [
          makePhase(
              lineId: 'line-staggered',
              orderIdx: 0,
              intervalDays: 7,
              dose: 25)
        ],
      );

      final plans = buildSchedule(
        lines: [host, staggered],
        logs: [
          injectionLog(0, 'line-host'),
          injectionLog(2, 'line-staggered'),
        ],
        now: t0 + 2 * day,
      );

      final hostPlans = plans.where((p) => p.lineId == 'line-host').toList();
      final staggeredPlans =
          plans.where((p) => p.lineId == 'line-staggered').toList();

      expect(intOffsets(hostPlans), [0, 14, 28]);
      expect(intOffsets(staggeredPlans), [2, 9, 16]);
      expect(
        staggeredPlans.firstWhere((p) => p.status == PlanStatus.done).dose,
        40,
      );
    });
  });

  group('口服线：打卡点生成', () {
    test('daily 每天一个打卡点，历史全量 + 未来覆盖默认天数', () {
      final plans = buildOralPlans(
        line: makeOralLine(frequency: OralFrequency.daily),
        logs: const [],
        now: t0 + 2 * day,
      );

      final days = intOffsets(plans);
      expect(days.first, 0);
      expect(days.last, 2 + oralHorizonDays);
      expect(days.length, 2 + oralHorizonDays + 1);
      expect(plans[0].kind, LineKind.oral);
      expect(plans[0].phaseId, isNull);
      expect(plans[0].status, PlanStatus.overdue);
      expect(plans[2].status, PlanStatus.due);
    });

    test('weekly 按每周次数均匀分布', () {
      final plans = buildOralPlans(
        line:
            makeOralLine(frequency: OralFrequency.weekly, timesPerPeriod: 2),
        logs: const [],
        now: t0 + 7 * day,
      );

      final days = intOffsets(plans);
      expect(days.sublist(0, 4), [0, 4, 7, 11]);
      expect(
        oralWeekdays(makeOralLine(
                frequency: OralFrequency.weekly, timesPerPeriod: 2)
            .oral!),
        [1, 5],
      );
      expect(
        oralWeekdays(makeOralLine(
                frequency: OralFrequency.weekly, timesPerPeriod: 3)
            .oral!),
        [1, 3, 6],
      );
      expect(
        oralWeekdays(makeOralLine(
                frequency: OralFrequency.weekly, timesPerPeriod: 1)
            .oral!),
        [1],
      );
    });

    test('custom 严格按 daysOfWeek 周几打卡', () {
      final plans = buildOralPlans(
        line: makeOralLine(
            frequency: OralFrequency.custom, daysOfWeek: const [0, 3]),
        logs: const [],
        now: t0 + 5 * day,
      );

      expect(intOffsets(plans).sublist(0, 4), [2, 6, 9, 13]);
    });

    test('durationDays 到期与停用后补录显示', () {
      final limited = buildOralPlans(
        line: makeOralLine(frequency: OralFrequency.daily, durationDays: 3),
        logs: const [],
        now: t0,
      );
      expect(intOffsets(limited), [0, 1, 2]);

      final skipped = makeLog(
        lineId: 'line-oral',
        status: DoseStatus.skipped,
        takenAt: null,
        scheduledAt: null,
        createdAt: t0 + 5 * day,
      );
      final withExtra = buildOralPlans(
        line: makeOralLine(
          frequency: OralFrequency.daily,
          durationDays: 2,
          endedAt: t0 + 10 * day,
        ),
        logs: [skipped],
        now: t0 + 12 * day,
      );
      final extra = withExtra.firstWhere((p) => p.plannedAt == t0 + 5 * day);
      expect(extra.doseLogId, skipped.id);
      expect(extra.status, PlanStatus.missed);
    });
  });

  group('通知覆盖与 nextDose / 停用 / effectiveFrom / totalPlannedDoses', () {
    test('futureDoseCountForHorizon 覆盖 56 天', () {
      final line14 = makeInjectionLine(
          phases: [makePhase(orderIdx: 0, intervalDays: 14)]);
      expect(futureDoseCountForHorizon([line14], 56), 6);

      final line56 = makeInjectionLine(
          phases: [makePhase(orderIdx: 0, intervalDays: 56)]);
      expect(futureDoseCountForHorizon([line56], 56), 3);
      expect(futureDoseCountForHorizon([makeOralLine()], 56), 2);
    });

    test('nextDose 跨线挑选，近期逾期优先于未来计划', () {
      final p1 = nextDose(
        lines: [
          makeInjectionLine(id: 'line-host'),
          makeOralLine(
            id: 'line-oral',
            frequency: OralFrequency.daily,
            startDate: t0 + day,
          ),
        ],
        logs: [injectionLog(0)],
        now: t0,
      );
      expect(p1?.lineId, 'line-oral');
      expect(p1?.plannedAt, t0 + day);

      final p2 = nextDoseForLine(
        line: makeInjectionLine(),
        logs: [injectionLog(0), injectionLog(14)],
        now: t0 + 30 * day,
      );
      expect(p2?.plannedAt, t0 + 28 * day);
      expect(p2?.status, PlanStatus.overdue);

      final finite = makeInjectionLine(phases: [
        makePhase(orderIdx: 0, intervalDays: 7, repeatCount: 2),
      ]);
      expect(
        nextDoseForLine(
            line: finite, logs: [injectionLog(0)], now: t0 + 300 * day),
        isNull,
      );
    });

    test('停用线拦截未来计划且保留停用后补录', () {
      final line = makeInjectionLine(
        id: 'line-host',
        endedAt: t0 + 30 * day,
        phases: [makePhase(orderIdx: 0, intervalDays: 14)],
      );
      final plans = buildInjectionPlans(
        line: line,
        logs: [
          injectionLog(0),
          injectionLog(14),
          injectionLog(28),
          injectionLog(34),
        ],
        now: t0 + 40 * day,
      );
      expect(intOffsets(plans), [0, 14, 28, 34]);
      expect(plans[3].status, PlanStatus.done);
    });

    test('effectiveFrom 生效时间新旧阶段互不破坏', () {
      final line = makeInjectionLine(
        phases: [
          makePhase(orderIdx: 0, intervalDays: 56, repeatCount: 0),
          makePhase(
            orderIdx: 1,
            intervalDays: 42,
            repeatCount: 0,
            effectiveFrom: t0 + 42 * day,
          ),
        ],
      );
      final plans = buildInjectionPlans(
        line: line,
        logs: [injectionLog(0)],
        now: t0 + 100 * day,
      );
      expect(intOffsets(plans).sublist(0, 3), [0, 42, 84]);

      final backfilledLine = makeInjectionLine(
        phases: [
          makePhase(orderIdx: 0, intervalDays: 56, repeatCount: 0),
          makePhase(
            orderIdx: 1,
            intervalDays: 42,
            repeatCount: 0,
            effectiveFrom: t0 + 100 * day,
          ),
        ],
      );
      final oldPlans = buildInjectionPlans(
        line: backfilledLine,
        logs: [injectionLog(0), injectionLog(56)],
        now: t0 + 80 * day,
      );
      expect(intOffsets(oldPlans).sublist(0, 2), [0, 56]);
    });

    test('totalPlannedDoses', () {
      expect(
        totalPlannedDoses([
          makePhase(orderIdx: 0, repeatCount: 2),
          makePhase(orderIdx: 1, repeatCount: 3),
        ]),
        5,
      );
      expect(totalPlannedDoses(const []), 0);
      expect(
        totalPlannedDoses([
          makePhase(orderIdx: 0, repeatCount: 2),
          makePhase(orderIdx: 1, repeatCount: 0),
        ]),
        double.infinity,
      );
    });
  });
}

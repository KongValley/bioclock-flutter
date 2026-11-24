import 'package:bioclock/data/catalog.dart';
import 'package:bioclock/data/diseases.dart';
import 'package:bioclock/domain/adherence.dart';
import 'package:bioclock/domain/calendar.dart';
import 'package:bioclock/domain/date_utils.dart';
import 'package:bioclock/domain/interval.dart';
import 'package:bioclock/domain/medication.dart';
import 'package:bioclock/domain/pain.dart';
import 'package:bioclock/domain/preview.dart';
import 'package:bioclock/domain/rotation.dart';
import 'package:bioclock/models/types.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  group('interval', () {
    test('buildIntervalChangePhases 追加生效维持阶段并替换同日及更晚旧生效阶段', () {
      final existing = [
        makePhase(orderIdx: 0, intervalDays: 56, repeatCount: 0),
        makePhase(
            orderIdx: 1,
            intervalDays: 28,
            repeatCount: 0,
            effectiveFrom: t0 + 50 * day),
      ];
      final updated = buildIntervalChangePhases(existing, 42, t0 + 40 * day);
      expect(updated.length, 2);
      expect(updated[0].intervalDays, 56);
      expect(updated[1].intervalDays, 42);
      expect(updated[1].effectiveFrom, t0 + 40 * day);
    });

    test('处于负荷阶段时拒绝调整间隔', () {
      final loadingOnly = [
        makePhase(
            orderIdx: 0,
            kind: PhaseKind.loading,
            intervalDays: 14,
            repeatCount: 2),
      ];
      expect(
        () => buildIntervalChangePhases(loadingOnly, 14, t0 + 28 * day),
        throwsA(predicate((e) => e.toString().contains('负荷阶段'))),
      );
    });
  });

  group('preview', () {
    test('buildPhasePreview 按阶段 repeatCount 累加天偏移', () {
      final preview = buildPhasePreview([
        const PreviewPhase(
          kind: PhaseKind.loading,
          intervalDays: 14,
          repeatCount: 1,
          dose: 160,
          unit: 'mg',
        ),
        const PreviewPhase(
          kind: PhaseKind.maintenance,
          intervalDays: 28,
          repeatCount: 0,
          dose: 80,
          unit: 'mg',
        ),
      ], max: 4);
      expect(preview.map((e) => e.dayOffset).toList(), [0, 14, 42, 70]);
      expect(preview.map((e) => e.dose).toList(), [160, 80, 80, 80]);
    });
  });

  group('rotation', () {
    test('空历史默认 abdomen_ul，之后避开最近 2 次并换侧、腹部优先', () {
      expect(recommendSite(const []), InjectionSite.abdomenUl);

      final afterFirst = recommendSite([
        SiteHistoryEntry(site: InjectionSite.abdomenUl, injectedAt: t0),
      ]);
      expect(afterFirst, InjectionSite.abdomenUr);

      final afterTwo = recommendSite([
        SiteHistoryEntry(site: InjectionSite.abdomenUl, injectedAt: t0),
        SiteHistoryEntry(
            site: InjectionSite.abdomenUr, injectedAt: t0 + 14 * day),
      ]);
      expect(afterTwo, InjectionSite.abdomenLl);
    });
  });

  group('adherence', () {
    test('混合注射线与口服线按线与汇总正确统计', () {
      final inj = makeInjectionLine(
        id: 'line-inj',
        anchor: RegimenAnchor.planned,
        windowDays: 2,
      );
      final oral = makeOralLine(
        id: 'line-oral',
        frequency: OralFrequency.daily,
        durationDays: 3,
      );
      final stats = computeAdherence(
        [inj, oral],
        [
          makeLog(lineId: 'line-inj', scheduledAt: t0, takenAt: t0),
          makeLog(
              lineId: 'line-inj',
              scheduledAt: t0 + 14 * day,
              takenAt: t0 + 18 * day),
          makeLog(lineId: 'line-oral', scheduledAt: t0, takenAt: t0),
        ],
        t0 + 20 * day,
      );

      expect(stats.total, 3);
      expect(stats.onTime, 1);
      expect(stats.late, 1);
      expect(stats.currentStreak, 0);
      expect(stats.missed, 2);
      expect(stats.byLine.length, 2);
    });
  });

  group('pain & medication', () {
    test('painBand 正确分档', () {
      expect(painBand(0), PainBand.none);
      expect(painBand(2), PainBand.mild);
      expect(painBand(5), PainBand.moderate);
      expect(painBand(9), PainBand.severe);
    });

    test('findMedicationByName 识别商品名与去噪声别名且内置药优先', () {
      final adalimumab = Medication(
        id: 'm1',
        name: '阿达木单抗',
        genericName: '阿达木单抗',
        brandNames: const ['修美乐'],
        defaultDose: 40,
        unit: 'mg',
        color: '#2B6CB0',
        route: MedicationRoute.sc,
        diseaseIds: const ['crohn'],
        catalogKey: 'adalimumab',
        isBuiltin: true,
        extra: const {},
        createdAt: t0,
      );
      final custom = Medication(
        id: 'm2',
        name: '自建修美乐',
        genericName: null,
        brandNames: const ['修美乐'],
        defaultDose: 40,
        unit: 'mg',
        color: '#000000',
        route: MedicationRoute.sc,
        diseaseIds: const [],
        catalogKey: null,
        isBuiltin: false,
        extra: const {},
        createdAt: t0,
      );
      expect(findMedicationByName([custom, adalimumab], '  （修-美 乐） ')?.id, 'm1');
    });
  });

  group('calendar & date_utils & catalog', () {
    test('buildMonthCells 输出 42 格且从周一开始', () {
      const cursor = MonthCursor(year: 2026, month: 0);
      final cells = buildMonthCells(cursor);
      expect(cells.length, 42);
      final firstDate = DateTime.fromMillisecondsSinceEpoch(cells.first);
      expect(firstDate.weekday, DateTime.monday);
      expect(monthTitle(cursor), '2026年1月');
      expect(shiftMonth(cursor, -1), const MonthCursor(year: 2025, month: 11));
    });

    test('parseManualDateTime & bumpTimeOfDay', () {
      final ts = parseManualDateTime('2026-03-15 09:30');
      expect(ts, isNotNull);
      expect(formatManualInput(ts!), '2026-03-15 09:30');
      expect(parseManualDateTime('2026-02-30 09:00'), isNull);
      expect(bumpTimeOfDay('23:55', 10), '23:05');
      expect(bumpTimeOfDay('09:00', -5), '09:55');
      expect(formatSignedDays(2.0), '+2 天');
      expect(formatSignedDays(-0.02), '0 天');
    });

    test('病种合并去重且保留一线优先', () {
      final resolved = resolveDiseaseIds({'disease_ids': '["crohn","as","crohn"]'});
      expect(resolved, ['crohn', 'as']);
      final choices = drugsForDiseases(['crohn', 'as']);
      expect(choices.any((c) => c.drug.key == 'adalimumab'), isTrue);
      expect(
        choices.where((c) => c.drug.key == 'infliximab').single.entry.firstLine,
        isTrue,
      );
    });
  });
}

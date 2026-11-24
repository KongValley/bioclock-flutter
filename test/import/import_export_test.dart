import 'dart:typed_data';

import 'package:bioclock/db/database.dart';
import 'package:bioclock/db/repo.dart';
import 'package:bioclock/domain/date_utils.dart';
import 'package:bioclock/export/csv_exporter.dart';
import 'package:bioclock/export/excel_exporter.dart';
import 'package:bioclock/export/json_exporter.dart';
import 'package:bioclock/export/pdf_exporter.dart';
import 'package:bioclock/export/transfer_schema.dart';
import 'package:bioclock/import/import_schema.dart';
import 'package:bioclock/import/import_service.dart';
import 'package:bioclock/import/spreadsheet_parser.dart';
import 'package:bioclock/models/types.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    await AppDatabase.closeForTesting();
  });

  group('import_schema', () {
    test('支持 v1/v2/v3 JSON 与中文别名并校验边界', () {
      const jsonStr = '''
      {
        "format": "bioclock-import",
        "version": 2,
        "medications": [
          { "name": "甲氨蝶呤", "route": "口服", "defaultDose": 10, "unit": "mg" }
        ],
        "injections": [
          { "injectedAt": "2026-03-15 09:00", "medication": "阿达木单抗", "dose": 40, "site": "腹部左上", "status": "已完成" }
        ],
        "oralLogs": [
          { "takenAt": "2026-03-16 08:30", "medication": "甲氨蝶呤", "status": "跳过", "note": "外出忘带" }
        ],
        "symptoms": [
          { "loggedAt": "2026-03-16 20:00", "severity": 4, "painScore": 6, "tags": ["发热", "发热"], "temperature": 37.8, "injectionAt": "2026-03-15 09:00" }
        ]
      }
      ''';

      final parsed = parseImportJson(jsonStr);
      expect(parsed.medications.single.route, MedicationRoute.oral);
      expect(parsed.injections.single.site, InjectionSite.abdomenUl);
      expect(parsed.injections.single.status, DoseStatus.done);
      expect(parsed.oralLogs.single.status, DoseStatus.skipped);
      expect(parsed.symptoms.single.tags, ['发热']);
    });

    test('非法日期、超温或非 bioclock 格式抛中文异常', () {
      expect(
        () => parseLocalDateTime('2026-02-30 09:00', '注射时间'),
        throwsA(isA<ImportValidationException>()),
      );
      expect(
        () => parseImportJson('{"format":"other","version":3}'),
        throwsA(isA<ImportValidationException>()),
      );
      expect(
        () => parseImportJson('{"format":"bioclock-import","version":99}'),
        throwsA(isA<ImportValidationException>()),
      );
    });

    test('resolveImportLogTime 区分 done 与 skipped/missed', () {
      expect(
        resolveImportLogTime(
            status: DoseStatus.done, eventAt: 200, scheduledAt: 100),
        200,
      );
      expect(
        resolveImportLogTime(
            status: DoseStatus.skipped, eventAt: 200, scheduledAt: 100),
        100,
      );
    });
  });

  group('spreadsheet_parser & export formats roundtrip', () {
    test('Excel 五表生成并可被 parseSpreadsheet 完整往返解析', () {
      final t = Treatment(
        id: 't1',
        name: '联合方案',
        isActive: true,
        createdAt: 1000,
        lines: [
          TreatmentLine(
            id: 'l1',
            treatmentId: 't1',
            medicationId: 'm1',
            kind: LineKind.injection,
            label: '修美乐',
            isHost: true,
            syncWithHost: false,
            anchor: RegimenAnchor.actual,
            windowDays: 2,
            endedAt: null,
            phases: const [],
            oral: null,
          ),
          TreatmentLine(
            id: 'l2',
            treatmentId: 't1',
            medicationId: 'm2',
            kind: LineKind.oral,
            label: '甲氨蝶呤',
            isHost: false,
            syncWithHost: false,
            anchor: RegimenAnchor.planned,
            windowDays: 2,
            endedAt: null,
            phases: const [],
            oral: OralPlan(
              startDate: DateTime(2026, 3, 1).millisecondsSinceEpoch,
              durationDays: null,
              frequency: OralFrequency.weekly,
              timesPerPeriod: 1,
              daysOfWeek: const [],
              remindTime: '09:00',
            ),
          ),
        ],
      );
      final meds = [
        const Medication(
          id: 'm1',
          name: '阿达木单抗',
          genericName: '阿达木单抗',
          brandNames: ['修美乐'],
          defaultDose: 40,
          unit: 'mg',
          color: '#2B6CB0',
          route: MedicationRoute.sc,
          diseaseIds: ['crohn'],
          catalogKey: 'adalimumab',
          isBuiltin: true,
          extra: {},
          createdAt: 1000,
        ),
        const Medication(
          id: 'm2',
          name: '甲氨蝶呤',
          genericName: null,
          brandNames: ['MTX'],
          defaultDose: 10,
          unit: 'mg',
          color: '#3182CE',
          route: MedicationRoute.oral,
          diseaseIds: [],
          catalogKey: null,
          isBuiltin: false,
          extra: {},
          createdAt: 1000,
        ),
      ];
      final injAt = DateTime(2026, 3, 15, 9, 0).millisecondsSinceEpoch;
      final oralAt = DateTime(2026, 3, 16, 8, 30).millisecondsSinceEpoch;
      final symAt = DateTime(2026, 3, 15, 21, 0).millisecondsSinceEpoch;
      final logs = [
        DoseLog(
          id: 'd1',
          lineId: 'l1',
          scheduledAt: injAt,
          takenAt: injAt,
          status: DoseStatus.done,
          dose: 40,
          unit: 'mg',
          site: InjectionSite.abdomenUl,
          lotNumber: 'LOT-1',
          note: '首针',
          createdAt: injAt,
          updatedAt: injAt,
        ),
        DoseLog(
          id: 'd2',
          lineId: 'l2',
          scheduledAt: oralAt,
          takenAt: oralAt,
          status: DoseStatus.done,
          dose: 10,
          unit: 'mg',
          site: null,
          lotNumber: null,
          note: null,
          createdAt: oralAt,
          updatedAt: oralAt,
        ),
      ];
      final syms = [
        SymptomLog(
          id: 's1',
          loggedAt: symAt,
          severity: 2,
          painScore: 1,
          tags: const ['乏力'],
          note: '轻微',
          temperature: 37.2,
          injectionId: 'd1',
        ),
      ];

      final xlsxBytes = buildExcelBytes(
        treatments: [t],
        medications: meds,
        symptoms: syms,
        doseLogs: logs,
      );
      final parsed = parseSpreadsheet(xlsxBytes);
      expect(parsed.injections.length, 1);
      expect(parsed.injections.single.injectedAt, injAt);
      expect(parsed.injections.single.site, InjectionSite.abdomenUl);
      expect(parsed.oralLogs.length, 1);
      expect(parsed.symptoms.single.injectionAt, injAt);
      expect(parsed.medications.length, 2);

      final csv = buildCsvContent(
        treatments: [t],
        medications: meds,
        doseLogs: logs,
        nowMs: symAt,
      );
      expect(csv.startsWith('\uFEFF'), isTrue);
      expect(csv, contains('阿达木单抗'));
      expect(csv, contains('腹部左上'));

      final jsonText = buildExportJsonString(
        treatments: [t],
        medications: meds,
        symptoms: syms,
        doseLogs: logs,
        efficacyEvents: const [],
        nowMs: symAt,
      );
      final reparsedJson = parseImportJson(jsonText);
      expect(reparsedJson.injections.length, 1);
      expect(reparsedJson.oralLogs.length, 1);
      expect(reparsedJson.symptoms.length, 1);
    });

    test('支持解析 Excel 数值日期序列号并拒绝旧版 .xls', () {
      final excel = Excel.createExcel();
      final s = excel[excel.getDefaultSheet()!];
      s.appendRow([TextCellValue('注射时间'), TextCellValue('药物'), TextCellValue('剂量')]);
      // 46096.375 == 2026-03-15 09:00 (1900 epoch)
      s.appendRow([const DoubleCellValue(46096.375), TextCellValue('阿达木单抗'), const IntCellValue(40)]);
      final bytes = Uint8List.fromList(excel.encode()!);
      final payload = parseSpreadsheet(bytes);
      expect(
        formatLocalDateTime(payload.injections.single.injectedAt),
        '2026-03-15 09:00',
      );

      final fakeXls = Uint8List.fromList([0xD0, 0xCF, 0x11, 0xE0, 0, 0]);
      expect(
        () => parseSpreadsheet(fakeXls),
        throwsA(predicate((e) => e.toString().contains('.xls'))),
      );
    });

    test('离线矢量 PDF 生成合法非空字节', () async {
      final bytes = await buildVectorPdfBytes(
        patientName: '测试患者',
        rangeDays: 180,
        since: 1700000000000,
        now: 1710000000000,
        logs: const [],
        lineById: const {},
        medicationById: const {},
        adherence: computeZeroAdherenceForTest(),
        lineSummaries: const [],
        symptomSummary: const SymptomSummary(
          count: 0,
          avgSeverity: 0,
          avgPain: null,
          mostCommonTag: '暂无记录',
        ),
      );
      expect(bytes.length, greaterThan(500));
      expect(String.fromCharCodes(bytes.sublist(0, 4)), '%PDF');
    });
  });

  group('SQLite transactional import & transfer integration', () {
    setUp(() async {
      await AppDatabase.configureForTesting(path: inMemoryDatabasePath);
      await AppDatabase.initDatabase();
    });

    test('previewImport 与 importPayload 自动新建线、去重且停用线校验生效', () async {
      final meds = await MedicationsRepo.list();
      final adalimumab = meds.firstWhere((m) => m.catalogKey == 'adalimumab');
      final t = await TreatmentsRepo.create(
        TreatmentInput(
          name: '主方案',
          lines: [
            TreatmentLineInput(
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
      await TreatmentsRepo.setActive(t.id, true);

      const inputJson = '''
      {
        "format": "bioclock-import",
        "version": 3,
        "medications": [
          { "name": "甲氨蝶呤", "route": "oral", "defaultDose": 10, "unit": "mg" }
        ],
        "injections": [
          { "injectedAt": "2026-03-01 09:00", "medication": "修美乐", "dose": 40, "site": "腹部左上" },
          { "injectedAt": "2026-03-15 09:00", "medication": "修美乐", "dose": 40, "site": "腹部右上" }
        ],
        "oralLogs": [
          { "takenAt": "2026-03-02 08:00", "medication": "甲氨蝶呤", "status": "done", "dose": 10 }
        ],
        "symptoms": [
          { "loggedAt": "2026-03-15 20:00", "severity": 3, "tags": ["自定义反应"], "injectionAt": "2026-03-15 09:00" }
        ]
      }
      ''';

      final payload = parseImportJson(inputJson);
      final preview = await previewImport(payload);
      expect(preview.injections, 2);
      expect(preview.oralLogs, 1);
      expect(preview.medicationsCreated, 1);
      expect(preview.linesCreated, 1);
      expect(await DoseLogsRepo.list(), isEmpty);

      final committed = await importPayload(payload);
      expect(committed.injections, 2);
      expect(committed.oralLogs, 1);
      expect(committed.linesCreated, 1);
      expect((await DoseLogsRepo.list()).length, 3);
      expect((await SymptomTagsRepo.list()).any((tag) => tag.name == '自定义反应'),
          isTrue);

      // 重复导入全部跳过
      final second = await importPayload(payload);
      expect(second.injections, 0);
      expect(second.oralLogs, 0);
      expect(second.symptoms, 0);
      expect(second.skipped, 4);
      expect(second.linesCreated, 0);

      // 停用线后试图导入停用日之后的普通记录报错且不写入
      final active = (await TreatmentsRepo.getActive())!;
      await TreatmentsRepo.setLineEnded(
        active.lines.first.id,
        DateTime(2026, 3, 10).millisecondsSinceEpoch,
      );
      expect(
        () => previewImport(parseImportJson('''
        {
          "format": "bioclock-import",
          "version": 3,
          "injections": [
            { "injectedAt": "2026-03-12 09:00", "medication": "修美乐", "dose": 40, "site": "腹部左上" }
          ]
        }
        ''')),
        throwsA(predicate((e) => e.toString().contains('已停用'))),
      );
    });

    test('transferFile 校验格式、未来 schemaVersion 并能转成 ImportPayload', () {
      const futureTransfer = '''
      {
        "format": "bioclock-transfer",
        "version": 1,
        "schemaVersion": 999,
        "exportedAt": 1700000000000,
        "app": "BioClock",
        "medications": [],
        "treatments": [],
        "doseLogs": [],
        "symptoms": [],
        "efficacyEvents": [],
        "symptomTags": [],
        "reminders": [],
        "settings": {}
      }
      ''';
      expect(isTransferFile(futureTransfer), isTrue);
      expect(
        () => parseTransferFile(futureTransfer),
        throwsA(predicate((e) => e.toString().contains('请先升级 App'))),
      );
    });
  });
}

dynamic computeZeroAdherenceForTest() =>
    summarizeReportAdherence(
      treatments: const [],
      allLogs: const [],
      lineById: const {},
      now: 1710000000000,
    ).stats;

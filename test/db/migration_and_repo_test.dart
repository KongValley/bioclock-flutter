import 'package:bioclock/db/database.dart';
import 'package:bioclock/db/repo.dart';
import 'package:bioclock/db/schema.dart';
import 'package:bioclock/models/types.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<List<String>> _tableNames(Database db) async {
  final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name");
  return [for (final r in rows) r['name'] as String];
}

Future<List<String>> _columnNames(Database db, String table) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return [for (final r in rows) r['name'] as String];
}

const String _v4SchemaSql = '''
CREATE TABLE medication (
  id TEXT PRIMARY KEY NOT NULL,
  name TEXT NOT NULL,
  generic_name TEXT,
  default_dose REAL,
  unit TEXT NOT NULL,
  color TEXT NOT NULL,
  is_builtin INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  route TEXT NOT NULL DEFAULT 'sc',
  disease_ids TEXT NOT NULL DEFAULT '[]',
  catalog_key TEXT,
  brand_names TEXT NOT NULL DEFAULT '[]',
  extra TEXT NOT NULL DEFAULT '{}'
);
CREATE TABLE regimen (
  id TEXT PRIMARY KEY NOT NULL,
  medication_id TEXT NOT NULL REFERENCES medication(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  anchor TEXT NOT NULL DEFAULT 'actual',
  window_days INTEGER NOT NULL DEFAULT 2,
  is_active INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);
CREATE TABLE regimen_phase (
  id TEXT PRIMARY KEY NOT NULL,
  regimen_id TEXT NOT NULL REFERENCES regimen(id) ON DELETE CASCADE,
  order_idx INTEGER NOT NULL,
  kind TEXT NOT NULL,
  interval_days INTEGER NOT NULL,
  repeat_count INTEGER NOT NULL DEFAULT 0,
  dose REAL,
  unit TEXT NOT NULL
);
CREATE TABLE injection (
  id TEXT PRIMARY KEY NOT NULL,
  regimen_id TEXT NOT NULL REFERENCES regimen(id) ON DELETE CASCADE,
  medication_id TEXT NOT NULL REFERENCES medication(id) ON DELETE CASCADE,
  injected_at INTEGER NOT NULL,
  dose REAL,
  unit TEXT NOT NULL,
  site TEXT NOT NULL,
  lot_number TEXT,
  note TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
''';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    await AppDatabase.closeForTesting();
  });

  group('SQLite 建库与迁移', () {
    test('全新库建出 v7 表结构与播种数据', () async {
      await AppDatabase.configureForTesting(path: inMemoryDatabasePath);
      final db = await AppDatabase.database;

      expect(await AppDatabase.readUserVersion(db), schemaVersion);
      final tables = await _tableNames(db);
      for (final name in [
        'medication',
        'treatment',
        'treatment_line',
        'treatment_phase',
        'efficacy_event',
        'dose_log',
        'reminder_rule',
        'symptom_log',
        'symptom_tag',
        'app_setting',
      ]) {
        expect(tables, contains(name));
      }

      final meds = await MedicationsRepo.list();
      expect(meds.length, 22);
      expect(meds.every((m) => m.isBuiltin), isTrue);

      final tags = await SymptomTagsRepo.list();
      expect(tags.length, 10);

      // 删除自定义标签后不会重新播种
      final added = await SymptomTagsRepo.create('测试标签');
      await SymptomTagsRepo.remove(added.id);
      await AppDatabase.migrateAndSeed(db);
      expect((await SymptomTagsRepo.list()).any((t) => t.name == '测试标签'), isFalse);
    });

    test('v4 老库打开后重建为 v7，旧表清除', () async {
      final db = await openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await db.execute('PRAGMA foreign_keys = ON');
      await executeSqlScript(db, _v4SchemaSql);
      await db.execute('PRAGMA user_version = 4');
      await db.rawInsert(
        "INSERT INTO medication (id, name, unit, color, is_builtin, created_at) VALUES ('m1', 'old', 'mg', '#000', 1, 1)",
      );
      await db.rawInsert(
        "INSERT INTO regimen (id, medication_id, name, created_at) VALUES ('r1', 'm1', 'old', 1)",
      );

      await AppDatabase.migrateAndSeed(db);
      expect(await AppDatabase.readUserVersion(db), 7);
      final tables = await _tableNames(db);
      expect(tables, isNot(contains('regimen')));
      expect(tables, isNot(contains('regimen_phase')));
      expect(tables, isNot(contains('injection')));
      expect(tables, contains('treatment'));
      expect(await _columnNames(db, 'treatment_phase'), contains('effective_from'));
      await db.close();
    });

    test('v5 库增量迁移保留全部业务数据并补齐 v6/v7 列与表', () async {
      final db = await openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await db.execute('PRAGMA foreign_keys = ON');
      await executeSqlScript(db, createTablesSql);
      await db.execute('DROP TABLE efficacy_event');
      await db.execute('ALTER TABLE treatment_line DROP COLUMN ended_at');
      await db.execute('ALTER TABLE treatment_phase DROP COLUMN effective_from');
      await db.execute('PRAGMA user_version = 5');

      await db.rawInsert(
        "INSERT INTO medication (id, name, unit, color, route, is_builtin, created_at) VALUES ('m1', '阿达木单抗', 'mg', '#2B6CB0', 'sc', 1, 1)",
      );
      await db.rawInsert(
        "INSERT INTO treatment (id, name, is_active, created_at) VALUES ('t1', '组合方案', 1, 1)",
      );
      await db.rawInsert(
        "INSERT INTO treatment_line (id, treatment_id, medication_id, kind, label, is_host, sync_with_host, anchor) VALUES ('l1', 't1', 'm1', 'injection', '阿达木单抗', 1, 0, 'actual')",
      );
      await db.rawInsert(
        "INSERT INTO treatment_phase (id, line_id, order_idx, kind, interval_days, repeat_count, dose, unit) VALUES ('p1', 'l1', 0, 'maintenance', 14, 0, 40, 'mg')",
      );
      await db.rawInsert(
        "INSERT INTO dose_log (id, line_id, scheduled_at, taken_at, status, dose, unit, created_at, updated_at) VALUES ('d1', 'l1', 1000, 1000, 'done', 40, 'mg', 1000, 1000)",
      );
      await db.rawInsert(
        "INSERT INTO symptom_log (id, logged_at, severity, tags, dose_log_id) VALUES ('s1', 2000, 2, '[]', 'd1')",
      );
      await db.rawInsert(
        "INSERT INTO app_setting (key, value) VALUES ('patient_name', 'Alice')",
      );

      await AppDatabase.migrateAndSeed(db);
      expect(await AppDatabase.readUserVersion(db), 7);
      expect(await _columnNames(db, 'treatment_line'), contains('ended_at'));
      expect(await _columnNames(db, 'treatment_phase'), contains('effective_from'));
      expect(await _tableNames(db), contains('efficacy_event'));

      final t = await db.rawQuery("SELECT name FROM treatment WHERE id = 't1'");
      expect(t.single['name'], '组合方案');
      final s = await db.rawQuery("SELECT dose_log_id FROM symptom_log WHERE id = 's1'");
      expect(s.single['dose_log_id'], 'd1');
      await db.close();
    });

    test('v6 缺列缺表与 v7 缺 effective_from 修复', () async {
      final db = await openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await executeSqlScript(db, createTablesSql);
      await db.execute('DROP TABLE efficacy_event');
      await db.execute('ALTER TABLE treatment_line DROP COLUMN ended_at');
      await db.execute('PRAGMA user_version = 6');

      await AppDatabase.migrateAndSeed(db);
      expect(await AppDatabase.readUserVersion(db), 7);
      expect(await _columnNames(db, 'treatment_line'), contains('ended_at'));
      expect(await _tableNames(db), contains('efficacy_event'));

      await db.execute('ALTER TABLE treatment_phase DROP COLUMN effective_from');
      await AppDatabase.migrateAndSeed(db);
      expect(await _columnNames(db, 'treatment_phase'), contains('effective_from'));
      await db.close();
    });
  });

  group('仓库层 CRUD 与校验', () {
    setUp(() async {
      await AppDatabase.configureForTesting(path: inMemoryDatabasePath);
      await AppDatabase.initDatabase();
    });

    test('treatment、doseLog、efficacyEvent、symptom 与 resetDatabase 全流程', () async {
      final meds = await MedicationsRepo.list();
      final adalimumab = meds.firstWhere((m) => m.catalogKey == 'adalimumab');
      final customMed = await MedicationsRepo.create(
        const MedicationInput(
          name: '甲氨蝶呤',
          route: MedicationRoute.oral,
          unit: 'mg',
          color: '#3182CE',
          defaultDose: 10,
        ),
      );

      final created = await TreatmentsRepo.create(
        TreatmentInput(
          name: '测试组合',
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
            TreatmentLineInput(
              medicationId: customMed.id,
              kind: LineKind.oral,
              label: customMed.name,
              oral: OralPlan(
                startDate: 1700000000000,
                durationDays: null,
                frequency: OralFrequency.weekly,
                timesPerPeriod: 1,
                daysOfWeek: const [],
                remindTime: '09:00',
              ),
            ),
          ],
        ),
      );
      await TreatmentsRepo.setActive(created.id, true);
      final active = await TreatmentsRepo.getActive();
      expect(active?.lines.length, 2);

      final injLine =
          active!.lines.firstWhere((l) => l.kind == LineKind.injection);
      final dose = await DoseLogsRepo.create(
        DoseLogInput(
          lineId: injLine.id,
          scheduledAt: 1700000000000,
          takenAt: 1700000000000,
          status: DoseStatus.done,
          dose: 40,
          unit: 'mg',
          site: InjectionSite.abdomenUl,
        ),
      );
      expect(dose.site, InjectionSite.abdomenUl);

      final event = await EfficacyEventsRepo.create(
        EfficacyEventInput(
          lineId: injLine.id,
          kind: EfficacyKind.reduced,
          occurredAt: 1700100000000,
          note: '第五周开始下降',
          stopLine: true,
        ),
      );
      expect(event.dosesCount, 1);
      final stoppedActive = await TreatmentsRepo.getActive();
      expect(
        stoppedActive!.lines.firstWhere((l) => l.id == injLine.id).endedAt,
        1700100000000,
      );

      final symptom = await SymptomsRepo.create(
        SymptomLogInput(
          loggedAt: 1700050000000,
          severity: 3,
          painScore: 4,
          tags: const ['乏力'],
          temperature: 37.5,
          injectionId: dose.id,
        ),
      );
      expect(symptom.painScore, 4);

      await ReminderRulesRepo.upsert(
        ReminderRuleInput(
          treatmentId: created.id,
          offsets: const [-2, -1, 0],
          timeOfDay: '09:00',
          snoozeMinutes: 10,
          enabled: true,
        ),
      );
      expect((await ReminderRulesRepo.getFor(created.id))?.offsets, [-2, -1, 0]);

      // 校验错误抛出 RepoValidationException
      await expectLater(
        () => DoseLogsRepo.create(
          DoseLogInput(
            lineId: injLine.id,
            scheduledAt: 1700000000000,
            takenAt: null,
            status: DoseStatus.done,
          ),
        ),
        throwsA(isA<RepoValidationException>()),
      );

      await AppDatabase.resetDatabase();
      expect(await TreatmentsRepo.list(), isEmpty);
      expect((await MedicationsRepo.list()).length, 22);
      expect((await SymptomTagsRepo.list()).length, 10);
    });
  });
}

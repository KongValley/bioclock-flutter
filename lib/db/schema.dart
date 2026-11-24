/// 手写 SQL DDL。
/// 列名统一 snake_case，仓库层负责与 `lib/models/types.dart` 的 camelCase 互转。
/// 时间列一律存 UTC 毫秒（INTEGER），布尔列存 0 / 1。
library;

const String databaseName = 'bioclock.db';

/// 当前数据库结构版本，写入 `PRAGMA user_version`。
///
/// - v5：重建「治疗方案」模型（`treatment / treatment_line / treatment_phase / dose_log`）。
/// - v6：新增 `efficacy_event` 与 `treatment_line.ended_at`。
/// - v7：新增 `treatment_phase.effective_from`，支持「从下一针起」调整间隔。
const int schemaVersion = 7;

const String createTablesSql = '''
CREATE TABLE IF NOT EXISTS medication (
  id           TEXT    PRIMARY KEY NOT NULL,
  name         TEXT    NOT NULL,
  generic_name TEXT,
  brand_names  TEXT    NOT NULL DEFAULT '[]',
  default_dose REAL,
  unit         TEXT    NOT NULL,
  color        TEXT    NOT NULL,
  route        TEXT    NOT NULL DEFAULT 'sc',
  disease_ids  TEXT    NOT NULL DEFAULT '[]',
  catalog_key  TEXT,
  is_builtin   INTEGER NOT NULL DEFAULT 0,
  extra        TEXT    NOT NULL DEFAULT '{}',
  created_at   INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS treatment (
  id         TEXT    PRIMARY KEY NOT NULL,
  name       TEXT    NOT NULL,
  is_active  INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS treatment_line (
  id                    TEXT    PRIMARY KEY NOT NULL,
  treatment_id          TEXT    NOT NULL REFERENCES treatment(id) ON DELETE CASCADE,
  medication_id         TEXT    NOT NULL REFERENCES medication(id) ON DELETE CASCADE,
  kind                  TEXT    NOT NULL CHECK (kind IN ('injection', 'oral')),
  label                 TEXT    NOT NULL,
  is_host               INTEGER NOT NULL DEFAULT 0,
  sync_with_host        INTEGER NOT NULL DEFAULT 0,
  anchor                TEXT    NOT NULL DEFAULT 'actual' CHECK (anchor IN ('actual', 'planned')),
  window_days           INTEGER NOT NULL DEFAULT 2,
  ended_at              INTEGER,
  oral_start            INTEGER,
  oral_duration_days    INTEGER,
  oral_frequency        TEXT    CHECK (oral_frequency IS NULL OR oral_frequency IN ('daily', 'weekly', 'custom')),
  oral_times_per_period INTEGER,
  oral_days_of_week     TEXT,
  oral_remind_time      TEXT
);

CREATE TABLE IF NOT EXISTS treatment_phase (
  id             TEXT    PRIMARY KEY NOT NULL,
  line_id        TEXT    NOT NULL REFERENCES treatment_line(id) ON DELETE CASCADE,
  order_idx      INTEGER NOT NULL,
  kind           TEXT    NOT NULL CHECK (kind IN ('loading', 'maintenance')),
  interval_days  INTEGER NOT NULL,
  repeat_count   INTEGER NOT NULL DEFAULT 0,
  dose           REAL,
  unit           TEXT    NOT NULL,
  effective_from INTEGER
);

CREATE TABLE IF NOT EXISTS efficacy_event (
  id          TEXT    PRIMARY KEY NOT NULL,
  line_id     TEXT    NOT NULL REFERENCES treatment_line(id) ON DELETE CASCADE,
  kind        TEXT    NOT NULL CHECK (kind IN ('reduced', 'failed', 'intolerance', 'antibody', 'other')),
  occurred_at INTEGER NOT NULL,
  doses_count INTEGER NOT NULL DEFAULT 0,
  note        TEXT,
  created_at  INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS dose_log (
  id           TEXT    PRIMARY KEY NOT NULL,
  line_id      TEXT    NOT NULL REFERENCES treatment_line(id) ON DELETE CASCADE,
  scheduled_at INTEGER,
  taken_at     INTEGER,
  status       TEXT    NOT NULL CHECK (status IN ('done', 'skipped', 'missed')),
  dose         REAL,
  unit         TEXT,
  site         TEXT,
  lot_number   TEXT,
  note         TEXT,
  created_at   INTEGER NOT NULL,
  updated_at   INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS symptom_log (
  id           TEXT    PRIMARY KEY NOT NULL,
  logged_at    INTEGER NOT NULL,
  severity     INTEGER NOT NULL CHECK (severity BETWEEN 1 AND 5),
  pain_score   REAL,
  tags         TEXT    NOT NULL DEFAULT '[]',
  note         TEXT,
  temperature  REAL,
  dose_log_id  TEXT REFERENCES dose_log(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS symptom_tag (
  id         TEXT    PRIMARY KEY NOT NULL,
  name       TEXT    NOT NULL UNIQUE,
  is_builtin INTEGER NOT NULL DEFAULT 0,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS reminder_rule (
  id             TEXT    PRIMARY KEY NOT NULL,
  treatment_id   TEXT    NOT NULL UNIQUE REFERENCES treatment(id) ON DELETE CASCADE,
  offsets        TEXT    NOT NULL DEFAULT '[-2,-1,0]',
  time_of_day    TEXT    NOT NULL DEFAULT '09:00',
  snooze_minutes INTEGER NOT NULL DEFAULT 10,
  enabled        INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS app_setting (
  key   TEXT PRIMARY KEY NOT NULL,
  value TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_treatment_line_treatment
  ON treatment_line (treatment_id);

CREATE INDEX IF NOT EXISTS idx_treatment_phase_order
  ON treatment_phase (line_id, order_idx);

CREATE INDEX IF NOT EXISTS idx_dose_log_line_time
  ON dose_log (line_id, scheduled_at);

CREATE INDEX IF NOT EXISTS idx_efficacy_event_line_time
  ON efficacy_event (line_id, occurred_at);

CREATE INDEX IF NOT EXISTS idx_symptom_log_logged_at
  ON symptom_log (logged_at);

CREATE INDEX IF NOT EXISTS idx_symptom_tag_order
  ON symptom_tag (sort_order, created_at);

CREATE UNIQUE INDEX IF NOT EXISTS idx_medication_catalog_key
  ON medication (catalog_key) WHERE catalog_key IS NOT NULL;
''';

const String createEfficacyEventSql = '''
CREATE TABLE IF NOT EXISTS efficacy_event (
  id          TEXT    PRIMARY KEY NOT NULL,
  line_id     TEXT    NOT NULL REFERENCES treatment_line(id) ON DELETE CASCADE,
  kind        TEXT    NOT NULL CHECK (kind IN ('reduced', 'failed', 'intolerance', 'antibody', 'other')),
  occurred_at INTEGER NOT NULL,
  doses_count INTEGER NOT NULL DEFAULT 0,
  note        TEXT,
  created_at  INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_efficacy_event_line_time
  ON efficacy_event (line_id, occurred_at);
''';

const String migration6Sql = '''
ALTER TABLE treatment_line ADD COLUMN ended_at INTEGER;

$createEfficacyEventSql
''';

const String migration7Sql = '''
ALTER TABLE treatment_phase ADD COLUMN effective_from INTEGER;
''';

String buildV7RepairSql({required bool hasEffectiveFrom}) {
  if (hasEffectiveFrom) return '';
  return '''
ALTER TABLE treatment_phase ADD COLUMN effective_from INTEGER;
PRAGMA user_version = $schemaVersion;''';
}

String buildV6RepairSql({
  required bool hasEndedAt,
  required bool hasEfficacyTable,
}) {
  final statements = <String>[];
  if (!hasEndedAt) {
    statements.add('ALTER TABLE treatment_line ADD COLUMN ended_at INTEGER;');
  }
  if (!hasEfficacyTable) {
    statements.add(createEfficacyEventSql);
  }
  if (statements.isEmpty) return '';
  return '${statements.join('\n')}\nPRAGMA user_version = $schemaVersion;';
}

const String deleteAllBusinessDataSql = '''
DELETE FROM efficacy_event;
DELETE FROM symptom_log;
DELETE FROM symptom_tag;
DELETE FROM dose_log;
DELETE FROM treatment_phase;
DELETE FROM treatment_line;
DELETE FROM reminder_rule;
DELETE FROM treatment;
DELETE FROM app_setting;
DELETE FROM medication WHERE is_builtin = 0;
''';

const String dropAllTablesSql = '''
DROP TABLE IF EXISTS efficacy_event;
DROP TABLE IF EXISTS symptom_log;
DROP TABLE IF EXISTS symptom_tag;
DROP TABLE IF EXISTS dose_log;
DROP TABLE IF EXISTS treatment_phase;
DROP TABLE IF EXISTS treatment_line;
DROP TABLE IF EXISTS reminder_rule;
DROP TABLE IF EXISTS treatment;
DROP TABLE IF EXISTS medication;
DROP TABLE IF EXISTS app_setting;
DROP TABLE IF EXISTS injection;
DROP TABLE IF EXISTS regimen_phase;
DROP TABLE IF EXISTS regimen;
''';

/// 根据起始版本号生成建库 / 迁移 SQL。
String buildMigrationSql(int fromVersion) {
  if (fromVersion == 0) {
    return '$createTablesSql\nPRAGMA user_version = $schemaVersion;';
  }
  if (fromVersion == 5) {
    return '$migration6Sql\n$migration7Sql\nPRAGMA user_version = $schemaVersion;';
  }
  if (fromVersion == 6) {
    return '$migration7Sql\nPRAGMA user_version = $schemaVersion;';
  }
  return '$dropAllTablesSql\n$createTablesSql\nPRAGMA user_version = $schemaVersion;';
}

/// 将包含多条语句与 `--` 注释的 SQL 脚本拆分为单条可执行语句，避免 Android `execSQL` 只执行第一条。
List<String> splitSqlStatements(String sql) {
  final statements = <String>[];
  final buffer = StringBuffer();
  var inSingleQuote = false;

  for (var i = 0; i < sql.length; i += 1) {
    final ch = sql[i];

    if (inSingleQuote) {
      buffer.write(ch);
      if (ch == "'") {
        if (i + 1 < sql.length && sql[i + 1] == "'") {
          buffer.write("'");
          i += 1;
        } else {
          inSingleQuote = false;
        }
      }
      continue;
    }

    if (ch == "'") {
      inSingleQuote = true;
      buffer.write(ch);
      continue;
    }

    if (ch == '-' && i + 1 < sql.length && sql[i + 1] == '-') {
      while (i < sql.length && sql[i] != '\n') {
        i += 1;
      }
      buffer.write('\n');
      continue;
    }

    if (ch == ';') {
      final stmt = buffer.toString().trim();
      if (stmt.isNotEmpty) statements.add(stmt);
      buffer.clear();
      continue;
    }

    buffer.write(ch);
  }

  final tail = buffer.toString().trim();
  if (tail.isNotEmpty) statements.add(tail);
  return statements;
}

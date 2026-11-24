import 'dart:io';

import 'package:bioclock/db/schema.dart';
import 'package:bioclock/db/seed.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 顺序执行多条 SQL 语句（处理注释、单引号字面量、PRAGMA 返回行问题）。
Future<void> executeSqlScript(DatabaseExecutor db, String script) async {
  for (final stmt in splitSqlStatements(script)) {
    await db.execute(stmt);
  }
}

/// 应用数据库单例管理器。
///
/// Android 使用 `sqflite` 原生驱动，Windows / Linux 与单元测试使用 `sqflite_common_ffi`。
class AppDatabase {
  AppDatabase._();

  static Future<Database>? _dbFuture;
  static Database? _rawDb;
  static bool _ffiInitialized = false;
  static String? _overridePath;

  static void ensureFfiInitialized() {
    if (_ffiInitialized) return;
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      _ffiInitialized = true;
    }
  }

  static Future<String> resolveDatabasePath() async {
    if (_overridePath != null) return _overridePath!;
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      final supportDir = await getApplicationSupportDirectory();
      final dbDir = Directory(supportDir.path);
      if (!await dbDir.exists()) {
        await dbDir.create(recursive: true);
      }
      return p.join(dbDir.path, databaseName);
    }
    final dbDir = await getDatabasesPath();
    return p.join(dbDir, databaseName);
  }

  /// 获取已迁移、已播种的数据库连接；迁移失败时不缓存失败的 Future。
  static Future<Database> get database {
    _dbFuture ??= _openAndMigrate().catchError((Object error, StackTrace stack) {
      _dbFuture = null;
      Error.throwWithStackTrace(error, stack);
    });
    return _dbFuture!;
  }

  static Future<void> initDatabase() async {
    await database;
  }

  static Future<T> runInTransaction<T>(
    Future<T> Function(Transaction txn) action, {
    DatabaseExecutor? existingExecutor,
  }) async {
    if (existingExecutor is Transaction) {
      return action(existingExecutor);
    }
    final db = await database;
    return db.transaction(action);
  }

  /// 清空全部业务数据（保留内置药并重新播种症状标签）。
  static Future<void> resetDatabase() async {
    final db = await database;
    await db.transaction((txn) async {
      await executeSqlScript(txn, deleteAllBusinessDataSql);
      await seedBuiltinMedications(txn);
      await seedBuiltinSymptomTags(txn);
    });
  }

  /// 测试辅助：使用内存数据库或指定路径并关闭旧连接。
  @visibleForTesting
  static Future<void> configureForTesting({String? path}) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    _ffiInitialized = true;
    await closeForTesting();
    _overridePath = path ?? inMemoryDatabasePath;
  }

  @visibleForTesting
  static Future<void> closeForTesting() async {
    final current = _rawDb;
    _rawDb = null;
    _dbFuture = null;
    if (current != null && current.isOpen) {
      await current.close();
    }
  }

  static Future<Database> _openAndMigrate() async {
    ensureFfiInitialized();
    final dbPath = await resolveDatabasePath();
    final db = await openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        singleInstance: false,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
      ),
    );

    try {
      await db.rawQuery('PRAGMA journal_mode = WAL');
    } catch (_) {
      // 内存库或不支持 WAL 的环境可忽略
    }
    await db.execute('PRAGMA foreign_keys = ON');

    await migrateAndSeed(db);
    _rawDb = db;
    return db;
  }

  /// 执行版本检查、迁移、v6/v7 缺列修复及幂等播种。
  @visibleForTesting
  static Future<void> migrateAndSeed(Database db) async {
    final current = await readUserVersion(db);
    if (current > schemaVersion) {
      throw StateError(
        '数据库版本（$current）高于当前应用支持的版本（$schemaVersion），请更新 BioClock 后再试',
      );
    }

    var effective = current;
    if (current == 0) {
      final legacy = await db.rawQuery(
        '''SELECT name FROM sqlite_master
            WHERE type = 'table' AND name IN ('regimen', 'regimen_phase', 'injection')
            LIMIT 1''',
      );
      if (legacy.isNotEmpty) effective = 1;
    }

    if (effective < schemaVersion) {
      await _migrate(db, effective);
    }

    if (effective >= 5) {
      await _repairV6Schema(db);
    }
    if (effective >= 6) {
      await _repairV7Schema(db);
    }

    await seedBuiltinMedications(db);
    try {
      await seedBuiltinSymptomTags(db);
    } catch (_) {
      // 标签播种失败不阻塞启动
    }
  }

  static Future<int> readUserVersion(DatabaseExecutor db) async {
    final rows = await db.rawQuery('PRAGMA user_version');
    if (rows.isEmpty) return 0;
    final val = rows.first.values.first;
    return val is int ? val : (val as num?)?.toInt() ?? 0;
  }

  static Future<void> _migrate(Database db, int fromVersion) async {
    if (fromVersion == 5) {
      await db.transaction((txn) async {
        final lineCols = await txn.rawQuery('PRAGMA table_info(treatment_line)');
        if (!lineCols.any((c) => c['name'] == 'ended_at')) {
          await txn.execute('ALTER TABLE treatment_line ADD COLUMN ended_at INTEGER');
        }
        await executeSqlScript(txn, createEfficacyEventSql);
        final phaseCols = await txn.rawQuery('PRAGMA table_info(treatment_phase)');
        if (!phaseCols.any((c) => c['name'] == 'effective_from')) {
          await txn.execute('ALTER TABLE treatment_phase ADD COLUMN effective_from INTEGER');
        }
        await txn.execute('PRAGMA user_version = $schemaVersion');
      });
      return;
    }
    if (fromVersion == 6) {
      await db.transaction((txn) async {
        final phaseCols = await txn.rawQuery('PRAGMA table_info(treatment_phase)');
        if (!phaseCols.any((c) => c['name'] == 'effective_from')) {
          await txn.execute('ALTER TABLE treatment_phase ADD COLUMN effective_from INTEGER');
        }
        await txn.execute('PRAGMA user_version = $schemaVersion');
      });
      return;
    }
    final sql = buildMigrationSql(fromVersion);
    if (fromVersion == 0) {
      await executeSqlScript(db, sql);
      return;
    }
    await db.transaction((txn) async {
      await executeSqlScript(txn, sql);
    });
  }

  static Future<void> _repairV6Schema(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(treatment_line)');
    if (columns.isEmpty) return;
    final hasEndedAt = columns.any((col) => col['name'] == 'ended_at');
    final efficacyTable = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'efficacy_event' LIMIT 1",
    );
    if (hasEndedAt && efficacyTable.isNotEmpty) return;

    final sql = buildV6RepairSql(
      hasEndedAt: hasEndedAt,
      hasEfficacyTable: efficacyTable.isNotEmpty,
    );
    if (sql.isEmpty) return;
    await db.transaction((txn) async {
      await executeSqlScript(txn, sql);
    });
  }

  static Future<void> _repairV7Schema(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(treatment_phase)');
    if (columns.isEmpty) return;
    final hasEffectiveFrom =
        columns.any((col) => col['name'] == 'effective_from');
    final sql = buildV7RepairSql(hasEffectiveFrom: hasEffectiveFrom);
    if (sql.isEmpty) return;
    await db.transaction((txn) async {
      await executeSqlScript(txn, sql);
    });
  }
}

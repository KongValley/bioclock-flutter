import 'dart:convert';

import 'package:bioclock/data/catalog.dart';
import 'package:bioclock/i18n/zh.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// 把药品目录幂等播种到 `medication` 表。
///
/// 1. 优先用 `catalog_key` 精确匹配；
/// 2. 兼容 v1 无 `catalog_key` 的老内置药，按 `generic_name` 认领；
/// 3. 名称、商品名、目录字段跟随目录更新，保留用户自定义 `default_dose`。
Future<void> seedBuiltinMedications(DatabaseExecutor db) async {
  final now = DateTime.now().millisecondsSinceEpoch;

  for (final drug in catalogDrugs) {
    final diseaseIds = diseaseIdsForDrug(drug.key);
    final diseaseIdsJson = jsonEncode(diseaseIds);
    final brandNamesJson = jsonEncode(drug.brandNames);

    final existing = await db.rawQuery(
      '''SELECT id FROM medication
          WHERE is_builtin = 1
            AND (catalog_key = ? OR (catalog_key IS NULL AND generic_name = ?))
          LIMIT 1''',
      [drug.key, drug.genericName],
    );

    if (existing.isNotEmpty) {
      final id = existing.first['id'] as String;
      await db.rawUpdate(
        '''UPDATE medication
              SET name = ?, generic_name = ?, brand_names = ?, unit = ?, color = ?,
                  route = ?, disease_ids = ?, catalog_key = ?, is_builtin = 1
            WHERE id = ?''',
        [
          drug.name,
          drug.genericName,
          brandNamesJson,
          drug.unit,
          drug.color,
          drug.route.wire,
          diseaseIdsJson,
          drug.key,
          id,
        ],
      );
      continue;
    }

    await db.rawInsert(
      '''INSERT INTO medication
          (id, name, generic_name, brand_names, default_dose, unit, color, route,
           disease_ids, catalog_key, is_builtin, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?)''',
      [
        _uuid.v4(),
        drug.name,
        drug.genericName,
        brandNamesJson,
        drug.defaultDose,
        drug.unit,
        drug.color,
        drug.route.wire,
        diseaseIdsJson,
        drug.key,
        now,
      ],
    );
  }
}

/// 症状标签只需要播种一次；通过 `app_setting.symptom_tags_seeded` 标记防止删空后回填。
Future<void> seedBuiltinSymptomTags(DatabaseExecutor db) async {
  final seeded = await db.rawQuery(
    "SELECT value FROM app_setting WHERE key = 'symptom_tags_seeded' LIMIT 1",
  );
  if (seeded.isNotEmpty) return;

  final now = DateTime.now().millisecondsSinceEpoch;
  var order = 0;
  for (final name in defaultSymptomTags) {
    await db.rawInsert(
      '''INSERT OR IGNORE INTO symptom_tag (id, name, is_builtin, sort_order, created_at)
         VALUES (?, ?, 1, ?, ?)''',
      [_uuid.v4(), name, order, now],
    );
    order += 1;
  }

  await db.rawInsert(
    "INSERT OR REPLACE INTO app_setting (key, value) VALUES ('symptom_tags_seeded', '1')",
  );
}

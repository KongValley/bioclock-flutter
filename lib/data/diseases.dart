import 'dart:convert';

import 'package:bioclock/models/types.dart';

/// 疾病目录。
///
/// 重要：本目录只是录入辅助，不是诊疗建议。
/// 适应症、剂量、给药间隔一律以医生处方和药品说明书为准。
const List<Disease> diseases = [
  Disease(
    id: 'crohn',
    name: '克罗恩病',
    aliases: ['CD', 'Crohn', '克罗恩'],
    group: DiseaseGroup.ibd,
    summary: '炎症性肠病，可累及消化道任何部位，常需长期生物制剂维持缓解。',
  ),
  Disease(
    id: 'uc',
    name: '溃疡性结肠炎',
    aliases: ['UC', '溃结'],
    group: DiseaseGroup.ibd,
    summary: '炎症性肠病，主要累及结肠黏膜，生物制剂多用于中重度或激素依赖者。',
  ),
  Disease(
    id: 'psoriasis',
    name: '银屑病',
    aliases: ['牛皮癣', 'PsO', '斑块状银屑病'],
    group: DiseaseGroup.skin,
    summary: '慢性免疫介导的皮肤病，中重度患者常用 IL-17 / IL-23 抑制剂。',
  ),
  Disease(
    id: 'psa',
    name: '银屑病关节炎',
    aliases: ['PsA'],
    group: DiseaseGroup.joint,
    summary: '银屑病合并关节受累，用药需同时兼顾皮损与关节。',
  ),
  Disease(
    id: 'as',
    name: '强直性脊柱炎',
    aliases: ['AS', '中轴型脊柱关节炎', 'axSpA', '强直'],
    group: DiseaseGroup.joint,
    summary: '主要累及骶髂关节和脊柱的慢性炎症，TNF 抑制剂与 IL-17 抑制剂为常用选择。',
  ),
  Disease(
    id: 'ra',
    name: '类风湿关节炎',
    aliases: ['RA', '类风湿'],
    group: DiseaseGroup.joint,
    summary: '对称性多关节滑膜炎，生物制剂通常在甲氨蝶呤基础上联合使用。',
  ),
  Disease(
    id: 'ad',
    name: '特应性皮炎',
    aliases: ['AD', '湿疹', '特应性湿疹'],
    group: DiseaseGroup.skin,
    summary: '慢性瘙痒性皮肤病，中重度患者可用 IL-4Rα 靶向生物制剂。',
  ),
  Disease(
    id: 'csu',
    name: '慢性自发性荨麻疹',
    aliases: ['CSU', '慢性荨麻疹'],
    group: DiseaseGroup.skin,
    summary: '抗组胺药控制不佳的风团/血管性水肿，可用抗 IgE 治疗。',
  ),
  Disease(
    id: 'sle',
    name: '系统性红斑狼疮',
    aliases: ['SLE', '狼疮'],
    group: DiseaseGroup.other,
    summary: '多系统自身免疫病，生物制剂多用于常规治疗控制不佳的活动期患者。',
  ),
  Disease(
    id: 'hs',
    name: '化脓性汗腺炎',
    aliases: ['HS', '反向性痤疮'],
    group: DiseaseGroup.skin,
    summary: '顶泌汗腺区域的慢性复发性炎症，中重度患者可用 TNF 或 IL-17 抑制剂。',
  ),
  Disease(
    id: 'asthma_eos',
    name: '重度嗜酸性哮喘',
    aliases: ['哮喘', '嗜酸粒细胞性哮喘', 'eos asthma'],
    group: DiseaseGroup.other,
    summary: '规范吸入治疗仍反复发作的重度哮喘，可按表型选择靶向生物制剂。',
  ),
  Disease(
    id: 'uveitis',
    name: '非感染性葡萄膜炎',
    aliases: ['葡萄膜炎', 'uveitis'],
    group: DiseaseGroup.other,
    summary: '眼内炎症，反复发作或激素依赖者可用 TNF 抑制剂控制。',
  ),
];

class DiseaseGroupInfo {
  const DiseaseGroupInfo({required this.id, required this.name});
  final DiseaseGroup id;
  final String name;
}

const List<DiseaseGroupInfo> diseaseGroups = [
  DiseaseGroupInfo(id: DiseaseGroup.ibd, name: '炎症性肠病'),
  DiseaseGroupInfo(id: DiseaseGroup.skin, name: '皮肤疾病'),
  DiseaseGroupInfo(id: DiseaseGroup.joint, name: '关节与脊柱'),
  DiseaseGroupInfo(id: DiseaseGroup.other, name: '其他免疫介导疾病'),
];

const String diseaseDisclaimer =
    '药名与方案仅用于快速录入，不构成用药建议。适应症、剂量和间隔请以医生处方及药品说明书为准。';

Disease? findDisease(String? id) {
  if (id == null || id.isEmpty) return null;
  for (final item in diseases) {
    if (item.id == id) return item;
  }
  return null;
}

/// 读取用户选择的病种 id（兼容老版单个 `disease_id` 与新版 `disease_ids`）。
List<String> resolveDiseaseIds(Map<String, String> settings) {
  final raw = settings['disease_ids'];
  if (raw != null && raw.isNotEmpty) {
    try {
      final parsed = jsonDecode(raw);
      if (parsed is List) {
        final ids = <String>[];
        for (final item in parsed) {
          if (item is String &&
              item.isNotEmpty &&
              !ids.contains(item) &&
              findDisease(item) != null) {
            ids.add(item);
          }
        }
        if (ids.isNotEmpty) return ids;
      }
    } catch (_) {
      // 坏数据回退到旧的单病种字段
    }
  }
  final single = settings['disease_id'];
  return single != null && findDisease(single) != null ? [single] : const [];
}

List<Disease> findDiseases(List<String> ids) {
  final result = <Disease>[];
  for (final id in ids) {
    final found = findDisease(id);
    if (found != null) result.add(found);
  }
  return result;
}

String diseasesLabel(List<String> ids) {
  final names = findDiseases(ids).map((item) => item.name).toList();
  return names.isNotEmpty ? names.join('、') : '未选择病种';
}

List<Disease> diseasesByGroup(DiseaseGroup group) {
  return diseases.where((item) => item.group == group).toList();
}

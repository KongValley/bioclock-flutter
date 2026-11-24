import 'dart:math' as math;

import 'package:bioclock/models/types.dart';

class SiteHistoryEntry {
  const SiteHistoryEntry({required this.site, required this.injectedAt});

  final InjectionSite site;
  final int injectedAt;
}

const Map<InjectionSite, String> siteLabels = {
  InjectionSite.abdomenUl: '腹部左上',
  InjectionSite.abdomenUr: '腹部右上',
  InjectionSite.abdomenLl: '腹部左下',
  InjectionSite.abdomenLr: '腹部右下',
  InjectionSite.thighL: '左大腿',
  InjectionSite.thighR: '右大腿',
  InjectionSite.armL: '左上臂',
  InjectionSite.armR: '右上臂',
};

const List<InjectionSite> allSites = [
  InjectionSite.abdomenUl,
  InjectionSite.abdomenUr,
  InjectionSite.abdomenLl,
  InjectionSite.abdomenLr,
  InjectionSite.thighL,
  InjectionSite.thighR,
  InjectionSite.armL,
  InjectionSite.armR,
];

const Map<InjectionSite, String> _siteSide = {
  InjectionSite.abdomenUl: 'l',
  InjectionSite.abdomenUr: 'r',
  InjectionSite.abdomenLl: 'l',
  InjectionSite.abdomenLr: 'r',
  InjectionSite.thighL: 'l',
  InjectionSite.thighR: 'r',
  InjectionSite.armL: 'l',
  InjectionSite.armR: 'r',
};

const Set<InjectionSite> _abdomenSites = {
  InjectionSite.abdomenUl,
  InjectionSite.abdomenUr,
  InjectionSite.abdomenLl,
  InjectionSite.abdomenLr,
};

Map<InjectionSite, int> siteUsage(List<SiteHistoryEntry> injections) {
  final usage = {for (final site in allSites) site: 0};
  for (final injection in injections) {
    usage[injection.site] = (usage[injection.site] ?? 0) + 1;
  }
  return usage;
}

/// 推荐下一次注射位点：
/// 1. 排除最近 2 次用过的位点；
/// 2. 选历史使用次数最少的；
/// 3. 同分优先与最近一次不同侧；
/// 4. 仍同分时（默认）腹部优先。
InjectionSite recommendSite(
  List<SiteHistoryEntry> injections, {
  bool preferAbdomen = true,
}) {
  if (injections.isEmpty) return InjectionSite.abdomenUl;

  final sorted = [...injections]
    ..sort((a, b) => a.injectedAt.compareTo(b.injectedAt));
  final lastSide = _siteSide[sorted.last.site];

  final recentStart = math.max(0, sorted.length - 2);
  final recentSites = sorted.sublist(recentStart).map((e) => e.site).toSet();

  var candidates = allSites.where((s) => !recentSites.contains(s)).toList();
  if (candidates.isEmpty) candidates = List<InjectionSite>.from(allSites);

  final usage = siteUsage(injections);
  final minUsage = candidates.map((s) => usage[s] ?? 0).reduce(math.min);
  candidates = candidates.where((s) => (usage[s] ?? 0) == minUsage).toList();

  final oppositeSide =
      candidates.where((s) => _siteSide[s] != lastSide).toList();
  if (oppositeSide.isNotEmpty) candidates = oppositeSide;

  if (preferAbdomen) {
    final abdomen =
        candidates.where((s) => _abdomenSites.contains(s)).toList();
    if (abdomen.isNotEmpty) candidates = abdomen;
  }

  return candidates.isNotEmpty ? candidates.first : InjectionSite.abdomenUl;
}

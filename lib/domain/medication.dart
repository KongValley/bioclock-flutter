import 'package:bioclock/data/catalog.dart';
import 'package:bioclock/models/types.dart';

final RegExp _stripNoiseRe = RegExp(r'[\s（）()【】\[\]·・\-—_/]');

String normalizeMedicationName(String value) {
  return value.trim().toLowerCase().replaceAll(_stripNoiseRe, '');
}

List<String> medicationAliases(Medication medication) {
  final raw = <String>[medication.name];
  if (medication.genericName != null) raw.add(medication.genericName!);
  raw.addAll(medication.brandNames);

  if (medication.catalogKey != null) {
    final drug = drugsByKey[medication.catalogKey!];
    if (drug != null) {
      raw.add(drug.name);
      raw.add(drug.genericName);
      raw.addAll(drug.brandNames);
    }
  }

  final seen = <String>{};
  final result = <String>[];
  for (final item in raw) {
    final key = normalizeMedicationName(item);
    if (key.isEmpty || !seen.add(key)) continue;
    result.add(key);
  }
  return result;
}

Medication? findMedicationByName(List<Medication> medications, String name) {
  final key = normalizeMedicationName(name);
  if (key.isEmpty) return null;

  for (final m in medications) {
    if (normalizeMedicationName(m.name) == key) return m;
  }

  final matches = medications
      .where((m) => medicationAliases(m).contains(key))
      .toList();
  if (matches.isEmpty) return null;
  if (matches.length == 1) return matches.first;
  matches.sort((a, b) => (b.isBuiltin ? 1 : 0) - (a.isBuiltin ? 1 : 0));
  return matches.first;
}

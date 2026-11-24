import 'package:bioclock/models/types.dart';

/// 本地通知文案。
///
/// 只描述「到时间了、该做什么」，不出现诊断性表述、剂量调整或用药建议。
/// 文案中的 offsetDays 表示距注射日的天数：0 = 当天，1 = 前一天，2 = 前两天。

const String notifyPrepHint = '提前 30 分钟从冰箱取出，回温后再注射';

class ReminderContent {
  const ReminderContent({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;
}

ReminderContent buildReminderContent({
  required String medicationName,
  required double? dose,
  required String unit,
  required int offsetDays,
  bool isSameDayEvening = false,
  required MedicationRoute route,
}) {
  final name = medicationName.trim().isEmpty ? '本次用药' : medicationName.trim();
  final doseLabel = _formatDose(dose, unit);
  final daysAhead = offsetDays.abs();

  if (route == MedicationRoute.iv) {
    return _buildInfusionContent(name, doseLabel, daysAhead, isSameDayEvening);
  }
  return _buildInjectionContent(name, doseLabel, daysAhead, isSameDayEvening);
}

ReminderContent buildOralReminderContent(List<String> names) {
  final unique = names
      .map((name) => name.trim())
      .where((name) => name.isNotEmpty)
      .toList();
  if (unique.isEmpty) {
    return const ReminderContent(
      title: '今天该服药了',
      body: '按医嘱服用即可，完成后记得回来打卡。',
    );
  }
  if (unique.length == 1) {
    return ReminderContent(
      title: '今天该服用${unique[0]}',
      body: '按医嘱服用即可，完成后记得回来打卡。',
    );
  }
  return ReminderContent(
    title: '今天有 ${unique.length} 种口服药',
    body: '${unique.join('、')}。按医嘱服用，完成后记得回来打卡。',
  );
}

ReminderContent _buildInjectionContent(
  String medicationName,
  String doseLabel,
  int daysAhead,
  bool isSameDayEvening,
) {
  if (daysAhead >= 2) {
    return ReminderContent(
      title: '还有 $daysAhead 天该注射了',
      body: '${_withDose(medicationName, doseLabel)}，可以开始安排时间了。',
    );
  }
  if (daysAhead == 1) {
    return ReminderContent(
      title: '明天该注射了',
      body: '${_withDose(medicationName, doseLabel)}，别忘了提前把冷藏药取出来回温。',
    );
  }
  if (isSameDayEvening) {
    return ReminderContent(
      title: '今天还没登记注射',
      body: '如果今天已经完成 $medicationName 注射，记得回来登记一下。',
    );
  }
  return ReminderContent(
    title: '今天该注射了',
    body: '${_withDose(medicationName, doseLabel)}。$notifyPrepHint',
  );
}

ReminderContent _buildInfusionContent(
  String medicationName,
  String doseLabel,
  int daysAhead,
  bool isSameDayEvening,
) {
  if (daysAhead >= 2) {
    return ReminderContent(
      title: '还有 $daysAhead 天该去医院输注了',
      body: '${_withDose(medicationName, doseLabel)}，请提前安排好时间。',
    );
  }
  if (daysAhead == 1) {
    return ReminderContent(
      title: '明天该去医院输注了',
      body: '${_withDose(medicationName, doseLabel)}，请提前确认就诊安排。',
    );
  }
  if (isSameDayEvening) {
    return ReminderContent(
      title: '今天还没登记输注',
      body: '如果今天已经在医院完成 $medicationName 输注，记得回来登记一下。',
    );
  }
  return ReminderContent(
    title: '今天该去医院输注了',
    body: '${_withDose(medicationName, doseLabel)}，请按预约时间前往医院。',
  );
}

String _withDose(String medicationName, String doseLabel) {
  return doseLabel.isNotEmpty ? '$medicationName $doseLabel' : medicationName;
}

String _formatDose(double? dose, String unit) {
  if (dose == null || !dose.isFinite) return '';
  final numText =
      dose == dose.truncateToDouble() ? dose.toInt().toString() : dose.toString();
  return '$numText$unit'.trim();
}

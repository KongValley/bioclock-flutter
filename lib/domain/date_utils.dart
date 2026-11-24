/// 本地时间工具。
/// 数据库统一存 UTC 毫秒，这里只负责「按设备本地时区」格式化与简单加减。
library;

const int msPerDay = 86400000;

const List<String> _weekdays = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];

String pad2(int value) => value < 10 ? '0$value' : value.toString();

int startOfDay(int timestamp) {
  final d = DateTime.fromMillisecondsSinceEpoch(timestamp);
  return DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
}

/// 自然日差值（a - b），今天与昨天返回 1。
int calendarDayDiff(int a, int b) {
  return ((startOfDay(a) - startOfDay(b)) / msPerDay).round();
}

int addDays(int timestamp, int days) {
  final d = DateTime.fromMillisecondsSinceEpoch(timestamp);
  return DateTime(
    d.year,
    d.month,
    d.day + days,
    d.hour,
    d.minute,
    d.second,
    d.millisecond,
  ).millisecondsSinceEpoch;
}

int addMinutes(int timestamp, int minutes) => timestamp + minutes * 60000;

String formatTime(int timestamp) {
  final d = DateTime.fromMillisecondsSinceEpoch(timestamp);
  return '${pad2(d.hour)}:${pad2(d.minute)}';
}

String formatDate(int timestamp, [int? now]) {
  final refNow = now ?? DateTime.now().millisecondsSinceEpoch;
  final d = DateTime.fromMillisecondsSinceEpoch(timestamp);
  final sameYear = d.year == DateTime.fromMillisecondsSinceEpoch(refNow).year;
  final base = '${d.month}月${d.day}日';
  return sameYear ? base : '${d.year}年$base';
}

String formatMonth(int timestamp) {
  final d = DateTime.fromMillisecondsSinceEpoch(timestamp);
  return '${d.year}年${d.month}月';
}

String monthKey(int timestamp) {
  final d = DateTime.fromMillisecondsSinceEpoch(timestamp);
  return '${d.year}-${pad2(d.month)}';
}

String formatWeekday(int timestamp) {
  final d = DateTime.fromMillisecondsSinceEpoch(timestamp);
  return _weekdays[d.weekday % 7];
}

String formatDateTime(int timestamp, [int? now]) {
  return '${formatDate(timestamp, now)} ${formatTime(timestamp)}';
}

String formatDateTimeFull(int timestamp) {
  final d = DateTime.fromMillisecondsSinceEpoch(timestamp);
  return '${d.year}年${d.month}月${d.day}日 ${_weekdays[d.weekday % 7]} ${pad2(d.hour)}:${pad2(d.minute)}';
}

String formatLocalDate(int timestamp) {
  final d = DateTime.fromMillisecondsSinceEpoch(timestamp);
  return '${d.year}-${pad2(d.month)}-${pad2(d.day)}';
}

String formatLocalDateTime(int timestamp) {
  return '${formatLocalDate(timestamp)} ${formatTime(timestamp)}';
}

/// 今天 / 昨天 / 明天 / 后天 / 前天，其余返回 M月D日。
String formatRelativeDay(int timestamp, [int? now]) {
  final refNow = now ?? DateTime.now().millisecondsSinceEpoch;
  final diff = calendarDayDiff(timestamp, refNow);
  if (diff == 0) return '今天';
  if (diff == 1) return '明天';
  if (diff == 2) return '后天';
  if (diff == -1) return '昨天';
  if (diff == -2) return '前天';
  return formatDate(timestamp, refNow);
}

String formatDuration(double days) {
  if (!days.isFinite) return '长期';
  if (days < 1) return '不足 1 天';
  final rounded = (days * 10).round() / 10;
  return '$rounded 天';
}

/// 供「手动输入」使用的固定格式：`YYYY-MM-DD HH:mm`。
String formatManualInput(int timestamp) => formatLocalDateTime(timestamp);

final RegExp _manualRe = RegExp(
  r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?:\s+(\d{1,2}):(\d{1,2}))?$',
);

/// 解析手动输入；非法返回 null。
int? parseManualDateTime(String text) {
  final match = _manualRe.firstMatch(text.trim());
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final hour = match.group(4) != null ? int.parse(match.group(4)!) : 9;
  final minute = match.group(5) != null ? int.parse(match.group(5)!) : 0;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  if (hour > 23 || minute > 59) return null;
  final d = DateTime(year, month, day, hour, minute);
  if (d.year != year ||
      d.month != month ||
      d.day != day ||
      d.hour != hour ||
      d.minute != minute) {
    return null;
  }
  return d.millisecondsSinceEpoch;
}

final RegExp _timeRe = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$');

({int hour, int minute})? parseTimeOfDay(String value) {
  final match = _timeRe.firstMatch(value.trim());
  if (match == null) return null;
  return (hour: int.parse(match.group(1)!), minute: int.parse(match.group(2)!));
}

String toTimeOfDay(int hour, int minute) {
  final normalizedHour = ((hour % 24) + 24) % 24;
  final normalizedMinute = ((minute % 60) + 60) % 60;
  return '${pad2(normalizedHour)}:${pad2(normalizedMinute)}';
}

String bumpTimeOfDay(String value, int deltaMinutes) {
  final parsed = parseTimeOfDay(value) ?? (hour: 9, minute: 0);
  return toTimeOfDay(parsed.hour, parsed.minute + deltaMinutes);
}

String formatSignedDays(double days) {
  if (days.abs() < 0.05) return '0 天';
  final rounded = (days.abs() * 10).round() / 10;
  final formatted =
      rounded == rounded.truncateToDouble() ? rounded.toInt().toString() : rounded.toString();
  return days > 0 ? '+$formatted 天' : '-$formatted 天';
}

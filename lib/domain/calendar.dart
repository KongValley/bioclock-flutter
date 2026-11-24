import 'package:bioclock/domain/schedule.dart';

class MonthCursor {
  const MonthCursor({required this.year, required this.month});

  final int year;

  /// 0 = 一月 … 11 = 十二月（对齐原模型与单测习惯）。
  final int month;

  @override
  bool operator ==(Object other) =>
      other is MonthCursor && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);
}

int dayStart(int timestamp) {
  final d = DateTime.fromMillisecondsSinceEpoch(timestamp);
  return DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
}

MonthCursor shiftMonth(MonthCursor cursor, int delta) {
  final d = DateTime(cursor.year, cursor.month + 1 + delta, 1);
  return MonthCursor(year: d.year, month: d.month - 1);
}

MonthCursor monthOf(int timestamp) {
  final d = DateTime.fromMillisecondsSinceEpoch(timestamp);
  return MonthCursor(year: d.year, month: d.month - 1);
}

bool isSameMonth(MonthCursor cursor, int timestamp) {
  final d = DateTime.fromMillisecondsSinceEpoch(timestamp);
  return d.year == cursor.year && (d.month - 1) == cursor.month;
}

/// 生成 6×7 月视图（周一起始），返回每格对应自然日的本地 0 点时间戳。
List<int> buildMonthCells(MonthCursor cursor) {
  final first = DateTime(cursor.year, cursor.month + 1, 1);
  final mondayOffset = ((first.weekday % 7) + 6) % 7;
  final start = DateTime(cursor.year, cursor.month + 1, 1 - mondayOffset);
  return [
    for (var index = 0; index < 42; index += 1)
      DateTime(start.year, start.month, start.day + index)
          .millisecondsSinceEpoch,
  ];
}

String monthTitle(MonthCursor cursor) => '${cursor.year}年${cursor.month + 1}月';

Map<int, List<SchedulePlan>> groupPlansByDay(List<SchedulePlan> plans) {
  final grouped = <int, List<SchedulePlan>>{};
  for (final plan in plans) {
    final key = dayStart(plan.plannedAt);
    (grouped[key] ??= []).add(plan);
  }
  for (final bucket in grouped.values) {
    bucket.sort((a, b) => a.plannedAt.compareTo(b.plannedAt));
  }
  return grouped;
}

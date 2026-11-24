import 'dart:async';
import 'dart:math' as math;

import 'package:bioclock/domain/adherence.dart';
import 'package:bioclock/domain/date_utils.dart';
import 'package:bioclock/i18n/zh.dart';
import 'package:bioclock/models/types.dart';
import 'package:bioclock/screens/modals/injection_modal.dart';
import 'package:bioclock/screens/modals/oral_modal.dart';
import 'package:bioclock/store/app_store.dart';
import 'package:bioclock/ui/components/app_icon.dart';
import 'package:bioclock/ui/components/app_layout.dart';
import 'package:bioclock/ui/components/app_primitives.dart';
import 'package:bioclock/ui/components/app_scope.dart';
import 'package:bioclock/ui/theme.dart';
import 'package:flutter/material.dart';

int _logTime(DoseLog log) => log.takenAt ?? log.scheduledAt ?? log.createdAt;

Color _severityColor(AppThemeData theme, int severity) {
  if (severity <= 1) return theme.colors.success;
  if (severity == 2) return theme.colors.primary;
  if (severity == 3) return theme.colors.warning;
  return theme.colors.danger;
}

class TrendsTab extends StatefulWidget {
  const TrendsTab({
    super.key,
    required this.onOpenOnboarding,
  });

  final VoidCallback onOpenOnboarding;

  @override
  State<TrendsTab> createState() => _TrendsTabState();
}

class _TrendsTabState extends State<TrendsTab> {
  int _now = DateTime.now().millisecondsSinceEpoch;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) setState(() => _now = DateTime.now().millisecondsSinceEpoch);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      await context.store.reload();
    } catch (err) {
      if (mounted) showToast(friendlyErrorMessage(err), isError: true);
    }
  }

  Widget _statTile(
    AppThemeData theme,
    String label,
    String value, {
    Color? color,
  }) {
    return SizedBox(
      width: 96,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: theme.colors.textTertiary,
              fontSize: theme.fontSize.xs,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: color ?? theme.colors.text,
              fontSize: theme.fontSize.xl,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final store = context.store;
    if (!store.ready) return const LoadingView();

    final treatment = store.treatment;
    final lines = treatment?.lines ?? const <TreatmentLine>[];
    final medById = {for (final m in store.medications) m.id: m};

    AdherenceStats? stats;
    if (treatment != null) {
      try {
        stats = computeAdherence(treatment.lines, store.doseLogs, _now);
      } catch (_) {
        stats = null;
      }
    }

    final kindByLine = {for (final l in lines) l.id: l.kind};
    final injectionMarks = [
      for (final log in store.doseLogs)
        if (kindByLine[log.lineId] == LineKind.injection) _logTime(log),
    ]..sort();

    final allTimes = [
      ...injectionMarks,
      for (final s in store.symptoms) s.loggedAt,
    ];
    final int? start = allTimes.isEmpty ? null : allTimes.reduce(math.min);
    final int? end = allTimes.isEmpty
        ? null
        : math.max(allTimes.reduce(math.max), start! + msPerDay);

    var maxWindowDays = 0;
    for (final line in lines) {
      if (line.kind == LineKind.injection) {
        maxWindowDays = math.max(maxWindowDays, line.windowDays);
      }
    }

    final hasData = store.doseLogs.isNotEmpty || store.symptoms.isNotEmpty;
    final isEmpty =
        treatment == null || lines.isEmpty || stats == null || !hasData;

    final String emptyActionLabel;
    final VoidCallback emptyActionTap;
    if (treatment == null) {
      emptyActionLabel = '去设置方案';
      emptyActionTap = widget.onOpenOnboarding;
    } else if (lines.any((l) => l.kind == LineKind.injection)) {
      emptyActionLabel = '去登记注射';
      emptyActionTap = () => showInjectionModal(context);
    } else {
      emptyActionLabel = '去登记口服';
      emptyActionTap = () => showOralModal(context);
    }

    return Scaffold(
      backgroundColor: theme.colors.background,
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(title: Zh.trends.title, subtitle: '回看节律，不评判对错'),
            Expanded(
              child: RefreshIndicator(
                color: theme.colors.primary,
                onRefresh: _refresh,
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    ResponsiveContainer(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          theme.spacing.lg,
                          0,
                          theme.spacing.lg,
                          32,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (isEmpty)
                              AppCard(
                                child: StateView(
                                  icon: AppIconName.activity,
                                  title: Zh.empty.trendsNoData,
                                  message: '按时、提前、延迟只用于自我回顾；偏差在方案窗口内都算按时。',
                                  actionLabel: emptyActionLabel,
                                  onAction: emptyActionTap,
                                ),
                              )
                            else ...[
                              SectionTitle(
                                title: Zh.trends.adherence,
                                hint:
                                    '按时窗口 ±$maxWindowDays 天 · 共 ${stats.total} 次记录',
                              ),
                              const SizedBox(height: 10),
                              AppCard(
                                child: Wrap(
                                  spacing: theme.spacing.md,
                                  runSpacing: theme.spacing.md,
                                  children: [
                                    _statTile(
                                      theme,
                                      Zh.trends.onTime,
                                      '${stats.onTime}',
                                      color: theme.colors.success,
                                    ),
                                    _statTile(
                                      theme,
                                      Zh.trends.early,
                                      '${stats.early}',
                                      color: theme.colors.primary,
                                    ),
                                    _statTile(
                                      theme,
                                      Zh.trends.late,
                                      '${stats.late}',
                                      color: theme.colors.warning,
                                    ),
                                    _statTile(
                                      theme,
                                      Zh.trends.avgDeviation,
                                      '${stats.avgDeviationDays.toStringAsFixed(1)} 天',
                                    ),
                                    _statTile(
                                      theme,
                                      '完成率',
                                      '${(stats.rate * 100).round()}%',
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                              const SectionTitle(
                                title: '各用药线',
                                hint: '按用药线分别统计',
                              ),
                              const SizedBox(height: 10),
                              for (final lineStat in stats.byLine) ...[
                                _buildLineStatsCard(
                                  theme,
                                  lineStat,
                                  lines,
                                  medById,
                                ),
                                const SizedBox(height: 10),
                              ],
                              const SizedBox(height: 6),
                              SectionTitle(
                                title: Zh.trends.symptomTimeline,
                                hint: '竖线为注射，圆点为症状严重度',
                              ),
                              const SizedBox(height: 10),
                              AppCard(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (start == null || end == null)
                                      const StateView(
                                        icon: AppIconName.smile,
                                        title: '还没有可对齐的数据',
                                        message: '登记注射或症状后，这里会按时间展示症状严重度。',
                                        compact: true,
                                      )
                                    else ...[
                                      Semantics(
                                        label: '症状与注射时间对齐图',
                                        child: SizedBox(
                                          height: 190,
                                          child: CustomPaint(
                                            size: const Size(
                                              double.infinity,
                                              190,
                                            ),
                                            painter: _SymptomChartPainter(
                                              theme: theme,
                                              start: start,
                                              end: end,
                                              injectionMarks: injectionMarks,
                                              symptoms: store.symptoms,
                                              startLabel: formatDate(start),
                                              endLabel: formatDate(end),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Wrap(
                                        spacing: 10,
                                        runSpacing: 6,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Container(
                                                width: 2,
                                                height: 12,
                                                color: theme.colors.primary,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                '注射',
                                                style: TextStyle(
                                                  color: theme
                                                      .colors.textSecondary,
                                                  fontSize: theme.fontSize.xs,
                                                ),
                                              ),
                                            ],
                                          ),
                                          for (var s = 1; s <= 5; s += 1)
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Container(
                                                  width: 8,
                                                  height: 8,
                                                  decoration: BoxDecoration(
                                                    color: _severityColor(
                                                      theme,
                                                      s,
                                                    ),
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  '$s',
                                                  style: TextStyle(
                                                    color: theme
                                                        .colors.textTertiary,
                                                    fontSize: theme.fontSize.xs,
                                                  ),
                                                ),
                                              ],
                                            ),
                                        ],
                                      ),
                                    ],
                                    const SizedBox(height: 10),
                                    Text(
                                      Zh.trends.correlationNote,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: theme.colors.textTertiary,
                                        fontSize: theme.fontSize.xs,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLineStatsCard(
    AppThemeData theme,
    LineAdherence lineStat,
    List<TreatmentLine> lines,
    Map<String, Medication> medById,
  ) {
    final line = lines.cast<TreatmentLine?>().firstWhere(
          (l) => l?.id == lineStat.lineId,
          orElse: () => null,
        );
    if (line == null) return const SizedBox.shrink();
    final med = medById[line.medicationId];
    final name = med?.name ?? line.label;
    final kindLabel = lineStat.kind == LineKind.injection
        ? (line.isHost ? '注射 · 主药' : '注射')
        : '口服';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            name,
            style: TextStyle(
              color: theme.colors.text,
              fontSize: theme.fontSize.md,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            kindLabel,
            style: TextStyle(
              color: theme.colors.textTertiary,
              fontSize: theme.fontSize.xs,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: theme.spacing.md,
            runSpacing: theme.spacing.md,
            children: switch (lineStat) {
              InjectionLineAdherence() => [
                  _statTile(
                    theme,
                    Zh.trends.onTime,
                    '${lineStat.onTime}',
                    color: theme.colors.success,
                  ),
                  _statTile(
                    theme,
                    Zh.trends.early,
                    '${lineStat.early}',
                    color: theme.colors.primary,
                  ),
                  _statTile(
                    theme,
                    Zh.trends.late,
                    '${lineStat.late}',
                    color: theme.colors.warning,
                  ),
                  _statTile(
                    theme,
                    Zh.trends.avgDeviation,
                    '${lineStat.avgDeviationDays.toStringAsFixed(1)} 天',
                  ),
                  _statTile(
                    theme,
                    '漏打',
                    '${lineStat.missed}',
                    color: theme.colors.danger,
                  ),
                ],
              OralLineAdherence() => [
                  _statTile(
                    theme,
                    '完成',
                    '${lineStat.total}',
                    color: theme.colors.success,
                  ),
                  _statTile(
                    theme,
                    '漏服',
                    '${lineStat.missed}',
                    color: theme.colors.danger,
                  ),
                  _statTile(
                    theme,
                    '完成率',
                    '${(lineStat.rate * 100).round()}%',
                  ),
                ],
            },
          ),
        ],
      ),
    );
  }
}

class _SymptomChartPainter extends CustomPainter {
  const _SymptomChartPainter({
    required this.theme,
    required this.start,
    required this.end,
    required this.injectionMarks,
    required this.symptoms,
    required this.startLabel,
    required this.endLabel,
  });

  final AppThemeData theme;
  final int start;
  final int end;
  final List<int> injectionMarks;
  final List<SymptomLog> symptoms;
  final String startLabel;
  final String endLabel;

  @override
  void paint(Canvas canvas, Size size) {
    const plotTop = 18.0;
    final plotBottom = size.height - 34.0;
    final plotHeight = plotBottom - plotTop;
    const paddingX = 10.0;
    final span = math.max(1, end - start);

    double xOf(int ts) =>
        paddingX + ((ts - start) / span) * (size.width - paddingX * 2);
    double yOf(int severity) =>
        plotBottom - ((severity - 1) / 4.0) * plotHeight;

    final gridPaint = Paint()
      ..color = theme.colors.border
      ..strokeWidth = 0.7;
    for (var s = 1; s <= 5; s += 1) {
      final y = yOf(s);
      canvas.drawLine(
        Offset(paddingX, y),
        Offset(size.width - paddingX, y),
        gridPaint,
      );
    }

    final injPaint = Paint()
      ..color = theme.colors.primary.withValues(alpha: 0.65)
      ..strokeWidth = 1.5;
    for (final mark in injectionMarks) {
      final x = xOf(mark);
      canvas.drawLine(Offset(x, plotTop), Offset(x, plotBottom), injPaint);
    }

    final borderPaint = Paint()
      ..color = theme.colors.surface
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final s in symptoms) {
      final pt = Offset(xOf(s.loggedAt), yOf(s.severity));
      canvas.drawCircle(
        pt,
        5.0,
        Paint()..color = _severityColor(theme, s.severity),
      );
      canvas.drawCircle(pt, 5.0, borderPaint);
    }

    final labelStyle = TextStyle(
      color: theme.colors.textTertiary,
      fontSize: 9,
      fontFamily: appFontFamily,
      fontFamilyFallback: appFontFamilyFallback,
    );
    final startTp = TextPainter(
      text: TextSpan(text: startLabel, style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    startTp.paint(canvas, Offset(paddingX, size.height - 18));

    final endTp = TextPainter(
      text: TextSpan(text: endLabel, style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    endTp.paint(
      canvas,
      Offset(size.width - paddingX - endTp.width, size.height - 18),
    );
  }

  @override
  bool shouldRepaint(covariant _SymptomChartPainter oldDelegate) =>
      oldDelegate.theme != theme ||
      oldDelegate.start != start ||
      oldDelegate.end != end ||
      oldDelegate.injectionMarks != injectionMarks ||
      oldDelegate.symptoms != symptoms;
}

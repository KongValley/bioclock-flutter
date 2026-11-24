import 'dart:math' as math;

import 'package:bioclock/models/types.dart';
import 'package:bioclock/ui/theme.dart';
import 'package:flutter/material.dart';

const Map<InjectionSite, Offset> _sitePoints = {
  InjectionSite.abdomenUl: Offset(87, 107),
  InjectionSite.abdomenUr: Offset(113, 107),
  InjectionSite.abdomenLl: Offset(87, 137),
  InjectionSite.abdomenLr: Offset(113, 137),
  InjectionSite.thighL: Offset(91, 176),
  InjectionSite.thighR: Offset(109, 176),
  InjectionSite.armL: Offset(54, 116),
  InjectionSite.armR: Offset(146, 116),
};

const Offset _navel = Offset(100, 122);
const double _calloutWidth = 34;
const double _calloutHeight = 14;

/// 极简人体示意图：用矢量轮廓高亮推荐 / 已选注射部位（坐标系 200 × 248）。
class BodyMap extends StatelessWidget {
  const BodyMap({
    super.key,
    this.selected,
    this.recommended,
    this.height = 220,
  });

  final InjectionSite? selected;
  final InjectionSite? recommended;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Semantics(
      label: recommended != null ? '推荐注射部位示意' : '人体注射部位示意图',
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: Center(
          child: AspectRatio(
            aspectRatio: 200 / 248,
            child: CustomPaint(
              painter: _BodyMapPainter(
                theme: theme,
                selected: selected,
                recommended: recommended,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BodyMapPainter extends CustomPainter {
  const _BodyMapPainter({
    required this.theme,
    required this.selected,
    required this.recommended,
  });

  final AppThemeData theme;
  final InjectionSite? selected;
  final InjectionSite? recommended;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    final scale = math.min(size.width / 200.0, size.height / 248.0);
    final dx = (size.width - 200.0 * scale) / 2;
    final dy = (size.height - 248.0 * scale) / 2;
    canvas.translate(dx, dy);
    canvas.scale(scale, scale);

    final outline = theme.colors.border;
    final fill = theme.colors.surface;
    final highlight = selected ?? recommended;
    final isAbdomen = highlight?.wire.startsWith('abdomen') ?? false;

    // 地面阴影
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(100, 234), width: 88, height: 9),
      Paint()..color = outline.withValues(alpha: 0.35),
    );

    // 身体轮廓（头、颈、躯干、双臂、大腿、小腿与脚）
    final bodyPath = _buildBodyPath();
    canvas.drawPath(
      bodyPath,
      Paint()
        ..color = fill
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      bodyPath,
      Paint()
        ..color = outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    // 腹部建议区虚线椭圆 + 肚脐
    final abdomenOval = Rect.fromCenter(
      center: _navel,
      width: 66,
      height: 58,
    );
    _drawDashedOval(
      canvas,
      abdomenOval,
      Paint()
        ..color = theme.colors.primary.withValues(alpha: isAbdomen ? 0.55 : 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
    canvas.drawCircle(
      _navel,
      2.0,
      Paint()..color = theme.colors.textTertiary.withValues(alpha: 0.5),
    );

    // 膝线
    final kneePaint = Paint()
      ..color = outline
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(68, 198), const Offset(94, 198), kneePaint);
    canvas.drawLine(const Offset(106, 198), const Offset(132, 198), kneePaint);

    // 8 个注射点
    for (final entry in _sitePoints.entries) {
      final site = entry.key;
      final point = entry.value;
      final isSelected = selected == site;
      final isRecommended = recommended == site;
      if (!isSelected && !isRecommended) {
        canvas.drawCircle(
          point,
          2.6,
          Paint()..color = theme.colors.textTertiary.withValues(alpha: 0.35),
        );
      } else {
        canvas.drawCircle(
          point,
          isSelected ? 6.5 : 5.0,
          Paint()
            ..color =
                isSelected ? theme.colors.primary : theme.colors.primaryMuted,
        );
        canvas.drawCircle(
          point,
          isSelected ? 6.5 : 5.0,
          Paint()
            ..color = theme.colors.primary
            ..style = PaintingStyle.stroke
            ..strokeWidth = isSelected ? 2.0 : 1.5,
        );
      }
    }

    // 推荐/选中 Callout 气泡
    if (highlight != null) {
      final point = _sitePoints[highlight]!;
      final offsetX = highlight.wire.endsWith('_r')
          ? -22.0
          : highlight.wire.endsWith('_l')
              ? 22.0
              : 0.0;
      final x = math.min(
        196.0 - _calloutWidth,
        math.max(4.0, point.dx + offsetX - _calloutWidth / 2),
      );
      final y = point.dy - 36.0;
      final anchorX = point.dx + offsetX;

      canvas.drawLine(
        Offset(point.dx, point.dy - 7),
        Offset(anchorX, y + _calloutHeight),
        Paint()
          ..color = theme.colors.primary.withValues(alpha: 0.5)
          ..strokeWidth = 1.0,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, _calloutWidth, _calloutHeight),
          const Radius.circular(_calloutHeight / 2),
        ),
        Paint()..color = theme.colors.primary,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: '推荐',
          style: TextStyle(
            color: theme.colors.onPrimary,
            fontSize: 9,
            fontWeight: FontWeight.w600,
            fontFamily: appFontFamily,
            fontFamilyFallback: appFontFamilyFallback,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          x + (_calloutWidth - tp.width) / 2,
          y + (_calloutHeight - tp.height) / 2,
        ),
      );
    }

    canvas.restore();
  }

  Path _buildBodyPath() {
    final p = Path();
    // 头
    p.addOval(Rect.fromCircle(center: const Offset(100, 32), radius: 18));
    // 颈
    p.addRect(const Rect.fromLTWH(93, 52, 14, 10));
    // 躯干
    p.moveTo(84, 62);
    p.cubicTo(74, 62, 68, 67, 67, 77);
    p.lineTo(63, 112);
    p.cubicTo(62, 132, 64, 146, 68, 158);
    p.lineTo(132, 158);
    p.cubicTo(136, 146, 138, 132, 137, 112);
    p.lineTo(133, 77);
    p.cubicTo(132, 67, 126, 62, 116, 62);
    p.close();
    // 右臂（画面左侧）
    p.moveTo(68, 76);
    p.cubicTo(62, 84, 59, 96, 58, 110);
    p.lineTo(55, 140);
    p.cubicTo(54, 148, 58, 152, 63, 152);
    p.lineTo(68, 152);
    p.cubicTo(72, 152, 74, 148, 73, 142);
    p.lineTo(74, 112);
    p.lineTo(76, 78);
    p.close();
    // 左臂（画面右侧）
    p.moveTo(132, 76);
    p.cubicTo(138, 84, 141, 96, 142, 110);
    p.lineTo(145, 140);
    p.cubicTo(146, 148, 142, 152, 137, 152);
    p.lineTo(132, 152);
    p.cubicTo(128, 152, 126, 148, 127, 142);
    p.lineTo(126, 112);
    p.lineTo(124, 78);
    p.close();
    // 右大腿 + 小腿
    p.moveTo(70, 158);
    p.lineTo(96, 158);
    p.cubicTo(95, 172, 95, 186, 95, 196);
    p.lineTo(66, 196);
    p.cubicTo(67, 186, 68, 172, 70, 158);
    p.close();
    p.moveTo(67, 200);
    p.cubicTo(80, 198, 94, 198, 95, 200);
    p.lineTo(95, 224);
    p.cubicTo(95, 228, 92, 230, 88, 230);
    p.lineTo(72, 230);
    p.cubicTo(68, 230, 66, 228, 66, 224);
    p.close();
    // 左大腿 + 小腿
    p.moveTo(104, 158);
    p.lineTo(130, 158);
    p.cubicTo(132, 172, 133, 186, 134, 196);
    p.lineTo(105, 196);
    p.cubicTo(105, 186, 105, 172, 104, 158);
    p.close();
    p.moveTo(105, 200);
    p.cubicTo(106, 198, 120, 198, 133, 200);
    p.lineTo(134, 224);
    p.cubicTo(134, 228, 132, 230, 128, 230);
    p.lineTo(112, 230);
    p.cubicTo(108, 230, 105, 228, 105, 224);
    p.close();
    return p;
  }

  void _drawDashedOval(Canvas canvas, Rect rect, Paint paint) {
    final full = Path()..addOval(rect);
    for (final metric in full.computeMetrics()) {
      var distance = 0.0;
      const dashLen = 4.0;
      const gapLen = 3.0;
      while (distance < metric.length) {
        final next = math.min(metric.length, distance + dashLen);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gapLen;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BodyMapPainter oldDelegate) =>
      oldDelegate.theme != theme ||
      oldDelegate.selected != selected ||
      oldDelegate.recommended != recommended;
}

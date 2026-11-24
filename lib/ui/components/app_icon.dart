import 'package:bioclock/ui/theme.dart';
import 'package:flutter/material.dart';

/// 应用内图标：统一 24×24 网格、2px 描边（Lucide 几何），不依赖字体与 emoji。
enum AppIconName {
  check,
  chevronRight,
  chevronLeft,
  close,
  plus,
  minus,
  pencil,
  unlock,
  lock,
  more,
  calendar,
  syringe,
  smile,
  activity,
  home,
  list,
  settings,
  alert,
  info,
  inbox,
  trash,
}

class AppIcon extends StatelessWidget {
  const AppIcon(
    this.name, {
    super.key,
    this.size = 24,
    this.color,
    this.strokeWidth = 2.0,
    this.semanticLabel,
  });

  final AppIconName name;
  final double size;
  final Color? color;
  final double strokeWidth;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? context.appTheme.colors.text;
    final paintWidget = CustomPaint(
      size: Size.square(size),
      painter: _AppIconPainter(
        name: name,
        color: tint,
        strokeWidth: strokeWidth,
      ),
    );

    if (semanticLabel == null) {
      return ExcludeSemantics(child: paintWidget);
    }
    return Semantics(
      label: semanticLabel,
      child: paintWidget,
    );
  }
}

class _AppIconPainter extends CustomPainter {
  const _AppIconPainter({
    required this.name,
    required this.color,
    required this.strokeWidth,
  });

  final AppIconName name;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24.0, size.height / 24.0);

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    switch (name) {
      case AppIconName.check:
        final path = Path()
          ..moveTo(20, 6)
          ..lineTo(9, 17)
          ..lineTo(4, 12);
        canvas.drawPath(path, strokePaint);
      case AppIconName.chevronRight:
        final path = Path()
          ..moveTo(9, 18)
          ..lineTo(15, 12)
          ..lineTo(9, 6);
        canvas.drawPath(path, strokePaint);
      case AppIconName.chevronLeft:
        final path = Path()
          ..moveTo(15, 18)
          ..lineTo(9, 12)
          ..lineTo(15, 6);
        canvas.drawPath(path, strokePaint);
      case AppIconName.close:
        canvas.drawLine(const Offset(18, 6), const Offset(6, 18), strokePaint);
        canvas.drawLine(const Offset(6, 6), const Offset(18, 18), strokePaint);
      case AppIconName.plus:
        canvas.drawLine(const Offset(5, 12), const Offset(19, 12), strokePaint);
        canvas.drawLine(const Offset(12, 5), const Offset(12, 19), strokePaint);
      case AppIconName.minus:
        canvas.drawLine(const Offset(5, 12), const Offset(19, 12), strokePaint);
      case AppIconName.pencil:
        final path = Path()
          ..moveTo(18.5, 3.5)
          ..lineTo(20.5, 5.5)
          ..lineTo(7.5, 18.5)
          ..lineTo(3, 21)
          ..lineTo(5.5, 16.5)
          ..close();
        canvas.drawPath(path, strokePaint);
        canvas.drawLine(const Offset(15, 7), const Offset(17, 9), strokePaint);
      case AppIconName.unlock:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(3, 11, 18, 11),
            const Radius.circular(2),
          ),
          strokePaint,
        );
        final shackle = Path()
          ..moveTo(7, 11)
          ..lineTo(7, 7)
          ..arcToPoint(
            const Offset(16.9, 6),
            radius: const Radius.circular(5),
          );
        canvas.drawPath(shackle, strokePaint);
      case AppIconName.lock:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(3, 11, 18, 11),
            const Radius.circular(2),
          ),
          strokePaint,
        );
        final shackle = Path()
          ..moveTo(7, 11)
          ..lineTo(7, 7)
          ..arcToPoint(
            const Offset(17, 7),
            radius: const Radius.circular(5),
          )
          ..lineTo(17, 11);
        canvas.drawPath(shackle, strokePaint);
      case AppIconName.more:
        canvas.drawCircle(const Offset(5, 12), 1.4, fillPaint);
        canvas.drawCircle(const Offset(12, 12), 1.4, fillPaint);
        canvas.drawCircle(const Offset(19, 12), 1.4, fillPaint);
      case AppIconName.calendar:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(3, 4, 18, 18),
            const Radius.circular(2),
          ),
          strokePaint,
        );
        canvas.drawLine(const Offset(8, 2), const Offset(8, 6), strokePaint);
        canvas.drawLine(const Offset(16, 2), const Offset(16, 6), strokePaint);
        canvas.drawLine(const Offset(3, 10), const Offset(21, 10), strokePaint);
      case AppIconName.syringe:
        canvas.drawLine(const Offset(18, 2), const Offset(22, 6), strokePaint);
        canvas.drawLine(const Offset(17, 7), const Offset(20, 4), strokePaint);
        final body = Path()
          ..moveTo(19, 9)
          ..lineTo(8.7, 19.3)
          ..arcToPoint(
            const Offset(5.3, 19.3),
            radius: const Radius.circular(2.4),
          )
          ..lineTo(4.7, 18.7)
          ..arcToPoint(
            const Offset(4.7, 15.3),
            radius: const Radius.circular(2.4),
          )
          ..lineTo(15, 5);
        canvas.drawPath(body, strokePaint);
        canvas.drawLine(const Offset(9, 11), const Offset(13, 15), strokePaint);
        canvas.drawLine(const Offset(5, 19), const Offset(2, 22), strokePaint);
        canvas.drawLine(const Offset(14, 4), const Offset(20, 10), strokePaint);
      case AppIconName.smile:
        canvas.drawCircle(const Offset(12, 12), 10, strokePaint);
        final mouth = Path()
          ..moveTo(8, 14)
          ..quadraticBezierTo(12, 17.5, 16, 14);
        canvas.drawPath(mouth, strokePaint);
        canvas.drawLine(const Offset(9, 9), const Offset(9.01, 9), strokePaint);
        canvas.drawLine(
          const Offset(15, 9),
          const Offset(15.01, 9),
          strokePaint,
        );
      case AppIconName.activity:
        final wave = Path()
          ..moveTo(22, 12)
          ..lineTo(18, 12)
          ..lineTo(15, 21)
          ..lineTo(9, 3)
          ..lineTo(6, 12)
          ..lineTo(2, 12);
        canvas.drawPath(wave, strokePaint);
      case AppIconName.home:
        final house = Path()
          ..moveTo(3, 10)
          ..lineTo(12, 3)
          ..lineTo(21, 10)
          ..lineTo(21, 19)
          ..arcToPoint(const Offset(19, 21), radius: const Radius.circular(2))
          ..lineTo(5, 21)
          ..arcToPoint(const Offset(3, 19), radius: const Radius.circular(2))
          ..close();
        canvas.drawPath(house, strokePaint);
        final door = Path()
          ..moveTo(9, 21)
          ..lineTo(9, 13)
          ..lineTo(15, 13)
          ..lineTo(15, 21);
        canvas.drawPath(door, strokePaint);
      case AppIconName.list:
        for (final y in [5.0, 12.0, 19.0]) {
          canvas.drawCircle(Offset(3.5, y), 1.1, fillPaint);
          canvas.drawLine(Offset(8, y), Offset(21, y), strokePaint);
        }
      case AppIconName.settings:
        canvas.drawLine(const Offset(20, 7), const Offset(10, 7), strokePaint);
        canvas.drawLine(const Offset(14, 17), const Offset(5, 17), strokePaint);
        canvas.drawCircle(const Offset(17, 17), 3, strokePaint);
        canvas.drawCircle(const Offset(7, 7), 3, strokePaint);
      case AppIconName.alert:
        canvas.drawCircle(const Offset(12, 12), 10, strokePaint);
        canvas.drawLine(const Offset(12, 8), const Offset(12, 12), strokePaint);
        canvas.drawCircle(const Offset(12, 16), 1.1, fillPaint);
      case AppIconName.info:
        canvas.drawCircle(const Offset(12, 12), 10, strokePaint);
        canvas.drawLine(const Offset(12, 11), const Offset(12, 16), strokePaint);
        canvas.drawCircle(const Offset(12, 8), 1.1, fillPaint);
      case AppIconName.inbox:
        final tray = Path()
          ..moveTo(22, 12)
          ..lineTo(16, 12)
          ..lineTo(14, 15)
          ..lineTo(10, 15)
          ..lineTo(8, 12)
          ..lineTo(2, 12);
        canvas.drawPath(tray, strokePaint);
        final box = Path()
          ..moveTo(5.45, 5.11)
          ..lineTo(2, 12)
          ..lineTo(2, 18)
          ..arcToPoint(const Offset(4, 20), radius: const Radius.circular(2))
          ..lineTo(20, 20)
          ..arcToPoint(const Offset(22, 18), radius: const Radius.circular(2))
          ..lineTo(22, 12)
          ..lineTo(18.55, 5.11)
          ..arcToPoint(
            const Offset(16.76, 4),
            radius: const Radius.circular(2),
            clockwise: false,
          )
          ..lineTo(7.24, 4)
          ..arcToPoint(
            const Offset(5.45, 5.11),
            radius: const Radius.circular(2),
            clockwise: false,
          );
        canvas.drawPath(box, strokePaint);
      case AppIconName.trash:
        canvas.drawLine(const Offset(3, 6), const Offset(21, 6), strokePaint);
        final bin = Path()
          ..moveTo(19, 6)
          ..lineTo(19, 20)
          ..arcToPoint(const Offset(17, 22), radius: const Radius.circular(2))
          ..lineTo(7, 22)
          ..arcToPoint(const Offset(5, 20), radius: const Radius.circular(2))
          ..lineTo(5, 6);
        canvas.drawPath(bin, strokePaint);
        final lid = Path()
          ..moveTo(8, 6)
          ..lineTo(8, 4)
          ..arcToPoint(const Offset(10, 2), radius: const Radius.circular(2))
          ..lineTo(14, 2)
          ..arcToPoint(const Offset(16, 4), radius: const Radius.circular(2))
          ..lineTo(16, 6);
        canvas.drawPath(lid, strokePaint);
        canvas.drawLine(
          const Offset(10, 11),
          const Offset(10, 17),
          strokePaint,
        );
        canvas.drawLine(
          const Offset(14, 11),
          const Offset(14, 17),
          strokePaint,
        );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AppIconPainter oldDelegate) =>
      oldDelegate.name != name ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}

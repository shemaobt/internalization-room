import 'package:flutter/material.dart';

import '../../../../core/theme/sala_colors.dart';

class ShemaMark extends StatelessWidget {
  final VoidCallback onTap;

  const ShemaMark({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ExcludeSemantics(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 46,
          height: 46,
          child: CustomPaint(
            painter: _ShemaMarkPainter(
              (dark ? ShemaBrand.branco : ShemaBrand.verde).withValues(
                alpha: 0.72,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShemaMarkPainter extends CustomPainter {
  final Color color;

  const _ShemaMarkPainter(this.color);

  static const _viewBox = 1000.0;

  static Path _shape() {
    final path = Path()
      ..moveTo(900, 451.61)
      ..lineTo(900, 151.07)
      ..lineTo(700, 151.07)
      ..relativeArcToPoint(
        const Offset(-83.83, 12.66),
        radius: const Radius.circular(278.79),
        clockwise: false,
      )
      ..relativeCubicTo(-71, 22.3, -116.17, 92, -116.17, 92)
      ..relativeCubicTo(0, 0, -45, -69.59, -116.17, -92)
      ..arcToPoint(
        const Offset(300, 151.07),
        radius: const Radius.circular(278.79),
        clockwise: false,
      )
      ..lineTo(100, 151.07)
      ..lineTo(100, 749)
      ..lineTo(300, 749)
      ..relativeArcToPoint(
        const Offset(83.83, 12.65),
        radius: const Radius.circular(279.12),
      )
      ..cubicTo(455, 784, 500, 848.93, 500, 848.93)
      ..relativeCubicTo(0, 0, 39.71, -57.16, 103.18, -82.68)
      ..relativeCubicTo(-0.33, -5.73, -0.52, -11.49, -0.52, -17.31)
      ..cubicTo(602.66, 585, 736.05, 451.61, 900, 451.61)
      ..close();
    final outer = Path()
      ..moveTo(827.11, 748.94)
      ..lineTo(900, 748.94)
      ..lineTo(900, 675.57)
      ..cubicTo(859.81, 675.57, 827.11, 708.49, 827.11, 748.94)
      ..close();
    final middle = Path()
      ..moveTo(734.56, 748.94)
      ..relativeLineTo(53.22, 0)
      ..relativeCubicTo(0, -62.14, 50.34, -112.71, 112.22, -112.71)
      ..lineTo(900, 583.5)
      ..cubicTo(808.77, 583.5, 734.56, 657.72, 734.56, 748.94)
      ..close();
    final inner = Path()
      ..moveTo(642, 748.94)
      ..relativeQuadraticBezierTo(0, 3, 0.08, 6)
      ..arcToPoint(
        const Offset(695.22, 749),
        radius: const Radius.circular(281.75),
      )
      ..relativeLineTo(0, -0.1)
      ..cubicTo(695.22, 636, 787.08, 544.16, 900, 544.16)
      ..lineTo(900, 490.94)
      ..cubicTo(757.74, 490.94, 642, 606.68, 642, 748.94)
      ..close();
    return path
      ..addPath(outer, Offset.zero)
      ..addPath(middle, Offset.zero)
      ..addPath(inner, Offset.zero);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / _viewBox, size.height / _viewBox);
    canvas.drawPath(_shape(), Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShemaMarkPainter old) => old.color != color;
}

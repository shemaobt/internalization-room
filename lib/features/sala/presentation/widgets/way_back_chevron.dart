import 'package:flutter/material.dart';

import '../../../../core/theme/sala_colors.dart';

class WayBackChevron extends StatelessWidget {
  const WayBackChevron({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: CustomPaint(
        painter: _WayBackChevronPainter(SalaColors.of(context).claquete),
      ),
    );
  }
}

class _WayBackChevronPainter extends CustomPainter {
  final Color color;

  const _WayBackChevronPainter(this.color);

  static const _viewBox = 24.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / _viewBox, size.height / _viewBox);
    canvas.drawPath(
      Path()
        ..moveTo(15, 5)
        ..relativeLineTo(-7, 7)
        ..relativeLineTo(7, 7),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WayBackChevronPainter old) => old.color != color;
}

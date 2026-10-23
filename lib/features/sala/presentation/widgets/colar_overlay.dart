import 'package:flutter/material.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../domain/session_state.dart';
import 'bead_styles.dart';
import 'motion.dart';

const _designWidth = 390.0;
const _designHeight = 812.0;

Offset cordPoint(double t) {
  final u = 1 - t;
  final x = u * u * 34 + 2 * u * t * 195 + t * t * 356;
  final y = u * u * 24 + 2 * u * t * 92 + t * t * 24;
  return Offset(x, y);
}

Path cordArc(double sx, double sy) => Path()
  ..moveTo(34 * sx, 24 * sy)
  ..quadraticBezierTo(195 * sx, 92 * sy, 356 * sx, 24 * sy);

Offset arcPoint(int i, int total) =>
    cordPoint(total > 1 ? i / (total - 1) : 0.0);

class ColarOverlay extends StatelessWidget {
  final SalaSessionState session;

  const ColarOverlay({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final sx = constraints.maxWidth / _designWidth;
          final sy = constraints.maxHeight / _designHeight;
          Offset map(Offset p) => Offset(p.dx * sx, p.dy * sy);

          return Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _CordPainter(color: colors.line, sx: sx, sy: sy),
                ),
              ),
              for (var i = 0; i < session.coverage.beadsTotal; i++)
                _bead(context, colors, i, map),
            ],
          );
        },
      ),
    );
  }

  Widget _bead(
    BuildContext context,
    SalaColors colors,
    int i,
    Offset Function(Offset) map,
  ) {
    final total = session.coverage.beadsTotal;
    const size = 16.0;
    final p = map(arcPoint(i, total));
    final lit = i < session.coverage.beadsFilled;

    BoxDecoration decoration;
    if (lit) {
      decoration = BoxDecoration(
        shape: BoxShape.circle,
        gradient: BeadStyles.wood,
        boxShadow: [
          ...BeadStyles.matte,
          BoxShadow(
            color: ShemaBrand.wood.withValues(alpha: 0.25),
            spreadRadius: 3,
          ),
        ],
      );
    } else {
      decoration = BoxDecoration(
        shape: BoxShape.circle,
        gradient: BeadStyles.oat(colors),
        border: Border.all(color: colors.line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A0A0703),
            offset: Offset(0, 1),
            blurRadius: 2,
          ),
        ],
      );
    }

    final bead = SizedBox(
      width: size,
      height: size,
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 1300),
        decoration: decoration,
      ),
    );

    return AnimatedPositioned(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 900),
      curve: Curves.easeInOut,
      left: p.dx - size / 2,
      top: p.dy - size / 2,
      child: ThreadIn(index: i, total: total, child: bead),
    );
  }
}

class _CordPainter extends CustomPainter {
  final Color color;
  final double sx;
  final double sy;

  const _CordPainter({required this.color, required this.sx, required this.sy});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(cordArc(sx, sy), paint);
  }

  @override
  bool shouldRepaint(_CordPainter oldDelegate) =>
      color != oldDelegate.color ||
      sx != oldDelegate.sx ||
      sy != oldDelegate.sy;
}

import 'package:flutter/material.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../domain/meaning_map.dart';
import '../../domain/session_state.dart';
import 'bead_styles.dart';
import 'motion.dart';

const _designWidth = 390.0;
const _designHeight = 812.0;

Offset arcPoint(int i) {
  final t = i / (RuthOneMeaningMap.count - 1);
  final u = 1 - t;
  final x = u * u * 34 + 2 * u * t * 195 + t * t * 356;
  final y = u * u * 24 + 2 * u * t * 92 + t * t * 24;
  return Offset(x, y);
}

Offset circlePoint(int i) {
  final angle = (-90 + i * 30) * 3.141592653589793 / 180;
  return Offset(195, 400) +
      Offset.fromDirection(angle, 122);
}

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
          final onFim = session.onFim;

          return Stack(
            children: [
              Positioned.fill(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 600),
                  child: CustomPaint(
                    key: ValueKey(onFim),
                    painter: _CordPainter(
                      color: colors.cord,
                      onFim: onFim,
                      sx: sx,
                      sy: sy,
                    ),
                  ),
                ),
              ),
              for (var i = 0; i < RuthOneMeaningMap.count; i++)
                _bead(context, colors, i, map, onFim),
              for (var k = 0; k < session.knots; k++)
                _knot(map, k, onFim),
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
    bool onFim,
  ) {
    final size = (onFim ? 26.0 : 18.0);
    final p = map(onFim ? circlePoint(i) : arcPoint(i));
    final isAbsence = i == RuthOneMeaningMap.absenceIndex;
    final engaged =
        session.stage != SalaStage.conversa || i < session.engaged;
    final surfacedOnly = session.stage == SalaStage.conversa &&
        i >= session.engaged &&
        i < session.surfaced;

    BoxDecoration decoration;
    if (engaged && isAbsence) {
      decoration = BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ShemaBrand.wood, width: 3),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2E0A0703),
            offset: Offset(0, 1),
            blurRadius: 3,
          ),
        ],
      );
    } else if (engaged) {
      decoration = const BoxDecoration(
        shape: BoxShape.circle,
        gradient: BeadStyles.wood,
        boxShadow: BeadStyles.matte,
      );
    } else if (surfacedOnly) {
      decoration = BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colors.card, colors.card, ShemaBrand.wood, ShemaBrand.wood],
          stops: const [0, 0.5, 0.5, 1],
        ),
        border: Border.all(color: colors.cord, width: 2),
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

    final pinged = session.ping?.contains(i) ?? false;
    final glowing = onFim && session.fimClosed;

    Widget bead = AnimatedContainer(
      duration: const Duration(milliseconds: 700),
      width: size,
      height: size,
      decoration: decoration,
    );
    if (pinged) {
      bead = PingIn(key: ValueKey('ping-$i-${session.engaged}'), child: bead);
    } else if (glowing) {
      bead = Loop(
        period: const Duration(milliseconds: 3000),
        builder: (context, t) => Container(
          width: size,
          height: size,
          decoration: decoration.copyWith(
            boxShadow: [
              ...?decoration.boxShadow,
              BoxShadow(
                color: ShemaBrand.verdeClaro
                    .withValues(alpha: 0.25 * (1 - t)),
                spreadRadius: 3 + 6 * t,
              ),
            ],
          ),
        ),
      );
    }

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeInOut,
      left: p.dx - size / 2,
      top: p.dy - size / 2,
      child: bead,
    );
  }

  Widget _knot(Offset Function(Offset) map, int k, bool onFim) {
    final p = map(
      onFim ? const Offset(195, 400) : Offset(178 + k * 24, 104),
    );
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeInOut,
      left: p.dx,
      top: p.dy,
      child: PingIn(
        child: Transform.rotate(
          angle: 0.785398,
          child: Container(
            width: 13,
            height: 13,
            decoration: const BoxDecoration(
              gradient: BeadStyles.azul,
              borderRadius: BorderRadius.all(Radius.circular(4)),
            ),
          ),
        ),
      ),
    );
  }
}

class _CordPainter extends CustomPainter {
  final Color color;
  final bool onFim;
  final double sx;
  final double sy;

  const _CordPainter({
    required this.color,
    required this.onFim,
    required this.sx,
    required this.sy,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path();
    if (onFim) {
      path.addOval(
        Rect.fromCenter(
          center: Offset(195 * sx, 400 * sy),
          width: 244 * sx,
          height: 244 * sx,
        ),
      );
    } else {
      path.moveTo(34 * sx, 24 * sy);
      path.quadraticBezierTo(195 * sx, 92 * sy, 356 * sx, 24 * sy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CordPainter oldDelegate) =>
      color != oldDelegate.color ||
      onFim != oldDelegate.onFim ||
      sx != oldDelegate.sx ||
      sy != oldDelegate.sy;
}

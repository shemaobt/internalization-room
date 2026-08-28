import 'package:flutter/material.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../domain/session_state.dart';
import 'colar_overlay.dart';

const _designWidth = 390.0;
const _designHeight = 812.0;

double cordFraction({
  required int atMs,
  required int partes,
  required List<int> fimDasPartes,
  required int parteNoArMs,
}) {
  if (partes <= 0) return 0;
  var parte = fimDasPartes.length;
  for (var i = 0; i < fimDasPartes.length; i++) {
    if (atMs < fimDasPartes[i]) {
      parte = i;
      break;
    }
  }
  if (parte >= partes) return 1;
  final inicio = parte == 0 ? 0 : fimDasPartes[parte - 1];
  final duracao =
      parte < fimDasPartes.length ? fimDasPartes[parte] - inicio : parteNoArMs;
  final dentro =
      duracao <= 0 ? 0.0 : ((atMs - inicio) / duracao).clamp(0.0, 1.0);
  return ((parte + dentro) / partes).clamp(0.0, 1.0);
}

class RetroCord extends StatelessWidget {
  final int partes;
  final List<int> fimDasPartes;
  final int parteNoArMs;
  final int ouvidoMs;
  final List<Trecho> trechos;

  const RetroCord({
    super.key,
    required this.partes,
    required this.fimDasPartes,
    required this.parteNoArMs,
    required this.ouvidoMs,
    required this.trechos,
  });

  double _at(int ms) => cordFraction(
        atMs: ms,
        partes: partes,
        fimDasPartes: fimDasPartes,
        parteNoArMs: parteNoArMs,
      );

  @override
  Widget build(BuildContext context) {
    if (partes <= 0) return const SizedBox.shrink();
    final colors = SalaColors.of(context);
    final contados = <int>{};
    final told = <_Span>[];
    for (final trecho in trechos) {
      if (trecho.parte < 0) continue;
      // The stretch is addressed inside its own recording; the cord draws the whole
      // rehearsal as one line. The offset of the part is what carries one onto the other.
      final inicio = trecho.parte == 0 || trecho.parte > fimDasPartes.length
          ? 0
          : fimDasPartes[trecho.parte - 1];
      final de = inicio + trecho.from.inMilliseconds;
      final ate = inicio + trecho.to.inMilliseconds;
      final again = !contados.add(de);
      told.add(_Span(_at(de), _at(ate), again));
    }
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) => CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: _CordPainter(
            sx: constraints.maxWidth / _designWidth,
            sy: constraints.maxHeight / _designHeight,
            cord: colors.cord,
            told: told,
            mark: _at(ouvidoMs),
            boundaries: [
              for (var i = 1; i < partes; i++) i / partes,
            ],
            colors: colors,
          ),
        ),
      ),
    );
  }
}

class _Span {
  final double from;
  final double to;
  final bool again;

  const _Span(this.from, this.to, this.again);
}

class _CordPainter extends CustomPainter {
  final double sx;
  final double sy;
  final Color cord;
  final List<_Span> told;
  final double mark;
  final List<double> boundaries;
  final SalaColors colors;

  const _CordPainter({
    required this.sx,
    required this.sy,
    required this.cord,
    required this.told,
    required this.mark,
    required this.boundaries,
    required this.colors,
  });

  Offset _on(double t) {
    final p = cordPoint(t.clamp(0.0, 1.0));
    return Offset(p.dx * sx, p.dy * sy);
  }

  void _tick(Canvas canvas, double t, Color color, double reach) {
    final at = _on(t);
    canvas.drawLine(
      at.translate(0, -reach),
      at.translate(0, reach),
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      cordArc(sx, sy),
      Paint()
        ..color = cord
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    for (final span in told) {
      final path = Path();
      final steps = 24;
      for (var i = 0; i <= steps; i++) {
        final t = span.from + (span.to - span.from) * (i / steps);
        final at = _on(t);
        i == 0 ? path.moveTo(at.dx, at.dy) : path.lineTo(at.dx, at.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = ShemaBrand.wood
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round,
      );
      for (final edge in [span.from, span.to]) {
        _tick(canvas, edge, span.again ? ShemaBrand.azulInk : colors.cord, 5);
      }
    }

    for (final at in boundaries) {
      _tick(canvas, at, colors.cord, 9);
    }

    canvas.drawCircle(_on(mark), 7, Paint()..color = colors.telha);
  }

  @override
  bool shouldRepaint(_CordPainter old) => true;
}

import 'package:flutter/material.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../domain/session_state.dart';
import 'colar_overlay.dart';

const _designWidth = 390.0;
const _designHeight = 812.0;

/// Where a stretch sits on the whole rehearsal, or null while that cannot be known.
///
/// A stretch is addressed inside its own recording and the cord draws the rehearsal as
/// one line, so the offset of the part is what carries one onto the other. That offset is
/// only learned by playing the part.
int? cordStartMs({
  required int parte,
  required int dentroMs,
  required List<int> fimDasPartes,
}) {
  if (parte < 0 || parte > fimDasPartes.length) return null;
  return (parte == 0 ? 0 : fimDasPartes[parte - 1]) + dentroMs;
}

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

  /// The room's name for the stretch the analyst pointed at, when it pointed at one.
  final String? apontado;

  const RetroCord({
    super.key,
    required this.partes,
    required this.fimDasPartes,
    required this.parteNoArMs,
    required this.ouvidoMs,
    required this.trechos,
    this.apontado,
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
      // A stretch out of a part this cord has not measured yet has no place on it. Not
      // drawing it leaves a gap that fills itself as the team plays that part through;
      // placing it at nought piled the stretches of a picked-up retro onto the first
      // part, on top of the ones that really are there.
      final de = cordStartMs(
        parte: trecho.parte,
        dentroMs: trecho.from.inMilliseconds,
        fimDasPartes: fimDasPartes,
      );
      final ate = cordStartMs(
        parte: trecho.parte,
        dentroMs: trecho.to.inMilliseconds,
        fimDasPartes: fimDasPartes,
      );
      if (de == null || ate == null) continue;
      final again = !contados.add(de);
      told.add(_Span(
        _at(de),
        _at(ate),
        again,
        apontado != null && trecho.segmentId == apontado,
      ));
    }
    return Semantics(
      label: told.any((span) => span.apontado)
          ? 'Trecho apontado pelo analista'
          : null,
      child: IgnorePointer(
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
      ),
    );
  }
}

class _Span {
  final double from;
  final double to;
  final bool again;
  /// Whether this is the stretch the analyst pointed at. The room has no readable words,
  /// so the cord is the only place the team can see *where* the problem is.
  final bool apontado;

  const _Span(this.from, this.to, this.again, [this.apontado = false]);
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
      if (span.apontado) {
        // The stretch drains and wears a halo. Error is never red in this room: the mark
        // is the room's own terracotta, the colour of focus, and mending is filling it in
        // again.
        canvas.drawPath(
          path,
          Paint()
            ..color = colors.halo
            ..style = PaintingStyle.stroke
            ..strokeWidth = 14
            ..strokeCap = StrokeCap.round,
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = span.apontado ? colors.oat : ShemaBrand.wood
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

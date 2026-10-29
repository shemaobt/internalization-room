import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/playback_repository.dart';
import '../../domain/pausa.dart';
import '../../domain/scene_rehearsal.dart';
import 'motion.dart';

/// What the scene strip draws, in pixels across its width: the take's loudness per
/// column, each placed frase's band and the tick at its end, the player and the pending
/// pausa.
final class SceneStripDrawing {
  final List<double> columns;
  final List<({double from, double to})> bands;
  final List<({double from, double to})> staleBands;
  final List<double> ticks;
  final double? playhead;
  final double? pausa;

  const SceneStripDrawing({
    required this.columns,
    required this.bands,
    this.staleBands = const [],
    required this.ticks,
    required this.playhead,
    required this.pausa,
  });
}

/// Her strip's geometry (stripGeometry.ts): seconds to pixels over the take, and the
/// loudest bin under each column, so a short gap between two frases never vanishes.
SceneStripDrawing sceneStripOf({
  required double width,
  required Duration? length,
  Envelope? envelope,
  List<SceneFrase> frases = const [],
  List<SceneFrase> stale = const [],
  Duration? playhead,
  Duration? pausa,
}) {
  final whole = length?.inMicroseconds ?? 0;
  double? xOf(Duration? at) => at == null || whole <= 0
      ? null
      : (at.inMicroseconds / whole * width).clamp(0, width).toDouble();
  List<({double from, double to})> bandsOf(List<SceneFrase> frases) => [
    for (final frase in frases.where((frase) => frase.placedIn(length)))
      (
        from: xOf(Duration(milliseconds: frase.startsMs!))!,
        to: xOf(Duration(milliseconds: frase.endsMs!))!,
      ),
  ];
  final bands = bandsOf(frases);
  return SceneStripDrawing(
    columns: envelope == null ? const [] : _columnsOf(envelope, width.floor()),
    bands: bands,
    staleBands: bandsOf(stale),
    ticks: [for (final band in bands) band.to],
    playhead: xOf(playhead),
    pausa: xOf(pausa),
  );
}

List<double> _columnsOf(Envelope envelope, int width) {
  final bins = envelope.loudness;
  final seconds = envelope.length.inMicroseconds;
  if (bins.isEmpty || seconds <= 0 || width <= 0) return const [];
  final binsPerColumn = bins.length / width;
  final columns = [
    for (var x = 0; x < width; x++)
      bins
          .getRange(
            (x * binsPerColumn).floor().clamp(0, bins.length - 1),
            max(
              (x * binsPerColumn).floor() + 1,
              ((x + 1) * binsPerColumn).ceil(),
            ).clamp(1, bins.length),
          )
          .reduce(max),
  ];
  final loudest = columns.reduce(max);
  return loudest <= 0
      ? columns
      : [for (final column in columns) column / loudest];
}

/// The scene rehearsal's wordless picture of its take while translating: a silence reads
/// as a valley. It carries no words and cannot be tapped.
class SceneStrip extends ConsumerWidget {
  static const fullWidth = 292.0;
  static const height = 44.0;

  final Envelope? envelope;
  final Duration? length;
  final List<SceneFrase> frases;
  final List<SceneFrase> stale;
  final Duration? pausa;
  final bool playing;
  final Duration? stoppedAt;
  final double width;

  const SceneStrip({
    super.key,
    required this.envelope,
    required this.length,
    required this.frases,
    this.stale = const [],
    required this.pausa,
    required this.playing,
    this.stoppedAt,
    this.width = SceneStrip.fullWidth,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = SalaColors.of(context);
    final playback = ref.read(playbackRepositoryProvider);
    return ExcludeSemantics(
      child: Loop(
        period: const Duration(seconds: 1),
        animate: playing,
        reducible: false,
        builder: (context, _) => CustomPaint(
          size: Size(width, height),
          painter: SceneStripPainter(
            sceneStripOf(
              width: width,
              length: length,
              envelope: envelope,
              frases: frases,
              stale: stale,
              playhead: playing ? playback.position : stoppedAt,
              pausa: pausa,
            ),
            colors,
          ),
        ),
      ),
    );
  }
}

class SceneStripPainter extends CustomPainter {
  final SceneStripDrawing drawing;
  final SalaColors colors;

  const SceneStripPainter(this.drawing, this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = colors.line.withValues(alpha: 0.22),
    );
    final columns = drawing.columns;
    if (columns.isNotEmpty) {
      final mid = h / 2;
      final amp = h * 0.46;
      final silhouette = Path()..moveTo(0, mid);
      for (var x = 0; x < columns.length; x++) {
        silhouette.lineTo(x + 0.5, mid - max(0.6, columns[x] * amp));
      }
      for (var x = columns.length - 1; x >= 0; x--) {
        silhouette.lineTo(x + 0.5, mid + max(0.6, columns[x] * amp));
      }
      canvas.drawPath(
        silhouette..close(),
        Paint()..color = colors.mut.withValues(alpha: 0.6),
      );
    }
    for (final band in drawing.staleBands) {
      canvas.drawRect(
        Rect.fromLTRB(band.from, 0, max(band.from + 1, band.to), h),
        Paint()..color = colors.line.withValues(alpha: 0.18),
      );
      final dot = Paint()
        ..color = colors.line.withValues(alpha: 0.9)
        ..strokeWidth = 1.5;
      for (var x = band.from; x < band.to; x += 5) {
        canvas.drawLine(Offset(x, 2), Offset(min(x + 2, band.to), 2), dot);
      }
    }
    for (final band in drawing.bands) {
      canvas.drawRect(
        Rect.fromLTRB(band.from, 0, max(band.from + 1, band.to), h),
        Paint()..color = colors.line.withValues(alpha: 0.28),
      );
    }
    void line(double x, double thickness, Color color) => canvas.drawRect(
      Rect.fromLTWH(
        (x - thickness / 2).clamp(0, size.width - thickness),
        0,
        thickness,
        h,
      ),
      Paint()..color = color,
    );
    for (final tick in drawing.ticks) {
      line(tick, 1.5, colors.ink.withValues(alpha: 0.75));
    }
    if (drawing.playhead case final x?) {
      line(x, 1.5, colors.ink.withValues(alpha: 0.9));
    }
    if (drawing.pausa case final x?) line(x, 3, colors.telha);
  }

  @override
  bool shouldRepaint(SceneStripPainter old) => true;
}

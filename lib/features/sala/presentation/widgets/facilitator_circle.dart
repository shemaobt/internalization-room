import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../domain/halt.dart';
import '../../domain/session_state.dart';
import 'bead_styles.dart';
import 'motion.dart';

enum Tongue { guide, motherTongue, bridge }

const facilitatorCircleSize = 160.0;

bool isTeamTalk({required bool peerCue, required VoiceState voice}) =>
    peerCue && (voice == VoiceState.invite || voice == VoiceState.done);

class FacilitatorCircle extends StatelessWidget {
  final double size;
  final VoiceState voice;
  final Tongue? tongue;
  final bool noteMode;
  final bool peerCue;
  final bool answersATouch;
  final bool enabled;
  final bool canvas;

  /// Her line after a telling the room made nothing of, said to VoiceOver by a mark on
  /// the other side of the disc, or null while no telling came back empty.
  final String? notUnderstood;
  final Halt halt;
  final double opacity;
  final String semanticLabel;
  final VoidCallback? onTap;

  const FacilitatorCircle({
    super.key,
    required this.size,
    required this.voice,
    this.tongue,
    required this.semanticLabel,
    this.noteMode = false,
    this.peerCue = false,
    this.answersATouch = true,
    this.enabled = true,
    this.canvas = false,
    this.notUnderstood,
    this.halt = const NoHalt(),
    this.opacity = 1,
    this.onTap,
  });

  bool get _teamTalk => isTeamTalk(peerCue: peerCue, voice: voice);

  bool get _noteBlue => noteMode && voice != VoiceState.done;

  @override
  Widget build(BuildContext context) {
    final underTheSign = halt is Blocking;
    return ExcludeSemantics(
      excluding: underTheSign,
      child: _circle(context, underTheSign ? 0 : opacity),
    );
  }

  Widget _circle(BuildContext context, double opacity) {
    final colors = SalaColors.of(context);
    final still = MediaQuery.disableAnimationsOf(context);
    return AnimatedOpacity(
      opacity: opacity,
      duration: const Duration(milliseconds: 500),
      child: Semantics(
        button: true,
        enabled: enabled ? null : false,
        label: semanticLabel,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                _body(colors, still),
                if (!_halted && voice == VoiceState.speaking)
                  ..._ripples(colors),
                if (!_halted && voice == VoiceState.listening)
                  _listenRing(colors),
                if (!_halted && voice == VoiceState.listening)
                  ..._gatheringIn(),
                if (notUnderstood != null && !_halted)
                  _notUnderstoodMark(notUnderstood!),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 1000),
                  child: _modeGlyph == null
                      ? const SizedBox.shrink()
                      : Icon(
                          _modeGlyph,
                          key: ValueKey(_modeGlyph),
                          size: size * 0.3,
                          color: ShemaBrand.branco,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _soundColor(SalaColors colors) {
    switch (tongue) {
      case Tongue.motherTongue:
        return ShemaBrand.woodLo;
      case Tongue.bridge:
        return ShemaBrand.azulInk;
      case Tongue.guide:
      case null:
        return colors.telha;
    }
  }

  List<Widget> _ripples(SalaColors colors) {
    final color = _soundColor(colors);
    Widget ring(double phase) => Ripple(
      period: const Duration(milliseconds: 3400),
      phase: phase,
      builder: (context, t) => Transform.scale(
        scale: 1 + 0.46 * t,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: color.withValues(alpha: 0.55 * (1 - t)),
              width: 3,
            ),
          ),
        ),
      ),
    );
    return [ring(0), ring(0.65)];
  }

  /// Whether the room is already showing a stop for this voice.
  ///
  /// A warning is a lesser thing than any of these — it asks somebody to come and
  /// look, and refuses nothing — so it never draws over a state that has already
  /// told the team to stop.
  bool get _halted => halt is Blocking;

  IconData? get _modeGlyph {
    if (_halted) return null;
    if (noteMode) return LucideIcons.hand;
    if (_teamTalk) return LucideIcons.users;
    // A voice that is only the room's own — speaking, inviting, listening, done — draws
    // no mark: the colour and the breath already say it, and the loudspeaker read as a
    // control the team could press. Only a mode says itself with a glyph.
    return null;
  }

  Widget _body(SalaColors colors, bool still) {
    if (!answersATouch) return _haltedBody(colors);
    if (_teamTalk) return _liveBreath(colors);

    switch (voice) {
      case VoiceState.invite:
      case VoiceState.done:
        return _liveBreath(colors);
      case VoiceState.listening:
        return _disc(
          gradient: tongue == Tongue.motherTongue
              ? BeadStyles.wood
              : BeadStyles.azul,
          shadows: [
            BoxShadow(
              color:
                  (tongue == Tongue.motherTongue
                          ? ShemaBrand.woodLo
                          : ShemaBrand.azulLo)
                      .withValues(alpha: 0.3),
              offset: const Offset(0, 10),
              blurRadius: 30,
            ),
          ],
        );
      case VoiceState.thinking:
        return _waiting(colors, still);
      case VoiceState.speaking:
        return Loop(
          period: const Duration(milliseconds: 3400),
          builder: (context, t) =>
              Transform.scale(scale: 1 + 0.02 * t, child: _liveDisc(colors)),
        );
    }
  }

  Gradient _liveGradient(SalaColors colors) {
    if (voice != VoiceState.speaking) {
      return _noteBlue ? BeadStyles.azul : BeadStyles.telha(colors);
    }
    switch (tongue) {
      case Tongue.motherTongue:
        return BeadStyles.wood;
      case Tongue.bridge:
        return BeadStyles.azul;
      case Tongue.guide:
      case null:
        return noteMode ? BeadStyles.azul : BeadStyles.telha(colors);
    }
  }

  Color _liveShadow(SalaColors colors) {
    if (voice != VoiceState.speaking) {
      return _noteBlue ? ShemaBrand.azulLo : colors.telha;
    }
    switch (tongue) {
      case Tongue.motherTongue:
        return ShemaBrand.woodLo;
      case Tongue.bridge:
        return ShemaBrand.azulLo;
      case Tongue.guide:
      case null:
        return noteMode ? ShemaBrand.azulLo : colors.telha;
    }
  }

  Widget _liveDisc(SalaColors colors) => _disc(
    gradient: _liveGradient(colors),
    shadows: [
      BoxShadow(
        color: _liveShadow(colors).withValues(alpha: 0.32),
        offset: const Offset(0, 10),
        blurRadius: 34,
      ),
    ],
  );

  Widget _waiting(SalaColors colors, bool still) {
    final body = _disc(
      gradient: BeadStyles.clay(colors),
      shadows: const [
        BoxShadow(
          color: Color(0x260A0703),
          offset: Offset(0, 6),
          blurRadius: 20,
        ),
      ],
    );
    final glow = RepaintBoundary(
      child: CustomPaint(
        size: Size.square(size),
        painter: GlowPainter(color: colors.telha.withValues(alpha: 0.16)),
      ),
    );
    final arcs = canvas
        ? [
            _arc(
              const Duration(milliseconds: 1600),
              1,
              ArcPainter(
                side: size * 1.14,
                stroke: size * 4 / 232,
                top: colors.telha,
                right: colors.telha.withValues(alpha: 0.35),
              ),
            ),
            _arc(
              const Duration(milliseconds: 2600),
              -1,
              ArcPainter(
                side: size * 1.26,
                stroke: size * 2 / 232,
                bottom: colors.telha.withValues(alpha: 0.55),
              ),
            ),
          ]
        : const <Widget>[];
    Widget over(Widget light) => Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [...arcs, body, light],
    );
    if (still) {
      return Loop(
        period: const Duration(milliseconds: 2400),
        reducible: false,
        builder: (context, t) =>
            Opacity(opacity: 0.72 + 0.24 * t, child: over(glow)),
      );
    }
    return Loop(
      period: const Duration(milliseconds: 2400),
      builder: (context, t) => Transform.scale(
        scale: 0.97 + 0.06 * t,
        child: Opacity(
          opacity: 0.82 + 0.18 * t,
          child: over(Opacity(opacity: 0.45 + 0.55 * t, child: glow)),
        ),
      ),
    );
  }

  Widget _arc(Duration period, double way, ArcPainter painter) => Spin(
    period: period,
    builder: (context, t) => Transform.rotate(
      angle: way * 2 * math.pi * t,
      child: RepaintBoundary(
        child: CustomPaint(size: Size.square(size), painter: painter),
      ),
    ),
  );

  Widget _notUnderstoodMark(String label) => Positioned(
    left: 0,
    bottom: 0,
    child: Semantics(
      container: true,
      label: label,
      child: Container(
        width: size * 0.22,
        height: size * 0.22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: BeadStyles.azul,
          boxShadow: BeadStyles.matte,
        ),
      ),
    ),
  );

  Widget _liveBreath(SalaColors colors) => Loop(
    period: const Duration(milliseconds: 4600),
    builder: (context, t) =>
        Transform.scale(scale: 1 + 0.045 * t, child: _liveDisc(colors)),
  );

  /// A circle that answers no touch, and is still running: slower and shallower than an
  /// invite on purpose, so the colour says this is not a turn to take and the breath only
  /// says the app is still there.
  Widget _haltedBody(SalaColors colors) {
    return Loop(
      period: const Duration(milliseconds: 6200),
      builder: (context, t) => Transform.scale(
        scale: 1 + 0.028 * t,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: BeadStyles.clay(colors),
            border: Border.all(color: colors.cord, width: 2),
          ),
        ),
      ),
    );
  }

  Widget _disc({
    Gradient? gradient,
    Color? background,
    List<BoxShadow>? shadows,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: gradient,
        color: background,
        boxShadow: shadows,
      ),
    );
  }

  Color get _listenColor =>
      tongue == Tongue.motherTongue ? ShemaBrand.woodLo : ShemaBrand.azulInk;

  Widget _listenRing(SalaColors colors) {
    final ring = _listenColor;
    final glow = tongue == Tongue.motherTongue
        ? ShemaBrand.wood
        : ShemaBrand.azul;
    return Loop(
      period: const Duration(milliseconds: 3200),
      builder: (context, t) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: ring, width: 3),
          boxShadow: [
            BoxShadow(
              color: glow.withValues(alpha: 0.5 * (1 - t)),
              spreadRadius: 4 + 12 * t,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _gatheringIn() {
    final color = _listenColor;
    Widget ring(double phase) => Ripple(
      period: const Duration(milliseconds: 3200),
      phase: phase,
      builder: (context, t) => Transform.scale(
        scale: 1.46 - 0.46 * t,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: color.withValues(alpha: 0.55 * t),
              width: 2.5,
            ),
          ),
        ),
      ),
    );
    return [ring(0), ring(0.5)];
  }
}

class GlowPainter extends CustomPainter {
  final Color color;

  const GlowPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final disc = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.shortestSide / 2,
    );
    canvas.drawOval(
      disc,
      Paint()
        ..shader = RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ).createShader(disc),
    );
  }

  @override
  bool shouldRepaint(GlowPainter old) => old.color != color;
}

class ArcPainter extends CustomPainter {
  final double side;
  final double stroke;
  final Color? top;
  final Color? right;
  final Color? bottom;

  const ArcPainter({
    required this.side,
    required this.stroke,
    this.top,
    this.right,
    this.bottom,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final ring = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: side - stroke,
      height: side - stroke,
    );
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    for (final (color, start) in [
      (top, -0.75 * math.pi),
      (right, -0.25 * math.pi),
      (bottom, 0.25 * math.pi),
    ]) {
      if (color == null) continue;
      canvas.drawArc(ring, start, math.pi / 2, false, pen..color = color);
    }
  }

  @override
  bool shouldRepaint(ArcPainter old) =>
      old.side != side ||
      old.stroke != stroke ||
      old.top != top ||
      old.right != right ||
      old.bottom != bottom;
}

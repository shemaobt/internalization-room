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

double herCircleSize(Size screen, int vw, double most) =>
    math.min(screen.width * vw / 100, most);

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

  bool get _herNote =>
      noteMode && (voice == VoiceState.invite || voice == VoiceState.listening);

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
    final drawing = Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        if (!_halted && canvas && !still && voice == VoiceState.listening)
          ..._herRipples(colors),
        if (canvas && voice == VoiceState.thinking)
          KeyedSubtree(
            key: const ValueKey(VoiceState.thinking),
            child: _herArcs(colors, still),
          ),
        if (!_halted && canvas && voice == VoiceState.speaking) _herGlow(still),
        if (canvas)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 1400),
            switchInCurve: Curves.ease,
            switchOutCurve: Curves.ease.flipped,
            transitionBuilder: (child, fade) =>
                FadeTransition(opacity: fade, child: child),
            child: KeyedSubtree(
              key: ValueKey((voice, _herNote)),
              child: _body(context, colors, still),
            ),
          )
        else
          _body(context, colors, still),
        if (!_halted && !canvas && voice == VoiceState.speaking)
          ..._ripples(colors),
        if (!_halted && !canvas && voice == VoiceState.listening)
          _listenRing(colors),
        if (!_halted && !canvas && voice == VoiceState.listening)
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
                  color: canvas ? _herInk(colors) : ShemaBrand.branco,
                ),
        ),
      ],
    );
    return AnimatedOpacity(
      opacity: opacity,
      duration: Duration(milliseconds: canvas ? 1400 : 500),
      curve: canvas ? Curves.ease : Curves.linear,
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
            child: canvas
                ? AnimatedScale(
                    scale: !_halted && voice == VoiceState.speaking ? 0.9 : 1,
                    duration: const Duration(milliseconds: 1400),
                    curve: Curves.ease,
                    child: drawing,
                  )
                : drawing,
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
  bool get _halted => halt is Blocking;

  IconData? get _modeGlyph {
    if (_halted) return null;
    if (noteMode) return LucideIcons.hand;
    if (_teamTalk) return LucideIcons.users;
    if (!canvas || voice == VoiceState.thinking) return null;
    return LucideIcons.volume2;
  }

  Color _herInk(SalaColors colors) {
    if (noteMode) return colors.azul;
    if (_teamTalk) return const Color(0xFF3F7F76);
    return colors.telha;
  }

  Widget _body(BuildContext context, SalaColors colors, bool still) {
    if (!answersATouch) return _haltedBody(colors);
    if (canvas && _herNote) return _herRing(context, colors);
    if (_teamTalk) return _liveBreath(colors);

    switch (voice) {
      case VoiceState.invite:
      case VoiceState.done:
        return _liveBreath(colors);
      case VoiceState.listening:
        if (canvas) return _herRing(context, colors);
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
        return _waiting(context, colors, still);
      case VoiceState.speaking:
        if (canvas) return _herRing(context, colors);
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

  Widget _waiting(BuildContext context, SalaColors colors, bool still) {
    if (canvas) {
      return _thinkBreath(
        still,
        (glowing) => Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Opacity(opacity: glowing, child: _herLight(.16, .62)),
            _herRing(context, colors),
          ],
        ),
      );
    }
    final clay = _disc(
      gradient: BeadStyles.clay(colors),
      shadows: const [
        BoxShadow(
          color: Color(0x260A0703),
          offset: Offset(0, 6),
          blurRadius: 20,
        ),
      ],
    );
    return still ? clay : _thinkBreath(false, (_) => clay);
  }

  Widget _thinkBreath(bool still, Widget Function(double glowing) inside) {
    if (still) {
      return Loop(
        period: const Duration(milliseconds: 2400),
        reducible: false,
        builder: (context, t) =>
            Opacity(opacity: 0.72 + 0.24 * t, child: inside(1)),
      );
    }
    return Loop(
      period: Duration(milliseconds: canvas ? 2400 : 4500),
      builder: (context, t) => Transform.scale(
        scale: 0.97 + 0.06 * t,
        child: Opacity(
          opacity: 0.82 + 0.18 * t,
          child: inside(0.45 + 0.55 * t),
        ),
      ),
    );
  }

  Widget _herArcs(SalaColors colors, bool still) => _thinkBreath(
    still,
    (_) => Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        _arc(
          const Duration(milliseconds: 1600),
          1,
          still,
          ArcPainter(
            side: size * 1.14,
            stroke: 4,
            top: colors.telha,
            right: colors.telha.withValues(alpha: 0.35),
          ),
        ),
        _arc(
          const Duration(milliseconds: 2600),
          -1,
          still,
          ArcPainter(
            side: size * 1.26,
            stroke: 2,
            bottom: colors.telha.withValues(alpha: 0.55),
          ),
        ),
      ],
    ),
  );

  Widget _arc(Duration period, double way, bool still, ArcPainter painter) {
    final turning = Spin(
      period: period,
      builder: (context, t) => Transform.rotate(
        angle: way * 2 * math.pi * t,
        child: RepaintBoundary(
          child: CustomPaint(size: Size.square(size), painter: painter),
        ),
      ),
    );
    return still ? Opacity(opacity: 0.9, child: turning) : turning;
  }

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
    period: Duration(milliseconds: canvas ? 6500 : 6000),
    builder: (context, t) => Transform.scale(
      scale: 1 + 0.035 * t,
      child: canvas ? _herRing(context, colors) : _liveDisc(colors),
    ),
  );

  Widget _herRing(BuildContext context, SalaColors colors) {
    final (fill, stops) = _herFill(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _herEdge(colors), width: 1.5),
        gradient: RadialGradient(
          center: const Alignment(0, -0.08),
          radius: 0.7359,
          colors: fill,
          stops: stops,
        ),
      ),
    );
  }

  List<Widget> _herRipples(SalaColors colors) {
    Widget ring(double phase) => Ripple(
      period: const Duration(milliseconds: 3200),
      phase: phase,
      curve: Curves.linear,
      builder: (context, t) => Transform.scale(
        scale: 0.62 + 0.88 * Curves.easeOut.transform(t),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: colors.azul.withValues(alpha: _ebb(t)),
              width: 1.2,
            ),
          ),
        ),
      ),
    );
    return [ring(0), ring(0.665625), ring(0.33125)];
  }

  Widget _herLight(double alpha, double reach) => OverflowBox(
    maxWidth: size * 1.12,
    maxHeight: size * 1.12,
    child: Container(
      width: size * 1.12,
      height: size * 1.12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          radius: 0.7071,
          colors: [
            Color.fromRGBO(190, 74, 1, alpha),
            const Color.fromRGBO(190, 74, 1, 0),
          ],
          stops: [0, reach],
        ),
      ),
    ),
  );

  Widget _herGlow(bool still) {
    final light = _herLight(.20, .66);
    if (still) return light;
    return Loop(
      period: const Duration(milliseconds: 3400),
      builder: (context, t) => Opacity(
        opacity: 0.55 + 0.45 * t,
        child: Transform.scale(scale: 0.98 + 0.08 * t, child: light),
      ),
    );
  }

  double _ebb(double t) => t <= 0.8
      ? 0.5 - 0.44 * Curves.easeOut.transform(t / 0.8)
      : 0.06 - 0.06 * Curves.easeOut.transform((t - 0.8) / 0.2);

  Color _herEdge(SalaColors colors) {
    if (_herNote) return colors.azul;
    if (_teamTalk) return colors.telha;
    switch (voice) {
      case VoiceState.invite:
      case VoiceState.done:
        return colors.telha;
      case VoiceState.listening:
        return colors.azul;
      case VoiceState.thinking:
        return colors.areia;
      case VoiceState.speaking:
        return const Color.fromRGBO(199, 194, 159, .5);
    }
  }

  (List<Color>, List<double>) _herFill(bool dark) {
    if (_herNote) {
      return (
        const [
          Color.fromRGBO(137, 170, 163, .16),
          Color.fromRGBO(199, 194, 159, .12),
          Color.fromRGBO(199, 194, 159, .04),
        ],
        const [0, .62, 1],
      );
    }
    if (_teamTalk) return _inviteFill;
    switch (voice) {
      case VoiceState.invite:
        return _inviteFill;
      case VoiceState.listening:
        return (
          const [
            Color.fromRGBO(137, 170, 163, .14),
            Color.fromRGBO(199, 194, 159, .12),
            Color.fromRGBO(199, 194, 159, 0),
          ],
          const [0, .64, 1],
        );
      case VoiceState.speaking:
        return (
          const [
            Color.fromRGBO(190, 74, 1, .06),
            Color.fromRGBO(190, 74, 1, 0),
          ],
          const [0, .6],
        );
      case VoiceState.done:
      case VoiceState.thinking:
        if (dark) {
          return (
            const [
              Color.fromRGBO(214, 97, 42, .16),
              Color.fromRGBO(110, 106, 87, .14),
              Color.fromRGBO(110, 106, 87, .04),
            ],
            const [0, .62, 1],
          );
        }
        return (
          const [
            Color.fromRGBO(190, 74, 1, .10),
            Color.fromRGBO(199, 194, 159, .16),
            Color.fromRGBO(199, 194, 159, .05),
          ],
          const [0, .62, 1],
        );
    }
  }

  static const _inviteFill = (
    [
      Color.fromRGBO(190, 74, 1, .14),
      Color.fromRGBO(199, 194, 159, .18),
      Color.fromRGBO(199, 194, 159, .04),
    ],
    [0.0, .6, 1.0],
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

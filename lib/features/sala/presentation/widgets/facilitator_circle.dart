import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../domain/room_reach.dart';
import '../../domain/session_state.dart';
import 'bead_styles.dart';
import 'motion.dart';

enum Tongue { guide, motherTongue, bridge }

const facilitatorCircleSize = 160.0;

class FacilitatorCircle extends StatelessWidget {
  final double size;
  final VoiceState voice;
  final Tongue? tongue;
  final RoomReach reach;
  final bool noteMode;
  final bool peerCue;
  final bool beckon;

  /// What the warning mark says to VoiceOver, or null while the server's last word
  /// was silence rather than a warning.
  ///
  /// The room has no text on screen, so a warning is a small mark beside the disc,
  /// never a colour drawn over it: the disc keeps saying the voice. Read only while
  /// [voice] is not one of the halted states — a room the team cannot use yet is
  /// still a stop, whatever the last warning said.
  final String? warning;
  final double opacity;
  final String semanticLabel;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const FacilitatorCircle({
    super.key,
    required this.size,
    required this.voice,
    this.tongue,
    this.reach = RoomReach.fine,
    required this.semanticLabel,
    this.noteMode = false,
    this.peerCue = false,
    this.beckon = false,
    this.warning,
    this.opacity = 1,
    this.onTap,
    this.onLongPress,
  });

  bool get _teamTalk => peerCue && voice == VoiceState.invite;

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    final still = MediaQuery.disableAnimationsOf(context);
    return AnimatedOpacity(
      opacity: opacity,
      duration: const Duration(milliseconds: 500),
      child: Semantics(
        button: true,
        label: semanticLabel,
        child: GestureDetector(
          onTap: onTap,
          onLongPress: onLongPress,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                if (beckon) ..._beckoning(colors),
                _body(colors, still),
                if (voice == VoiceState.speaking) ..._ripples(colors),
                if (voice == VoiceState.listening) _listenRing(colors),
                if (voice == VoiceState.listening) ..._gatheringIn(),
                if (warning != null && !_halted) _warningMark(warning!),
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

  List<Widget> _beckoning(SalaColors colors) {
    Widget ring(double phase) => Ripple(
      period: const Duration(milliseconds: 2600),
      phase: phase,
      builder: (context, t) => Transform.scale(
        scale: 1 + 0.42 * t,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: colors.telha.withValues(alpha: 0.55 * (1 - t)),
              width: 3,
            ),
          ),
        ),
      ),
    );
    return [ring(0), ring(0.5)];
  }

  /// A tablet with no network at all, or a network with no room answering on it.
  ///
  /// The check has always known which; it collapsed both into one face, and a wrong
  /// address on a working wi-fi told the team the internet had gone.
  IconData get _offlineGlyph => reach == RoomReach.roomSilent
      ? LucideIcons.serverOff
      : LucideIcons.cloudOff;

  /// Whether the room is already showing a stop for this voice.
  ///
  /// A warning is a lesser thing than any of these — it asks somebody to come and
  /// look, and refuses nothing — so it never draws over a state that has already
  /// told the team to stop.
  bool get _halted =>
      voice == VoiceState.needsPerson ||
      voice == VoiceState.offline ||
      voice == VoiceState.blocked;

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
    if (voice == VoiceState.needsPerson) {
      return _haltedBody(colors, LucideIcons.userCheck);
    }
    if (voice == VoiceState.offline) return _haltedBody(colors, _offlineGlyph);
    if (_teamTalk) return _liveBreath(colors);

    switch (voice) {
      case VoiceState.invite:
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
      case VoiceState.done:
        return _doneDisc();
      case VoiceState.needsPerson:
        return _haltedBody(colors, LucideIcons.userCheck);
      case VoiceState.offline:
        return _haltedBody(colors, _offlineGlyph);
      case VoiceState.blocked:
        return _haltedBody(colors, LucideIcons.micOff);
    }
  }

  Widget _doneDisc() => _disc(
    gradient: BeadStyles.verde,
    shadows: [
      BoxShadow(
        color: ShemaBrand.verdeLo.withValues(alpha: 0.28),
        offset: const Offset(0, 10),
        blurRadius: 34,
      ),
    ],
  );

  Gradient _liveGradient(SalaColors colors) {
    if (voice != VoiceState.speaking) {
      return noteMode ? BeadStyles.azul : BeadStyles.telha(colors);
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
      return noteMode ? ShemaBrand.azulLo : colors.telha;
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
    Widget over(Widget light) => Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [body, light],
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

  Widget _warningMark(String label) => Positioned(
    right: 0,
    bottom: 0,
    child: Semantics(
      container: true,
      label: label,
      child: Container(
        width: size * 0.22,
        height: size * 0.22,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: BeadStyles.verde,
          boxShadow: BeadStyles.matte,
        ),
      ),
    ),
  );

  Widget _liveBreath(SalaColors colors) => Loop(
    period: Duration(milliseconds: beckon ? 1800 : 4600),
    builder: (context, t) => Transform.scale(
      scale: 1 + (beckon ? 0.09 : 0.045) * t,
      child: _liveDisc(colors),
    ),
  );

  /// A room that has stopped, and is still running.
  ///
  /// This served `needsPerson`, `offline` and `blocked` as a bare `Container` — the three
  /// states that outlast every other, each of which speaks its line once and then never
  /// again. Offline ends when the network returns, `needsPerson` when somebody who is not
  /// the team walks over, and `blocked` is the first screen the app ever shows on that
  /// path. A team glancing up at any of them had nothing to tell a room that is waiting
  /// from one that has died.
  ///
  /// Slower and shallower than an invite on purpose: the colour and the glyph already say
  /// this is not a turn to take. The breath only says the app is still there.
  Widget _haltedBody(SalaColors colors, IconData? glyph) {
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
          child: glyph == null
              ? null
              : Icon(glyph, size: size * 0.28, color: colors.mut),
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

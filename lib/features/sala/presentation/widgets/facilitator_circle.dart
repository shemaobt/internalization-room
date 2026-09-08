import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../domain/room_reach.dart';
import '../../domain/session_state.dart';
import 'bead.dart';
import 'bead_styles.dart';
import 'motion.dart';

class FacilitatorCircle extends StatelessWidget {
  final double size;
  final VoiceState voice;
  final RoomReach reach;
  final bool noteMode;
  final bool peerCue;
  final bool beckon;

  /// Whether the open microphone is taking down the team's own tongue.
  ///
  /// Correcting a stretch can cost two recordings in a row — the mother tongue first, the
  /// telling of it in the bridge language after — and both are the same
  /// `VoiceState.listening`. Blue belongs to the telling, the voice that travels to the
  /// analyst; the team's own voice is wood, the colour their recordings already wear on
  /// the cord. Read while listening and nowhere else: which tongue is being taken down
  /// says nothing about a room that is thinking, waiting or done.
  final bool motherTongue;

  /// Whether the server's last word was a warning rather than silence.
  ///
  /// The room has no text on screen, so the only way to show a warning is the colour
  /// it already wears when a passage is done: green asks nobody to stop, only to
  /// notice. Read only while [voice] is not one of the halted states — a room the
  /// team cannot use yet is still a stop, whatever the last warning said.
  final bool warning;
  final double opacity;
  final Widget? child;
  final String semanticLabel;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const FacilitatorCircle({
    super.key,
    required this.size,
    required this.voice,
    this.reach = RoomReach.fine,
    required this.semanticLabel,
    this.noteMode = false,
    this.peerCue = false,
    this.motherTongue = false,
    this.beckon = false,
    this.warning = false,
    this.opacity = 1,
    this.child,
    this.onTap,
    this.onLongPress,
  });

  bool get _teamTalk => peerCue && voice == VoiceState.invite;

  /// The ink of the open microphone: the ring that says it is open, and the rings closing
  /// in on it. Both draw the same line, so both read the tongue from here.
  Color get _openMicInk => motherTongue ? ShemaBrand.woodLo : ShemaBrand.azulInk;

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
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
                _body(colors),
                if (voice == VoiceState.speaking) ..._ripples(colors),
                if (voice == VoiceState.listening) _listenRing(colors),
                if (child != null && voice != VoiceState.listening) child!,
                if (voice == VoiceState.listening) ..._gatheringIn(),
                if (voice == VoiceState.listening && noteMode)
                  KnotMark(size: size * 0.16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _ripples(SalaColors colors) {
    Widget ring(double phase) => Ripple(
          period: const Duration(milliseconds: 1600),
          phase: phase,
          builder: (context, t) => Transform.scale(
            scale: 1 + 0.46 * t,
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

  Widget _body(SalaColors colors) {
    if (voice == VoiceState.needsPerson) return _haltedBody(colors, LucideIcons.userCheck);
    if (voice == VoiceState.offline) return _haltedBody(colors, _offlineGlyph);
    if (warning && !_halted) return _doneDisc();
    if (_teamTalk) return _teamTalkBody(colors);

    switch (voice) {
      case VoiceState.invite:
        return Loop(
          period: Duration(milliseconds: beckon ? 1800 : 4600),
          builder: (context, t) => Transform.scale(
            scale: 1 + (beckon ? 0.09 : 0.045) * t,
            child: _liveDisc(colors),
          ),
        );
      case VoiceState.listening:
        return _disc(
          gradient: motherTongue ? BeadStyles.wood : BeadStyles.azul,
          shadows: [
            BoxShadow(
              color: (motherTongue ? ShemaBrand.woodLo : ShemaBrand.azulLo)
                  .withValues(alpha: 0.3),
              offset: const Offset(0, 10),
              blurRadius: 30,
            ),
          ],
        );
      case VoiceState.thinking:
        return Loop(
          period: const Duration(milliseconds: 2600),
          builder: (context, t) => Transform.scale(
            scale: 1 + 0.06 * t,
            child: _disc(
              gradient: BeadStyles.clay(colors, t),
              shadows: [
                const BoxShadow(
                  color: Color(0x260A0703),
                  offset: Offset(0, 6),
                  blurRadius: 20,
                ),
                BoxShadow(
                  color: colors.clayHi.withValues(alpha: 0.30 * t),
                  spreadRadius: 2 + 10 * t,
                  blurRadius: 18,
                ),
              ],
            ),
          ),
        );
      case VoiceState.speaking:
        return Loop(
          period: const Duration(milliseconds: 900),
          builder: (context, t) => Transform.scale(
            scale: 1 + 0.02 * t,
            child: _liveDisc(colors),
          ),
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

  Widget _liveDisc(SalaColors colors) => _disc(
        gradient: noteMode ? BeadStyles.azul : BeadStyles.telha(colors),
        shadows: [
          BoxShadow(
            color: (noteMode ? ShemaBrand.azulLo : colors.telha)
                .withValues(alpha: 0.32),
            offset: const Offset(0, 10),
            blurRadius: 34,
          ),
        ],
      );

  Widget _teamTalkBody(SalaColors colors) {
    return Loop(
      period: const Duration(milliseconds: 4600),
      builder: (context, t) => Transform.scale(
        scale: 1 + 0.045 * t,
        child: Stack(
          alignment: Alignment.center,
          children: [
            _disc(
              gradient: BeadStyles.azul,
              shadows: [
                BoxShadow(
                  color: ShemaBrand.azulLo.withValues(alpha: 0.32),
                  offset: const Offset(0, 10),
                  blurRadius: 30,
                ),
              ],
            ),
            Icon(LucideIcons.users, size: size * 0.3, color: ShemaBrand.branco),
          ],
        ),
      ),
    );
  }

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
            gradient: BeadStyles.clay(colors, 0),
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

  Widget _listenRing(SalaColors colors) {
    final halo = motherTongue ? ShemaBrand.wood : ShemaBrand.azul;
    return Loop(
      period: const Duration(milliseconds: 1600),
      builder: (context, t) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: _openMicInk, width: 3),
          boxShadow: [
            BoxShadow(
              color: halo.withValues(alpha: 0.5 * (1 - t)),
              spreadRadius: 4 + 12 * t,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _gatheringIn() {
    Widget ring(double phase) => Ripple(
          period: const Duration(milliseconds: 1900),
          phase: phase,
          builder: (context, t) => Transform.scale(
            scale: 1.46 - 0.46 * t,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _openMicInk.withValues(alpha: 0.55 * t),
                  width: 2.5,
                ),
              ),
            ),
          ),
        );
    return [ring(0), ring(0.5)];
  }
}

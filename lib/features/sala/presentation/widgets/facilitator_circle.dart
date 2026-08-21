import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../domain/session_state.dart';
import 'bead.dart';
import 'bead_styles.dart';
import 'motion.dart';

class FacilitatorCircle extends StatelessWidget {
  final double size;
  final VoiceState voice;
  final bool noteMode;
  final bool peerCue;
  final bool beckon;
  final double opacity;
  final Widget? child;
  final String semanticLabel;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const FacilitatorCircle({
    super.key,
    required this.size,
    required this.voice,
    required this.semanticLabel,
    this.noteMode = false,
    this.peerCue = false,
    this.beckon = false,
    this.opacity = 1,
    this.child,
    this.onTap,
    this.onLongPress,
  });

  bool get _teamTalk => peerCue && voice == VoiceState.invite;

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
                if (voice == VoiceState.speaking) ..._ripples(colors),
                if (beckon) ..._beckoning(colors),
                _body(colors),
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

  Widget _body(SalaColors colors) {
    if (voice == VoiceState.needsPerson) return _haltedBody(colors, LucideIcons.userCheck);
    if (voice == VoiceState.offline) return _haltedBody(colors, null);
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
          gradient: BeadStyles.azul,
          shadows: [
            BoxShadow(
              color: ShemaBrand.azulLo.withValues(alpha: 0.3),
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
        return _disc(
          gradient: BeadStyles.verde,
          shadows: [
            BoxShadow(
              color: ShemaBrand.verdeLo.withValues(alpha: 0.28),
              offset: const Offset(0, 10),
              blurRadius: 34,
            ),
          ],
        );
      case VoiceState.needsPerson:
        return _haltedBody(colors, LucideIcons.userCheck);
      case VoiceState.offline:
        return _haltedBody(colors, null);
    }
  }

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
    return Stack(
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
    );
  }

  Widget _haltedBody(SalaColors colors, IconData? glyph) {
    return Container(
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
    const ringColor = ShemaBrand.azulInk;
    return Loop(
      period: const Duration(milliseconds: 1600),
      builder: (context, t) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: ringColor, width: 3),
          boxShadow: [
            BoxShadow(
              color: ShemaBrand.azul.withValues(alpha: 0.5 * (1 - t)),
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
                  color: ShemaBrand.azulInk.withValues(alpha: 0.55 * t),
                  width: 2.5,
                ),
              ),
            ),
          ),
        );
    return [ring(0), ring(0.5)];
  }
}

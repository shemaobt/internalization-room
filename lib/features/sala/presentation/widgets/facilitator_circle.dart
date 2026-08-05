import 'package:flutter/material.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../domain/session_state.dart';
import 'bead_styles.dart';
import 'motion.dart';

class FacilitatorCircle extends StatelessWidget {
  final double size;
  final VoiceState voice;
  final bool azulMode;
  final bool showListenDot;
  final double opacity;
  final Widget? child;
  final String semanticLabel;
  final VoidCallback? onTap;
  final VoidCallback? onHoldStart;
  final VoidCallback? onHoldEnd;
  final VoidCallback? onHoldCancel;

  const FacilitatorCircle({
    super.key,
    required this.size,
    required this.voice,
    required this.semanticLabel,
    this.azulMode = false,
    this.showListenDot = false,
    this.opacity = 1,
    this.child,
    this.onTap,
    this.onHoldStart,
    this.onHoldEnd,
    this.onHoldCancel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    return AnimatedOpacity(
      opacity: opacity,
      duration: const Duration(milliseconds: 500),
      child: Semantics(
        button: true,
        label: semanticLabel,
        child: Listener(
          onPointerDown: onHoldStart == null ? null : (_) => onHoldStart!(),
          onPointerUp: onHoldEnd == null ? null : (_) => onHoldEnd!(),
          onPointerCancel:
              onHoldCancel == null ? null : (_) => onHoldCancel!(),
          child: GestureDetector(
            onTap: onTap,
            child: SizedBox(
              width: size,
              height: size,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  if (voice == VoiceState.speaking) ..._ripples(colors),
                  _body(colors),
                  if (voice == VoiceState.listening) _listenRing(colors),
                  if (child != null && voice != VoiceState.listening) child!,
                  if (showListenDot) _listenDot(colors),
                ],
              ),
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
            scale: 0.92 + 0.53 * t,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: colors.halo.withValues(
                    alpha: colors.halo.a * (1 - t),
                  ),
                  width: 2,
                ),
              ),
            ),
          ),
        );
    return [ring(0), ring(0.65)];
  }

  Widget _body(SalaColors colors) {
    switch (voice) {
      case VoiceState.invite:
        return Loop(
          period: const Duration(milliseconds: 4600),
          builder: (context, t) => Transform.scale(
            scale: 1 + 0.045 * t,
            child: _disc(
              gradient: azulMode ? BeadStyles.azul : BeadStyles.telha(colors),
              shadows: [
                BoxShadow(
                  color: colors.telha.withValues(alpha: 0.32),
                  offset: const Offset(0, 10),
                  blurRadius: 34,
                ),
              ],
            ),
          ),
        );
      case VoiceState.listening:
        return _disc(background: colors.paper);
      case VoiceState.thinking:
        return Loop(
          period: const Duration(milliseconds: 2600),
          builder: (context, t) => _disc(
            gradient: BeadStyles.clay(colors, t),
            shadows: const [
              BoxShadow(
                color: Color(0x260A0703),
                offset: Offset(0, 6),
                blurRadius: 20,
              ),
            ],
          ),
        );
      case VoiceState.speaking:
        return Loop(
          period: const Duration(milliseconds: 1000),
          builder: (context, t) => Transform.scale(
            scale: 1 + 0.02 * t,
            child: _disc(
              gradient: azulMode ? BeadStyles.azul : BeadStyles.telha(colors),
              shadows: [
                BoxShadow(
                  color: colors.telha.withValues(alpha: 0.32),
                  offset: const Offset(0, 10),
                  blurRadius: 34,
                ),
              ],
            ),
          ),
        );
    }
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
    final ringColor = azulMode ? ShemaBrand.azul : colors.telha;
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
              color: colors.halo.withValues(alpha: colors.halo.a * (1 - t)),
              spreadRadius: 4 + 12 * t,
            ),
          ],
        ),
      ),
    );
  }

  Widget _listenDot(SalaColors colors) {
    return Loop(
      period: const Duration(milliseconds: 1100),
      builder: (context, t) => Transform.scale(
        scale: 1 + 0.12 * t,
        child: Opacity(
          opacity: 1 - 0.15 * t,
          child: Container(
            width: size * 0.135,
            height: size * 0.135,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.telha,
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../../core/theme/sala_colors.dart';
import 'motion.dart';

abstract class BeadStyles {
  static const _beadCenter = Alignment(-0.3, -0.4);

  static const wood = RadialGradient(
    center: _beadCenter,
    radius: 1.1,
    colors: [ShemaBrand.woodHi, ShemaBrand.wood, ShemaBrand.woodLo],
    stops: [0, 0.55, 1],
  );

  static const azul = RadialGradient(
    center: _beadCenter,
    radius: 1.1,
    colors: [ShemaBrand.azulHi, ShemaBrand.azul, ShemaBrand.azulLo],
    stops: [0, 0.55, 1],
  );

  static const verde = RadialGradient(
    center: _beadCenter,
    radius: 1.1,
    colors: [ShemaBrand.verdeHi, ShemaBrand.verdeClaro, ShemaBrand.verdeLo],
    stops: [0, 0.6, 1],
  );

  static RadialGradient oat(SalaColors colors) => RadialGradient(
    center: _beadCenter,
    radius: 1.0,
    colors: [colors.oatHi, colors.oat],
    stops: const [0, 0.7],
  );

  static RadialGradient clay(SalaColors colors) => RadialGradient(
    center: _beadCenter,
    radius: 1.0,
    colors: [colors.clayHi, colors.clay],
    stops: const [0, 0.7],
  );

  static RadialGradient telha(SalaColors colors) => RadialGradient(
    center: const Alignment(-0.32, -0.4),
    radius: 1.0,
    colors: [Color.lerp(colors.telha, ShemaBrand.branco, 0.28)!, colors.telha],
    stops: const [0, 0.68],
  );

  static const matte = [
    BoxShadow(color: Color(0x330A0703), offset: Offset(0, 1), blurRadius: 3),
  ];
}

/// A round button's state: lit answers a tap, dimmed stays in place and refuses,
/// beckoning is lit with a pulsing halo asking to be pressed.
enum ButtonMood { lit, dimmed, beckoning }

class RoundActionButton extends StatelessWidget {
  final double size;
  final VoidCallback onTap;
  final Widget? child;
  final Gradient? gradient;
  final Color? background;
  final BoxBorder? border;
  final List<BoxShadow>? shadows;
  final String semanticLabel;
  final VoidCallback? onLongPress;
  final ButtonMood mood;
  final Color halo;

  const RoundActionButton({
    super.key,
    required this.size,
    required this.onTap,
    required this.semanticLabel,
    this.child,
    this.gradient,
    this.background,
    this.border,
    this.shadows,
    this.onLongPress,
    this.mood = ButtonMood.lit,
    this.halo = ShemaBrand.verdeClaro,
  });

  bool get _live => mood != ButtonMood.dimmed;

  Widget _button(double t) => Semantics(
    button: true,
    enabled: _live,
    label: semanticLabel,
    child: AnimatedOpacity(
      opacity: _live ? 1 : 0.35,
      duration: const Duration(milliseconds: 300),
      child: GestureDetector(
        onTap: _live ? onTap : null,
        onLongPress: _live ? onLongPress : null,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: gradient,
            color: background,
            border: border,
            boxShadow: mood == ButtonMood.lit
                ? shadows
                : [
                    ...?shadows,
                    const BoxShadow(
                      color: Color(0x330A0703),
                      offset: Offset(0, 4),
                      blurRadius: 12,
                    ),
                    BoxShadow(
                      color: halo.withValues(alpha: 0.35 * (1 - t)),
                      spreadRadius: 12 * t,
                    ),
                  ],
          ),
          child: child == null ? null : Center(child: child),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (mood == ButtonMood.lit) return _button(0);
    return FadeUp(
      child: Loop(
        period: const Duration(milliseconds: 2400),
        animate: mood == ButtonMood.beckoning,
        builder: (context, t) => _button(t),
      ),
    );
  }
}

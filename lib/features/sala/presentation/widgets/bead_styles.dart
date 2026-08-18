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

  static RadialGradient clay(SalaColors colors, double glow) => RadialGradient(
    center: _beadCenter,
    radius: 1.0,
    colors: [
      Color.lerp(colors.clayHi, Colors.white, glow * 0.14)!,
      Color.lerp(colors.clay, Colors.white, glow * 0.14)!,
    ],
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

class RoundActionButton extends StatelessWidget {
  final double size;
  final VoidCallback onTap;
  final Widget child;
  final Gradient? gradient;
  final Color? background;
  final Border? border;
  final List<BoxShadow>? shadows;
  final String semanticLabel;

  const RoundActionButton({
    super.key,
    required this.size,
    required this.onTap,
    required this.child,
    required this.semanticLabel,
    this.gradient,
    this.background,
    this.border,
    this.shadows,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: gradient,
            color: background,
            border: border,
            boxShadow: shadows,
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class AdvanceButton extends StatelessWidget {
  final double size;
  final VoidCallback onTap;
  final Gradient gradient;
  final Widget? child;
  final String semanticLabel;
  final Color halo;
  final BoxBorder? border;

  /// Whether the touch is live yet.
  ///
  /// A button that leaves the tree while the room speaks takes its own hit box with it,
  /// so a finger already on the way lands on nothing at all. It stays, dimmed and deaf,
  /// and comes back without moving.
  final bool ready;

  const AdvanceButton({
    super.key,
    required this.onTap,
    required this.gradient,
    required this.semanticLabel,
    this.size = 64,
    this.child,
    this.halo = ShemaBrand.verdeClaro,
    this.border,
    this.ready = true,
  });

  @override
  Widget build(BuildContext context) {
    return FadeUp(
      child: Loop(
        period: const Duration(milliseconds: 2400),
        animate: ready,
        builder: (context, t) => Semantics(
          button: true,
          enabled: ready,
          label: semanticLabel,
          child: AnimatedOpacity(
            opacity: ready ? 1 : 0.35,
            duration: const Duration(milliseconds: 300),
            child: GestureDetector(
              onTap: ready ? onTap : null,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: gradient,
                  border: border,
                  boxShadow: [
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
                child: Center(child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

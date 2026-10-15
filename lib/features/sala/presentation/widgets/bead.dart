import 'package:flutter/material.dart';

import '../../../../core/theme/sala_colors.dart';
import 'bead_styles.dart';

class Bead extends StatelessWidget {
  final double size;
  final double opacity;
  final Border? border;
  final bool filled;

  /// Whether this is the one bead of the row the screen is singling out.
  final bool marcada;

  const Bead({
    super.key,
    required this.size,
    this.opacity = 1,
    this.border,
    this.filled = true,
    this.marcada = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    return Opacity(
      opacity: marcada ? 1 : opacity,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: filled ? BeadStyles.wood : BeadStyles.oat(colors),
          boxShadow: BeadStyles.matte,
          border: marcada
              ? Border.all(color: colors.telha, width: 2)
              : border ?? (filled ? null : Border.all(color: colors.line)),
        ),
      ),
    );
  }
}

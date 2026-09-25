import 'package:flutter/material.dart';

import '../../../../core/theme/sala_colors.dart';
import 'bead_styles.dart';

enum BeadFill { translucent, solid, drained }

class BeadRowEntry {
  final BeadFill fill;
  final bool current;
  final String semanticLabel;

  const BeadRowEntry({
    required this.fill,
    this.current = false,
    required this.semanticLabel,
  });
}

class BeadRow extends StatelessWidget {
  static const _beadSize = 28.0;
  static const _ringSize = 40.0;
  static const _gap = 16.0;

  final List<BeadRowEntry> entries;
  final ValueChanged<int> onTap;

  const BeadRow({super.key, required this.entries, required this.onTap});

  double _opacityOf(BeadFill fill) => fill == BeadFill.translucent ? 0.3 : 1;

  Gradient _gradientOf(BeadFill fill, SalaColors colors) =>
      fill == BeadFill.drained ? BeadStyles.oat(colors) : BeadStyles.wood;

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var index = 0; index < entries.length; index++) ...[
          if (index > 0) const SizedBox(width: _gap),
          _bead(entries[index], index, colors),
        ],
      ],
    );
  }

  Widget _bead(BeadRowEntry entry, int index, SalaColors colors) {
    final bead = Opacity(
      opacity: _opacityOf(entry.fill),
      child: Container(
        width: _beadSize,
        height: _beadSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: _gradientOf(entry.fill, colors),
          boxShadow: BeadStyles.matte,
        ),
      ),
    );
    return Semantics(
      button: true,
      label: entry.semanticLabel,
      child: GestureDetector(
        onTap: () => onTap(index),
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: _ringSize,
          height: _ringSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              bead,
              if (entry.current)
                Container(
                  width: _ringSize,
                  height: _ringSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: ShemaBrand.telha, width: 2.5),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../domain/session_state.dart';
import 'bead_styles.dart';
import 'motion.dart';

const _beadSize = 9.0;
const _beadGap = 11.0;

class ColarOverlay extends StatelessWidget {
  final SalaSessionState session;

  const ColarOverlay({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final total = session.coverage.beadsTotal;
          final row = total * _beadSize + (total - 1) * _beadGap;
          final left = (constraints.maxWidth - row) / 2;
          final top =
              constraints.maxHeight -
              MediaQuery.sizeOf(context).height * 0.09 -
              _beadSize;

          return Stack(
            children: [
              for (var i = 0; i < total; i++)
                _bead(
                  context,
                  colors,
                  i,
                  Offset(left + i * (_beadSize + _beadGap), top),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _bead(BuildContext context, SalaColors colors, int i, Offset at) {
    final total = session.coverage.beadsTotal;
    final lit = i < session.coverage.beadsFilled;

    BoxDecoration decoration;
    if (lit) {
      decoration = BoxDecoration(
        shape: BoxShape.circle,
        gradient: BeadStyles.wood,
        boxShadow: [
          ...BeadStyles.matte,
          BoxShadow(
            color: ShemaBrand.wood.withValues(alpha: 0.25),
            spreadRadius: 3,
          ),
        ],
      );
    } else {
      decoration = BoxDecoration(
        shape: BoxShape.circle,
        gradient: BeadStyles.oat(colors),
        border: Border.all(color: colors.line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A0A0703),
            offset: Offset(0, 1),
            blurRadius: 2,
          ),
        ],
      );
    }

    final bead = SizedBox(
      width: _beadSize,
      height: _beadSize,
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 1300),
        decoration: decoration,
      ),
    );

    return AnimatedPositioned(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 900),
      curve: Curves.easeInOut,
      left: at.dx,
      top: at.dy,
      child: ThreadIn(index: i, total: total, child: bead),
    );
  }
}

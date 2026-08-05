import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/meaning_map.dart';
import '../../domain/session_state.dart';
import 'bead_styles.dart';
import 'facilitator_circle.dart';
import 'motion.dart';

class RetroView extends ConsumerWidget {
  const RetroView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(salaSessionProvider);
    final notifier = ref.read(salaSessionProvider.notifier);
    final colors = SalaColors.of(context);
    final listening = session.retroPhase == RetroPhase.ouvir;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < RuthOneMeaningMap.segmentCount; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: _retroBead(colors, session, i, listening),
              ),
          ],
        ),
        const SizedBox(height: 46),
        FacilitatorCircle(
          size: 150,
          voice: session.voice,
          showListenDot: session.showListenDot,
          opacity: listening && session.voice == VoiceState.invite ? 0.35 : 1,
          semanticLabel: 'Segurar para contar em português',
          onHoldStart: notifier.retroHoldStart,
          onHoldEnd: notifier.retroHoldEnd,
          onHoldCancel: notifier.holdCancel,
        ),
      ],
    );
  }

  Widget _retroBead(
    SalaColors colors,
    SalaSessionState session,
    int i,
    bool listening,
  ) {
    final fill = session.fills[i];
    final current = i == session.retroIndex;
    final size = current ? 46.0 : 34.0;

    BoxDecoration decoration;
    if (fill == 2) {
      decoration = const BoxDecoration(
        shape: BoxShape.circle,
        gradient: BeadStyles.wood,
        boxShadow: BeadStyles.matte,
      );
    } else if (fill == 1) {
      decoration = BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [ShemaBrand.wood, ShemaBrand.wood, colors.card, colors.card],
          stops: const [0, 0.5, 0.5, 1],
        ),
        border: Border.all(color: colors.cord, width: 2),
      );
    } else {
      decoration = BoxDecoration(
        shape: BoxShape.circle,
        gradient: BeadStyles.oat(colors),
        border: Border.all(color: colors.line),
      );
    }

    final highlighted = current && listening;
    final bead = AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      width: size,
      height: size,
      decoration: highlighted
          ? decoration.copyWith(
              boxShadow: [
                ...?decoration.boxShadow,
                BoxShadow(color: colors.halo, spreadRadius: 5),
              ],
            )
          : decoration,
    );
    if (!highlighted) return bead;
    return Loop(
      period: const Duration(milliseconds: 1400),
      builder: (context, t) =>
          Transform.scale(scale: 1 + 0.12 * t, child: bead),
    );
  }
}

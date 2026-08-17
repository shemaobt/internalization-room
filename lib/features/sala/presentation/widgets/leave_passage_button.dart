import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/session_state.dart';

/// The way out of a passage the team no longer wants to work.
///
/// It sits below the necklace on the left — the four corners are already spoken for by
/// the hand, the hear-again button and the two ends of the cord. It is cord-coloured, not
/// wood: wood means advance everywhere else in the room, and leaving is not advancing.
class LeavePassageButton extends ConsumerWidget {
  const LeavePassageButton({super.key});

  static const _inside = {
    SalaStage.conversa,
    SalaStage.ensaio,
    SalaStage.retro,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(salaSessionProvider);
    if (!_inside.contains(session.stage)) return const SizedBox.shrink();
    final colors = SalaColors.of(context);

    return Positioned(
      left: 14,
      top: 118 + MediaQuery.viewPaddingOf(context).top,
      child: Semantics(
        button: true,
        label: 'Deixar esta passagem e escolher outra',
        child: GestureDetector(
          onTap: ref.read(salaSessionProvider.notifier).leaveThePassage,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.oat,
              border: Border.all(color: colors.cord, width: 2),
            ),
            child: Icon(LucideIcons.undo2, size: 20, color: colors.mut),
          ),
        ),
      ),
    );
  }
}

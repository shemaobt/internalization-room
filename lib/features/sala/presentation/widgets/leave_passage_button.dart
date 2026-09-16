import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/session_state.dart';

class LeavePassageButton extends ConsumerWidget {
  const LeavePassageButton({super.key});

  static const _inside = {
    SalaStage.conversa,
    SalaStage.ensaio,
    SalaStage.retro,
  };

  static const _busy = {
    VoiceState.listening,
    VoiceState.thinking,
    VoiceState.speaking,
    VoiceState.needsPerson,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(salaSessionProvider);
    if (!_inside.contains(session.stage)) return const SizedBox.shrink();
    final colors = SalaColors.of(context);

    // A halt at the resting screen is the one halt the team can walk out of: the release
    // was refused, the room is calling a person, and the passage they are held in is
    // exactly what this way out leads away from. No station of the room is a dead end.
    final paradaNaConferida = session.voice == VoiceState.needsPerson &&
        session.btPhase == BtPhase.conferida;
    final away = _busy.contains(session.voice) && !paradaNaConferida;

    return Positioned(
      left: 14,
      top: 118 + MediaQuery.viewPaddingOf(context).top,
      child: IgnorePointer(
        ignoring: away,
        child: AnimatedOpacity(
          opacity: away ? 0 : 1,
          duration: const Duration(milliseconds: 400),
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
        ),
      ),
    );
  }
}

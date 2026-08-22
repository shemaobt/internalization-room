import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/session_state.dart';
import 'bead.dart';
import 'bead_styles.dart';
import 'facilitator_circle.dart';
import 'motion.dart';

class RetroView extends ConsumerWidget {
  const RetroView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(salaSessionProvider);
    final notifier = ref.read(salaSessionProvider.notifier);
    final conferida = session.btPhase == BtPhase.conferida;
    final clipRunning =
        session.btPhase == BtPhase.playing && !session.btClipEnded;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ChunkBeads(
          passes: session.btChunkPasses,
          unsent: session.unsentChunks,
        ),
        const SizedBox(height: 46),
        SizedBox(
          width: 200,
          height: 200,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (clipRunning) const _ClipHalo(),
              FacilitatorCircle(
                size: 150,
                voice: conferida ? VoiceState.done : session.voice,
                      semanticLabel: _circleLabel(session),
                onTap: notifier.retroTap,
              onLongPress: notifier.resolveWithPerson,
              ),
            ],
          ),
        ),
        const SizedBox(height: 44),
        SizedBox(
          height: 64,
          child: _actions(session, notifier),
        ),
      ],
    );
  }

  Widget? _actions(SalaSessionState session, SalaSessionNotifier notifier) {
    if (session.btPhase == BtPhase.findings) {
      return FadeUp(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RoundActionButton(
              size: 60,
              semanticLabel: 'Ouvir e contar esta parte de novo',
              gradient: BeadStyles.wood,
              onTap: notifier.retellChunk,
              child: const Icon(
                LucideIcons.rotateCcw,
                size: 24,
                color: ShemaBrand.branco,
              ),
            ),
            const SizedBox(width: 28),
            RoundActionButton(
              size: 60,
              semanticLabel: 'Gravar esta parte de novo',
              gradient: BeadStyles.azul,
              onTap: notifier.reRecordClip,
              child: const Icon(
                LucideIcons.mic,
                size: 24,
                color: ShemaBrand.branco,
              ),
            ),
          ],
        ),
      );
    }
    if (session.canFinishBackTranslation) {
      return AdvanceButton(
        gradient: BeadStyles.verde,
        semanticLabel: 'Terminei de contar de volta',
        onTap: notifier.finishBackTranslation,
        child: const Icon(
          LucideIcons.check,
          size: 26,
          color: ShemaBrand.branco,
        ),
      );
    }
    return null;
  }

  String _circleLabel(SalaSessionState session) {
    switch (session.btPhase) {
      case BtPhase.playing:
        return 'Tocar para contar este pedaço em português';
      case BtPhase.capturing:
        return 'Tocar ao terminar o pedaço';
      case BtPhase.thinking:
      case BtPhase.findings:
      case BtPhase.conferida:
        return 'Contada de volta';
    }
  }
}

class _ClipHalo extends StatelessWidget {
  const _ClipHalo();

  @override
  Widget build(BuildContext context) {
    return Loop(
      period: const Duration(milliseconds: 2200),
      builder: (context, t) => Container(
        width: 176 + 8 * t,
        height: 176 + 8 * t,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: ShemaBrand.azul.withValues(alpha: 0.55 - 0.25 * t),
            width: 2,
          ),
        ),
      ),
    );
  }
}

class _ChunkBeads extends StatelessWidget {
  final List<int> passes;
  final int unsent;

  const _ChunkBeads({required this.passes, required this.unsent});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < passes.length; index++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7),
              child: PingIn(
                child: Bead(
                  size: 26,
                  filled: true,
                  border: passes[index] > 1
                      ? Border.all(color: ShemaBrand.azulInk, width: 2.5)
                      : null,
                ),
              ),
            ),
          for (var waiting = 0; waiting < unsent; waiting++)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 7),
              child: Bead(size: 26, filled: false),
            ),
        ],
      ),
    );
  }
}

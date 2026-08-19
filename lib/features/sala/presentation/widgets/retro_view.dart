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
    final colors = SalaColors.of(context);
    final conferida = session.btPhase == BtPhase.conferida;
    final clipRunning = (session.btPhase == BtPhase.playing &&
            !session.btClipEnded &&
            !session.btParteFronteira) ||
        session.btTrechoTocando;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ChunkBeads(
          passes: session.btChunkPasses,
          failures: session.btChunkFailures,
          colors: colors,
        ),
        const SizedBox(height: 46),
        SizedBox(
          width: 200,
          height: 200,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (clipRunning) _ClipHalo(colors: colors),
              FacilitatorCircle(
                size: 150,
                voice: conferida ? VoiceState.done : session.voice,
                      semanticLabel: _circleLabel(session),
                onTap: notifier.retroTap,
              onLongPress: session.canResolveWithPerson
              ? notifier.resolveWithPerson
              : null,
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
    if (session.btPhase == BtPhase.playing &&
        session.btParteFronteira &&
        !session.btClipEnded) {
      return AdvanceButton(
        gradient: BeadStyles.wood,
        semanticLabel: 'Ouvir a proxima parte da gravacao',
        onTap: notifier.proximaParte,
        child: const Icon(
          LucideIcons.skipForward,
          size: 26,
          color: ShemaBrand.branco,
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
      case BtPhase.findings:
        return 'Ouvir de novo a parte apontada';
      case BtPhase.thinking:
        return 'Um instante';
      case BtPhase.conferida:
        return 'Contada de volta';
    }
  }
}

class _ClipHalo extends StatelessWidget {
  final SalaColors colors;

  const _ClipHalo({required this.colors});

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

/// One bead per stretch the team told, in the order they told them.
///
/// A stretch that landed is filled; one the room never took is hollow, and sits where it
/// was actually told rather than at the end of the row. Subtracting a count of failures
/// from a list of successes drew neither: the two never described the same stretch.
class _ChunkBeads extends StatelessWidget {
  final List<int> passes;
  final List<int> failures;
  final SalaColors colors;

  const _ChunkBeads({
    required this.passes,
    required this.failures,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    var told = 0;
    return SizedBox(
      height: 44,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var place = 1; place <= passes.length + failures.length; place++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7),
              child: PingIn(
                child: failures.contains(place)
                    ? const Bead(size: 26, filled: false)
                    : Bead(
                        size: 26,
                        filled: true,
                        border: passes[told++] > 1
                            ? Border.all(color: ShemaBrand.azulInk, width: 2.5)
                            : null,
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/bt_finding.dart';
import '../../domain/session_state.dart';
import 'bead_styles.dart';
import 'onde_mora_grade.dart';
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
    final clipRunning = session.btClipRodando || session.btTrechoTocando;

    // The question is its own composition, not a row of buttons under the usual circle:
    // the grid is the screen, and the room's voice steps back to make room for it.
    if (session.btPhase == BtPhase.findings && session.btFindingTrecho != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FacilitatorCircle(
            size: 54,
            voice: session.voice,
            warning: session.warning,
            semanticLabel: _circleLabel(session),
            onTap: notifier.retroTap,
            onLongPress:
                session.canResolveWithPerson ? notifier.resolveWithPerson : null,
          ),
          const SizedBox(height: 46),
          OndeMoraGrade(
            onOuvirMaterna: notifier.ouvirVozMaterna,
            onOuvirRetro: notifier.ouvirTraducaoEmPortugues,
            onRegravarMaterna: notifier.regravarAVozMaterna,
            onTraduzirDeNovo: notifier.traduzirDeNovoEmPortugues,
            tocandoMaterna: session.btTrechoTocando,
            tocandoRetro: session.btRetroTocando,
            podeOuvirRetro: session.btFindingTrecho?.retroPath != null,
            offline: session.offline,
            onCortar: session.btTrechoTocando
                ? () => unawaited(notifier.dividirTrecho())
                : null,
          ),
        ],
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
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
                warning: session.warning,
                motherTongue: session.btPhase == BtPhase.gravandoMaterna,
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

  IconData _listenGlyph(SalaSessionState session) {
    if (session.btClipRodando) return LucideIcons.pause;
    if (session.btParteFronteira) return LucideIcons.skipForward;
    return LucideIcons.play;
  }

  String _listenLabel(SalaSessionState session) {
    if (session.btClipRodando) return 'Pausar a gravação';
    if (session.btParteFronteira) return 'Ouvir a próxima parte da gravação';
    return 'Ouvir a gravação';
  }

  IconData _tellGlyph(SalaSessionState session) =>
      session.btClipRodando ? LucideIcons.scissors : LucideIcons.mic;

  String _tellLabel(SalaSessionState session) => session.btClipRodando
      ? 'Cortar aqui e traduzir esta parte'
      : 'Traduzir esta parte na língua ponte';

  Widget? _actions(SalaSessionState session, SalaSessionNotifier notifier) {
    if (session.btPhase == BtPhase.findings) {
      // Which voice needs to speak again is the team's to say. It used to be read off the
      // kind of finding, and the team was never asked, on the one question only they can
      // answer.
      // With no stretch to ask about, the question cannot be put, and the room falls back
      // to what it always did — including reading the kind: telling the whole recording
      // again settles nothing a re-recording kind names, and the pointer being absent must
      // not smuggle that offer back in.
      final retellingCanSettleIt =
          !session.btFindings.any((finding) => finding.exitsByReRecording);
      return FadeUp(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (retellingCanSettleIt) ...[
              RoundActionButton(
                size: 60,
                semanticLabel: 'Ouvir e traduzir a gravação de novo',
                gradient: BeadStyles.wood,
                onTap: notifier.startRetro,
                child: const Icon(
                  LucideIcons.rotateCcw,
                  size: 24,
                  color: ShemaBrand.branco,
                ),
              ),
              const SizedBox(width: 28),
            ],
            // Back to the rehearsal with the takes, the stretches and the colar kept: a
            // finding of something missing that fits in no stretch is the end of the
            // story never recorded, and what it asks for is more recording, not the
            // recording again. Starting the clip over — the room retiring it, the
            // rehearsal emptied — is `reRecordClip`, which no button on this screen
            // reaches any more.
            RoundActionButton(
              size: 60,
              semanticLabel: 'Gravar esta parte de novo',
              gradient: BeadStyles.azul,
              onTap: notifier.continuarOEnsaio,
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
    if (session.btPhase == BtPhase.conferida) {
      // The room stays open after a clean verdict: the voice invites one last listening
      // and then the approval, and the passage is not finished until the team presses.
      return FadeUp(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RoundActionButton(
              size: 60,
              semanticLabel: _listenLabel(session),
              gradient: BeadStyles.wood,
              onTap: notifier.ouvirGravacao,
              child: Icon(
                _listenGlyph(session),
                size: 24,
                color: ShemaBrand.branco,
              ),
            ),
            const SizedBox(width: 28),
            RoundActionButton(
              size: 60,
              semanticLabel: 'Aprovar como rascunho final',
              gradient: BeadStyles.verde,
              onTap: notifier.aprovarRascunhoFinal,
              child: const Icon(
                LucideIcons.award,
                size: 24,
                color: ShemaBrand.branco,
              ),
            ),
          ],
        ),
      );
    }
    if (session.btPhase == BtPhase.playing && !session.btTrechoTocando) {
      // Two gestures, one meaning each. They were a single tap on the circle — listen,
      // cut, and hand the microphone over all at once — and the room could only guess how
      // much of the rehearsal a team had actually heard.
      return FadeUp(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (session.canFinishBackTranslation)
              RoundActionButton(
                size: 60,
                semanticLabel: 'Terminei de traduzir',
                gradient: BeadStyles.verde,
                onTap: notifier.finishBackTranslation,
                child: const Icon(
                  LucideIcons.check,
                  size: 24,
                  color: ShemaBrand.branco,
                ),
              )
            else
              RoundActionButton(
                size: 60,
                semanticLabel: _listenLabel(session),
                gradient: BeadStyles.wood,
                onTap: notifier.ouvirGravacao,
                child: Icon(
                  _listenGlyph(session),
                  size: 24,
                  color: ShemaBrand.branco,
                ),
              ),
            const SizedBox(width: 28),
            // The same gesture under two names. Cutting *here* only describes something
            // while an audio is running under the team's finger — there is an instant
            // being pointed at, and they are choosing it. Stopped, there is no instant to
            // point at and no place the word "here" could mean, and what is left of the
            // gesture is telling this part. The cut still happens either way: stopped, the
            // player sits where the team stopped listening, which is the same place they
            // would have chosen.
            RoundActionButton(
              size: 60,
              semanticLabel: _tellLabel(session),
              gradient: BeadStyles.azul,
              onTap: notifier.cortarTrecho,
              child: Icon(
                _tellGlyph(session),
                size: 24,
                color: ShemaBrand.branco,
              ),
            ),
          ],
        ),
      );
    }
    return null;
  }

  String _circleLabel(SalaSessionState session) {
    switch (session.btPhase) {
      case BtPhase.playing:
        return 'Tocar para traduzir este pedaço em português';
      case BtPhase.capturing:
        return 'Tocar ao terminar o pedaço';
      case BtPhase.findings:
        return 'Ouvir a pergunta de novo';
      case BtPhase.gravandoMaterna:
        return session.voice == VoiceState.listening
            ? 'Tocar ao terminar a gravação'
            : 'Gravar este trecho';
      case BtPhase.thinking:
        return 'Um instante';
      case BtPhase.conferida:
        return 'Traduzida';
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/bt_finding.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/session_state.dart';
import 'bead_row.dart';
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
    final language = ref.watch(roomLanguageProvider);
    // A halted voice is never painted over. The checked circle is drawn done because the
    // passage is right, and that read over a room stopped for a person or with no
    // network: the team got a green circle, two buttons the guards refuse, no way out of
    // the passage, and nothing at all saying why. It cost nothing while conferida lasted
    // 700 ms; it is where the team now waits.
    final conferida =
        session.btPhase == BtPhase.conferida &&
        !session.needsPerson &&
        !session.offline;

    // The question is its own composition, not a row of buttons under the usual circle:
    // the grid is the screen, and the room's voice steps back to make room for it.
    if (session.btPhase == BtPhase.findings &&
        session.btFindingTrecho != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FacilitatorCircle(
            size: 54,
            voice: session.voice,
            warning: session.warning,
            semanticLabel: _circleLabel(session, language),
            onTap: notifier.retroTap,
            onLongPress: session.canResolveWithPerson
                ? notifier.resolveWithPerson
                : null,
          ),
          const SizedBox(height: 46),
          OndeMoraGrade(
            onOuvirMaterna: notifier.ouvirVozMaterna,
            onOuvirRetro: notifier.ouvirTraducaoEmPortugues,
            onGravarAParteDeNovo: notifier.gravarAParteDeNovo,
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
      children: [
        const SizedBox(height: 92),
        SizedBox(
          height: 40,
          child: BeadRow(entries: _contas(session, language), onTap: (_) {}),
        ),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FacilitatorCircle(
                  size: 160,
                  voice: conferida ? VoiceState.done : session.voice,
                  warning: session.warning,
                  semanticLabel: _circleLabel(session, language),
                  onTap: notifier.retroTap,
                  onLongPress: session.canResolveWithPerson
                      ? notifier.resolveWithPerson
                      : null,
                ),
                const SizedBox(height: 116),
                SizedBox(
                  height: 64,
                  child: _actions(session, notifier, language),
                ),
                if (session.btPhase != BtPhase.findings &&
                    session.btPhase != BtPhase.conferida) ...[
                  const SizedBox(height: 66),
                  FadeUp(
                    child: RoundActionButton(
                      size: 78,
                      semanticLabel: retroLabelFor('advance', language),
                      gradient: BeadStyles.wood,
                      shadows: RoundActionButton.dropShadow,
                      mood: session.canAdvanceToTheVerdict
                          ? ButtonMood.beckoning
                          : ButtonMood.dimmed,
                      onTap: () => unawaited(notifier.finishBackTranslation()),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<BeadRowEntry> _contas(SalaSessionState session, String language) {
    final aberta = session.btPhase != BtPhase.conferida;
    final fills = [
      for (final trecho in session.btTrechos)
        if (trecho.segmentId != null &&
            trecho.segmentId == session.btEsperandoConserto)
          BeadFill.drained
        else if (trecho.contado)
          BeadFill.solid
        else
          BeadFill.translucent,
    ];
    final pendente = fills.length;
    if (aberta && !session.btContadaInteira) {
      fills.add(BeadFill.translucent);
      if (session.btRestoDepoisDoCorte) fills.add(BeadFill.translucent);
    }
    final nome = retroLabelFor('stretch', language);
    return [
      for (var onde = 0; onde < fills.length; onde++)
        BeadRowEntry(
          fill: fills[onde],
          current: aberta && onde == pendente,
          semanticLabel: '$nome ${onde + 1}',
        ),
    ];
  }

  IconData _listenGlyph(SalaSessionState session) {
    if (session.btClipRodando || session.btTrechoTocando) {
      return LucideIcons.pause;
    }
    if (session.btParteFronteira && !session.btCortado) {
      return LucideIcons.skipForward;
    }
    return LucideIcons.play;
  }

  Widget? _actions(
    SalaSessionState session,
    SalaSessionNotifier notifier,
    String language,
  ) {
    if (session.btPhase == BtPhase.findings) {
      // Which voice needs to speak again is the team's to say. It used to be read off the
      // kind of finding, and the team was never asked, on the one question only they can
      // answer.
      // With no stretch to ask about, the question cannot be put, and the room falls back
      // to what it always did — including reading the kind: telling the whole recording
      // again settles nothing a re-recording kind names, and the pointer being absent must
      // not smuggle that offer back in.
      final retellingCanSettleIt = !session.btFindings.any(
        (finding) => finding.exitsByReRecording,
      );
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
            // recording again. The name says the additive act, because the grid's wood
            // microphone next door records a part again in place.
            RoundActionButton(
              size: 60,
              semanticLabel: 'Continuar o ensaio',
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
    final soando = session.btClipRodando || session.btTrechoTocando;
    if (session.btPhase == BtPhase.conferida) {
      // The room stays open after a clean verdict: the voice invites one last listening
      // and then the approval, and the passage is not finished until the team presses.
      return FadeUp(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RoundActionButton(
              size: 60,
              semanticLabel: retroLabelFor(
                soando ? 'pause' : 'listenToTheRecording',
                language,
              ),
              gradient: BeadStyles.wood,
              mood: session.canListenAtConferida
                  ? ButtonMood.lit
                  : ButtonMood.dimmed,
              onTap: notifier.ouvirGravacao,
              child: Icon(
                _listenGlyph(session),
                size: 24,
                color: ShemaBrand.branco,
              ),
            ),
            const SizedBox(width: 24),
            RoundActionButton(
              size: 60,
              semanticLabel: retroLabelFor('approve', language),
              gradient: BeadStyles.verde,
              onTap: notifier.aprovarRascunhoFinal,
              child: const Icon(
                LucideIcons.check,
                size: 24,
                color: ShemaBrand.branco,
              ),
            ),
          ],
        ),
      );
    }
    return FadeUp(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RoundActionButton(
            size: 60,
            semanticLabel: retroLabelFor(soando ? 'pause' : 'listen', language),
            gradient: BeadStyles.wood,
            mood: session.canListenToThePendingStretch
                ? ButtonMood.lit
                : ButtonMood.dimmed,
            onTap: notifier.ouvirGravacao,
            child: Icon(
              _listenGlyph(session),
              size: 24,
              color: ShemaBrand.branco,
            ),
          ),
          const SizedBox(width: 24),
          RoundActionButton(
            size: 60,
            semanticLabel: retroLabelFor('cut', language),
            gradient: BeadStyles.wood,
            mood: session.canCut ? ButtonMood.lit : ButtonMood.dimmed,
            onTap: notifier.cortarTrecho,
            child: const Icon(
              LucideIcons.scissors,
              size: 24,
              color: ShemaBrand.branco,
            ),
          ),
          const SizedBox(width: 24),
          RoundActionButton(
            size: 60,
            semanticLabel: retroLabelFor('confirm', language),
            gradient: BeadStyles.verde,
            mood: session.canConfirmTranslation
                ? ButtonMood.lit
                : ButtonMood.dimmed,
            onTap: () => unawaited(notifier.confirmarTraducao()),
            child: const Icon(
              LucideIcons.check,
              size: 24,
              color: ShemaBrand.branco,
            ),
          ),
        ],
      ),
    );
  }

  String _circleLabel(SalaSessionState session, String language) {
    if (session.needsPerson) return 'Um momento para uma pessoa';
    if (session.offline) return 'Tocar para tentar de novo';
    switch (session.btPhase) {
      case BtPhase.playing:
        return retroLabelFor('record', language);
      case BtPhase.capturing:
        return retroLabelFor('recording', language);
      case BtPhase.findings:
        return 'Ouvir a pergunta de novo';
      case BtPhase.thinking:
        return 'Um instante';
      case BtPhase.conferida:
        return 'Traduzida';
    }
  }
}

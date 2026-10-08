import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/session_notifier.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/session_state.dart';
import 'bead_row.dart';
import 'bead_styles.dart';
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

    final avanca =
        session.btPhase != BtPhase.findings &&
        session.btPhase != BtPhase.conferida;
    final contas = _contas(session, notifier, language);
    final (voz, lingua) = _voz(session, conferida);
    return Column(
      children: [
        const Spacer(flex: 86),
        SizedBox(
          height: 40,
          child: BeadRow(
            entries: [for (final conta in contas) conta.$1],
            onTap: (onde) => contas[onde].$2?.call(),
          ),
        ),
        const Spacer(flex: 330),
        FacilitatorCircle(
          size: facilitatorCircleSize,
          halt: session.halt,
          voice: voz,
          tongue: lingua,
          warning: session.warning ? warningNoticeLabelFor(language) : null,
          notUnderstood: session.wordlessTelling
              ? retroLabelFor('notUnderstood', language)
              : null,
          semanticLabel: _circleLabel(session, language),
          onTap: notifier.retroTap,
          onLongPress: session.canResolveWithPerson
              ? notifier.resolveWithPerson
              : null,
        ),
        const Spacer(flex: 64),
        SizedBox(height: 60, child: _actions(session, notifier, language)),
        const Spacer(flex: 58),
        SizedBox(height: 78, child: _disc(session, notifier, language, avanca)),
        const Spacer(flex: 304),
      ],
    );
  }

  Widget? _disc(
    SalaSessionState session,
    SalaSessionNotifier notifier,
    String language,
    bool avanca,
  ) {
    if (session.btPhase == BtPhase.findings &&
        session.btFindingTrecho == null) {
      return FadeUp(
        child: RoundActionButton(
          size: 78,
          semanticLabel: findingLabelFor('continue', language),
          gradient: BeadStyles.wood,
          shadows: RoundActionButton.dropShadow,
          halo: ShemaBrand.wood,
          mood: ButtonMood.beckoning,
          onTap: notifier.continuarOEnsaio,
        ),
      );
    }
    if (!avanca) return null;
    return FadeUp(
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
    );
  }

  (VoiceState, Tongue?) _voz(SalaSessionState session, bool conferida) {
    if (conferida) return (VoiceState.done, null);
    if (session.voice == VoiceState.listening) {
      return (VoiceState.listening, Tongue.bridge);
    }
    if (session.voice != VoiceState.invite) return (session.voice, null);
    if (session.btRetroTocando) return (VoiceState.speaking, Tongue.bridge);
    if (session.btClipRodando || session.btTrechoTocando) {
      return (VoiceState.speaking, Tongue.motherTongue);
    }
    return (VoiceState.invite, null);
  }

  List<(BeadRowEntry, VoidCallback?)> _contas(
    SalaSessionState session,
    SalaSessionNotifier notifier,
    String language,
  ) {
    final naPergunta = session.btPhase == BtPhase.findings;
    final aberta = session.btPhase != BtPhase.conferida && !naPergunta;
    final nomeado = aberta ? session.btTrechoTraduzidoDeNovo : null;
    final escolhida = aberta ? session.btContaEscolhida : null;
    final apontado = naPergunta
        ? session.btFindingTrecho?.segmentId
        : nomeado?.segmentId == session.btFindingSegmentId
        ? nomeado?.segmentId
        : null;
    final contas = <(BeadFill, bool, bool, VoidCallback?)>[
      for (final (onde, trecho) in session.btTrechos.indexed)
        if (naPergunta)
          (
            _fillOf(trecho, session),
            trecho.segmentId == apontado,
            apontado != null && trecho.segmentId != apontado,
            null,
          )
        else if (nomeado != null && trecho.segmentId == nomeado.segmentId)
          (
            _fillOf(trecho, session),
            escolhida == null,
            false,
            notifier.ouvirOTrechoPendente,
          )
        else
          (
            _fillOf(trecho, session),
            escolhida == onde,
            apontado != null,
            aberta && trecho.contado
                ? () => notifier.ouvirOTrechoContado(onde)
                : null,
          ),
    ];
    if (aberta && nomeado == null && !session.btContadaInteira) {
      final lugar = session.btTrechos
          .where(
            (trecho) =>
                trecho.parte < session.btParte ||
                (trecho.parte == session.btParte &&
                    trecho.lugarFrom < session.btCursor),
          )
          .length;
      contas.insertAll(lugar, [
        (
          BeadFill.translucent,
          escolhida == null,
          false,
          notifier.ouvirOTrechoPendente,
        ),
        if (session.btRestoDepoisDoCorte)
          (BeadFill.translucent, false, false, null),
      ]);
    }
    final nome = retroLabelFor('stretch', language);
    return [
      for (final (onde, (fill, current, dimmed, onTap)) in contas.indexed)
        (
          BeadRowEntry(
            fill: fill,
            current: current,
            dimmed: dimmed,
            semanticLabel: '$nome ${onde + 1}',
          ),
          onTap,
        ),
    ];
  }

  BeadFill _fillOf(Trecho trecho, SalaSessionState session) {
    if (trecho.segmentId != null &&
        trecho.segmentId == session.btFindingSegmentId) {
      final regravando =
          session.btPhase == BtPhase.capturing ||
          (session.btPhase != BtPhase.findings &&
              session.btTraducaoPendente != null &&
              !session.btTraducaoPendenteEmprestada);
      return regravando ? BeadFill.translucent : BeadFill.drained;
    }
    return trecho.contado ? BeadFill.solid : BeadFill.translucent;
  }

  IconData _listenGlyph(SalaSessionState session) {
    if (session.btClipRodando ||
        session.btTrechoTocando ||
        session.btRetroTocando) {
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
      final humor = session.btFindingTrecho == null
          ? ButtonMood.dimmed
          : ButtonMood.lit;
      final soando = session.btTrechoTocando || session.btRetroTocando;
      return FadeUp(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RoundActionButton(
              size: 60,
              semanticLabel: findingLabelFor('play', language),
              mood: humor,
              gradient: BeadStyles.wood,
              onTap: notifier.ouvirOTrechoEATraducao,
              child: Icon(
                soando ? LucideIcons.pause : LucideIcons.play,
                size: 24,
                color: ShemaBrand.branco,
              ),
            ),
            const SizedBox(width: 24),
            RoundActionButton(
              size: 60,
              semanticLabel: findingLabelFor('recordThePart', language),
              mood: humor,
              gradient: BeadStyles.wood,
              onTap: notifier.gravarAParteDeNovo,
              child: const Icon(
                LucideIcons.mic,
                size: 24,
                color: ShemaBrand.branco,
              ),
            ),
            const SizedBox(width: 24),
            RoundActionButton(
              size: 60,
              semanticLabel: findingLabelFor('translateTheStretch', language),
              mood: humor,
              gradient: BeadStyles.azul,
              onTap: notifier.traduzirDeNovoEmPortugues,
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
    final soando =
        session.btClipRodando ||
        session.btTrechoTocando ||
        session.btRetroTocando;
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
            semanticLabel: retroLabelFor(
              soando
                  ? 'pause'
                  : session.btTraducaoPendente != null &&
                        session.btContaEscolhida == null
                  ? 'listenToTheTranslation'
                  : 'listen',
              language,
            ),
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
    if (session.needsPerson) return circleLabelFor('needsPerson', language);
    if (session.offline) return circleLabelFor('offline', language);
    if (session.wordlessTelling) {
      return retroLabelFor('notUnderstood', language);
    }
    switch (session.btPhase) {
      case BtPhase.playing:
        if (session.btTrechoTraduzidoDeNovo == null &&
            !session.btCortado &&
            session.nothingHeardSinceCursor) {
          return retroLabelFor('listenFirst', language);
        }
        return retroLabelFor(
          session.btTraducaoPendente != null ? 'recordAgain' : 'record',
          language,
        );
      case BtPhase.capturing:
        return retroLabelFor('recording', language);
      case BtPhase.findings:
        return findingLabelFor('circle', language);
      case BtPhase.thinking:
        return retroLabelFor('thinking', language);
      case BtPhase.conferida:
        return retroLabelFor('translated', language);
    }
  }
}

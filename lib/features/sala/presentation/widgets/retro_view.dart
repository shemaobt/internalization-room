import 'dart:async';
import 'dart:math';

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
import 'facilitator_circle.dart';
import 'frase_list.dart';
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
    final conferida = _conferida(session);

    final avanca =
        session.btPhase != BtPhase.findings &&
        session.btPhase != BtPhase.conferida;
    final contas = _contas(session, notifier, language);
    final (voz, lingua) = _voz(session, conferida);
    final colors = SalaColors.of(context);
    final titulo = retroLabelFor('title', language);
    final linha = _linha(session, language);
    final veredito =
        session.btPhase == BtPhase.findings ||
        session.btPhase == BtPhase.conferida ||
        session.btFindings.isNotEmpty;
    return SizedBox.expand(
      child: SingleChildScrollView(
        child: Column(
          children: [
            SizedBox(height: 24 + MediaQuery.viewPaddingOf(context).top),
            Semantics(
              header: true,
              label: titulo,
              child: ExcludeSemantics(
                child: Text(
                  titulo,
                  style: TextStyle(
                    color: colors.ink,
                    fontSize: 26,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Text(
                retroLabelFor(veredito ? 'subVerdict' : 'subTell', language),
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.mut, fontSize: 15, height: 1.35),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 40,
              child: BeadRow(
                entries: [for (final conta in contas) conta.$1],
                onTap: (onde) => contas[onde].$2?.call(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: avanca
                  ? _thePauseControls(session, notifier, language)
                  : null,
            ),
            const SizedBox(height: 24),
            FacilitatorCircle(
              size: facilitatorCircleSize,
              halt: session.halt,
              voice: voz,
              tongue: lingua,
              answersATouch: !conferida || session.btRegravacao != null,
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
            if (linha != null) ...[
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Text(
                  linha,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.telha, fontSize: 15),
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(height: 60, child: _actions(session, notifier, language)),
            const SizedBox(height: 32),
            FraseList(
              rows: _frases(session, notifier, language),
              language: language,
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 78,
              child: _disc(session, notifier, language, avanca),
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  List<FraseRow> _frases(
    SalaSessionState session,
    SalaSessionNotifier notifier,
    String language,
  ) {
    final aberta =
        session.btPhase != BtPhase.conferida &&
        session.btPhase != BtPhase.findings;
    final contadas = [
      for (final (onde, trecho) in session.btTrechos.indexed)
        if (trecho.contado) (onde, trecho),
    ];
    final maior = contadas.fold(
      Duration.zero,
      (maior, contada) => contada.$2.to - contada.$2.from > maior
          ? contada.$2.to - contada.$2.from
          : maior,
    );
    return [
      for (final (onde, trecho) in contadas)
        FraseRow(
          n: trecho.frase,
          parte: trecho.parte >= 0 ? trecho.parte + 1 : null,
          share: maior > Duration.zero
              ? max(
                  0.08,
                  (trecho.to - trecho.from).inMicroseconds /
                      maior.inMicroseconds,
                )
              : 1,
          onHear: aberta ? () => notifier.ouvirOTrechoContado(onde) : null,
          mark: trecho.segmentId == session.btFraseQueAguarda
              ? sceneRehearsalLabelFor('awaiting', language)
              : switch (_markOn(trecho.frase, session)) {
                  null || BtFindingKind.nuance => null,
                  final kind => retroLabelFor(kind.name, language),
                },
          nuance: _markOn(trecho.frase, session) == BtFindingKind.nuance,
          regravar:
              session.fraseRegravavel(trecho) &&
                  (session.btPhase != BtPhase.conferida ||
                      _markOn(trecho.frase, session) == BtFindingKind.nuance)
              ? sceneRehearsalLabelFor(
                  'rerecordFrase',
                  language,
                  n: trecho.frase,
                )
              : null,
          onRegravar:
              session.btRegravacao == null ||
                  session.btRegravacao?.frase == trecho.frase
              ? () => notifier.regravarAFrase(trecho)
              : null,
          revisao:
              session.btRegravacao?.frase == trecho.frase &&
                  session.btRegravacao?.passo == PassoDaRegravacao.revendo
              ? FraseRevisao(
                  ouvir: sceneRehearsalLabelFor(
                    'listenN',
                    language,
                    n: trecho.frase,
                  ),
                  onOuvir: notifier.ouvirAFraseGravada,
                  gravarDeNovo: sceneRehearsalLabelFor('recordAgain', language),
                  onGravarDeNovo: notifier.gravarAFraseDeNovo,
                  usarEsta: sceneRehearsalLabelFor('useTake', language),
                  onUsarEsta: notifier.usarEstaFrase,
                )
              : null,
          estado: switch (session.btRegravacao) {
            RegravacaoDaFrase(:final frase, passo: PassoDaRegravacao.enviando)
                when frase == trecho.frase =>
              sceneRehearsalLabelFor('takeSending', language),
            RegravacaoDaFrase(
              :final frase,
              passo: PassoDaRegravacao.longaDemais,
            )
                when frase == trecho.frase =>
              sceneRehearsalLabelFor('spliceTooLong', language),
            null when session.btFraseGuardada == trecho.frase =>
              sceneRehearsalLabelFor('spliceFail', language),
            _ => null,
          },
          onEstado:
              session.btRegravacao == null &&
                  session.btFraseGuardada == trecho.frase
              ? notifier.tentarAFraseDeNovo
              : null,
        ),
    ];
  }

  String? _linha(SalaSessionState session, String language) {
    if (session.machine.theVerdictWaitsForTheTap) {
      return retroLabelFor('checkFailed', language);
    }
    final recusa = switch (session.btRecusa) {
      CheckRefusal.partUnheard => 'partUnheard',
      CheckRefusal.nothingTranslated => 'nothingTranslated',
      CheckRefusal.checkUnavailable => 'checkFailed',
      _ => null,
    };
    if (recusa != null) return retroLabelFor(recusa, language);
    if (session.wordlessTelling) {
      return retroLabelFor('notUnderstood', language);
    }
    if (session.btRegravacao?.passo
        case PassoDaRegravacao.pronta || PassoDaRegravacao.gravando) {
      return sceneRehearsalLabelFor('respeakHint', language);
    }
    if (_conferida(session)) {
      return '✓ ${retroLabelFor('translated', language)}';
    }
    return null;
  }

  bool _conferida(SalaSessionState session) =>
      session.btPhase == BtPhase.conferida &&
      !session.needsPerson &&
      !session.offline;

  BtFindingKind? _markOn(int? frase, SalaSessionState session) {
    if (frase == null) return null;
    for (final finding in session.btFindings) {
      if (finding.frase == frase) return finding.kind;
    }
    return null;
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
    final terminei = retroLabelFor(
      session.btConferindo ? 'checking' : 'advance',
      language,
    );
    return FadeUp(
      child: RoundActionButton(
        size: 78,
        semanticLabel: terminei,
        gradient: BeadStyles.wood,
        shadows: RoundActionButton.dropShadow,
        mood: session.canAdvanceToTheVerdict
            ? ButtonMood.beckoning
            : ButtonMood.dimmed,
        onTap: () => unawaited(notifier.finishBackTranslation()),
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                terminei,
                style: const TextStyle(
                  color: ShemaBrand.branco,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  (VoiceState, Tongue?) _voz(SalaSessionState session, bool conferida) {
    if (session.btRegravacao?.passo == PassoDaRegravacao.gravando) {
      return (VoiceState.listening, Tongue.motherTongue);
    }
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
    String parte(int onde) => '${retroLabelFor('part', language)} ${onde + 1}';
    String nome(Trecho trecho) => switch (trecho.frase) {
      final n? => sceneRehearsalLabelFor('frase', language, n: n),
      null => parte(trecho.parte),
    };
    final contas = <(BeadFill, bool, bool, VoidCallback?, String)>[
      for (final (onde, trecho) in session.btTrechos.indexed)
        if (naPergunta)
          (
            _fillOf(trecho, session),
            trecho.segmentId == apontado,
            apontado != null && trecho.segmentId != apontado,
            null,
            nome(trecho),
          )
        else if (nomeado != null && trecho.segmentId == nomeado.segmentId)
          (
            _fillOf(trecho, session),
            escolhida == null,
            false,
            notifier.ouvirOTrechoPendente,
            nome(trecho),
          )
        else
          (
            _fillOf(trecho, session),
            escolhida == onde,
            apontado != null,
            aberta && trecho.contado
                ? () => notifier.ouvirOTrechoContado(onde)
                : null,
            nome(trecho),
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
          parte(session.btParte),
        ),
        if (session.btRestoDepoisDoCorte)
          (BeadFill.translucent, false, false, null, parte(session.btParte)),
      ]);
    }
    return [
      for (final (fill, current, dimmed, onTap, label) in contas)
        (
          BeadRowEntry(
            fill: fill,
            current: current,
            dimmed: dimmed,
            semanticLabel: label,
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
            semanticLabel: retroLabelFor('pauseHere', language),
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

  Widget _thePauseControls(
    SalaSessionState session,
    SalaSessionNotifier notifier,
    String language,
  ) {
    final mood = session.canAdjustThePause ? ButtonMood.lit : ButtonMood.dimmed;
    Widget control(String label, IconData glyph, VoidCallback onTap) =>
        RoundActionButton(
          size: 48,
          semanticLabel: retroLabelFor(label, language),
          gradient: BeadStyles.wood,
          mood: mood,
          onTap: onTap,
          child: Icon(glyph, size: 20, color: ShemaBrand.branco),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        control(
          'pauseEarlier',
          LucideIcons.chevronLeft,
          notifier.pausaUmPoucoAntes,
        ),
        const SizedBox(width: 24),
        control('hearThePause', LucideIcons.ear, notifier.ouvirAPausa),
        const SizedBox(width: 24),
        control(
          'pauseLater',
          LucideIcons.chevronRight,
          notifier.pausaUmPoucoDepois,
        ),
      ],
    );
  }

  String _circleLabel(SalaSessionState session, String language) {
    if (session.needsPerson) return circleLabelFor('needsPerson', language);
    if (session.offline) return circleLabelFor('offline', language);
    if (session.wordlessTelling) {
      return retroLabelFor('notUnderstood', language);
    }
    if (session.btRegravacao?.passo
        case PassoDaRegravacao.pronta || PassoDaRegravacao.gravando) {
      return sceneRehearsalLabelFor('respeakHint', language);
    }
    switch (session.btPhase) {
      case BtPhase.playing:
        if (session.thePauseStands) {
          return retroLabelFor(
            session.btPausaAjustavel ? 'pauseHint' : 'pauseAtTheTap',
            language,
          );
        }
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

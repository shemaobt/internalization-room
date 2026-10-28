import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/playback_repository.dart';
import '../../data/session_notifier.dart';
import '../../domain/kept_take.dart';
import '../../domain/bt_finding.dart';
import '../../domain/channel.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/session_state.dart';
import 'bead_row.dart';
import 'bead_styles.dart';
import 'facilitator_circle.dart';
import 'frase_list.dart';
import 'external_check_button.dart';
import 'listeners_line.dart';
import 'motion.dart';
import 'pause_adjust_row.dart';
import 'saved_screen.dart';
import 'stage_heading.dart';
import 'status_lines.dart';

class RetroView extends ConsumerWidget {
  const RetroView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(salaSessionProvider);
    final notifier = ref.read(salaSessionProvider.notifier);
    final language = ref.watch(roomLanguageProvider);
    if (session.ensaioSalvo case final versao?) {
      return SavedScreen(version: versao);
    }
    // A halted voice is never painted over. The checked circle is drawn done because the
    // passage is right, and that read over a room stopped for a person or with no
    // network: the team got a green circle, two buttons the guards refuse, no way out of
    // the passage, and nothing at all saying why. It cost nothing while conferida lasted
    // 700 ms; it is where the team now waits.
    final conferida = _conferida(session);

    final avanca = session.btPhase != BtPhase.conferida && !session.btSoOuvir;
    final contas = _contas(session, notifier, language);
    final (voz, lingua) = _voz(session, conferida);
    final colors = SalaColors.of(context);
    final titulo = session.joined
        ? recordingHomeLabelFor('joinedTitle', language)
        : retroLabelFor('title', language);
    final estado = _estado(session, language);
    final nota = session.btRecomecada
        ? retroLabelFor(
            session.joined ? 'restartedJoined' : 'restarted',
            language,
          )
        : null;
    final linha = estado == null && nota == null
        ? _linha(session, language)
        : null;
    final veredito = session.btVeredito || session.btFindings.isNotEmpty;
    final scrolling = SizedBox.expand(
      child: SingleChildScrollView(
        child: Column(
          children: [
            StageHeading(
              stage: SalaStage.retro,
              text: titulo,
              style: TextStyle(
                color: colors.ink,
                fontSize: 26,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Text(
                  retroLabelFor(
                    session.btSoOuvir
                        ? session.joined
                              ? 'listenOnly'
                              : 'listenOnlyRecording'
                        : veredito
                        ? session.offersASentence
                              ? 'subVerdictSentence'
                              : 'subVerdict'
                        : 'subTell',
                    language,
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.mut,
                    fontSize: 15,
                    height: 1.35,
                  ),
                ),
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
                  ? PauseAdjustRow(
                      lit: session.canAdjustThePause,
                      language: language,
                      onEarlier: notifier.pausaUmPoucoAntes,
                      onHear: notifier.ouvirAPausa,
                      onLater: notifier.pausaUmPoucoDepois,
                    )
                  : null,
            ),
            const SizedBox(height: 24),
            FacilitatorCircle(
              size: herCircleSize(MediaQuery.sizeOf(context), 38, 150),
              halt: session.halt,
              voice: voz,
              tongue: lingua,
              answersATouch:
                  session.aBackTranslationGestureActs &&
                  (!conferida || session.btRegravacao != null),
              notUnderstood: session.wordlessTelling
                  ? retroLabelFor('notUnderstood', language)
                  : null,
              semanticLabel: _circleLabel(session, language),
              onTap: notifier.retroTap,
            ),
            if (_traduzindoDeNovo(session) case final n?) ...[
              const SizedBox(height: 12),
              _ManterADeAntes(
                label: sceneRehearsalLabelFor('keepTheEarlier', language),
                onTap: session.btPhase == BtPhase.playing
                    ? notifier.manterATraducaoDeAntes
                    : null,
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  sceneRehearsalLabelFor(
                    session.canAdjustThePause
                        ? 'retellingLast'
                        : session.btPausaSoNaUltima
                        ? 'retellingOther'
                        : 'retelling',
                    language,
                    n: n,
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.telha, fontSize: 15),
                ),
              ),
            ],
            StatusLines(line: estado, note: nota),
            if (session.btSoOuvir) ...[
              const SizedBox(height: 12),
              _APosicaoDaEscuta(session: session, language: language),
            ],
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
            SizedBox(
              height: 60,
              child: _actions(session, notifier, language, colors),
            ),
            if (session.offersTheVerdictAgain) ...[
              const SizedBox(height: 12),
              _botaoEscrito(
                retroLabelFor('hearTheVerdict', language),
                colors,
                session.canHearTheVerdictAgain
                    ? notifier.ouvirARespostaDeNovo
                    : null,
              ),
            ],
            if (session.approvedDraftDrawn case final aprovado?) ...[
              ListenersLine(aprovado.listeners),
              const SizedBox(height: 12),
              const ExternalCheckButton(),
            ],
            const SizedBox(height: 32),
            FraseList(
              rows: _frases(session, notifier, language),
              language: language,
            ),
            if (!session.btSoOuvir &&
                (session.btTrechos.any((trecho) => trecho.contado) ||
                    session.btTrechosRegravados.isNotEmpty)) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _recomeco(session, colors, notifier, language),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              height: 78,
              child: _disc(session, notifier, language, avanca),
            ),
            if (avanca && session.btVeredito) ...[
              const SizedBox(height: 16),
              _botaoEscrito(
                findingLabelFor('recordThePart', language),
                colors,
                session.btFindingTrecho != null &&
                        session.btPhase == BtPhase.playing
                    ? notifier.gravarAParteDeNovo
                    : null,
              ),
            ],
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
    return SafeArea(bottom: false, child: scrolling);
  }

  List<FraseRow> _frases(
    SalaSessionState session,
    SalaSessionNotifier notifier,
    String language,
  ) {
    final atua = session.aBackTranslationGestureActs;
    final contadas = [
      for (final (onde, trecho) in session.btTrechos.indexed)
        if (trecho.contado) (onde, trecho),
    ];
    final maior =
        [
          for (final (_, trecho) in contadas) trecho,
          ...session.btTrechosRegravados,
        ].fold(
          Duration.zero,
          (maior, trecho) =>
              trecho.to - trecho.from > maior ? trecho.to - trecho.from : maior,
        );
    double share(Trecho trecho) =>
        maior > Duration.zero && trecho.to > trecho.from
        ? max(
                8,
                ((trecho.to - trecho.from).inMicroseconds /
                        maior.inMicroseconds *
                        100)
                    .round(),
              ) /
              100
        : 1;
    int? parteDe(Trecho trecho) =>
        trecho.parte < 0 ||
            session.partes.elementAtOrNull(trecho.parte)?.scopeId ==
                KeptScope.whole
        ? null
        : trecho.parte + 1;
    final regravadas = [
      for (final (_, trecho)
          in [...session.btTrechosRegravados.indexed]..sort(
            (a, b) => a.$2.parte == b.$2.parte
                ? a.$1.compareTo(b.$1)
                : a.$2.parte.compareTo(b.$2.parte),
          ))
        FraseRow(
          n: null,
          parte: parteDe(trecho),
          share: share(trecho),
          onHear: null,
          mark: retroLabelFor('stale', language),
        ),
    ];
    final atuais = [
      for (final (onde, trecho) in contadas)
        FraseRow(
          n: trecho.frase,
          parte: parteDe(trecho),
          share: share(trecho),
          onHear:
              session.canHearAFrase &&
                  switch (session.aParteDoTrecho(trecho)) {
                    null => true,
                    final parte =>
                      session.partsAway[parte.takeId] == PartAway.missed,
                  }
              ? () => notifier.ouvirOTrechoContado(onde)
              : null,
          onRetell:
              session.canRetellAFrase &&
                  trecho.segmentId != null &&
                  session.aParteDoTrechoEstaAqui(trecho)
              ? () => notifier.traduzirAFraseDeNovo(onde)
              : null,
          mark:
              session.btFraseQueAguarda != null &&
                  trecho.segmentId == session.btFraseQueAguarda
              ? sceneRehearsalLabelFor('awaiting', language)
              : switch (_markOn(trecho.frase, session)) {
                  null || BtFindingKind.nuance => null,
                  final kind => retroLabelFor(kind.name, language),
                },
          nuance: _markOn(trecho.frase, session) == BtFindingKind.nuance,
          regravar:
              session.fraseRegravavel(trecho) &&
                  (session.btPhase != BtPhase.conferida ||
                      _markOn(trecho.frase, session) == BtFindingKind.nuance ||
                      session.overAnApprovedDraft)
              ? session.armedTap?.control == 'rerecord:${trecho.frase}'
                    ? retroLabelFor('reopenArmed', language)
                    : sceneRehearsalLabelFor(
                        'rerecordFrase',
                        language,
                        n: trecho.frase,
                      )
              : null,
          regravarDormindo: _dormindo('rerecord:${trecho.frase}', session),
          onRegravar:
              session.btRegravacao == null ||
                  session.btRegravacao?.frase == trecho.frase
              ? () => notifier.regravarAFrase(trecho)
              : null,
          revisao:
              atua &&
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
            null
                when trecho.frase != null &&
                    session.btFraseGuardada == trecho.frase =>
              session.armedTap?.control == 'resend:${trecho.frase}'
                  ? retroLabelFor('reopenArmed', language)
                  : sceneRehearsalLabelFor('spliceFail', language),
            _ => null,
          },
          estadoDormindo: _dormindo('resend:${trecho.frase}', session),
          onEstado:
              atua &&
                  session.btRegravacao == null &&
                  trecho.frase != null &&
                  session.btFraseGuardada == trecho.frase
              ? notifier.tentarAFraseDeNovo
              : null,
        ),
    ];
    final linhas = <FraseRow>[];
    var antes = 0;
    for (final linha in atuais) {
      while (antes < regravadas.length &&
          (regravadas[antes].parte ?? 0) < (linha.parte ?? 0)) {
        linhas.add(regravadas[antes++]);
      }
      linhas.add(linha);
    }
    return [...linhas, ...regravadas.skip(antes)];
  }

  Widget _recomeco(
    SalaSessionState session,
    SalaColors colors,
    SalaSessionNotifier notifier,
    String language,
  ) {
    final rotulo = session.armedTap?.control != 'restart'
        ? retroLabelFor('restart', language)
        : retroLabelFor(
            session.joined ? 'restartArmedJoined' : 'restartArmed',
            language,
            n:
                session.btTrechos.where((trecho) => trecho.contado).length +
                session.btTrechosRegravados.length,
          );
    final dormindo =
        _dormindo('restart', session) || !session.aBackTranslationGestureActs;
    return Semantics(
      button: true,
      enabled: !dormindo,
      label: rotulo,
      child: Opacity(
        opacity: dormindo ? 0.4 : 1,
        child: ExcludeSemantics(
          child: GestureDetector(
            onTap: notifier.recomecarATraducao,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: colors.mut),
              ),
              child: Text(
                rotulo,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.mut, fontSize: 15),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _botaoEscrito(String rotulo, SalaColors colors, VoidCallback? onTap) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: rotulo,
      child: Opacity(
        opacity: onTap != null ? 1 : 0.4,
        child: ExcludeSemantics(
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: colors.mut),
              ),
              child: Text(
                rotulo,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.mut, fontSize: 15),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _dormindo(String control, SalaSessionState session) =>
      session.armedTap?.control == control &&
      session.armedTap?.phase == BtRecomeco.armado;

  String? _estado(SalaSessionState session, String language) {
    if (session.btAprovadoAgora case final versao?) {
      return retroLabelFor('approved', language, n: versao);
    }
    final aviso = switch (session.btAviso) {
      BtAviso.recomecoFalhou => 'restartFailed',
      BtAviso.pausaSoNaUltima => 'pauseOnlyOnTheLast',
      BtAviso.pausaPassaDoFim => 'pausePastTheEnd',
      BtAviso.pausaNaoFica => 'pauseCannotStandThere',
      BtAviso.checagemFalhou => 'externalCheckFailed',
      BtAviso.checagemNaoAbre => 'externalCheckNotFinal',
      null => null,
    };
    if (aviso != null) return retroLabelFor(aviso, language);
    if (session.btRecusa == CheckRefusal.stretchUntranslated) {
      return untranslatedHintFor(session.btCenasSemTraducao, language);
    }
    final recusa = switch (session.btRecusa) {
      CheckRefusal.partUnheard => 'partUnheard',
      CheckRefusal.nothingTranslated => 'nothingTranslated',
      CheckRefusal.notConferida => 'notConferida',
      CheckRefusal.checkUnavailable => 'checkFailed',
      _ => null,
    };
    if (recusa != null) return retroLabelFor(recusa, language);
    if (session.wordlessTelling) {
      return retroLabelFor('notUnderstood', language);
    }
    return null;
  }

  String? _linha(SalaSessionState session, String language) {
    if (session.btRegravacao?.passo
        case PassoDaRegravacao.pronta || PassoDaRegravacao.gravando) {
      return sceneRehearsalLabelFor('respeakHint', language);
    }
    if (_conferida(session)) {
      return '✓ ${retroLabelFor('translated', language)}';
    }
    return null;
  }

  int? _traduzindoDeNovo(SalaSessionState session) =>
      session.btFraseTraduzidaDeNovo?.frase;

  bool _conferida(SalaSessionState session) =>
      session.btPhase == BtPhase.conferida && !session.needsPerson;

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
    final aberta = session.btPhase != BtPhase.conferida;
    final nomeado = aberta ? session.btTrechoTraduzidoDeNovo : null;
    final escolhida = aberta ? session.btContaEscolhida : null;
    final apontado = nomeado?.segmentId == session.btFindingSegmentId
        ? nomeado?.segmentId
        : null;
    String parte(int onde) => '${retroLabelFor('part', language)} ${onde + 1}';
    String nome(Trecho trecho) => switch (trecho.frase) {
      final n? => sceneRehearsalLabelFor('frase', language, n: n),
      null => parte(trecho.parte),
    };
    final contas = <(BeadFill, bool, bool, VoidCallback?, String)>[
      for (final (onde, trecho) in session.btTrechos.indexed)
        if (nomeado != null && trecho.segmentId == nomeado.segmentId)
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
            aberta && trecho.contado ? () => notifier.ouvirAConta(onde) : null,
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
          session.btSoOuvir ? null : notifier.ouvirOTrechoPendente,
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
          (session.btTraducaoPendente != null &&
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
    SalaColors colors,
  ) {
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
            if (session.approvedDraftDrawn case final aprovado?)
              Text(
                retroLabelFor('approvedDraft', language, n: aprovado.version),
                style: TextStyle(
                  color: colors.ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                ),
              )
            else
              RoundActionButton(
                size: 60,
                semanticLabel: retroLabelFor('approve', language),
                gradient: BeadStyles.verde,
                mood: session.canApprove ? ButtonMood.lit : ButtonMood.dimmed,
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
            semanticLabel: session.btSoOuvir
                ? sceneRehearsalLabelFor('playPause', language)
                : retroLabelFor(
                    soando
                        ? 'pause'
                        : session.btTraducaoPendente != null &&
                              session.btContaEscolhida == null
                        ? 'listenToTheTranslation'
                        : 'listen',
                    language,
                  ),
            gradient: BeadStyles.wood,
            mood: session.btSoOuvir || session.canListenToThePendingStretch
                ? ButtonMood.lit
                : ButtonMood.dimmed,
            onTap: notifier.ouvirGravacao,
            child: Icon(
              _listenGlyph(session),
              size: 24,
              color: ShemaBrand.branco,
            ),
          ),
        ],
      ),
    );
  }

  String _circleLabel(SalaSessionState session, String language) {
    if (session.btSoOuvir) {
      return retroLabelFor(
        session.btClipRodando ? 'listening' : 'listenOnly',
        language,
      );
    }
    if (session.wordlessTelling) {
      return retroLabelFor('notUnderstood', language);
    }
    if (session.btRegravacao?.passo
        case PassoDaRegravacao.pronta || PassoDaRegravacao.gravando) {
      return sceneRehearsalLabelFor('respeakHint', language);
    }
    switch (session.btPhase) {
      case BtPhase.playing:
        if (session.btClipEnded &&
            !session.btTrechoTocando &&
            !session.btParteFronteira &&
            session.btTraducaoPendente == null &&
            session.btTrechoTraduzidoDeNovo == null) {
          return retroLabelFor('endOfTheRecording', language);
        }
        if (session.thePauseStands) {
          return retroLabelFor(
            session.btPausaAjustavel ? 'pauseHint' : 'pauseAtTheTap',
            language,
          );
        }
        if (session.btClipRodando || session.btTrechoTocando) {
          return retroLabelFor('listening', language);
        }
        if (session.btTrechoTraduzidoDeNovo == null &&
            !session.btCortado &&
            session.nothingHeardSinceCursor) {
          return retroLabelFor(
            session.btClipEnded || session.btClipPausada
                ? 'paused'
                : 'listenFirst',
            language,
          );
        }
        if (session.btClipPausada &&
            session.btTraducaoPendente == null &&
            session.btTrechoTraduzidoDeNovo == null) {
          return retroLabelFor('paused', language);
        }
        return retroLabelFor(
          session.btTraducaoPendente != null ? 'recordAgain' : 'record',
          language,
        );
      case BtPhase.capturing:
        return retroLabelFor('recording', language);
      case BtPhase.thinking:
        return retroLabelFor('thinking', language);
      case BtPhase.conferida:
        return retroLabelFor('translated', language);
    }
  }
}

/// «ouvindo a gravação de vocês… — parte 2 · 0:41 / 1:10» while a part sounds, the place
/// alone while it is held.
class _APosicaoDaEscuta extends ConsumerWidget {
  final SalaSessionState session;
  final String language;

  const _APosicaoDaEscuta({required this.session, required this.language});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (parte, soando) = switch (session.channel) {
      PartPlaying(:final part) => (part.part, true),
      Paused(what: final PartSound part) => (part.part, false),
      _ => (null, false),
    };
    if (parte == null) return const SizedBox.shrink();
    final playback = ref.read(playbackRepositoryProvider);
    final colors = SalaColors.of(context);
    return Loop(
      period: const Duration(seconds: 1),
      animate: soando,
      reducible: false,
      builder: (context, _) {
        final lugar = firstListenPositionFor(
          parte + 1,
          playback.position,
          playback.playingLength,
          language,
        );
        return Text(
          soando ? '${retroLabelFor('listening', language)} — $lugar' : lugar,
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.telha, fontSize: 15),
        );
      },
    );
  }
}

class _ManterADeAntes extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _ManterADeAntes({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = SalaColors.of(context);
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      child: Opacity(
        opacity: onTap == null ? 0.35 : 1,
        child: GestureDetector(
          onTap: onTap,
          child: ExcludeSemantics(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.mut),
              ),
              child: Text(
                label,
                style: TextStyle(color: colors.mut, fontSize: 15),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

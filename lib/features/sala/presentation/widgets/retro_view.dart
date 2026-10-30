import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/sala_colors.dart';
import '../../data/playback_repository.dart';
import '../../data/session_notifier.dart';
import '../../domain/kept_take.dart';
import '../../domain/scene_rehearsal.dart';
import '../../domain/bt_finding.dart';
import '../../domain/channel.dart';
import '../../domain/facilitator_script.dart';
import '../../domain/session_state.dart';
import 'approve_button.dart';
import 'bead_styles.dart';
import 'facilitator_circle.dart';
import 'frase_list.dart';
import 'grain_choice_view.dart';
import 'motion.dart';
import 'part_strips.dart';
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
    final voz = _voz(session, conferida);
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
    final dica = retroLabelFor('stretchUntranslated', language);
    final debaixo = session.btAindaFaltaOuvir
        ? retroLabelFor('partUnheard', language)
        : session.btFaltaTraduzirUmTrecho &&
              !(estado?.startsWith(dica) ?? false)
        ? dica
        : null;
    final veredito = session.btVeredito || session.btFindings.isNotEmpty;
    final circulo = herCircleSize(MediaQuery.sizeOf(context), 38, 150);
    final anel = circulo * facilitatorRippleGrowth / 2;
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
            PartStrips(rows: _faixas(session, language)),
            const SizedBox(height: 16),
            if (avanca && session.thePauseCanMove)
              PauseAdjustRow(
                lit: session.canAdjustThePause,
                language: language,
                onEarlier: notifier.pausaUmPoucoAntes,
                onHear: notifier.ouvirAPausa,
                onLater: notifier.pausaUmPoucoDepois,
              ),
            if (!session.btSoOuvir) ...[
              SizedBox(height: 24 + anel),
              FacilitatorCircle(
                size: circulo,
                halt: session.halt,
                voice: voz,
                notUnderstood: session.wordlessTelling
                    ? retroLabelFor('notUnderstood', language)
                    : null,
                semanticLabel: _circleLabel(session, language),
                onTap: notifier.retroTap,
              ),
              SizedBox(height: anel),
            ],
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
              _ALinhaDaEscuta(
                session: session,
                language: language,
                linha: session.btClipRodando ? 'listening' : null,
              ),
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 60),
                child: _actions(session, notifier, language, colors),
              ),
            ),
            if (session.approveOnTheCheck) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FadeUp(
                  child: ApproveButton(live: session.approveActsOnTheCheck),
                ),
              ),
            ],
            if (session.approvedOnTheTell case final aprovado?
                when session.approvalStillOpen ||
                    session.btPhase != BtPhase.conferida) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  retroLabelFor('approvedDraft', language, n: aprovado.version),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
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
            if (!session.btSoOuvir)
              _pilula(session, colors, notifier, language),
            if (avanca && debaixo != null) ...[
              const SizedBox(height: 17.6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  debaixo,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.telha, fontSize: 12.8),
                ),
              ),
            ],
            if (!session.btSoOuvir) ...[
              const SizedBox(height: 16),
              _botaoEscrito(
                findingLabelFor('recordThePart', language),
                colors,
                session.canGoBackToRecordAPart
                    ? notifier.leaveTheBackTranslation
                    : null,
              ),
            ],
            if (session.joined && !session.btSoOuvir) ...[
              const SizedBox(height: 8),
              wholeAtOnce(
                session,
                language,
                notifier.recordTheWholePassage,
                open: session.wholeSwitchActsOnTheCheck,
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
    final quieta = session.theFraseListIsIdle;
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
    int? parteDe(Trecho trecho) => _parteNaTela(session, trecho);
    bool aguarda(Trecho trecho) =>
        session.btFraseQueAguarda != null &&
        trecho.segmentId == session.btFraseQueAguarda;
    FraseRow regravada(int onde, Trecho trecho, int n) => FraseRow(
      n: n,
      parte: parteDe(trecho),
      share: share(trecho),
      onHear:
          quieta &&
              session.canHearAFrase &&
              (trecho.retroPath ?? trecho.bridgeTakeId) != null
          ? () => notifier.ouvirAFraseRegravada(onde)
          : null,
      onRetell:
          quieta &&
              session.canRetellAFrase &&
              trecho.segmentId != null &&
              session.regravadaTraduzivelDeNovo(trecho)
          ? () => notifier.traduzirAFraseRegravadaDeNovo(onde)
          : null,
      mark: retroLabelFor('stale', language),
      achado: _achadoNoTrecho(trecho.segmentId, session),
      regravada: true,
    );
    FraseRow atual(int onde, Trecho trecho, int n) => FraseRow(
      n: n,
      parte: parteDe(trecho),
      share: share(trecho),
      onHear: quieta && session.canHearAFrase
          ? () => notifier.ouvirOTrechoContado(onde)
          : null,
      onRetell: quieta && session.canRetellAFrase && trecho.segmentId != null
          ? () => notifier.traduzirAFraseDeNovo(onde)
          : null,
      mark: aguarda(trecho)
          ? sceneRehearsalLabelFor('awaiting', language)
          : switch (_markOn(trecho.frase, session)) {
              null || BtFindingKind.nuance => null,
              BtFindingKind.other => retroLabelFor('addition', language),
              final kind => retroLabelFor(kind.name, language),
            },
      achado: aguarda(trecho) ? null : _markOn(trecho.frase, session),
      aguardando: aguarda(trecho),
      traduzindoDeNovo:
          trecho.segmentId != null &&
          trecho.segmentId == session.btFraseTraduzidaDeNovo?.segmentId,
      regravando:
          trecho.frase != null && session.btRegravacao?.frase == trecho.frase,
      regravar:
          _aFraseVai(trecho, session) ||
              session.fraseRegravavel(trecho) &&
                  (session.btPhase != BtPhase.conferida ||
                      _markOn(trecho.frase, session) == BtFindingKind.nuance ||
                      session.overAnApprovedDraft)
          ? session.armedTap?.control == 'rerecord:${trecho.frase}'
                ? retroLabelFor('reopenArmed', language)
                : sceneRehearsalLabelFor('rerecordFrase', language, n: n)
          : null,
      regravarDormindo: _dormindo('rerecord:${trecho.frase}', session),
      regravarArmado: session.armedTap?.control == 'rerecord:${trecho.frase}',
      onRegravar:
          switch (session.btRegravacao) {
            null => quieta,
            final regravacao =>
              regravacao.frase == trecho.frase &&
                  regravacao.passo != PassoDaRegravacao.gravando &&
                  regravacao.passo != PassoDaRegravacao.enviando,
          }
          ? () => notifier.regravarAFrase(trecho)
          : null,
      revisao:
          atua &&
              session.btRegravacao?.frase == trecho.frase &&
              session.btRegravacao?.passo == PassoDaRegravacao.revendo
          ? FraseRevisao(
              ouvir: sceneRehearsalLabelFor('listenN', language, n: n),
              tocando: session.btFraseGravadaTocando,
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
        RegravacaoDaFrase(:final frase, passo: PassoDaRegravacao.longaDemais)
            when frase == trecho.frase =>
          sceneRehearsalLabelFor('spliceTooLong', language),
        null
            when trecho.segmentId != null &&
                session.btFraseGuardada == trecho.segmentId =>
          session.armedTap?.control == 'resend:${trecho.segmentId}'
              ? retroLabelFor('reopenArmed', language)
              : sceneRehearsalLabelFor('spliceFail', language),
        _ => null,
      },
      estadoDormindo: _dormindo('resend:${trecho.segmentId}', session),
      estadoArmado: session.armedTap?.control == 'resend:${trecho.segmentId}',
      onEstado:
          atua &&
              quieta &&
              !session.needsPerson &&
              !session.btSoOuvir &&
              session.btRegravacao == null &&
              trecho.segmentId != null &&
              session.btFraseGuardada == trecho.segmentId
          ? notifier.tentarAFraseDeNovo
          : null,
    );
    return [
      for (final (posicao, (:dela, :onde, :trecho)) in _naOrdem(
        session,
      ).indexed)
        dela
            ? regravada(onde, trecho, posicao + 1)
            : atual(onde, trecho, posicao + 1),
    ];
  }

  int? _parteNaTela(SalaSessionState session, Trecho trecho) =>
      trecho.parte < 0 ||
          session.partes.elementAtOrNull(trecho.parte)?.scopeId ==
              KeptScope.whole
      ? null
      : session.numeroDaParte(trecho.parte);

  List<({bool dela, int onde, Trecho trecho})> _naOrdem(
    SalaSessionState session,
  ) {
    final regravadas = [
      for (final (onde, trecho)
          in [...session.btTrechosRegravados.indexed]..sort(
            (a, b) => a.$2.parte == b.$2.parte
                ? a.$1.compareTo(b.$1)
                : a.$2.parte.compareTo(b.$2.parte),
          ))
        (dela: true, onde: onde, trecho: trecho),
    ];
    final ordem = <({bool dela, int onde, Trecho trecho})>[];
    var antes = 0;
    for (final (onde, trecho) in session.btTrechos.indexed) {
      if (!trecho.contado) continue;
      while (antes < regravadas.length &&
          (_parteNaTela(session, regravadas[antes].trecho) ?? 0) <
              (_parteNaTela(session, trecho) ?? 0)) {
        ordem.add(regravadas[antes++]);
      }
      ordem.add((dela: false, onde: onde, trecho: trecho));
    }
    return [...ordem, ...regravadas.skip(antes)];
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
        _dormindo('restart', session) ||
        !session.aBackTranslationGestureActs ||
        !session.theFraseListIsIdle ||
        session.btRegravacao != null;
    return Semantics(
      button: true,
      enabled: !dormindo,
      label: rotulo,
      onTap: dormindo ? null : notifier.recomecarATraducao,
      child: Opacity(
        opacity: dormindo ? 0.4 : 1,
        child: ExcludeSemantics(
          child: GestureDetector(
            onTap: dormindo ? null : notifier.recomecarATraducao,
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
      onTap: onTap,
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

  bool _aFraseVai(Trecho trecho, SalaSessionState session) =>
      session.btFraseDevida == null &&
      session.btRegravacao?.frase == trecho.frase &&
      session.btRegravacao?.passo == PassoDaRegravacao.enviando;

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
      BtAviso.tocarFalhou => 'checkFailed',
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
    return null;
  }

  int? _traduzindoDeNovo(SalaSessionState session) {
    final nome = session.btFraseTraduzidaDeNovo?.segmentId;
    if (nome == null) return null;
    final posicao = _naOrdem(
      session,
    ).indexWhere((linha) => linha.trecho.segmentId == nome);
    return posicao < 0 ? null : posicao + 1;
  }

  bool _conferida(SalaSessionState session) =>
      session.btPhase == BtPhase.conferida && !session.needsPerson;

  BtFindingKind? _achadoNoTrecho(String? segmentId, SalaSessionState session) {
    if (segmentId == null) return null;
    for (final finding in session.btFindings) {
      if (finding.segmentId == segmentId) return finding.kind;
    }
    return null;
  }

  BtFindingKind? _markOn(int? frase, SalaSessionState session) {
    if (frase == null) return null;
    for (final finding in session.btFindings) {
      if (finding.frase == frase) return finding.kind;
    }
    return null;
  }

  Widget _pilula(
    SalaSessionState session,
    SalaColors colors,
    SalaSessionNotifier notifier,
    String language,
  ) {
    final terminei = retroLabelFor(
      session.btConferindo ? 'checking' : 'advance',
      language,
    );
    final acesa = session.canAdvanceToTheVerdict;
    return FadeUp(
      child: Semantics(
        button: true,
        enabled: acesa,
        label: terminei,
        child: GestureDetector(
          onTap: acesa
              ? () => unawaited(notifier.finishBackTranslation())
              : null,
          child: ExcludeSemantics(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: AnimatedOpacity(
                    opacity: acesa ? 1 : 0.35,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      decoration: BoxDecoration(
                        color: colors.telha,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 35.2,
                    vertical: 12.8,
                  ),
                  child: Text(
                    terminei,
                    style: TextStyle(
                      color: acesa ? colors.paper : colors.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  VoiceState _voz(SalaSessionState session, bool conferida) {
    if (session.btRegravacao?.passo == PassoDaRegravacao.gravando) {
      return VoiceState.listening;
    }
    if (conferida) return VoiceState.done;
    if (session.voice != VoiceState.invite) return session.voice;
    if (session.btRetroTocando ||
        session.btClipRodando ||
        session.btTrechoTocando) {
      return VoiceState.speaking;
    }
    return VoiceState.invite;
  }

  List<PartStripRow> _faixas(SalaSessionState session, String language) => [
    for (final (onde, parte) in session.partes.indexed)
      PartStripRow(
        label: parte.scopeId == KeptScope.whole
            ? recordingHomeLabelFor('wholePassage', language)
            : '${retroLabelFor('part', language)} ${onde + 1}',
        length: session.partLoudness[parte.path]?.length,
        envelope: session.partLoudness[parte.path]?.envelope,
        told: [
          for (final trecho in session.btTrechos)
            if (trecho.contado && trecho.parte == onde)
              _naFaixa(trecho, ate: _aPausaQueAnda(session, trecho)),
        ],
        stale: [
          for (final trecho in session.btTrechosRegravados)
            if (trecho.parte == onde) _naFaixa(trecho),
        ],
        pausa: session.btCortado && session.btParte == onde
            ? session.btCorte
            : null,
        playing: switch (session.channel) {
          PartPlaying(:final part) => part.part == onde,
          _ => false,
        },
        now: switch (session.channel) {
          PartPlaying(:final part) ||
          Paused(what: final PartSound part) ||
          GuideSpeaking(held: Paused(what: final PartSound part)) ||
          Microphone(
            held: Paused(what: final PartSound part),
          ) => part.part == onde,
          _ => session.btParteQueTocou == onde,
        },
        unheard:
            parte.takeId == null || session.btNaoOuvidas.contains(parte.takeId),
        paused: switch (_aParteParada(session.channel)) {
          final Paused parada && Paused(what: PartSound(:final part))
              when part == onde =>
            parada,
          _ => null,
        },
      ),
  ];

  Paused? _aParteParada(Channel channel) => switch (channel) {
    final Paused parada when parada.what is PartSound => parada,
    Playing(sound: final StretchSound outra, :final held) ||
    Paused(
      what: final StretchSound outra,
      :final held,
    ) when !outra.telling && outra.path != held?.what.path => null,
    Playing(:final held) ||
    Paused(:final held) ||
    Microphone(:final held) => held,
    _ => null,
  };

  Duration? _aPausaQueAnda(SalaSessionState session, Trecho trecho) =>
      switch (session.btTrechoTraduzidoDeNovo?.segmentId) {
        final contadaDeNovo? when contadaDeNovo == trecho.segmentId =>
          trecho.lugarFrom + session.btCorte - trecho.from,
        _ => null,
      };

  SceneFrase _naFaixa(Trecho trecho, {Duration? ate}) => SceneFrase(
    fraseId: trecho.segmentId ?? trecho.takeId,
    startsMs: trecho.lugarFrom.inMilliseconds,
    endsMs: (ate ?? trecho.lugarTo).inMilliseconds,
  );

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
            if (session.approvedDraftDrawn != null &&
                !session.approvalStillOpen)
              const SizedBox(width: 24),
            if (session.approvedDraftDrawn case final aprovado?
                when !session.approvalStillOpen)
              Flexible(
                child: Text(
                  retroLabelFor('approvedDraft', language, n: aprovado.version),
                  style: TextStyle(
                    color: colors.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                  ),
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
          if (_aEscuta(session) case final linha
              when linha != null ||
                  !session.btSoOuvir && _parteNoAr(session) != null) ...[
            const SizedBox(width: 11.2),
            Flexible(
              child: _ALinhaDaEscuta(
                session: session,
                language: language,
                linha: linha,
                textAlign: TextAlign.start,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String? _aEscuta(SalaSessionState session) {
    if (session.btSoOuvir) return null;
    if (session.btTrechoTraduzidoDeNovo != null ||
        session.btRegravacao != null) {
      return session.btTrechoTocando ? 'listening' : null;
    }
    if (session.btClipEnded && !session.btParteFronteira) {
      return 'endOfTheRecording';
    }
    if (session.btCortado) {
      return session.btPausaAjustavel ? 'pauseHint' : 'pauseAtTheTap';
    }
    if (session.btClipRodando || session.btTrechoTocando) return 'listening';
    if (session.btParteFronteira) return null;
    return 'paused';
  }

  String _circleLabel(SalaSessionState session, String language) {
    if (session.wordlessTelling) {
      return retroLabelFor('notUnderstood', language);
    }
    if (session.btRegravacao?.passo
        case PassoDaRegravacao.pronta ||
            PassoDaRegravacao.gravando ||
            PassoDaRegravacao.revendo) {
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

/// «ouvindo a gravação de vocês… — parte 2 · 0:41 / 1:10»: her line, then the place while
/// a part sounds or is held, or the end of a sentence told or recorded again while nothing
/// sounds; either alone when the other is missing.
class _ALinhaDaEscuta extends ConsumerWidget {
  final SalaSessionState session;
  final String language;
  final String? linha;
  final TextAlign textAlign;

  const _ALinhaDaEscuta({
    required this.session,
    required this.language,
    required this.linha,
    this.textAlign = TextAlign.center,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parte = _parteNoAr(session);
    if (parte == null && linha == null) return const SizedBox.shrink();
    final playback = ref.read(playbackRepositoryProvider);
    final colors = SalaColors.of(context);
    return Loop(
      period: const Duration(seconds: 1),
      animate: session.channel is PartPlaying,
      reducible: false,
      builder: (context, _) {
        final lugar = switch (parte) {
          null => null,
          (:final parte, :final ondeFicou) => _oLugar(
            session,
            parte,
            ondeFicou ?? playback.position,
            ondeFicou == null
                ? playback.playingLength
                : session.btTamanhoDaParte(parte),
            language,
          ),
        };
        return Text(
          [
            if (linha case final linha?) retroLabelFor(linha, language),
            ?lugar,
          ].join(' — '),
          textAlign: textAlign,
          style: TextStyle(color: colors.telha, fontSize: 15),
        );
      },
    );
  }
}

String _oLugar(
  SalaSessionState session,
  int parte,
  Duration at,
  Duration? length,
  String language,
) => session.partes.elementAtOrNull(parte)?.scopeId == KeptScope.whole
    ? sceneClockOf(at, length)
    : firstListenPositionFor(
        session.numeroDaParte(parte),
        at,
        length,
        language,
      );

({int parte, Duration? ondeFicou})? _parteNoAr(SalaSessionState session) =>
    switch (session.channel) {
      PartPlaying(:final part) ||
      Paused(what: final PartSound part) ||
      Microphone(
        held: Paused(what: final PartSound part),
      ) => (parte: part.part, ondeFicou: null),
      Playing(held: Paused(what: final PartSound part)) => (
        parte: part.part,
        ondeFicou: part.from,
      ),
      _ when !session.btTrechoTocando => switch (_aFraseDeNovo(session)) {
        final trecho?
            when trecho.parte >= 0 && trecho.parte < session.partes.length =>
          (parte: trecho.parte, ondeFicou: trecho.lugarTo),
        _ => null,
      },
      _ => null,
    };

Trecho? _aFraseDeNovo(SalaSessionState session) =>
    session.btTrechoTraduzidoDeNovo ??
    switch (session.btRegravacao) {
      final regravacao? =>
        session.btTrechos
            .where((trecho) => trecho.frase == regravacao.frase)
            .firstOrNull,
      null => null,
    };

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

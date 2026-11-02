import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show settle;
import 'um_ensaio_de_tres_partes.dart';

const _gravacao = 'gravacao-1';
const _umaParte = Duration(seconds: 30);

Future<Sala> _conferidaEDeixadaPelaVolta() async {
  final it = await umEnsaioDeTresPartesContadoInteiro();
  it.harness.room.retroSoFar = BackTranslationProgress(
    segments: [...it.harness.room.segments],
    checked: true,
  );
  await pedirOVeredito(it);
  expect(it.estado.btPhase, BtPhase.conferida);
  it.sala.leaveTheBackTranslation();
  await waitFor(
    'a equipe voltar à casa da gravação',
    () => it.estado.stage == SalaStage.ensaio,
  );
  return it;
}

Future<void> _traduzirAGravacao(Sala it) async {
  it.sala.startRetro();
  await waitFor(
    'a tradução voltar',
    () => it.estado.stage == SalaStage.retro && !it.estado.awaitingTheGuide,
  );
  await settle();
}

void main() {
  test(
    'coming back from the home to a passage checked clean lands on its verdict, '
    'with nothing played and nothing said',
    () async {
      final it = await _conferidaEDeixadaPelaVolta();
      it.harness.room.listeningUnheardTakeIds = const [];
      final tocadas = it.harness.playback.played.length;
      final falas = it.harness.voice.fixedLines.length;

      await _traduzirAGravacao(it);

      expect(
        it.estado.btPhase,
        BtPhase.conferida,
        reason: 'a volta da casa esquecia a conferência e reabria a tradução',
      );
      expect(it.estado.btVeredito, isTrue);
      expect(it.harness.playback.played.skip(tocadas), isEmpty);
      expect(it.harness.voice.fixedLines.skip(falas), isEmpty);
    },
  );

  test(
    'a room that says nothing of what was heard still brings the checked '
    'passage back to its verdict, not to the untold ground playing',
    () async {
      final it = await _conferidaEDeixadaPelaVolta();
      it.harness.room.listeningUnheardTakeIds = null;
      final tocadas = it.harness.playback.played.length;

      await _traduzirAGravacao(it);

      expect(it.estado.btPhase, BtPhase.conferida);
      expect(
        it.harness.playback.played.skip(tocadas),
        isEmpty,
        reason: 'a última parte voltava a tocar sobre a conferência limpa',
      );
    },
  );

  test('a passage checked clean comes back with the marks the room keeps on '
      'its frases', () async {
    final it = await _conferidaEDeixadaPelaVolta();
    final trechos = [
      for (final (n, one) in it.harness.room.segments.indexed)
        SegmentView(
          segmentId: one.segmentId,
          takeId: one.takeId,
          startsMs: one.startsMs,
          endsMs: one.endsMs,
          told: one.told,
          frase: n + 1,
        ),
    ];
    it.harness.room
      ..listeningUnheardTakeIds = const []
      ..retroSoFar = BackTranslationProgress(
        segments: trechos,
        checked: true,
        namedNuance: BtFinding(
          kind: BtFindingKind.nuance,
          frase: 1,
          segmentId: trechos[0].segmentId,
        ),
        findings: [
          BtFinding(
            kind: BtFindingKind.unclear,
            frase: 2,
            segmentId: trechos[1].segmentId,
          ),
        ],
      );

    await _traduzirAGravacao(it);

    expect(it.estado.btPhase, BtPhase.conferida);
    expect(
      [
        for (final trecho in it.estado.btTrechos)
          [
            for (final f in it.estado.btFindings)
              if (f.frase == trecho.frase) f.kind,
          ],
      ],
      [
        [BtFindingKind.nuance],
        [BtFindingKind.unclear],
        for (var n = 2; n < trechos.length; n++) <BtFindingKind>[],
      ],
      reason: 'a volta à conferência voltava sem as marcas que a sala guardou',
    );
  });

  test('a passage the room no longer counts as checked when the team comes '
      'back gets no verdict restored', () async {
    final it = await _conferidaEDeixadaPelaVolta();
    it.harness.room
      ..listeningUnheardTakeIds = const []
      ..retroSoFar = BackTranslationProgress(
        segments: [...it.harness.room.segments],
      );

    await _traduzirAGravacao(it);

    expect(
      it.estado.btPhase,
      BtPhase.playing,
      reason: 'o veredito voltava sobre uma passagem que a sala já não conta',
    );
  });

  test('an approved passage opened from the home lands on its verdict with its '
      'badge and its frases, never the parts played again', () async {
    final harness = SalaHarness()
      ..playback.length = _umaParte
      ..playback.measured = _umaParte;
    harness.room
      ..approvedDraft = const ApprovedDraft(version: 1)
      ..retroSoFar = const BackTranslationProgress(
        segments: [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: _gravacao,
            startsMs: 0,
            endsMs: 12000,
          ),
          SegmentView(
            segmentId: 'trecho-2',
            takeId: _gravacao,
            startsMs: 12000,
            endsMs: 30000,
          ),
        ],
        checked: true,
      )
      ..takes.add(
        const TakeView(
          takeId: _gravacao,
          kind: 'ensaio',
          scope: 'parte-1',
          ordinal: 1,
        ),
      )
      ..takeAudio[_gravacao] = Uint8List.fromList([7, 7, 7, 7])
      ..openedSessions.add('sessao-antiga')
      ..listeningUnheardTakeIds = const [];
    harness.emAberto.rows['Ruth/P01/${harness.lingua}'] = const ResumePoint(
      sessionId: 'sessao-antiga',
      stage: SalaStage.retro,
    );
    final container = harness.container();
    addTearDown(container.dispose);
    final sala = container.read(salaSessionProvider.notifier);
    SalaSessionState estado() => container.read(salaSessionProvider);
    await sala.abrirEscolha();
    await settle();
    await sala.goConversa(book: 'Ruth', pericope: 'P01');
    await waitFor(
      'a passagem aprovada pousar na conversa',
      () => estado().stage == SalaStage.conversa && !estado().awaitingTheGuide,
    );
    sala.openTheEnsaioFinal();
    await waitFor(
      'a casa da gravação abrir com a parte da sala',
      () => estado().stage == SalaStage.ensaio && estado().partes.isNotEmpty,
    );
    await settle();
    final tocadas = harness.playback.played.length;
    final falas = harness.voice.fixedLines.length;

    sala.startRetro();
    await waitFor(
      'a tradução abrir',
      () => estado().stage == SalaStage.retro && !estado().awaitingTheGuide,
    );
    await settle();

    expect(
      estado().btPhase,
      BtPhase.conferida,
      reason: 'a passagem aprovada recomeçava a tradução do zero',
    );
    expect(estado().approvedDraftDrawn?.version, 1);
    expect(estado().btTrechos, hasLength(2));
    expect(
      harness.playback.played.skip(tocadas),
      isEmpty,
      reason: 'as partes tocavam de novo antes do selo',
    );
    expect(harness.voice.fixedLines.skip(falas), isEmpty);
  });

  test('re-entering a checked passage shows the check at once, and the marks '
      'are drawn when the read answers', () async {
    final it = await _conferidaEDeixadaPelaVolta();
    final trechos = [
      for (final (n, one) in it.harness.room.segments.indexed)
        SegmentView(
          segmentId: one.segmentId,
          takeId: one.takeId,
          startsMs: one.startsMs,
          endsMs: one.endsMs,
          told: one.told,
          frase: n + 1,
        ),
    ];
    it.harness.room
      ..listeningUnheardTakeIds = const []
      ..retroSoFar = BackTranslationProgress(
        segments: trechos,
        checked: true,
        findings: [
          BtFinding(
            kind: BtFindingKind.unclear,
            frase: 2,
            segmentId: trechos[1].segmentId,
          ),
        ],
      )
      ..holdNextState();

    it.sala.startRetro();
    await waitFor('a tradução abrir', () => it.estado.stage == SalaStage.retro);
    await settle();

    expect(
      it.estado.btPhase,
      BtPhase.conferida,
      reason: 'a passagem conferida mostrava «pensando» enquanto a sala lia',
    );
    expect(it.estado.btVeredito, isFalse);

    it.harness.room.finishHeldState();
    await waitFor('o veredito chegar', () => it.estado.btVeredito);

    expect(it.estado.btPhase, BtPhase.conferida);
    expect(
      [for (final f in it.estado.btFindings) f.kind],
      [BtFindingKind.unclear],
    );
  });

  const _trechos = [
    SegmentView(
      segmentId: 'trecho-1',
      takeId: _gravacao,
      startsMs: 0,
      endsMs: 12000,
      frase: 1,
    ),
    SegmentView(
      segmentId: 'trecho-2',
      takeId: _gravacao,
      startsMs: 12000,
      endsMs: 30000,
      frase: 2,
    ),
  ];

  Future<(SalaHarness, ProviderContainer)> _relaunchedOnAChecked() async {
    final harness = SalaHarness()
      ..playback.length = _umaParte
      ..playback.measured = _umaParte;
    harness.room
      ..retroSoFar = const BackTranslationProgress(
        segments: _trechos,
        checked: true,
        namedNuance: BtFinding(
          kind: BtFindingKind.nuance,
          frase: 1,
          segmentId: 'trecho-1',
        ),
      )
      ..takes.add(
        const TakeView(
          takeId: _gravacao,
          kind: 'ensaio',
          scope: 'parte-1',
          ordinal: 1,
        ),
      )
      ..takeAudio[_gravacao] = Uint8List.fromList([7, 7, 7, 7])
      ..openedSessions.add('sessao-antiga')
      ..listeningUnheardTakeIds = const [];
    harness.emAberto.rows['Ruth/P01/${harness.lingua}'] = const ResumePoint(
      sessionId: 'sessao-antiga',
      stage: SalaStage.retro,
    );
    final container = harness.container();
    addTearDown(container.dispose);
    final sala = container.read(salaSessionProvider.notifier);
    SalaSessionState estado() => container.read(salaSessionProvider);
    await sala.abrirEscolha();
    await settle();
    await sala.goConversa(book: 'Ruth', pericope: 'P01');
    await waitFor(
      'a passagem pousar na conversa',
      () => estado().stage == SalaStage.conversa && !estado().awaitingTheGuide,
    );
    sala.openTheEnsaioFinal();
    await waitFor(
      'a casa da gravação abrir com a parte da sala',
      () => estado().stage == SalaStage.ensaio && estado().partes.isNotEmpty,
    );
    await settle();
    return (harness, container);
  }

  Future<Sala> _reenteredWhileTheReadIsInTheAir() async {
    final it = await _conferidaEDeixadaPelaVolta();
    it.harness.room
      ..listeningUnheardTakeIds = const []
      ..holdNextState();
    it.sala.startRetro();
    await waitFor('a tradução abrir', () => it.estado.stage == SalaStage.retro);
    await settle();
    return it;
  }

  test('a relaunch onto a checked passage shows the check at once, and the '
      'marks are drawn when the read answers', () async {
    final (harness, container) = await _relaunchedOnAChecked();
    SalaSessionState estado() => container.read(salaSessionProvider);
    harness.room.holdNextState();

    container.read(salaSessionProvider.notifier).startRetro();
    await waitFor('a tradução abrir', () => estado().stage == SalaStage.retro);
    await settle();

    expect(estado().btPhase, BtPhase.conferida);
    expect(estado().btVeredito, isFalse);

    harness.room.finishHeldState();
    await waitFor('o veredito chegar', () => estado().btVeredito);

    expect(estado().btPhase, BtPhase.conferida);
    expect(
      [for (final f in estado().btFindings) f.kind],
      [BtFindingKind.nuance],
    );
  });

  test('a resume whose re-entry read fails opens the check with the nuance '
      'mark the resume restored', () async {
    final (harness, container) = await _relaunchedOnAChecked();
    SalaSessionState estado() => container.read(salaSessionProvider);
    harness.room.failStateOnceWith = const NetworkFailed('sem rede');

    container.read(salaSessionProvider.notifier).startRetro();
    await waitFor(
      'a tradução abrir',
      () => estado().stage == SalaStage.retro && !estado().awaitingTheGuide,
    );
    await settle();

    expect(estado().btPhase, BtPhase.conferida);
    expect(
      [for (final f in estado().btFindings) f.kind],
      [BtFindingKind.nuance],
      reason: 'a leitura falha abria a conferência sem a marca de nuance',
    );
  });

  test(
    'while the re-entry read is in the air the gestures act on the last '
    'restored verdict, and the room\'s refusal is shown as it is today',
    () async {
      final it = await _reenteredWhileTheReadIsInTheAir();
      it.harness.room.releaseBlockers = const ['telling_back_not_checked'];

      await it.sala.aprovarRascunhoFinal();
      await settle();

      expect(it.harness.room.releasesAsked, hasLength(1));
      expect(it.estado.btRecusa, CheckRefusal.notConferida);

      final tocadas = it.harness.playback.played.length;
      it.sala.ouvirGravacao();
      await settle();

      expect(it.harness.playback.played.length, tocadas + 1);
      it.harness.room.finishHeldState();
      await settle();
    },
  );

  test('a frase retold while the re-entry read is in the air keeps its open '
      'microphone when the read lands, and the circle closes it', () async {
    final it = await _reenteredWhileTheReadIsInTheAir();
    it.sala.traduzirAFraseDeNovo(1);
    await settle();
    it.sala.retroTap();
    await settle();
    expect(it.estado.channel, isA<Microphone>());

    it.harness.room.finishHeldState();
    await settle();

    expect(
      it.estado.channel,
      isA<Microphone>(),
      reason: 'a leitura que pousou fechou o microfone sem a frase subir',
    );
    expect(
      it.estado.btPhase,
      BtPhase.capturing,
      reason: 'a leitura tomava a fase de debaixo do microfone aberto',
    );
    it.sala.retroTap();
    await settle();
    expect(it.estado.channel, isNot(isA<Microphone>()));
  });

  test('a read that names an unheard part never lets the guide speak over a '
      'screen standing as the verdict', () async {
    final it = await _conferidaEDeixadaPelaVolta();
    it.harness.room.listeningUnheardTakeIds = [it.estado.partes.first.takeId!];
    it.harness.voice.holdNextLine();
    final fases = <BtPhase>[];
    it.container.listen<SalaSessionState>(salaSessionProvider, (_, s) {
      if (s.channel is GuideSpeaking) fases.add(s.btPhase);
    });

    it.sala.startRetro();
    await waitFor('a sala falar', () => it.estado.channel is GuideSpeaking);
    await settle();

    expect(fases, isNotEmpty);
    expect(
      fases,
      everyElement(isNot(BtPhase.conferida)),
      reason: 'a tela já dizia conferida enquanto a sala convidava a ouvir',
    );
    it.harness.voice.finishHeldLine();
    await settle();
  });

  test('a read that no longer counts the passage as checked corrects the '
      'screen it stood in as the verdict', () async {
    final it = await _reenteredWhileTheReadIsInTheAir();
    it.harness.room.retroSoFar = BackTranslationProgress(
      segments: [...it.harness.room.segments],
    );

    it.harness.room.finishHeldState();
    await waitFor('a leitura pousar', () => !it.estado.awaitingTheGuide);
    await settle();

    expect(it.estado.btPhase, BtPhase.playing);
    expect(it.estado.btVeredito, isFalse);
  });
}

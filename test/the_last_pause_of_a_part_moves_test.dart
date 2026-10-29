import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/part_strips.dart';
import 'package:internalization_room/features/sala/presentation/widgets/scene_strip.dart';

import 'package:internalization_room/main.dart';

import 'a_wav_take.dart';
import 'fakes.dart';
import 'scenario_helpers.dart'
    show byLabel, stateReads, traduzirOApontadoDeNovo;
import 'the_back_translation_is_told_by_beads_test.dart'
    show aceso, entrarNaTraducao, parte, tocar;
import 'the_pause_snaps_to_silence_test.dart'
    show
        antes,
        depois,
        ouvirAPausa,
        pausarAos,
        rotuloDoCirculo,
        s,
        traduzirEConfirmar;

final _duasLacunas = aSpokenWav(gaps: [(s(3.0), s(3.4)), (s(6.0), s(6.4))]);

Future<void> _passo(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 100));

String _barra(int n) => 'Ouvir esta frase de novo e traduzir de novo — $n';

List<List<(int?, int?)>> _bandas(WidgetTester tester) => [
  for (final faixa in tester.widgetList<SceneStrip>(
    find.descendant(
      of: find.byType(PartStrips),
      matching: find.byType(SceneStrip),
    ),
  ))
    [for (final frase in faixa.frases) (frase.startsMs, frase.endsMs)],
];

Future<ProviderContainer> _duasFrasesNoVeredito(
  WidgetTester tester,
  SalaHarness harness, {
  String? apontada,
}) async {
  final container = await entrarNaTraducao(tester, harness, partes: 1);
  for (final (n, toque) in [(1, s(4.2)), (2, s(7.0))]) {
    await pausarAos(tester, harness, toque);
    await traduzirEConfirmar(tester);
    await waitFor(
      'a frase $n chegar à sala',
      () =>
          container
              .read(salaSessionProvider)
              .btTrechos
              .where((trecho) => trecho.contado)
              .length ==
          n,
      step: () => _passo(tester),
    );
  }
  harness.playback.at = parte;
  harness.playback.finishPlayback();
  await _passo(tester);
  harness.room
    ..verdictChecked = apontada == null
    ..verdictHasFinding = apontada != null
    ..verdictFindingSegmentId = apontada;
  unawaited(
    container.read(salaSessionProvider.notifier).finishBackTranslation(),
  );
  await waitFor(
    'o veredito chegar',
    () =>
        container.read(salaSessionProvider).btPhase ==
        (apontada == null ? BtPhase.conferida : BtPhase.playing),
    step: () => _passo(tester),
  );
  await _passo(tester);
  return container;
}

Future<ProviderContainer> _duasFrasesEUmAchadoNa(
  WidgetTester tester,
  SalaHarness harness,
  String apontada,
) async {
  final container = await _duasFrasesNoVeredito(
    tester,
    harness,
    apontada: apontada,
  );
  traduzirOApontadoDeNovo(container);
  await waitFor(
    'a frase apontada ficar para traduzir de novo',
    () => container.read(salaSessionProvider).btTrechoTraduzidoDeNovo != null,
    step: () => _passo(tester),
  );
  harness.playback.finishPlayback();
  await _passo(tester);
  return container;
}

Future<ProviderContainer> _voltaComAFraseQueAguarda(
  WidgetTester tester,
  SalaHarness harness, {
  bool aguarda = true,
}) async {
  final pasta = Directory.systemTemp.createTempSync('sala-1223');
  addTearDown(() => pasta.deleteSync(recursive: true));
  const daSala = [
    SegmentView(
      segmentId: 'trecho-1',
      takeId: 'gravacao-1',
      startsMs: 0,
      endsMs: 4000,
      frase: 1,
    ),
    SegmentView(
      segmentId: 'trecho-2',
      takeId: 'gravacao-1',
      startsMs: 4000,
      endsMs: 10000,
      frase: 2,
    ),
  ];
  harness.emAberto.rows['Ruth/P01/pt'] = ResumePoint(
    sessionId: 'sessao-antiga',
    stage: SalaStage.retro,
    takes: [
      KeptTake(
        scopeId: KeptScope.parte(1),
        path: (File(
          '${pasta.path}/p1.wav',
        )..writeAsBytesSync(aSpokenWav(length: parte))).path,
        takeId: 'gravacao-1',
      ),
    ],
  );
  harness.room
    ..segments.addAll(daSala)
    ..takes.add(
      TakeView(
        takeId: 'gravacao-1',
        kind: 'ensaio',
        scope: KeptScope.parte(1),
        ordinal: 1,
      ),
    )
    ..retroSoFar = BackTranslationProgress(
      segments: daSala,
      awaitingSegmentId: aguarda ? 'trecho-2' : null,
    );
  final container = harness.container();
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await _passo(tester);
  unawaited(
    container
        .read(salaSessionProvider.notifier)
        .goConversa(book: 'Ruth', pericope: 'P01'),
  );
  await waitFor(
    aguarda
        ? 'a frase 2 voltar esperando a tradução'
        : 'a tradução voltar com as duas frases',
    () => aguarda
        ? container
                  .read(salaSessionProvider)
                  .btTrechoTraduzidoDeNovo
                  ?.segmentId ==
              'trecho-2'
        : container.read(salaSessionProvider).btTrechos.length == 2,
    step: () => letTheRehearsalReachTheRoom(tester),
  );
  await _passo(tester);
  return container;
}

void main() {
  testWidgets(
    'the last frase of a part told again takes a later pause, and its span follows it',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true)
        ..recorder.rehearsalSpeaks = _duasLacunas;
      final container = await _duasFrasesEUmAchadoNa(
        tester,
        harness,
        'trecho-2',
      );

      for (final controle in [antes, ouvirAPausa, depois]) {
        expect(
          aceso(tester, controle),
          isTrue,
          reason: 'a última frase não abria a fileira da pausa: $controle',
        );
      }
      await tocar(tester, depois);
      await tocar(tester, 'Tocar para gravar a tradução de novo');
      await tocar(tester, 'Tocar ao terminar');
      await waitFor(
        'a frase voltar da sala',
        () => harness.room.replacesAsked.isNotEmpty,
        step: () => _passo(tester),
      );

      expect(
        harness.room.replacesAsked.single,
        endsWith(':3200-6600'),
        reason: 'a pausa nova não ia para a sala; a frase guardava o fim velho',
      );
      await waitFor(
        'a frase pousar com o fim novo',
        () =>
            container.read(salaSessionProvider).btTrechoTraduzidoDeNovo == null,
        step: () => _passo(tester),
      );
      expect(
        [
          for (final trecho in container.read(salaSessionProvider).btTrechos)
            trecho.to,
        ],
        [s(3.2), s(6.6)],
        reason: 'a frase seguia com o fim de antes',
      );
      closeTheRoom(container);
    },
  );

  testWidgets(
    'a tap on the bar of the last frase of a part opens her controls, and the moved pause becomes its span',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true)
        ..recorder.rehearsalSpeaks = _duasLacunas;
      final container = await _duasFrasesNoVeredito(
        tester,
        harness,
        apontada: 'trecho-1',
      );

      await tocar(tester, _barra(2));
      for (final controle in [antes, ouvirAPausa, depois]) {
        expect(
          aceso(tester, controle),
          isTrue,
          reason:
              'o toque na barra da última frase não abria a pausa: $controle',
        );
      }
      await tocar(tester, depois);
      await tocar(tester, 'Tocar para gravar a tradução de novo');
      await tocar(tester, 'Tocar ao terminar');
      await waitFor(
        'a frase pousar com o fim novo',
        () =>
            container.read(salaSessionProvider).btTrechoTraduzidoDeNovo == null,
        step: () => _passo(tester),
      );

      expect(harness.room.replacesAsked, ['trecho-2@gravacao-1:3200-6600']);
      expect(
        [
          for (final trecho in container.read(salaSessionProvider).btTrechos)
            trecho.to,
        ],
        [s(3.2), s(6.6)],
        reason: 'a frase tocada na barra seguia com o fim de antes',
      );
      closeTheRoom(container);
    },
  );

  testWidgets(
    'a second tap on the bar of the frase being told again keeps the pause the team moved and replays up to it',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true)
        ..recorder.rehearsalSpeaks = _duasLacunas;
      final container = await _duasFrasesNoVeredito(
        tester,
        harness,
        apontada: 'trecho-1',
      );
      await tocar(tester, _barra(2));
      await tocar(tester, depois);

      await tocar(tester, _barra(2));

      expect(
        container.read(salaSessionProvider).btCorte,
        s(6.6),
        reason: 'o segundo toque na barra devolvia a pausa ao fim de antes',
      );
      expect(
        harness.playback.ranges.last,
        '3200-6600',
        reason: 'a frase tocava até o fim de antes e não até a pausa movida',
      );
      await tocar(tester, 'ouvindo a gravação de vocês…');
      await tocar(tester, 'Tocar ao terminar');
      await waitFor(
        'a frase voltar da sala',
        () => harness.room.replacesAsked.isNotEmpty,
        step: () => _passo(tester),
      );
      expect(
        harness.room.replacesAsked,
        ['trecho-2@gravacao-1:3200-6600'],
        reason:
            'a pausa movida se perdia no segundo toque e a sala recebia o fim velho',
      );
      closeTheRoom(container);
    },
  );

  testWidgets(
    'the band of the frase being told again ends at the pause the team moves, not at its old end',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true)
        ..recorder.rehearsalSpeaks = _duasLacunas;
      final container = await _duasFrasesNoVeredito(
        tester,
        harness,
        apontada: 'trecho-1',
      );
      await tocar(tester, _barra(2));

      await tocar(tester, depois);

      expect(
        _bandas(tester),
        [
          [(0, 3200), (3200, 6600)],
        ],
        reason:
            'a faixa da frase traduzida de novo seguia no fim de antes, longe da pausa movida',
      );
      closeTheRoom(container);
    },
  );

  testWidgets(
    'a frase told on a recording this tablet does not hold replays up to the moved pause on the ruler of its place',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true)
        ..recorder.rehearsalSpeaks = _duasLacunas;
      final container = await _duasFrasesNoVeredito(
        tester,
        harness,
        apontada: 'trecho-1',
      );
      await tocar(tester, _barra(2));
      final antigas = [...harness.room.segments];
      harness.room
        ..failReplaceWith = const Refused('PAUSE_CANNOT_STAND_THERE')
        ..segments.clear()
        ..segments.addAll([
          for (final one in antigas)
            SegmentView(
              segmentId: one.segmentId,
              takeId: 'gravacao-9',
              startsMs: one.startsMs + 1000,
              endsMs: one.endsMs + 1000,
              frase: one.frase,
            ),
        ]);
      await tocar(tester, 'ouvindo a gravação de vocês…');
      await tocar(tester, 'Tocar ao terminar');
      await waitFor(
        'as frases voltarem na gravação que este aparelho não tem',
        () =>
            container.read(salaSessionProvider).btTrechoTraduzidoDeNovo ==
                null &&
            container
                .read(salaSessionProvider)
                .btTrechos
                .every((trecho) => trecho.takeId == 'gravacao-9'),
        step: () => _passo(tester),
      );
      await _passo(tester);
      harness.room.failReplaceWith = null;
      await tocar(tester, _barra(2));
      await tocar(tester, depois);
      final movida = container.read(salaSessionProvider).btCorte;
      expect(
        movida,
        greaterThan(s(7.2)),
        reason: 'a pausa não andou para depois',
      );

      await tocar(tester, _barra(2));

      expect(
        harness.playback.ranges.last,
        '3200-${movida.inMilliseconds - 1000}',
        reason:
            'a pausa movida ia na régua do arquivo e a frase começava na régua do lugar',
      );
      closeTheRoom(container);
    },
  );

  testWidgets(
    '«manter a tradução de antes» drops the pause the team moved, and the bar after it starts from the old end',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true)
        ..recorder.rehearsalSpeaks = _duasLacunas;
      final container = await _duasFrasesNoVeredito(
        tester,
        harness,
        apontada: 'trecho-1',
      );
      await tocar(tester, _barra(2));
      await tocar(tester, depois);

      await tocar(tester, 'manter a tradução de antes');
      await _passo(tester);

      expect(
        container.read(salaSessionProvider).btCorte,
        s(6.2),
        reason: 'a pausa movida seguia de pé depois de manter a tradução',
      );
      await tocar(tester, _barra(2));
      expect(container.read(salaSessionProvider).btCorte, s(6.2));
      expect(
        harness.playback.ranges.last,
        '3200-6200',
        reason: 'a barra depois de manter tocava até uma pausa já largada',
      );
      closeTheRoom(container);
    },
  );

  testWidgets(
    'the bar of another frase drops the pause the team moved, and the last frase starts from the old end',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true)
        ..recorder.rehearsalSpeaks = _duasLacunas;
      final container = await _duasFrasesNoVeredito(
        tester,
        harness,
        apontada: 'trecho-1',
      );
      await tocar(tester, _barra(2));
      await tocar(tester, depois);
      await tocar(tester, _barra(1));

      await tocar(tester, _barra(2));

      expect(
        container.read(salaSessionProvider).btCorte,
        s(6.2),
        reason: 'a pausa movida sobrevivia ao toque na barra de outra frase',
      );
      expect(
        harness.playback.ranges.last,
        '3200-6200',
        reason: 'a última frase tocava até a pausa que a outra barra largou',
      );
      closeTheRoom(container);
    },
  );

  testWidgets('the bar of the last frase says her line that the pause may move', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true)
      ..recorder.rehearsalSpeaks = _duasLacunas;
    final container = await _duasFrasesNoVeredito(
      tester,
      harness,
      apontada: 'trecho-1',
    );

    await tocar(tester, _barra(2));

    expect(
      find.text(
        'traduzindo de novo a frase 2 — se precisar, movam a pausa; depois toquem no círculo',
      ),
      findsOneWidget,
      reason: 'a tela não dizia que a pausa da última frase se move',
    );
    closeTheRoom(container);
  });

  testWidgets(
    'the bar of an earlier frase keeps its pause, draws none of her controls and says why',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true)
        ..recorder.rehearsalSpeaks = _duasLacunas;
      final container = await _duasFrasesNoVeredito(
        tester,
        harness,
        apontada: 'trecho-2',
      );

      await tocar(tester, _barra(1));

      for (final controle in [antes, ouvirAPausa, depois]) {
        expect(
          byLabel(controle),
          findsNothing,
          reason: 'a pausa de uma frase do meio ficava com a linha, apagada',
        );
      }
      expect(
        find.text(
          'traduzindo de novo a frase 1 — toquem no círculo (a pausa só se move na última frase; para mudar uma pausa anterior, recomeçar a tradução)',
        ),
        findsOneWidget,
        reason: 'a tela não dizia por que a pausa da frase do meio não se move',
      );
      closeTheRoom(container);
    },
  );

  testWidgets(
    'a frase heard on its bead while the last frase is retold dims her controls and takes back «movam a pausa»',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true)
        ..recorder.rehearsalSpeaks = _duasLacunas;
      final container = await _duasFrasesNoVeredito(
        tester,
        harness,
        apontada: 'trecho-1',
      );
      await tocar(tester, _barra(2));

      await tocar(tester, 'ouvir a minha tradução da frase 1');
      await waitFor(
        'a conta da frase 1 tocar',
        () => container.read(salaSessionProvider).btContaEscolhida != null,
        step: () => _passo(tester),
      );

      for (final controle in [antes, ouvirAPausa, depois]) {
        expect(
          aceso(tester, controle),
          isFalse,
          reason: 'a pausa se movia com outra frase tocando: $controle',
        );
      }
      expect(
        find.text(
          'traduzindo de novo a frase 2 — se precisar, movam a pausa; depois toquem no círculo',
        ),
        findsNothing,
        reason: 'a tela dizia que a pausa se move com os controles apagados',
      );
      expect(
        find.text('traduzindo de novo a frase 2 — toquem no círculo'),
        findsOneWidget,
      );
      closeTheRoom(container);
    },
  );

  testWidgets(
    'at conferida a second bar tap on the last frase keeps its pause where it fell',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true)
        ..recorder.rehearsalSpeaks = _duasLacunas;
      final container = await _duasFrasesNoVeredito(tester, harness);

      await tocar(tester, _barra(1));
      await tocar(tester, _barra(2));

      for (final controle in [antes, ouvirAPausa, depois]) {
        expect(
          byLabel(controle),
          findsNothing,
          reason: 'numa passagem conferida a linha ficava, apagada: $controle',
        );
      }
      expect(
        find.text('traduzindo de novo a frase 2 — toquem no círculo'),
        findsOneWidget,
      );
      closeTheRoom(container);
    },
  );

  testWidgets(
    'at conferida the bar of an earlier frase says the plain line, since no pause moves there',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true)
        ..recorder.rehearsalSpeaks = _duasLacunas;
      final container = await _duasFrasesNoVeredito(tester, harness);

      await tocar(tester, _barra(1));

      expect(
        find.text('traduzindo de novo a frase 1 — toquem no círculo'),
        findsOneWidget,
        reason:
            'a conferida mandava recomeçar para mover uma pausa que ali não se move',
      );
      closeTheRoom(container);
    },
  );

  testWidgets(
    'a refusal line of a moved pause leaves when the team taps the bar again',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true)
        ..recorder.rehearsalSpeaks = _duasLacunas;
      final container = await _duasFrasesNoVeredito(
        tester,
        harness,
        apontada: 'trecho-1',
      );
      harness.room.failReplaceWith = const Refused(
        'PAUSE_ONLY_ON_THE_LAST_FRASE',
      );
      await tocar(tester, _barra(2));
      await tocar(tester, depois);
      await tocar(tester, 'Tocar para gravar a tradução de novo');
      await tocar(tester, 'Tocar ao terminar');
      await waitFor(
        'a recusa chegar',
        () => container.read(salaSessionProvider).btAviso != null,
        step: () => _passo(tester),
      );
      await _passo(tester);
      const recusa =
          'a pausa só se move na última frase — as frases mudaram; toquem na barra de novo';
      expect(find.text(recusa), findsOneWidget);

      await tocar(tester, _barra(2));

      expect(
        find.text(recusa),
        findsNothing,
        reason: 'a linha pedia para tocar na barra e ficava depois do toque',
      );
      closeTheRoom(container);
    },
  );

  testWidgets(
    '«manter a tradução de antes» with the pause of the last frase open closes her controls',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true)
        ..recorder.rehearsalSpeaks = _duasLacunas;
      final container = await _duasFrasesEUmAchadoNa(
        tester,
        harness,
        'trecho-1',
      );
      await tocar(tester, 'Tocar para gravar a tradução de novo');
      await tocar(tester, 'Tocar ao terminar');
      await waitFor(
        'a frase 1 pousar',
        () =>
            container.read(salaSessionProvider).btTrechoTraduzidoDeNovo == null,
        step: () => _passo(tester),
      );
      await _passo(tester);
      await tocar(tester, _barra(2));
      expect(aceso(tester, depois), isTrue);
      await tocar(tester, depois);

      await tocar(tester, 'manter a tradução de antes');
      await _passo(tester);

      expect(container.read(salaSessionProvider).btPhase, BtPhase.playing);
      for (final controle in [antes, ouvirAPausa, depois]) {
        expect(
          byLabel(controle),
          findsNothing,
          reason:
              'a pausa seguia aberta depois de manter a tradução: $controle',
        );
      }
      expect(harness.room.replacesAsked, ['trecho-1@gravacao-1:0-3200']);
      closeTheRoom(container);
    },
  );

  testWidgets(
    'a re-recorded frase that awaits its translation keeps its pause, even as the last of its part',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _voltaComAFraseQueAguarda(tester, harness);

      expect(container.read(salaSessionProvider).btFraseQueAguarda, 'trecho-2');
      for (final controle in [antes, ouvirAPausa, depois]) {
        expect(
          byLabel(controle),
          findsNothing,
          reason:
              'a frase que espera a tradução ficava com a linha, apagada: $controle',
        );
      }
      expect(
        find.textContaining('movam a pausa'),
        findsNothing,
        reason: 'a frase que espera a tradução convidava a mover a pausa',
      );
      closeTheRoom(container);
    },
  );

  test('her two retell lines are hers in English too', () {
    expect(
      sceneRehearsalLabelFor('retellingLast', 'en', n: 2),
      'translating sentence 2 again — move the pause if you need to; then tap the circle',
    );
    expect(
      sceneRehearsalLabelFor('retellingOther', 'en', n: 1),
      'translating sentence 1 again — tap the circle (the pause only moves on the last sentence; to change an earlier pause, start the translation over)',
    );
  });

  testWidgets(
    'an earlier frase told again keeps its pause, with none of her controls drawn',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true)
        ..recorder.rehearsalSpeaks = _duasLacunas;
      final container = await _duasFrasesEUmAchadoNa(
        tester,
        harness,
        'trecho-1',
      );

      for (final controle in [antes, ouvirAPausa, depois]) {
        expect(
          byLabel(controle),
          findsNothing,
          reason: 'a pausa de uma frase do meio ficava com a linha, apagada',
        );
      }
      closeTheRoom(container);
    },
  );

  testWidgets(
    'a part kept compressed keeps the pause of its last frase where it fell',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _duasFrasesEUmAchadoNa(
        tester,
        harness,
        'trecho-2',
      );

      for (final controle in [antes, ouvirAPausa, depois]) {
        expect(
          byLabel(controle),
          findsNothing,
          reason: 'um m4a não se deixa buscar, e a linha ficava, apagada',
        );
      }
      closeTheRoom(container);
    },
  );

  testWidgets(
    'the moved pause never comes closer than 0.2 s to the start of its frase',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true)
        ..recorder.rehearsalSpeaks = _duasLacunas;
      final container = await _duasFrasesEUmAchadoNa(
        tester,
        harness,
        'trecho-2',
      );

      for (var vez = 0; vez < 12; vez++) {
        await tocar(tester, antes);
      }

      expect(
        container.read(salaSessionProvider).btCorte,
        s(3.4),
        reason: 'a frase encolhia até sumir, antes do começo dela',
      );
      closeTheRoom(container);
    },
  );

  test(
    'a conferida passage keeps the pause of its last frase where it fell',
    () {
      final ultima = Trecho(
        segmentId: 'trecho-2',
        takeId: 'gravacao-1',
        parte: 0,
        from: s(3.2),
        to: s(6.2),
        lugarFrom: s(3.2),
        lugarTo: s(6.2),
        frase: 2,
      );

      expect(
        SalaSessionState(btTrechos: [ultima]).theLastPauseMoves(ultima),
        isTrue,
      );
      expect(
        SalaSessionState(
          btTrechos: [ultima],
          btPhase: BtPhase.conferida,
        ).theLastPauseMoves(ultima),
        isFalse,
        reason: 'a pausa se movia numa passagem já conferida',
      );
    },
  );

  for (final (codigo, linha) in const [
    (
      'PAUSE_ONLY_ON_THE_LAST_FRASE',
      'a pausa só se move na última frase — as frases mudaram; toquem na barra de novo',
    ),
    (
      'PAUSE_PAST_THE_END',
      'a pausa nova passa do fim da gravação — um pouco antes',
    ),
    (
      'PAUSE_CANNOT_STAND_THERE',
      'a pausa não pode ficar aí — a frase foi atualizada; toquem na barra de novo',
    ),
  ]) {
    testWidgets(
      'a moved pause the room refuses with $codigo is dropped, the frases are read again, and her line says why',
      (tester) async {
        final harness = SalaHarness(filaEmMemoria: true)
          ..recorder.rehearsalSpeaks = _duasLacunas;
        final container = await _duasFrasesEUmAchadoNa(
          tester,
          harness,
          'trecho-2',
        );
        harness.room.failReplaceWith = Refused(codigo);
        final leituras = stateReads(harness);

        await tocar(tester, depois);
        await tocar(tester, 'Tocar para gravar a tradução de novo');
        await tocar(tester, 'Tocar ao terminar');
        await waitFor(
          'a mudança cair',
          () =>
              container.read(salaSessionProvider).btTrechoTraduzidoDeNovo ==
              null,
          step: () => _passo(tester),
        );
        await _passo(tester);

        expect(
          find.text(linha),
          findsOneWidget,
          reason: 'a sala recusava a pausa e a tela não dizia por quê',
        );
        expect(
          stateReads(harness),
          greaterThan(leituras),
          reason: 'as frases não eram lidas de novo depois da recusa',
        );
        expect(
          [
            for (final trecho in container.read(salaSessionProvider).btTrechos)
              trecho.to,
          ],
          [s(3.2), s(6.2)],
        );
        closeTheRoom(container);
      },
    );
  }

  testWidgets(
    'a refused move whose read-back finds no network calls no person',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true)
        ..recorder.rehearsalSpeaks = _duasLacunas;
      final container = await _duasFrasesEUmAchadoNa(
        tester,
        harness,
        'trecho-2',
      );
      harness.room
        ..failReplaceWith = const Refused('PAUSE_PAST_THE_END')
        ..failStateOnceWith = const NetworkFailed('sem rede');

      await tocar(tester, depois);
      await tocar(tester, 'Tocar para gravar a tradução de novo');
      await tocar(tester, 'Tocar ao terminar');
      await waitFor(
        'a mudança cair',
        () =>
            container.read(salaSessionProvider).btTrechoTraduzidoDeNovo == null,
        step: () => _passo(tester),
      );
      await _passo(tester);

      expect(container.read(salaSessionProvider).needsPerson, isFalse);
      closeTheRoom(container);
    },
  );

  testWidgets(
    'a refusal line of a moved pause leaves when «terminei» asks the check again',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true)
        ..recorder.rehearsalSpeaks = _duasLacunas;
      final container = await _duasFrasesEUmAchadoNa(
        tester,
        harness,
        'trecho-2',
      );
      harness.room.failReplaceWith = const Refused('PAUSE_PAST_THE_END');
      await tocar(tester, depois);
      await tocar(tester, 'Tocar para gravar a tradução de novo');
      await tocar(tester, 'Tocar ao terminar');
      await waitFor(
        'a mudança cair',
        () => container.read(salaSessionProvider).btAviso != null,
        step: () => _passo(tester),
      );
      harness.room
        ..verdictChecked = true
        ..verdictHasFinding = false
        ..verdictFindingSegmentId = null;

      unawaited(
        container.read(salaSessionProvider.notifier).finishBackTranslation(),
      );
      await waitFor(
        'a passagem ficar conferida',
        () => container.read(salaSessionProvider).btPhase == BtPhase.conferida,
        step: () => _passo(tester),
      );
      await _passo(tester);

      expect(
        find.text('a pausa nova passa do fim da gravação — um pouco antes'),
        findsNothing,
        reason: 'a recusa da pausa ficava por cima do resultado da conferência',
      );
      closeTheRoom(container);
    },
  );

  testWidgets(
    'a frase told again with no translation on this tablet, held by its moved pause, '
    'still invites to record, not «pausado»',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _voltaComAFraseQueAguarda(
        tester,
        harness,
        aguarda: false,
      );
      harness.playback.at = parte;
      harness.playback.finishPlayback();
      await _passo(tester);
      harness.room
        ..verdictChecked = false
        ..verdictHasFinding = true
        ..verdictFindingSegmentId = 'trecho-1';
      unawaited(
        container.read(salaSessionProvider.notifier).finishBackTranslation(),
      );
      await waitFor(
        'o veredito chegar',
        () =>
            container.read(salaSessionProvider).btPhase == BtPhase.playing &&
            container.read(salaSessionProvider).btVeredito,
        step: () => _passo(tester),
      );
      await _passo(tester);
      await tocar(tester, _barra(2));

      await tocar(tester, antes);

      final state = container.read(salaSessionProvider);
      expect(state.btTrechoTraduzidoDeNovo?.segmentId, 'trecho-2');
      expect(state.btTraducaoPendente, isNull);
      expect(state.btClipPausada, isTrue);
      expect(
        rotuloDoCirculo(tester),
        'Tocar para gravar a tradução deste trecho',
        reason:
            'a frase traduzida de novo dizia pausado, que ela nunca mostra '
            'com uma frase sendo traduzida de novo',
      );
      closeTheRoom(container);
    },
  );
}

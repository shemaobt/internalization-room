import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'a_wav_take.dart';
import 'fakes.dart';
import 'scenario_helpers.dart' show stateReads;
import 'the_back_translation_is_told_by_beads_test.dart'
    show aceso, confirmar, entrarNaTraducao, parte, tocar;
import 'the_pause_snaps_to_silence_test.dart'
    show antes, depois, ouvirAPausa, pausarAos, s, traduzirEConfirmar;

final _duasLacunas = aSpokenWav(gaps: [(s(3.0), s(3.4)), (s(6.0), s(6.4))]);

Future<void> _passo(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 100));

String _barra(int n) => 'Ouvir esta frase de novo e traduzir de novo — $n';

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
        (apontada == null ? BtPhase.conferida : BtPhase.findings),
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
  await tocar(tester, 'Traduzir este trecho de novo');
  await waitFor(
    'a frase apontada ficar para traduzir de novo',
    () => container.read(salaSessionProvider).btTrechoTraduzidoDeNovo != null,
    step: () => _passo(tester),
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
      await tocar(tester, confirmar);
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
      await tocar(tester, confirmar);
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
    'the bar of an earlier frase keeps its pause, dims her controls and says why',
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
          aceso(tester, controle),
          isFalse,
          reason: 'a pausa de uma frase do meio mudava o começo da seguinte',
        );
      }
      final corte = container.read(salaSessionProvider).btCorte;
      await tocar(tester, depois);
      expect(container.read(salaSessionProvider).btCorte, corte);
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
    'the findings retell after the bar of an earlier frase says the plain line again',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true)
        ..recorder.rehearsalSpeaks = _duasLacunas;
      final container = await _duasFrasesNoVeredito(
        tester,
        harness,
        apontada: 'trecho-1',
      );
      await tocar(tester, _barra(1));
      await tocar(tester, 'manter a tradução de antes');
      await _passo(tester);

      await tocar(tester, 'Traduzir este trecho de novo');

      expect(
        find.text('traduzindo de novo a frase 1 — toquem no círculo'),
        findsOneWidget,
        reason: 'a linha da barra ficava no reconto que veio do achado',
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
          aceso(tester, controle),
          isFalse,
          reason: 'a pausa se movia numa passagem conferida: $controle',
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
    'an earlier frase told again keeps its pause, with her controls dimmed',
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
          aceso(tester, controle),
          isFalse,
          reason: 'a pausa de uma frase do meio mudava o começo da seguinte',
        );
      }
      final corte = container.read(salaSessionProvider).btCorte;
      await tocar(tester, depois);
      expect(container.read(salaSessionProvider).btCorte, corte);
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
          aceso(tester, controle),
          isFalse,
          reason: 'um m4a não se deixa buscar, e a pausa movida caía no escuro',
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
        await tocar(tester, confirmar);
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
    'a refused move whose read-back finds no network takes the room out of reach',
    (tester) async {
      final harness = SalaHarness(
        filaEmMemoria: true,
        retryBackoff: const [Duration(minutes: 1)],
      )..recorder.rehearsalSpeaks = _duasLacunas;
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
      await tocar(tester, confirmar);
      await waitFor(
        'a mudança cair',
        () =>
            container.read(salaSessionProvider).btTrechoTraduzidoDeNovo == null,
        step: () => _passo(tester),
      );
      await _passo(tester);

      expect(
        container.read(salaSessionProvider).unreachable,
        isTrue,
        reason: 'a leitura das frases caía calada e a sala se dizia ao alcance',
      );
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
      await tocar(tester, confirmar);
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
      expect(find.text('✓ traduzida e conferida'), findsOneWidget);
      closeTheRoom(container);
    },
  );
}

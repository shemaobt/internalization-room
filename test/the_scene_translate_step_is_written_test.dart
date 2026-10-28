import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/sala_colors.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/scene_rehearsal_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/scene_strip.dart';

import 'a_scene_room.dart' show articulation, pumpUntil;
import 'a_wav_take.dart';
import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show byLabel;

const _session = 'sessao-1';

const _listenLine =
    'A tradução deste ensaio da cena já foi para a voz. Toquem numa frase '
    'para ouvir o ensaio naquela parte, e no alto-falante para ouvir a '
    'tradução de vocês.';

String _bar(int n) => 'Ouvir esta frase de novo e traduzir de novo — $n';

SceneFrase _frase(String id, int startsMs, int endsMs) =>
    SceneFrase(fraseId: id, startsMs: startsMs, endsMs: endsMs);

SceneRehearsalRecord _rehearsal({
  int n = 1,
  String? scene,
  DateTime? recordedAt,
  String? sentAt,
  List<SceneFrase> frases = const [],
}) => SceneRehearsalRecord(
  rehearsalId: 'ensaio-da-cena-$n',
  sessionId: _session,
  n: n,
  scene: scene,
  recordedAt: recordedAt,
  sentAt: sentAt,
  frases: frases,
);

Future<(SalaHarness, ProviderContainer)> _onTheSceneScreen(
  WidgetTester tester, {
  List<SceneRehearsalRecord> rehearsals = const [],
  bool scenesHeld = false,
  Size view = const Size(820, 2400),
  required bool Function(SalaSessionState state) until,
}) async {
  final harness = SalaHarness(filaEmMemoria: true)
    ..room.passages = const [Passagem(pericope: 'P01', audioUrl: '/voice/p01')]
    ..room.nextMoment = articulation;
  harness.room.sceneRehearsals.addAll(rehearsals);
  harness.room.sceneAudio = aSpokenWav(length: const Duration(seconds: 10));
  harness.playback.measured = const Duration(seconds: 10);
  tester.view
    ..physicalSize = view
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = await pumpSala(tester, harness);
  addTearDown(() => closeTheRoom(container));
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.abrirEscolha();
  await tester.pump(const Duration(milliseconds: 300));
  unawaited(notifier.goConversa(book: 'Ruth', pericope: 'P01'));
  await pumpUntil(
    tester,
    () => container.read(salaSessionProvider).voice == VoiceState.invite,
  );
  await tester.pump(const Duration(milliseconds: 1500));
  if (scenesHeld) harness.room.holdNextScenes();
  await tester.tap(byLabel('ensaio da cena'));
  await pumpUntil(tester, () => until(container.read(salaSessionProvider)));
  await tester.pump(const Duration(milliseconds: 500));
  expect(until(container.read(salaSessionProvider)), isTrue);
  return (harness, container);
}

void _titled(WidgetTester tester, String title) {
  expect(find.text(title), findsOneWidget, reason: 'o título não está escrito');
  expect(byLabel(title), findsOneWidget);
  expect(
    tester.widget<Semantics>(byLabel(title)).properties.header,
    isTrue,
    reason: 'o título é o cabeçalho da tela, como o h1 dela',
  );
}

Future<(SalaHarness, ProviderContainer)> _inListenMode(
  WidgetTester tester, {
  List<SceneRehearsalRecord>? rehearsals,
  Size view = const Size(820, 2400),
}) async {
  final (harness, container) = await _onTheSceneScreen(
    tester,
    view: view,
    rehearsals:
        rehearsals ??
        [
          _rehearsal(
            sentAt: '2026-10-27T10:00:00+00:00',
            frases: [_frase('f1', 0, 3000)],
          ),
        ],
    until: (state) => state.sceneRehearsals.isNotEmpty,
  );
  container
      .read(salaSessionProvider.notifier)
      .openTheListedSceneRehearsal('ensaio-da-cena-1');
  await pumpUntil(
    tester,
    () => container.read(salaSessionProvider).scene.step == SceneStep.sent,
  );
  await tester.pump(const Duration(milliseconds: 300));
  expect(container.read(salaSessionProvider).scene.step, SceneStep.sent);
  return (harness, container);
}

void main() {
  testWidgets(
    'the scene screen is headed «Ensaio da cena» while its scenes are still on their way, and on the record step after',
    (tester) async {
      final (harness, container) = await _onTheSceneScreen(
        tester,
        scenesHeld: true,
        until: (state) => state.stage == SalaStage.cena,
      );

      expect(container.read(salaSessionProvider).scene.step, SceneStep.record);
      _titled(tester, 'Ensaio da cena');

      harness.room.finishHeldScenes();
      await pumpUntil(
        tester,
        () => byLabel('Gravar o ensaio da cena').evaluate().isNotEmpty,
      );

      expect(byLabel('Gravar o ensaio da cena'), findsOneWidget);
      _titled(tester, 'Ensaio da cena');
    },
  );

  testWidgets('the translate step is headed «Ensaio da cena»', (tester) async {
    await _onTheSceneScreen(
      tester,
      rehearsals: [
        _rehearsal(frases: [_frase('f1', 0, 3000)]),
      ],
      until: (state) => state.scene.step == SceneStep.translate,
    );

    _titled(tester, 'Ensaio da cena');
  });

  testWidgets('a scene rehearsal whose frase places cannot be read is headed '
      '«Ensaio da cena»', (tester) async {
    await _onTheSceneScreen(
      tester,
      rehearsals: [
        _rehearsal(frases: [_frase('f1', 0, 12000)]),
      ],
      until: (state) => state.scene.step == SceneStep.placesUnknown,
    );

    _titled(tester, 'Ensaio da cena');
  });

  testWidgets('a sent scene rehearsal opened from the list is headed '
      '«Ensaio da cena»', (tester) async {
    final (_, container) = await _onTheSceneScreen(
      tester,
      rehearsals: [
        _rehearsal(
          sentAt: '2026-10-27T10:00:00+00:00',
          frases: [_frase('f1', 0, 3000)],
        ),
      ],
      until: (state) => state.sceneRehearsals.isNotEmpty,
    );

    container
        .read(salaSessionProvider.notifier)
        .openTheListedSceneRehearsal('ensaio-da-cena-1');
    await pumpUntil(
      tester,
      () => container.read(salaSessionProvider).scene.step == SceneStep.sent,
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).scene.step, SceneStep.sent);
    _titled(tester, 'Ensaio da cena');
    expect(
      tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(SceneRehearsalView),
              matching: find.byType(Text),
            ),
          )
          .map((text) => text.data),
      [
        'Ensaio da cena',
        _listenLine,
        'FRASES TRADUZIDAS',
        '1',
        'frase 1',
        'gravar o ensaio da cena de novo',
        'ENSAIOS DA CENA DESTA SESSÃO',
        '1',
        '1 · frases traduzidas',
        'enviado',
      ],
      reason:
          'a escuta escreve só as palavras dela; uma palavra a mais escapava '
          'da varredura',
    );
  });

  testWidgets('in English the scene screen is headed «Scene rehearsal»', (
    tester,
  ) async {
    final (_, container) = await _onTheSceneScreen(
      tester,
      rehearsals: [
        _rehearsal(frases: [_frase('f1', 0, 3000)]),
      ],
      until: (state) => state.scene.step == SceneStep.translate,
    );

    container.read(roomLanguageProvider.notifier).choose('en');
    await tester.pump(const Duration(milliseconds: 300));

    _titled(tester, 'Scene rehearsal');
    expect(find.text('Ensaio da cena'), findsNothing);
  });

  testWidgets(
    '«frases traduzidas» heads the frases told, under the circle and over the first one',
    (tester) async {
      await _onTheSceneScreen(
        tester,
        rehearsals: [
          _rehearsal(frases: [_frase('f1', 0, 3000), _frase('f2', 3000, 6000)]),
        ],
        until: (state) => state.scene.step == SceneStep.translate,
      );
      final heading = byLabel('frases traduzidas');

      expect(find.text('FRASES TRADUZIDAS'), findsOneWidget);
      expect(heading, findsOneWidget);
      expect(tester.widget<Semantics>(heading).properties.header, isTrue);
      expect(
        tester.getTopLeft(heading).dy,
        greaterThan(
          tester
              .getBottomLeft(
                byLabel('Toque para traduzir esta frase do ensaio da cena'),
              )
              .dy,
        ),
      );
      expect(
        tester.getBottomLeft(heading).dy,
        lessThan(tester.getTopLeft(byLabel(_bar(1))).dy),
        reason: 'o cabeçalho ficava fora da lista, ou não existia',
      );
    },
  );

  testWidgets('in English the frases told are headed «translated sentences»', (
    tester,
  ) async {
    final (_, container) = await _onTheSceneScreen(
      tester,
      rehearsals: [
        _rehearsal(frases: [_frase('f1', 0, 3000)]),
      ],
      until: (state) => state.scene.step == SceneStep.translate,
    );

    container.read(roomLanguageProvider.notifier).choose('en');
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('TRANSLATED SENTENCES'), findsOneWidget);
    expect(byLabel('translated sentences'), findsOneWidget);
  });

  testWidgets('a translate step with no frase told yet carries no heading', (
    tester,
  ) async {
    await _onTheSceneScreen(
      tester,
      rehearsals: [_rehearsal()],
      until: (state) => state.scene.step == SceneStep.translate,
    );

    expect(byLabel('traduzir o ensaio da cena'), findsOneWidget);
    expect(find.text('FRASES TRADUZIDAS'), findsNothing);
    expect(byLabel('frases traduzidas'), findsNothing);
  });

  for (final (language, restart, armed) in [
    (
      'pt',
      'recomeçar a tradução',
      'toque de novo para apagar as 2 frases traduzidas',
    ),
    (
      'en',
      'start the translation over',
      'tap again to discard the 2 translated sentences',
    ),
  ]) {
    testWidgets(
      '$language: «recomeçar a tradução» is a written button, and armed it writes the count it discards',
      (tester) async {
        final (_, container) = await _onTheSceneScreen(
          tester,
          rehearsals: [
            _rehearsal(
              frases: [_frase('f1', 0, 3000), _frase('f2', 3000, 6000)],
            ),
          ],
          until: (state) => state.scene.step == SceneStep.translate,
        );
        container.read(roomLanguageProvider.notifier).choose(language);
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text(restart), findsOneWidget);
        expect(byLabel(restart), findsOneWidget);
        expect(
          tester.widget<Semantics>(byLabel(restart)).properties.button,
          isTrue,
        );

        await tester.tap(find.text(restart));
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          find.text(armed),
          findsOneWidget,
          reason: 'a contagem armada só chegava ao VoiceOver',
        );
        expect(byLabel(armed), findsOneWidget);
        expect(find.text(restart), findsNothing);
        await tester.pump(const Duration(seconds: 6));
      },
    );
  }

  testWidgets(
    'on a phone the armed «recomeçar» keeps 16 points on each side, its words centred',
    (tester) async {
      final (_, container) = await _onTheSceneScreen(
        tester,
        view: const Size(420, 1600),
        rehearsals: [
          _rehearsal(frases: [_frase('f1', 0, 3000), _frase('f2', 3000, 6000)]),
        ],
        until: (state) => state.scene.step == SceneStep.translate,
      );
      const armed = 'toque de novo para apagar as 2 frases traduzidas';

      await tester.tap(find.text('recomeçar a tradução'));
      await tester.pump(const Duration(milliseconds: 300));

      final pill = tester.getRect(byLabel(armed));
      expect(
        pill.left,
        greaterThanOrEqualTo(16),
        reason: 'no iPhone SE o botão armado encostava nas duas bordas',
      );
      expect(pill.right, lessThanOrEqualTo(420 - 16));
      expect(tester.widget<Text>(find.text(armed)).textAlign, TextAlign.center);
      expect(container.read(salaSessionProvider).sceneRestart, isNotNull);
      await tester.pump(const Duration(seconds: 6));
    },
  );

  for (final (language, line, terminei, restart, again) in [
    (
      'pt',
      'as frases já traduzidas não estão neste computador — toquem em terminei '
          'para enviar, ou recomecem a tradução',
      'terminei',
      'recomeçar a tradução',
      'gravar o ensaio da cena de novo',
    ),
    (
      'en',
      'the phrases already translated are not on this computer — tap done to '
          'send them, or start the translation over',
      'done',
      'start the translation over',
      'record the scene rehearsal again',
    ),
  ]) {
    testWidgets(
      '$language: a scene rehearsal whose frase places cannot be read writes her line, then «recomeçar», «terminei» and «gravar de novo» as written buttons',
      (tester) async {
        final (_, container) = await _onTheSceneScreen(
          tester,
          rehearsals: [
            _rehearsal(frases: [_frase('f1', 0, 12000)]),
          ],
          until: (state) => state.scene.step == SceneStep.placesUnknown,
        );
        container.read(roomLanguageProvider.notifier).choose(language);
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          find.text(line),
          findsOneWidget,
          reason: 'a linha dela só chegava ao VoiceOver',
        );
        expect(byLabel(line), findsOneWidget);
        for (final button in [restart, terminei, again]) {
          expect(find.text(button), findsOneWidget, reason: button);
          expect(byLabel(button), findsOneWidget, reason: button);
          expect(
            tester.widget<Semantics>(byLabel(button)).properties.button,
            isTrue,
            reason: button,
          );
        }
        expect(
          tester.widget<Semantics>(byLabel(terminei)).properties.enabled,
          isTrue,
        );
        final tops = [
          line,
          restart,
          terminei,
          again,
        ].map((words) => tester.getTopLeft(find.text(words)).dy).toList();
        for (var i = 1; i < tops.length; i++) {
          expect(tops[i], greaterThan(tops[i - 1]), reason: 'o controle $i');
        }
      },
    );
  }

  testWidgets(
    'on a phone her places-unknown line keeps 16 points on each side',
    (tester) async {
      await _onTheSceneScreen(
        tester,
        view: const Size(420, 1600),
        rehearsals: [
          _rehearsal(frases: [_frase('f1', 0, 12000)]),
        ],
        until: (state) => state.scene.step == SceneStep.placesUnknown,
      );

      final line = tester.getRect(
        find.text(
          'as frases já traduzidas não estão neste computador — toquem em '
          'terminei para enviar, ou recomecem a tradução',
        ),
      );
      expect(
        line.left,
        greaterThanOrEqualTo(16),
        reason: 'no iPhone SE a linha dela ia de uma borda à outra',
      );
      expect(line.right, lessThanOrEqualTo(420 - 16));
    },
  );

  testWidgets(
    'while «terminei» is in the air on places unknown, «enviando…», «recomeçar» and «gravar de novo» are written and dimmed',
    (tester) async {
      final (harness, _) = await _onTheSceneScreen(
        tester,
        rehearsals: [
          _rehearsal(frases: [_frase('f1', 0, 12000)]),
        ],
        until: (state) => state.scene.step == SceneStep.placesUnknown,
      );
      const sending = 'enviando a tradução do ensaio da cena para a voz…';
      const restart = 'recomeçar a tradução';
      const again = 'gravar o ensaio da cena de novo';
      bool? enabled(String words) =>
          tester.widget<Semantics>(byLabel(words)).properties.enabled;
      expect(enabled(restart), isTrue);
      expect(enabled(again), isTrue);
      harness.room.holdNextTurn();

      await tester.tap(find.text('terminei'));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text(sending), findsOneWidget);
      expect(find.text('terminei'), findsNothing);
      expect(
        enabled(sending),
        isFalse,
        reason: 'o terminei aceitava outro toque',
      );
      expect(enabled(restart), isFalse);
      expect(enabled(again), isFalse);
      harness.room.finishHeldTurn();
      await tester.pump(const Duration(seconds: 2));
    },
  );

  testWidgets(
    'at twice the text size «Ensaio da cena» takes the whole width and holds one line, with no «Escolher outra passagem» beside it',
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _onTheSceneScreen(
        tester,
        until: (state) =>
            state.stage == SalaStage.cena &&
            state.scene.step == SceneStep.record,
      );

      expect(
        tester.getSize(find.text('Ensaio da cena')).height,
        lessThan(80),
        reason:
            'o título ficava preso entre as margens do botão e quebrava em duas linhas',
      );
      expect(byLabel('Escolher outra passagem'), findsNothing);
    },
  );
  for (final (language, line) in [
    ('pt', _listenLine),
    (
      'en',
      'This scene rehearsal\'s translation already went to the voice. Tap a '
          'phrase to hear the rehearsal there, and the speaker to hear your '
          'translation of it.',
    ),
  ]) {
    testWidgets(
      '$language: a sent scene rehearsal writes her line under its title',
      (tester) async {
        final (_, container) = await _inListenMode(tester);
        container.read(roomLanguageProvider.notifier).choose(language);
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          find.text(line),
          findsOneWidget,
          reason: 'a linha dela só chegava ao VoiceOver',
        );
        expect(byLabel(line), findsOneWidget);
        expect(
          tester.getTopLeft(find.text(line)).dy,
          greaterThan(
            tester
                .getBottomLeft(
                  find.text(
                    language == 'pt' ? 'Ensaio da cena' : 'Scene rehearsal',
                  ),
                )
                .dy,
          ),
        );
      },
    );
  }
  testWidgets(
    'a sent scene rehearsal writes «ouvindo o ensaio da cena…» with her clock beside play while the take plays',
    (tester) async {
      final (harness, container) = await _inListenMode(tester);
      const line = 'ouvindo o ensaio da cena… — 0:03 / 0:10';
      final play = byLabel('Tocar ou pausar a gravação');

      expect(find.textContaining('ouvindo'), findsNothing);
      await tester.tap(play);
      await pumpUntil(
        tester,
        () => container.read(salaSessionProvider).channel is PartPlaying,
      );
      harness.playback.at = const Duration(seconds: 3);
      await tester.pump(const Duration(milliseconds: 1100));

      expect(
        find.text(line),
        findsOneWidget,
        reason: 'a escuta tocava sem dizer onde estava',
      );
      expect(byLabel(line), findsOneWidget);
      expect(
        tester.getCenter(find.text(line)).dx,
        greaterThan(tester.getCenter(play).dx),
      );
      expect(
        (tester.getCenter(find.text(line)).dy - tester.getCenter(play).dy)
            .abs(),
        lessThan(20),
        reason: 'o relógio fica ao lado do play, como no dela',
      );
    },
  );

  for (final (language, play, paused) in [
    (
      'pt',
      'Tocar ou pausar a gravação',
      'pausado — toque no círculo para marcar onde a frase acaba',
    ),
    (
      'en',
      'Play or pause your recording',
      'paused — tap the circle to mark where the sentence ends',
    ),
  ]) {
    testWidgets(
      '$language: a sent scene rehearsal stopped mid-take writes her paused hint, and nothing before it plays',
      (tester) async {
        final (_, container) = await _inListenMode(tester);
        container.read(roomLanguageProvider.notifier).choose(language);
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text(paused), findsNothing);
        await tester.tap(byLabel(play));
        await pumpUntil(
          tester,
          () => container.read(salaSessionProvider).channel is PartPlaying,
        );
        await tester.tap(byLabel(play));
        await pumpUntil(
          tester,
          () => container.read(salaSessionProvider).channel is! PartPlaying,
        );
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          find.text(paused),
          findsOneWidget,
          reason: 'a escuta parada não dizia nada ao lado do play',
        );
        expect(byLabel(paused), findsOneWidget);
      },
    );
  }

  for (final (language, play, ended, paused) in [
    (
      'pt',
      'Tocar ou pausar a gravação',
      'fim do ensaio da cena',
      'pausado — toque no círculo para marcar onde a frase acaba',
    ),
    (
      'en',
      'Play or pause your recording',
      'end of the scene rehearsal',
      'paused — tap the circle to mark where the sentence ends',
    ),
  ]) {
    testWidgets(
      '$language: a sent scene rehearsal heard to its end writes her ended hint, not the paused one',
      (tester) async {
        final (harness, container) = await _inListenMode(tester);
        container.read(roomLanguageProvider.notifier).choose(language);
        await tester.pump(const Duration(milliseconds: 300));

        await tester.tap(byLabel(play));
        await pumpUntil(
          tester,
          () => container.read(salaSessionProvider).channel is PartPlaying,
        );
        harness.playback.finishPlayback();
        await pumpUntil(
          tester,
          () => container.read(salaSessionProvider).channel is! PartPlaying,
        );
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          find.text(ended),
          findsOneWidget,
          reason: 'a escuta ouvida até o fim não dizia que acabou',
        );
        expect(byLabel(ended), findsOneWidget);
        expect(find.text(paused), findsNothing);
      },
    );
  }

  testWidgets(
    'a frase of a sent scene rehearsal replayed to its end leaves her paused hint, not a blank row',
    (tester) async {
      final (harness, container) = await _inListenMode(tester);
      const paused =
          'pausado — toque no círculo para marcar onde a frase acaba';

      await tester.tap(byLabel('frase 1'));
      await pumpUntil(
        tester,
        () => container.read(salaSessionProvider).channel is PartPlaying,
      );
      expect(harness.playback.ranges.last, '0-3000');
      harness.playback.finishPlayback();
      await pumpUntil(
        tester,
        () => container.read(salaSessionProvider).channel is! PartPlaying,
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text(paused),
        findsOneWidget,
        reason: 'a frase ouvida de novo deixava a linha do play em branco',
      );
      expect(find.text('fim do ensaio da cena'), findsNothing);
    },
  );

  testWidgets(
    'the team\'s translation heard over a playing sent scene rehearsal leaves her paused hint once it stops',
    (tester) async {
      final (harness, container) = await _inListenMode(tester);
      const paused =
          'pausado — toque no círculo para marcar onde a frase acaba';
      final take = container.read(salaSessionProvider).scene.take;

      await tester.tap(byLabel('Tocar ou pausar a gravação'));
      await pumpUntil(
        tester,
        () => container.read(salaSessionProvider).channel is PartPlaying,
      );
      await tester.tap(byLabel('ouvir a minha tradução da frase 1'));
      await pumpUntil(
        tester,
        () =>
            harness.playback.played.isNotEmpty &&
            harness.playback.played.last != take,
      );
      expect(harness.playback.played.last, isNot(take));
      harness.playback.finishPlayback();
      await pumpUntil(
        tester,
        () => container.read(salaSessionProvider).channel is! PartPlaying,
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text(paused),
        findsOneWidget,
        reason: 'a tradução da equipe tocada sobre a escuta apagava a linha',
      );
    },
  );

  testWidgets('a sent scene rehearsal draws her strip', (tester) async {
    await _inListenMode(tester);

    expect(
      find.descendant(
        of: find.byType(SceneRehearsalView),
        matching: find.byType(SceneStrip),
      ),
      findsOneWidget,
      reason: 'a escuta desenhava uma faixa lisa, não a dela',
    );
  });
  testWidgets(
    'a sent scene rehearsal heads its frases «frases traduzidas» and writes each as its number, a bar and «frase N», beside its speaker',
    (tester) async {
      await _inListenMode(
        tester,
        rehearsals: [
          _rehearsal(
            sentAt: '2026-10-27T10:00:00+00:00',
            frases: [_frase('f1', 0, 3000), _frase('f2', 3000, 6000)],
          ),
        ],
      );
      final heading = byLabel('frases traduzidas');

      expect(
        find.text('FRASES TRADUZIDAS'),
        findsOneWidget,
        reason: 'as frases da escuta não tinham cabeçalho escrito',
      );
      expect(tester.widget<Semantics>(heading).properties.header, isTrue);
      expect(
        tester.getBottomLeft(heading).dy,
        lessThan(tester.getTopLeft(byLabel('frase 1')).dy),
      );
      for (final n in [1, 2]) {
        final row = byLabel('frase $n');
        expect(
          find.descendant(of: row, matching: find.text('$n')),
          findsOneWidget,
          reason: 'a barra da frase $n não tinha número',
        );
        expect(
          find.descendant(of: row, matching: find.text('frase $n')),
          findsOneWidget,
        );
        expect(
          (tester.getCenter(byLabel('ouvir a minha tradução da frase $n')).dy -
                  tester.getCenter(row).dy)
              .abs(),
          lessThan(20),
        );
      }
    },
  );
  testWidgets(
    'a sent scene rehearsal writes «gravar o ensaio da cena de novo», and a tap on the words records again',
    (tester) async {
      final (_, container) = await _inListenMode(tester);
      const again = 'gravar o ensaio da cena de novo';

      expect(
        find.text(again),
        findsOneWidget,
        reason: 'o gravar de novo era um microfone sem palavra',
      );
      expect(
        tester.widget<Semantics>(byLabel(again)).properties.button,
        isTrue,
      );

      await tester.tap(find.text(again));
      await tester.pump(const Duration(milliseconds: 300));

      expect(container.read(salaSessionProvider).scene.step, SceneStep.record);
    },
  );
  for (final (
        language,
        heading,
        scene,
        sentWords,
        unsentWords,
        sentRow,
        rowOnScreen,
      )
      in [
        (
          'pt',
          'ENSAIOS DA CENA DESTA SESSÃO',
          'cena 2',
          ['3 · frases traduzidas', 'enviado'],
          ['0 · frases traduzidas', 'não enviado'],
          'ouvir o ensaio da cena 1 — cena 2, 14:05, 3 · frases traduzidas, enviado',
          'Ensaio da cena 2, 14:10, 0 · frases traduzidas, não enviado',
        ),
        (
          'en',
          'SCENE REHEARSALS OF THIS SESSION',
          'scene 2',
          ['3 · translated sentences', 'sent'],
          ['0 · translated sentences', 'not sent'],
          'listen to scene rehearsal 1 — scene 2, 14:05, 3 · translated sentences, sent',
          'Scene rehearsal 2, 14:10, 0 · translated sentences, not sent',
        ),
      ]) {
    testWidgets(
      '$language: the list writes its heading and each rehearsal as its number, scene, time, frases and whether it was sent',
      (tester) async {
        final (_, container) = await _onTheSceneScreen(
          tester,
          rehearsals: [
            _rehearsal(
              scene: 'S2',
              recordedAt: DateTime(2026, 10, 15, 14, 5),
              sentAt: '2026-10-15T14:20:00+00:00',
              frases: [
                _frase('f1', 0, 3000),
                _frase('f2', 3000, 6000),
                _frase('f3', 6000, 9000),
              ],
            ),
            _rehearsal(n: 2, recordedAt: DateTime(2026, 10, 15, 14, 10)),
          ],
          until: (state) => state.scene.rehearsal?.n == 2,
        );
        container.read(roomLanguageProvider.notifier).choose(language);
        await tester.pump(const Duration(milliseconds: 300));
        List<String?> written(String row) => [
          for (final text in tester.widgetList<Text>(
            find.descendant(of: byLabel(row), matching: find.byType(Text)),
          ))
            text.data,
        ];

        expect(
          find.text(heading),
          findsOneWidget,
          reason: 'a lista era uma fileira de ícones, sem cabeçalho escrito',
        );
        expect(written(sentRow), ['1', scene, '14:05', ...sentWords]);
        expect(
          written(rowOnScreen),
          ['2', '14:10', ...unsentWords],
          reason: 'um ensaio sem cena escolhida não ganha «cena N»',
        );
        expect(
          tester.widget<Text>(find.text(unsentWords.last)).style?.color,
          SalaColors.light.telha,
          reason: '«não enviado» é telha, como no dela',
        );
      },
    );
  }
  testWidgets(
    'the row on screen is marked in azul, not dimmed, and a row that cannot be opened while a translation comes down is not dimmed either',
    (tester) async {
      const sentRow =
          'ouvir o ensaio da cena 1, 1 · frases traduzidas, enviado';
      const rowOnScreen =
          'Ensaio da cena 2, 1 · frases traduzidas, não enviado';
      final (harness, container) = await _onTheSceneScreen(
        tester,
        rehearsals: [
          _rehearsal(
            sentAt: '2026-10-15T14:20:00+00:00',
            frases: [_frase('f1', 0, 3000)],
          ),
          _rehearsal(n: 2, frases: [_frase('f2', 0, 3000)]),
        ],
        until: (state) => state.scene.rehearsal?.n == 2,
      );
      Iterable<double> opacities(String row) => tester
          .widgetList<Opacity>(
            find.descendant(of: byLabel(row), matching: find.byType(Opacity)),
          )
          .map((opacity) => opacity.opacity);
      Color? border(String row) =>
          ((tester
                              .widget<Container>(
                                find.descendant(
                                  of: byLabel(row),
                                  matching: find.byType(Container),
                                ),
                              )
                              .decoration
                          as BoxDecoration?)
                      ?.border
                  as Border?)
              ?.top
              .color;

      expect(
        opacities(rowOnScreen),
        everyElement(1.0),
        reason: 'a linha da tela vinha apagada; no dela ela é marcada',
      );
      expect(border(rowOnScreen), ShemaBrand.azul);
      expect(border(sentRow), isNot(ShemaBrand.azul));

      harness.room.holdNextClip();
      await tester.tap(byLabel('ouvir a minha tradução da frase 1'));
      await pumpUntil(
        tester,
        () => container.read(salaSessionProvider).scene.waiting,
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(container.read(salaSessionProvider).scene.waiting, isTrue);
      expect(
        tester.widget<Semantics>(byLabel(sentRow)).properties.enabled,
        isFalse,
      );
      expect(
        opacities(sentRow),
        everyElement(1.0),
        reason: 'no dela uma linha que não abre agora não se apaga',
      );
      harness.room.finishHeldClip();
      await tester.pump(const Duration(milliseconds: 500));
    },
  );
  testWidgets(
    'each frase of a sent scene rehearsal draws its bar, the longest across the whole track',
    (tester) async {
      await _inListenMode(
        tester,
        rehearsals: [
          _rehearsal(
            sentAt: '2026-10-27T10:00:00+00:00',
            frases: [_frase('f1', 0, 2000), _frase('f2', 2000, 6000)],
          ),
        ],
      );
      Size bar(int n) => tester.getSize(
        find.descendant(
          of: byLabel('frase $n'),
          matching: find.byType(DecoratedBox),
        ),
      );

      expect(
        bar(2).height,
        10,
        reason: 'a barra da frase tinha altura zero e não aparecia',
      );
      expect(bar(2).width, 200);
      expect(bar(1).width, 100);
    },
  );
  testWidgets('on a phone her listen line keeps 16 points on each side', (
    tester,
  ) async {
    await _inListenMode(tester, view: const Size(420, 1600));

    final line = tester.getRect(find.text(_listenLine));
    expect(
      line.left,
      greaterThanOrEqualTo(16),
      reason: 'no iPhone SE a linha da escuta encostava nas duas bordas',
    );
    expect(line.right, lessThanOrEqualTo(420 - 16));
  });
  testWidgets(
    'on a phone the list heading that takes two lines in English stays centred',
    (tester) async {
      final (_, container) = await _inListenMode(
        tester,
        view: const Size(420, 1600),
      );
      container.read(roomLanguageProvider.notifier).choose('en');
      await tester.pump(const Duration(milliseconds: 300));
      const heading = 'SCENE REHEARSALS OF THIS SESSION';

      expect(
        tester.widget<Text>(find.text(heading)).textAlign,
        TextAlign.center,
        reason: 'no iPhone SE o cabeçalho quebrava em duas linhas à esquerda',
      );
    },
  );
  testWidgets(
    'on a phone her clock line wraps beside play, 16 points from the edge, instead of running off it',
    (tester) async {
      final (harness, container) = await _inListenMode(
        tester,
        view: const Size(420, 1600),
      );
      container.read(roomLanguageProvider.notifier).choose('en');
      await tester.pump(const Duration(milliseconds: 300));
      const line = 'listening to the scene rehearsal… — 0:03 / 0:10';

      await tester.tap(byLabel('Play or pause your recording'));
      await pumpUntil(
        tester,
        () => container.read(salaSessionProvider).channel is PartPlaying,
      );
      harness.playback.at = const Duration(seconds: 3);
      await tester.pump(const Duration(milliseconds: 1100));

      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(find.text(line)).right,
        lessThanOrEqualTo(420 - 16),
        reason: 'no iPhone SE o relógio passava da borda da tela',
      );
      expect(
        tester.getRect(byLabel('Play or pause your recording')).left,
        greaterThanOrEqualTo(60),
        reason:
            'no iPhone SE o relógio empurrava o play para a borda esquerda, '
            'para baixo do voltar',
      );
      expect(
        tester
            .getRect(byLabel('Play or pause your recording'))
            .overlaps(tester.getRect(byLabel('Back to the current passage'))),
        isFalse,
      );
    },
  );
  testWidgets(
    'a long list of the session\'s scene rehearsals scrolls in a third of the screen instead of pushing the step off it',
    (tester) async {
      await _onTheSceneScreen(
        tester,
        view: const Size(420, 700),
        rehearsals: [
          for (var n = 1; n < 14; n++)
            _rehearsal(n: n, sentAt: '2026-10-27T10:00:00+00:00'),
          _rehearsal(n: 14),
        ],
        until: (state) => state.scene.rehearsal?.n == 14,
      );

      expect(
        tester.takeException(),
        isNull,
        reason: 'catorze linhas escritas empurravam o passo para fora da tela',
      );
      expect(
        tester.getSize(byLabel('ensaios da cena desta sessão')).height,
        lessThanOrEqualTo(700 / 3),
      );
    },
  );
  testWidgets(
    'a sent scene rehearsal whose take the tablet cannot measure still draws each bar against the longest, not every bar full',
    (tester) async {
      final (harness, container) = await _onTheSceneScreen(
        tester,
        rehearsals: [
          _rehearsal(
            sentAt: '2026-10-27T10:00:00+00:00',
            frases: [_frase('f1', 0, 2000), _frase('f2', 2000, 6000)],
          ),
          _rehearsal(n: 2),
        ],
        until: (state) => state.scene.rehearsal?.n == 2,
      );
      harness.playback.measured = null;
      container
          .read(salaSessionProvider.notifier)
          .openTheListedSceneRehearsal('ensaio-da-cena-1');
      await pumpUntil(
        tester,
        () => container.read(salaSessionProvider).scene.step == SceneStep.sent,
      );
      await tester.pump(const Duration(milliseconds: 300));
      Size bar(int n) => tester.getSize(
        find.descendant(
          of: byLabel('frase $n'),
          matching: find.byType(DecoratedBox),
        ),
      );

      expect(container.read(salaSessionProvider).scene.length, isNull);
      expect(bar(2).width, 200);
      expect(
        bar(1).width,
        100,
        reason: 'sem a medida do take toda barra saía cheia, como a mais longa',
      );
    },
  );
  testWidgets(
    'on a phone the translate step\'s clock line wraps beside play too, and play stays clear of the back button',
    (tester) async {
      final (harness, container) = await _onTheSceneScreen(
        tester,
        view: const Size(420, 1600),
        rehearsals: [
          _rehearsal(frases: [_frase('f1', 0, 3000)]),
        ],
        until: (state) => state.scene.step == SceneStep.translate,
      );
      container.read(roomLanguageProvider.notifier).choose('en');
      await tester.pump(const Duration(milliseconds: 300));
      const line = 'listening to the scene rehearsal… — 0:05 / 0:10';

      await tester.tap(find.text('translate the scene rehearsal'));
      await pumpUntil(
        tester,
        () => container.read(salaSessionProvider).channel is PartPlaying,
      );
      harness.playback.at = const Duration(seconds: 5);
      await tester.pump(const Duration(milliseconds: 1100));

      expect(
        tester.takeException(),
        isNull,
        reason: 'no iPhone SE o relógio do passo de traduzir passava da borda',
      );
      expect(
        tester.getRect(find.text(line)).right,
        lessThanOrEqualTo(420 - 16),
      );
      expect(
        tester.getRect(byLabel('Play or pause your recording')).left,
        greaterThanOrEqualTo(60),
        reason: 'o relógio do passo de traduzir empurrava o play para a borda',
      );
      expect(
        tester
            .getRect(byLabel('Play or pause your recording'))
            .overlaps(tester.getRect(byLabel('Back to the current passage'))),
        isFalse,
      );
    },
  );
}

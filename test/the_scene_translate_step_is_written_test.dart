import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:internalization_room/core/theme/sala_colors.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/back_to_passage_button.dart';
import 'package:internalization_room/features/sala/presentation/widgets/scene_rehearsal_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/scene_strip.dart';
import 'package:internalization_room/features/sala/presentation/widgets/scene_translate_step.dart';

import 'a_scene_room.dart' show articulation, pumpUntil;
import 'a_wav_take.dart';
import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show byLabel;
import 'the_check_screen_shows_her_words_and_numbered_frases_test.dart'
    show piorContraste;
import 'the_scene_circles_are_her_check_ring_test.dart' show fadesOn, theEdgeOf;

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

double? _playhead(WidgetTester tester) =>
    (tester
                .widget<CustomPaint>(
                  find.descendant(
                    of: find.byType(SceneStrip),
                    matching: find.byType(CustomPaint),
                  ),
                )
                .painter!
            as SceneStripPainter)
        .drawing
        .playhead;

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

void _numberedDisc(
  WidgetTester tester,
  Finder row,
  String n, {
  required Color fill,
  required Color digit,
}) {
  final number = find.descendant(of: row, matching: find.text(n));
  final disc = find.ancestor(
    of: number,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is DecoratedBox &&
          widget.decoration is BoxDecoration &&
          (widget.decoration as BoxDecoration).shape == BoxShape.circle,
    ),
  );

  expect(
    disc,
    findsOneWidget,
    reason: 'o número era um dígito solto, sem o disco dela',
  );
  expect(tester.getSize(disc), const Size(22, 22));
  expect(
    (tester.widget<DecoratedBox>(disc).decoration as BoxDecoration).color,
    fill,
  );
  final style = tester.widget<Text>(number).style;
  expect(style?.color, digit);
  expect(style?.fontSize, 11.84);
  expect(style?.fontWeight, FontWeight.w600);
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

  for (final (language, instruction, line) in [
    (
      'pt',
      'Ouçam o ensaio da cena; toquem no círculo para pausar onde a frase '
          'acaba, e de novo para traduzir só aquela frase.',
      'as frases já traduzidas não estão neste computador — toquem em terminei '
          'para enviar, ou recomecem a tradução',
    ),
    (
      'en',
      'Listen to the scene rehearsal; tap the circle to pause where the phrase '
          'ends, and again to translate only that phrase.',
      'the phrases already translated are not on this computer — tap done to '
          'send them, or start the translation over',
    ),
  ]) {
    testWidgets(
      '$language: a scene rehearsal whose frase places cannot be read writes the translate step\'s instruction above her line, not her line alone',
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
          find.text(instruction),
          findsOneWidget,
          reason: 'a tela de lugares desconhecidos não dizia o que fazer',
        );
        expect(byLabel(instruction), findsOneWidget);
        expect(
          tester.getTopLeft(find.text(instruction)).dy,
          lessThan(tester.getTopLeft(find.text(line)).dy),
        );
      },
    );
  }

  testWidgets(
    'a scene rehearsal whose frase places cannot be read shows the play control dimmed under the instruction, and a tap on it plays nothing',
    (tester) async {
      final (harness, _) = await _onTheSceneScreen(
        tester,
        rehearsals: [
          _rehearsal(frases: [_frase('f1', 0, 12000)]),
        ],
        until: (state) => state.scene.step == SceneStep.placesUnknown,
      );
      final play = byLabel('Tocar ou pausar a gravação');
      final played = harness.playback.played.length;

      expect(
        play,
        findsOneWidget,
        reason: 'a tela de lugares desconhecidos não tinha o controle de tocar',
      );
      expect(tester.widget<Semantics>(play).properties.enabled, isFalse);
      expect(
        tester.getTopLeft(play).dy,
        greaterThan(
          tester
              .getTopLeft(
                find.textContaining(
                  'Ouçam o ensaio da cena; toquem no círculo',
                ),
              )
              .dy,
        ),
      );
      expect(
        tester.getTopLeft(play).dy,
        lessThan(
          tester
              .getTopLeft(
                find.textContaining('as frases já traduzidas não estão'),
              )
              .dy,
        ),
      );

      await tester.tap(play);
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        harness.playback.played,
        hasLength(played),
        reason: 'no dela, com os lugares desconhecidos, nada toca',
      );
      expect(find.textContaining(RegExp(r'\d:\d\d')), findsNothing);
    },
  );

  testWidgets(
    'a scene rehearsal whose frase places cannot be read draws its strip with the take\'s loudness under the play control, with no frase band and no player',
    (tester) async {
      await _onTheSceneScreen(
        tester,
        rehearsals: [
          _rehearsal(frases: [_frase('f1', 0, 12000)]),
        ],
        until: (state) => state.scene.step == SceneStep.placesUnknown,
      );
      final strip = find.byType(SceneStrip);
      SceneStripDrawing? drawing() => strip.evaluate().isEmpty
          ? null
          : (tester
                        .widget<CustomPaint>(
                          find.descendant(
                            of: strip,
                            matching: find.byType(CustomPaint),
                          ),
                        )
                        .painter!
                    as SceneStripPainter)
                .drawing;
      await pumpUntil(tester, () => drawing()?.columns.isNotEmpty ?? false);

      expect(
        strip,
        findsOneWidget,
        reason: 'a tela de lugares desconhecidos não desenhava a faixa',
      );
      expect(
        drawing()!.columns,
        isNotEmpty,
        reason: 'o dela busca o volume da gravação também nessa retomada',
      );
      expect(drawing()!.bands, isEmpty);
      expect(drawing()!.playhead, isNull);
      expect(
        tester.getTopLeft(strip).dy,
        greaterThan(
          tester.getTopLeft(byLabel('Tocar ou pausar a gravação')).dy,
        ),
      );
      expect(
        tester.getTopLeft(strip).dy,
        lessThan(
          tester
              .getTopLeft(
                find.textContaining('as frases já traduzidas não estão'),
              )
              .dy,
        ),
      );
    },
  );

  testWidgets(
    'a tap on the strip of a scene rehearsal whose frase places cannot be read plays nothing, as on the translate step',
    (tester) async {
      final (harness, container) = await _onTheSceneScreen(
        tester,
        rehearsals: [
          _rehearsal(frases: [_frase('f1', 0, 12000)]),
        ],
        until: (state) => state.scene.step == SceneStep.placesUnknown,
      );
      final played = harness.playback.played.length;

      await tester.tap(find.byType(SceneStrip));
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        harness.playback.played,
        hasLength(played),
        reason: 'a faixa dela não se toca, e sem os lugares nada toca',
      );
      expect(
        container.read(salaSessionProvider).channel,
        isNot(isA<PartPlaying>()),
      );
    },
  );

  testWidgets(
    'a scene rehearsal whose frase places cannot be read shows her telha ring at full strength between the strip and her line, and a tap on it opens no microphone',
    (tester) async {
      final (harness, container) = await _onTheSceneScreen(
        tester,
        rehearsals: [
          _rehearsal(frases: [_frase('f1', 0, 12000)]),
        ],
        until: (state) => state.scene.step == SceneStep.placesUnknown,
      );
      final circle = byLabel(
        'Toque para traduzir esta frase do ensaio da cena',
      );
      final captures = harness.recorder.captures;

      expect(
        circle,
        findsOneWidget,
        reason: 'a tela de lugares desconhecidos não tinha o círculo',
      );
      expect(tester.widget<Semantics>(circle).properties.enabled, isFalse);
      expect(
        theEdgeOf(
          tester,
          'Toque para traduzir esta frase do ensaio da cena',
        ).border!.top.color,
        const Color(0xFFBE4A01),
        reason: 'o dela fica em repouso, telha, mesmo desabilitado',
      );
      expect(
        fadesOn(tester, 'Toque para traduzir esta frase do ensaio da cena'),
        everyElement(1.0),
        reason: 'o dela não apaga o círculo; o nosso caía para 35%',
      );
      expect(
        tester.getTopLeft(circle).dy,
        greaterThan(tester.getBottomLeft(find.byType(SceneStrip)).dy),
      );
      expect(
        tester.getBottomLeft(circle).dy,
        lessThan(
          tester
              .getTopLeft(
                find.textContaining('as frases já traduzidas não estão'),
              )
              .dy,
        ),
      );

      await tester.tap(circle);
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        container.read(salaSessionProvider).channel,
        isNot(isA<Microphone>()),
        reason: 'no dela o círculo fica desabilitado sem os lugares',
      );
      expect(harness.recorder.captures, captures);
    },
  );

  testWidgets(
    'while «recomeçar» is in the air on places unknown the circle breathes her areia thinking ring, and still takes no tap',
    (tester) async {
      final (harness, _) = await _onTheSceneScreen(
        tester,
        rehearsals: [
          _rehearsal(frases: [_frase('f1', 0, 12000)]),
        ],
        until: (state) => state.scene.step == SceneStep.placesUnknown,
      );
      const tell = 'Toque para traduzir esta frase do ensaio da cena';
      final circle = byLabel(tell);
      Color edge() => theEdgeOf(tester, tell).border!.top.color;
      expect(edge(), const Color(0xFFBE4A01));
      harness.room.holdNextRestart();

      await tester.tap(byLabel('recomeçar a tradução'));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.tap(
        byLabel('toque de novo para apagar as 1 frases traduzidas'),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        edge(),
        const Color(0xFFC5C29F),
        reason: 'no dela o círculo pensa enquanto o recomeço está no ar',
      );
      expect(tester.widget<Semantics>(circle).properties.enabled, isFalse);
      harness.room.finishHeldRestart();
      await tester.pump(const Duration(seconds: 7));
    },
  );

  testWidgets(
    'on an iPhone SE the places-unknown screen keeps every control whole, apart and on the screen, down to «gravar de novo» above the list',
    (tester) async {
      tester.view.padding = const FakeViewPadding(top: 20);
      addTearDown(tester.view.resetPadding);
      await _onTheSceneScreen(
        tester,
        view: const Size(375, 667),
        rehearsals: [
          _rehearsal(frases: [_frase('f1', 0, 12000)]),
        ],
        until: (state) => state.scene.step == SceneStep.placesUnknown,
      );
      const again = 'gravar o ensaio da cena de novo';
      final controls = {
        'instrução': find.textContaining('Ouçam o ensaio da cena'),
        'tocar': byLabel('Tocar ou pausar a gravação'),
        'faixa': find.byType(SceneStrip),
        'círculo': byLabel('Toque para traduzir esta frase do ensaio da cena'),
        'linha': find.textContaining('as frases já traduzidas não estão'),
        'recomeçar': byLabel('recomeçar a tradução'),
        'terminei': byLabel('terminei'),
        'gravar de novo': byLabel(again),
        'volta': find.byType(BackToPassageButton),
      };

      expect(tester.takeException(), isNull);
      final rects = {
        for (final MapEntry(:key, :value) in controls.entries)
          key: tester.getRect(value),
      };
      for (final MapEntry(:key, value: rect) in rects.entries) {
        expect(rect.left, greaterThanOrEqualTo(0), reason: key);
        expect(rect.right, lessThanOrEqualTo(375), reason: key);
        for (final MapEntry(key: other, value: beside) in rects.entries) {
          if (other == key) continue;
          expect(
            rect.overlaps(beside),
            isFalse,
            reason: '$key cobria $other no iPhone SE',
          );
        }
      }

      await tester.dragUntilVisible(
        find.text(again),
        find.byType(ScenePlacesUnknown),
        const Offset(0, -80),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        tester.getRect(byLabel(again)).bottom,
        lessThanOrEqualTo(
          tester.getRect(find.text('ENSAIOS DA CENA DESTA SESSÃO')).top,
        ),
        reason: 'o gravar de novo ficava cortado sob a lista',
      );
    },
  );

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
    'a written button keeps its outline outside its padding, so «terminei» and «traduzir» are not 3 points smaller than they were',
    (tester) async {
      await _onTheSceneScreen(
        tester,
        rehearsals: [
          _rehearsal(frases: [_frase('f1', 0, 3000)]),
        ],
        until: (state) => state.scene.step == SceneStep.translate,
      );

      for (final (words, across, down) in [
        ('terminei', 32 + 1.5, 14 + 1.5),
        ('traduzir o ensaio da cena', 20 + 1.5, 10 + 1.5),
        ('gravar o ensaio da cena de novo', 20.0, 10.0),
      ]) {
        final button = tester.getRect(byLabel(words));
        final text = tester.getRect(
          find.descendant(of: byLabel(words), matching: find.text(words)),
        );
        expect(
          text.left - button.left,
          closeTo(across, 0.01),
          reason: 'o contorno saía de dentro do espaço das palavras: $words',
        );
        expect(button.right - text.right, closeTo(across, 0.01), reason: words);
        expect(text.top - button.top, closeTo(down, 0.01), reason: words);
        expect(button.bottom - text.bottom, closeTo(down, 0.01), reason: words);
      }
    },
  );
  for (final look in [Brightness.light, Brightness.dark]) {
    testWidgets(
      'in the ${look.name} look a dimmed «terminei» on the scene rehearsal reads at 4.5:1 or better, not its paper fading with the pill',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = look;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await _onTheSceneScreen(
          tester,
          rehearsals: [_rehearsal()],
          until: (state) => state.scene.step == SceneStep.translate,
        );

        expect(
          tester.widget<Semantics>(byLabel('terminei')).properties.enabled,
          isFalse,
        );
        expect(
          piorContraste(tester, 'terminei', tela: SceneRehearsalView),
          greaterThanOrEqualTo(4.5),
          reason:
              'o terminei apagado escrevia o papel sobre o vermelho a 35%, a '
              '1,2:1',
        );
      },
    );
    testWidgets(
      'in the ${look.name} look the scene rehearsal on its way to the voice reads «enviando…» at 4.5:1 or better while it is dimmed',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = look;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final (harness, _) = await _onTheSceneScreen(
          tester,
          rehearsals: [
            _rehearsal(frases: [_frase('f1', 0, 12000)]),
          ],
          until: (state) => state.scene.step == SceneStep.placesUnknown,
        );
        const sending = 'enviando a tradução do ensaio da cena para a voz…';
        harness.room.holdNextTurn();

        await tester.tap(find.text('terminei'));
        await tester.pump(const Duration(milliseconds: 500));

        expect(
          tester.widget<Semantics>(_theButton(sending)).properties.enabled,
          isFalse,
        );
        expect(
          piorContraste(
            tester,
            sending,
            tela: SceneRehearsalView,
            control: _theButton(sending),
          ),
          greaterThanOrEqualTo(4.5),
          reason: 'o enviando… apagava junto com a pílula, a 1,2:1',
        );
        harness.room.finishHeldTurn();
        await tester.pump(const Duration(seconds: 2));
      },
    );
    testWidgets(
      'in the ${look.name} look a lit «terminei» on the scene rehearsal reads at 4.6:1 or better',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = look;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await _onTheSceneScreen(
          tester,
          rehearsals: [
            _rehearsal(frases: [_frase('f1', 0, 3000)]),
          ],
          until: (state) => state.scene.step == SceneStep.translate,
        );

        expect(
          tester.widget<Semantics>(byLabel('terminei')).properties.enabled,
          isTrue,
        );
        expect(
          piorContraste(tester, 'terminei', tela: SceneRehearsalView),
          greaterThanOrEqualTo(4.6),
        );
      },
    );
  }

  testWidgets(
    'while «terminei» is in the air the translate circle breathes her areia thinking ring at full strength, not a faded red disc',
    (tester) async {
      final (harness, container) = await _onTheSceneScreen(
        tester,
        rehearsals: [
          _rehearsal(frases: [_frase('f1', 0, 3000)]),
        ],
        until: (state) => state.scene.step == SceneStep.translate,
      );
      const tell = 'Toque para traduzir esta frase do ensaio da cena';
      harness.room.holdNextTurn();

      await tester.tap(find.text('terminei'));
      await tester.pump(const Duration(milliseconds: 500));

      expect(container.read(salaSessionProvider).theSceneIsSending, isTrue);
      expect(
        theEdgeOf(tester, tell).border!.top.color,
        const Color(0xFFC5C29F),
        reason: 'com o terminei no ar o dela pensa, de borda areia',
      );
      expect(
        fadesOn(tester, tell),
        everyElement(1.0),
        reason: 'o dela não apaga o círculo; o nosso caía para 35%',
      );
      expect(
        tester.widget<Semantics>(byLabel(tell)).properties.enabled,
        isFalse,
      );
      harness.room.finishHeldTurn();
      await tester.pump(const Duration(seconds: 2));
    },
  );

  testWidgets(
    'while «terminei» is in the air on places unknown the circle breathes her areia thinking ring, not the ring at rest',
    (tester) async {
      final (harness, container) = await _onTheSceneScreen(
        tester,
        rehearsals: [
          _rehearsal(frases: [_frase('f1', 0, 12000)]),
        ],
        until: (state) => state.scene.step == SceneStep.placesUnknown,
      );
      const tell = 'Toque para traduzir esta frase do ensaio da cena';
      harness.room.holdNextTurn();

      await tester.tap(find.text('terminei'));
      await tester.pump(const Duration(milliseconds: 500));

      expect(container.read(salaSessionProvider).theSceneIsSending, isTrue);
      expect(
        theEdgeOf(tester, tell).border!.top.color,
        const Color(0xFFC5C29F),
        reason:
            'com o terminei no ar o dela pensa também aqui; o nosso ficava em '
            'repouso',
      );
      harness.room.finishHeldTurn();
      await tester.pump(const Duration(seconds: 2));
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

      expect(
        find.text(sending),
        findsNWidgets(2),
        reason:
            'o botão e a linha ao lado do play dizem «enviando…», como no dela',
      );
      expect(find.text('terminei'), findsNothing);
      expect(
        tester.widget<Semantics>(_theButton(sending)).properties.enabled,
        isFalse,
        reason: 'o terminei aceitava outro toque',
      );
      expect(enabled(restart), isFalse);
      expect(enabled(again), isFalse);
      harness.room.finishHeldTurn();
      await tester.pump(const Duration(seconds: 2));
    },
  );

  for (final (language, play, terminei, sending) in [
    (
      'pt',
      'Tocar ou pausar a gravação',
      'terminei',
      'enviando a tradução do ensaio da cena para a voz…',
    ),
    (
      'en',
      'Play or pause your recording',
      'done',
      'sending the translation of the scene rehearsal to the voice…',
    ),
  ]) {
    testWidgets(
      '$language: while terminei is in the air on places unknown the line beside play reads her sending words, not only the button',
      (tester) async {
        final (harness, container) = await _onTheSceneScreen(
          tester,
          rehearsals: [
            _rehearsal(frases: [_frase('f1', 0, 12000)]),
          ],
          until: (state) => state.scene.step == SceneStep.placesUnknown,
        );
        container.read(roomLanguageProvider.notifier).choose(language);
        await tester.pump(const Duration(milliseconds: 300));
        expect(_besidePlay(play, sending), findsNothing);
        harness.room.holdNextTurn();

        await tester.tap(byLabel(terminei));
        await pumpUntil(
          tester,
          () => container.read(salaSessionProvider).theSceneIsSending,
        );
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          _besidePlay(play, sending),
          findsOneWidget,
          reason:
              'na tela de lugares desconhecidos só o botão dizia que a tradução ia para a voz; a linha ao lado do play ficava calada',
        );

        harness.room.finishHeldTurn();
        await pumpUntil(
          tester,
          () => container.read(salaSessionProvider).stage == SalaStage.conversa,
        );
        await tester.pump(const Duration(seconds: 2));
      },
    );
  }

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
      'pausado — toque no círculo para marcar onde a frase acaba — 0:07 / 0:10',
    ),
    (
      'en',
      'Play or pause your recording',
      'paused — tap the circle to mark where the sentence ends — 0:07 / 0:10',
    ),
  ]) {
    testWidgets(
      '$language: a sent scene rehearsal stopped mid-take writes her paused hint with the clock where it stopped, and nothing before it plays',
      (tester) async {
        final (harness, container) = await _inListenMode(tester);
        container.read(roomLanguageProvider.notifier).choose(language);
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text(paused), findsNothing);
        await tester.tap(byLabel(play));
        await pumpUntil(
          tester,
          () => container.read(salaSessionProvider).channel is PartPlaying,
        );
        harness.playback.at = const Duration(seconds: 7);
        await tester.tap(byLabel(play));
        await pumpUntil(
          tester,
          () => container.read(salaSessionProvider).channel is! PartPlaying,
        );
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          find.text(paused),
          findsOneWidget,
          reason: 'a escuta parada não dizia onde o take parou',
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
    'a frase of a sent scene rehearsal replayed to its end leaves her paused hint at the frase\'s end, not a blank row',
    (tester) async {
      final (harness, container) = await _inListenMode(tester);
      const paused =
          'pausado — toque no círculo para marcar onde a frase acaba — 0:03 / 0:10';

      await tester.tap(byLabel('frase 1'));
      await pumpUntil(
        tester,
        () => container.read(salaSessionProvider).channel is PartPlaying,
      );
      expect(harness.playback.ranges.last, '0-3000');
      harness.playback.at = const Duration(seconds: 3);
      harness.playback.finishPlayback();
      await pumpUntil(
        tester,
        () => container.read(salaSessionProvider).channel is! PartPlaying,
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text(paused),
        findsOneWidget,
        reason: 'a frase ouvida de novo não dizia que o take parou no fim dela',
      );
      expect(find.text('fim do ensaio da cena'), findsNothing);
    },
  );

  testWidgets(
    'a frase of a sent scene rehearsal replayed counts her clock from the take\'s start, not from the frase\'s',
    (tester) async {
      final (harness, container) = await _inListenMode(
        tester,
        rehearsals: [
          _rehearsal(
            sentAt: '2026-10-27T10:00:00+00:00',
            frases: [_frase('f1', 0, 4000), _frase('f2', 4000, 8000)],
          ),
        ],
      );
      const line = 'ouvindo o ensaio da cena… — 0:05 / 0:10';

      await tester.tap(byLabel('frase 2'));
      await pumpUntil(
        tester,
        () => container.read(salaSessionProvider).channel is PartPlaying,
      );
      expect(harness.playback.ranges.last, '4000-8000');
      harness.playback.at = const Duration(seconds: 1);
      await tester.pump(const Duration(milliseconds: 1100));

      expect(
        find.text(line),
        findsOneWidget,
        reason: 'a frase 2 ouvida de novo dizia 0:01, contado do começo dela',
      );
    },
  );

  testWidgets(
    'a frase of a sent scene rehearsal left to play never reads past its own end, as a clip of the take answers',
    (tester) async {
      final (harness, container) = await _inListenMode(
        tester,
        rehearsals: [
          _rehearsal(
            sentAt: '2026-10-27T10:00:00+00:00',
            frases: [_frase('f1', 0, 4000), _frase('f2', 4000, 8000)],
          ),
        ],
      );
      const line = 'ouvindo o ensaio da cena… — 0:08 / 0:10';
      harness.playback.walkWhilePlaying();

      await tester.tap(byLabel('frase 2'));
      await pumpUntil(
        tester,
        () => switch (container.read(salaSessionProvider).channel) {
          PartPlaying(:final opened) => opened,
          _ => false,
        },
      );
      expect(harness.playback.ranges.last, '4000-8000');
      for (var second = 0; second < 6; second++) {
        await tester.pump(const Duration(seconds: 1));
      }

      expect(
        find.text(line),
        findsOneWidget,
        reason:
            'o clipe da frase 2 andava até o comprimento do arquivo — 0:10 / 0:10',
      );
    },
  );

  testWidgets(
    'a frase of a sent scene rehearsal that never says it ended is closed at its own end, with her clock and the strip at the take\'s time',
    (tester) async {
      final (harness, container) = await _inListenMode(
        tester,
        rehearsals: [
          _rehearsal(
            sentAt: '2026-10-27T10:00:00+00:00',
            frases: [_frase('f1', 0, 4000), _frase('f2', 4000, 8000)],
          ),
        ],
      );
      harness.playback.length = const Duration(seconds: 10);
      const paused =
          'pausado — toque no círculo para marcar onde a frase acaba — 0:08 / 0:10';

      await tester.tap(byLabel('frase 2'));
      await pumpUntil(
        tester,
        () => switch (container.read(salaSessionProvider).channel) {
          PartPlaying(:final opened) => opened,
          _ => false,
        },
      );
      expect(harness.playback.ranges.last, '4000-8000');
      harness.playback.at = const Duration(seconds: 4);
      for (var second = 0; second < 15; second++) {
        await tester.pump(const Duration(seconds: 1));
      }

      expect(
        container.read(salaSessionProvider).channel,
        isNot(isA<PartPlaying>()),
        reason:
            'o teto da escuta da frase 2 era armado com os 10 s do arquivo, '
            'não com os 4 s do trecho, e a frase seguia no ar',
      );
      expect(
        find.text(paused),
        findsOneWidget,
        reason: 'a frase fechada pelo teto não dizia onde o take parou',
      );
      expect(
        _playhead(tester),
        closeTo(233.6, 0.01),
        reason: 'o marcador não ficava no fim da frase 2, contado no take',
      );
    },
  );

  testWidgets(
    'a frase of a sent scene rehearsal still opening shows her clock at the frase\'s start, not the clip before it added on',
    (tester) async {
      final (harness, container) = await _inListenMode(
        tester,
        rehearsals: [
          _rehearsal(
            sentAt: '2026-10-27T10:00:00+00:00',
            frases: [_frase('f1', 0, 4000), _frase('f2', 4000, 8000)],
          ),
        ],
      );
      const line = 'ouvindo o ensaio da cena… — 0:04 / 0:10';

      harness.playback.holdNextOpening();
      await tester.tap(byLabel('frase 2'));
      await pumpUntil(
        tester,
        () => container.read(salaSessionProvider).channel is PartPlaying,
      );
      expect(
        container.read(salaSessionProvider).channel,
        isA<PartPlaying>().having((part) => part.opened, 'opened', isFalse),
      );
      harness.playback.at = const Duration(seconds: 8);
      await tester.pump(const Duration(milliseconds: 1100));

      expect(
        find.text(line),
        findsOneWidget,
        reason:
            'a frase 2 ainda abrindo somava o começo dela ao lugar do clipe anterior — 0:12 / 0:10',
      );
      harness.playback.finishHeldOpening();
    },
  );

  testWidgets(
    'a frase translated again counts her clock from the take\'s start, not from the frase\'s',
    (tester) async {
      final (harness, container) = await _onTheSceneScreen(
        tester,
        rehearsals: [
          _rehearsal(
            frases: [
              _frase('f1', 0, 4000),
              _frase('f2', 4000, 8000),
              _frase('f3', 8000, 10000),
            ],
          ),
        ],
        until: (state) => state.scene.step == SceneStep.translate,
      );
      const line = 'ouvindo o ensaio da cena… — 0:05 / 0:10';

      await tester.tap(byLabel(_bar(2)));
      await pumpUntil(
        tester,
        () => container.read(salaSessionProvider).channel is PartPlaying,
      );
      expect(harness.playback.ranges.last, '4000-8000');
      harness.playback.at = const Duration(seconds: 1);
      await tester.pump(const Duration(milliseconds: 1100));

      expect(
        find.text(line),
        findsOneWidget,
        reason:
            'a frase 2 traduzida de novo dizia 0:01, contado do começo dela',
      );
    },
  );

  for (final step in [SceneStep.sent, SceneStep.translate]) {
    testWidgets(
      '${step.name}: a frase 2 replayed draws the strip\'s playhead at the take\'s own time, not counted from the frase\'s start',
      (tester) async {
        final frases = [_frase('f1', 0, 4000), _frase('f2', 4000, 8000)];
        final (harness, container) = step == SceneStep.sent
            ? await _inListenMode(
                tester,
                rehearsals: [
                  _rehearsal(
                    sentAt: '2026-10-27T10:00:00+00:00',
                    frases: frases,
                  ),
                ],
              )
            : await _onTheSceneScreen(
                tester,
                rehearsals: [_rehearsal(frases: frases)],
                until: (state) => state.scene.step == SceneStep.translate,
              );

        await tester.tap(byLabel(step == SceneStep.sent ? 'frase 2' : _bar(2)));
        await pumpUntil(
          tester,
          () => container.read(salaSessionProvider).channel is PartPlaying,
        );
        expect(harness.playback.ranges.last, '4000-8000');
        await pumpUntil(
          tester,
          () => switch (container.read(salaSessionProvider).channel) {
            PartPlaying(:final opened) => opened,
            _ => false,
          },
        );
        harness.playback.at = const Duration(seconds: 1);
        await tester.pump(const Duration(milliseconds: 1100));

        expect(
          _playhead(tester),
          closeTo(146, 0.01),
          reason:
              'a frase 2 desenhava o marcador em 0:01, contado do começo dela',
        );
      },
    );
  }

  for (final step in [SceneStep.sent, SceneStep.translate]) {
    testWidgets(
      '${step.name}: while the team\'s translation plays, the row shows the take paused where it stopped, not «ouvindo o ensaio da cena…» on the translation\'s clock',
      (tester) async {
        final (harness, container) = step == SceneStep.sent
            ? await _inListenMode(tester)
            : await _onTheSceneScreen(
                tester,
                rehearsals: [
                  _rehearsal(frases: [_frase('f1', 0, 3000)]),
                ],
                until: (state) => state.scene.step == SceneStep.translate,
              );
        const paused =
            'pausado — toque no círculo para marcar onde a frase acaba — 0:07 / 0:10';
        final play = byLabel('Tocar ou pausar a gravação');
        final take = container.read(salaSessionProvider).scene.take;

        await tester.tap(
          step == SceneStep.sent
              ? play
              : find.text('traduzir o ensaio da cena'),
        );
        await pumpUntil(
          tester,
          () => container.read(salaSessionProvider).channel is PartPlaying,
        );
        harness.playback.at = const Duration(seconds: 7);
        await tester.tap(byLabel('ouvir a minha tradução da frase 1'));
        await pumpUntil(
          tester,
          () =>
              harness.playback.played.last != take &&
              container.read(salaSessionProvider).channel is PartPlaying,
        );
        expect(harness.playback.played.last, isNot(take));
        expect(container.read(salaSessionProvider).channel, isA<PartPlaying>());
        harness.playback.at = const Duration(seconds: 2);
        await tester.pump(const Duration(milliseconds: 1100));

        expect(
          find.text(paused),
          findsOneWidget,
          reason:
              'a tradução da equipe tocando dizia que o ensaio da cena tocava, no relógio dela',
        );
        expect(find.textContaining('ouvindo'), findsNothing);
        expect(
          find.descendant(of: play, matching: find.byIcon(LucideIcons.play)),
          findsOneWidget,
          reason: 'o play mostrava pausa com o take parado',
        );
      },
    );

    testWidgets(
      '${step.name}: while the team\'s translation plays, the strip\'s playhead stands where the take stopped, not on the translation\'s clock',
      (tester) async {
        final (harness, container) = step == SceneStep.sent
            ? await _inListenMode(tester)
            : await _onTheSceneScreen(
                tester,
                rehearsals: [
                  _rehearsal(frases: [_frase('f1', 0, 3000)]),
                ],
                until: (state) => state.scene.step == SceneStep.translate,
              );
        final take = container.read(salaSessionProvider).scene.take;

        await tester.tap(
          step == SceneStep.sent
              ? byLabel('Tocar ou pausar a gravação')
              : find.text('traduzir o ensaio da cena'),
        );
        await pumpUntil(
          tester,
          () => container.read(salaSessionProvider).channel is PartPlaying,
        );
        harness.playback.at = const Duration(seconds: 7);
        await tester.tap(byLabel('ouvir a minha tradução da frase 1'));
        await pumpUntil(
          tester,
          () =>
              harness.playback.played.last != take &&
              container.read(salaSessionProvider).channel is PartPlaying,
        );
        expect(harness.playback.played.last, isNot(take));
        harness.playback.at = const Duration(seconds: 2);
        await tester.pump(const Duration(milliseconds: 1100));

        expect(
          _playhead(tester),
          closeTo(204.4, 0.01),
          reason:
              'o marcador andava pela faixa do take no relógio da tradução da equipe',
        );
      },
    );
  }

  testWidgets(
    'the team\'s translation heard over a playing sent scene rehearsal leaves her paused hint with the clock where the take stopped, not where the translation did',
    (tester) async {
      final (harness, container) = await _inListenMode(tester);
      const paused =
          'pausado — toque no círculo para marcar onde a frase acaba — 0:07 / 0:10';
      final take = container.read(salaSessionProvider).scene.take;

      await tester.tap(byLabel('Tocar ou pausar a gravação'));
      await pumpUntil(
        tester,
        () => container.read(salaSessionProvider).channel is PartPlaying,
      );
      harness.playback.at = const Duration(seconds: 7);
      await tester.tap(byLabel('ouvir a minha tradução da frase 1'));
      await pumpUntil(
        tester,
        () =>
            harness.playback.played.isNotEmpty &&
            harness.playback.played.last != take,
      );
      expect(harness.playback.played.last, isNot(take));
      harness.playback.at = const Duration(seconds: 2);
      harness.playback.finishPlayback();
      await pumpUntil(
        tester,
        () => container.read(salaSessionProvider).channel is! PartPlaying,
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text(paused),
        findsOneWidget,
        reason:
            'a tradução da equipe tocada sobre a escuta não dizia onde o take parou',
      );
    },
  );

  testWidgets(
    'a sent scene rehearsal stopped mid-take keeps the strip\'s playhead where the take stopped, and draws none before it plays',
    (tester) async {
      final (harness, container) = await _inListenMode(tester);
      final play = byLabel('Tocar ou pausar a gravação');

      expect(_playhead(tester), isNull);
      await tester.tap(play);
      await pumpUntil(
        tester,
        () => container.read(salaSessionProvider).channel is PartPlaying,
      );
      harness.playback.at = const Duration(seconds: 7);
      await tester.tap(play);
      await pumpUntil(
        tester,
        () => container.read(salaSessionProvider).channel is! PartPlaying,
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        _playhead(tester),
        closeTo(204.4, 0.01),
        reason: 'o take parado apagava o marcador da faixa',
      );
    },
  );

  testWidgets(
    'another rehearsal opened from the list draws no playhead where the take before it stopped',
    (tester) async {
      final (harness, container) = await _inListenMode(
        tester,
        rehearsals: [
          for (final n in [1, 2])
            _rehearsal(
              n: n,
              sentAt: '2026-10-27T10:00:00+00:00',
              frases: [_frase('f1', 0, 3000)],
            ),
        ],
      );
      final play = byLabel('Tocar ou pausar a gravação');

      await tester.tap(play);
      await pumpUntil(
        tester,
        () => container.read(salaSessionProvider).channel is PartPlaying,
      );
      harness.playback.at = const Duration(seconds: 7);
      await tester.tap(play);
      await pumpUntil(
        tester,
        () => container.read(salaSessionProvider).channel is! PartPlaying,
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(_playhead(tester), closeTo(204.4, 0.01));

      container
          .read(salaSessionProvider.notifier)
          .openTheListedSceneRehearsal('ensaio-da-cena-2');
      await pumpUntil(
        tester,
        () =>
            container.read(salaSessionProvider).scene.rehearsal?.rehearsalId ==
            'ensaio-da-cena-2',
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        container.read(salaSessionProvider).scene.rehearsal?.rehearsalId,
        'ensaio-da-cena-2',
      );
      expect(
        _playhead(tester),
        isNull,
        reason: 'o ensaio aberto da lista herdava o marcador do take anterior',
      );
    },
  );

  testWidgets(
    'a translation started over draws no playhead where the take stopped before it',
    (tester) async {
      final (harness, container) = await _onTheSceneScreen(
        tester,
        rehearsals: [
          _rehearsal(frases: [_frase('f1', 0, 3000)]),
        ],
        until: (state) => state.scene.step == SceneStep.translate,
      );

      await tester.tap(find.text('traduzir o ensaio da cena'));
      await pumpUntil(
        tester,
        () => container.read(salaSessionProvider).channel is PartPlaying,
      );
      harness.playback.at = const Duration(seconds: 7);
      await tester.tap(byLabel('Tocar ou pausar a gravação'));
      await pumpUntil(
        tester,
        () => container.read(salaSessionProvider).channel is! PartPlaying,
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(_playhead(tester), closeTo(204.4, 0.01));

      await tester.tap(find.text('recomeçar a tradução'));
      await tester.pump(const Duration(milliseconds: 800));
      await tester.tap(
        find.text('toque de novo para apagar as 1 frases traduzidas'),
      );
      await pumpUntil(
        tester,
        () =>
            harness.room.restartsSent.isNotEmpty &&
            container
                    .read(salaSessionProvider)
                    .scene
                    .rehearsal
                    ?.translatedFrases ==
                0,
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(harness.room.restartsSent, hasLength(1));
      expect(
        _playhead(tester),
        isNull,
        reason: 'a tradução recomeçada ainda marcava onde o take tinha parado',
      );
      await tester.pump(const Duration(seconds: 6));
    },
  );

  for (final (language, translate, play, hearThePause, marked, heard) in [
    (
      'pt',
      'traduzir o ensaio da cena',
      'Tocar ou pausar a gravação',
      'ouvir a pausa',
      'a pausa ficou aqui — ouçam, ajustem se precisar e toquem no círculo para traduzir — 0:07 / 0:10',
      'a pausa ficou aqui — ouçam, ajustem se precisar e toquem no círculo para traduzir — 0:06 / 0:10',
    ),
    (
      'en',
      'translate the scene rehearsal',
      'Play or pause your recording',
      'hear the pause',
      'the pause is here — listen, move it if you need to, then tap the circle to translate — 0:07 / 0:10',
      'the pause is here — listen, move it if you need to, then tap the circle to translate — 0:06 / 0:10',
    ),
  ]) {
    testWidgets(
      '$language: a pausa marked carries her clock where the take stopped, and the live clock while «ouvir a pausa» plays',
      (tester) async {
        final (harness, container) = await _onTheSceneScreen(
          tester,
          rehearsals: [
            _rehearsal(frases: [_frase('f1', 0, 3000)]),
          ],
          until: (state) =>
              state.scene.step == SceneStep.translate &&
              state.sceneEnvelope != null,
        );
        container.read(roomLanguageProvider.notifier).choose(language);
        await tester.pump(const Duration(milliseconds: 300));

        await tester.tap(find.text(translate));
        await pumpUntil(
          tester,
          () => switch (container.read(salaSessionProvider).channel) {
            PartPlaying(:final opened) => opened,
            _ => false,
          },
        );
        harness.playback.at = const Duration(seconds: 7);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(byLabel(play));
        await pumpUntil(
          tester,
          () => container.read(salaSessionProvider).scene.pausa != null,
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          container.read(salaSessionProvider).scene.pausa,
          const Duration(seconds: 7),
        );

        expect(
          find.text(marked),
          findsOneWidget,
          reason: 'a pausa marcada apagava o relógio do take',
        );
        expect(byLabel(marked), findsOneWidget);

        await tester.tap(byLabel(hearThePause));
        await pumpUntil(
          tester,
          () => switch (container.read(salaSessionProvider).channel) {
            PartPlaying(:final opened) => opened,
            _ => false,
          },
        );
        expect(harness.playback.ranges.last, '5500-7000');
        harness.playback.at = const Duration(seconds: 1);
        await tester.pump(const Duration(milliseconds: 1100));

        expect(
          find.text(heard),
          findsOneWidget,
          reason: '«ouvir a pausa» tocava sem dizer onde o take estava',
        );
      },
    );
  }

  testWidgets(
    '«um pouco antes» carries the clock and the strip\'s playhead to the pausa it moved to, not where the take stopped',
    (tester) async {
      final (harness, container) = await _onTheSceneScreen(
        tester,
        rehearsals: [
          _rehearsal(frases: [_frase('f1', 0, 3000)]),
        ],
        until: (state) =>
            state.scene.step == SceneStep.translate &&
            state.sceneEnvelope != null,
      );
      const moved =
          'a pausa ficou aqui — ouçam, ajustem se precisar e toquem no círculo para traduzir — 0:06 / 0:10';

      await tester.tap(find.text('traduzir o ensaio da cena'));
      await pumpUntil(
        tester,
        () => switch (container.read(salaSessionProvider).channel) {
          PartPlaying(:final opened) => opened,
          _ => false,
        },
      );
      harness.playback.at = const Duration(seconds: 7);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(byLabel('Tocar ou pausar a gravação'));
      await pumpUntil(
        tester,
        () => container.read(salaSessionProvider).scene.pausa != null,
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(_playhead(tester), closeTo(204.4, 0.01));

      await tester.tap(byLabel('um pouco antes'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        container.read(salaSessionProvider).scene.pausa,
        const Duration(milliseconds: 6600),
      );

      expect(
        find.text(moved),
        findsOneWidget,
        reason: 'a pausa movida deixava o relógio onde o take tinha parado',
      );
      expect(
        _playhead(tester),
        closeTo(192.72, 0.01),
        reason: 'a pausa movida deixava o marcador onde o take tinha parado',
      );
    },
  );

  for (final (which, frases) in [
    (
      'an earlier frase',
      [
        _frase('f1', 0, 4000),
        _frase('f2', 4000, 8000),
        _frase('f3', 8000, 10000),
      ],
    ),
    (
      'the last frase, its pausa on the move,',
      [_frase('f1', 0, 4000), _frase('f2', 4000, 8000)],
    ),
  ]) {
    testWidgets(
      '$which translated again reads «ouvindo o ensaio da cena…» with her clock while it plays, and only the clock once it stops',
      (tester) async {
        final (harness, container) = await _onTheSceneScreen(
          tester,
          rehearsals: [_rehearsal(frases: frases)],
          until: (state) =>
              state.scene.step == SceneStep.translate &&
              state.sceneEnvelope != null,
        );
        const playing = 'ouvindo o ensaio da cena… — 0:05 / 0:10';
        const stopped = '0:08 / 0:10';

        await tester.tap(byLabel(_bar(2)));
        await pumpUntil(
          tester,
          () => switch (container.read(salaSessionProvider).channel) {
            PartPlaying(:final opened) => opened,
            _ => false,
          },
        );
        expect(harness.playback.ranges.last, '4000-8000');
        harness.playback.at = const Duration(seconds: 1);
        await tester.pump(const Duration(milliseconds: 1100));

        expect(
          find.text(playing),
          findsOneWidget,
          reason:
              'a frase traduzida de novo tocando não dizia que o take tocava',
        );

        harness.playback.at = const Duration(seconds: 4);
        harness.playback.finishPlayback();
        await pumpUntil(
          tester,
          () => container.read(salaSessionProvider).channel is! PartPlaying,
        );
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          find.text(stopped),
          findsOneWidget,
          reason:
              'a frase traduzida de novo parada escrevia uma dica em vez de só o relógio',
        );
        expect(byLabel(stopped), findsOneWidget);
      },
    );
  }

  testWidgets(
    'the last frase translated again up to the take\'s end, once stopped, reads only her clock, not «fim do ensaio da cena»',
    (tester) async {
      final (harness, container) = await _onTheSceneScreen(
        tester,
        rehearsals: [
          _rehearsal(
            frases: [_frase('f1', 0, 4000), _frase('f2', 4000, 10000)],
          ),
        ],
        until: (state) =>
            state.scene.step == SceneStep.translate &&
            state.sceneEnvelope != null,
      );

      await tester.tap(byLabel(_bar(2)));
      await pumpUntil(
        tester,
        () => switch (container.read(salaSessionProvider).channel) {
          PartPlaying(:final opened) => opened,
          _ => false,
        },
      );
      expect(harness.playback.ranges.last, '4000-10000');
      expect(
        container.read(salaSessionProvider).scene.pausa,
        const Duration(seconds: 10),
      );
      harness.playback.at = const Duration(seconds: 6);
      harness.playback.finishPlayback();
      await pumpUntil(
        tester,
        () => container.read(salaSessionProvider).channel is! PartPlaying,
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text('0:10 / 0:10'),
        findsOneWidget,
        reason:
            'a frase traduzida de novo até o fim do take dizia «fim do ensaio da cena»',
      );
      expect(find.text('fim do ensaio da cena'), findsNothing);
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
    'a sent scene rehearsal opened from the list draws its strip with the take\'s loudness',
    (tester) async {
      await _inListenMode(tester);

      final strip = tester.widget<SceneStrip>(
        find.descendant(
          of: find.byType(SceneRehearsalView),
          matching: find.byType(SceneStrip),
        ),
      );
      expect(
        strip.envelope?.length,
        const Duration(seconds: 10),
        reason:
            'a escuta aberta da lista desenhava a faixa sem o volume do take',
      );
    },
  );

  testWidgets(
    'a scene rehearsal whose frase places cannot be read, answered as already sent, draws its sent strip with the take\'s loudness',
    (tester) async {
      final (harness, container) = await _onTheSceneScreen(
        tester,
        rehearsals: [
          _rehearsal(frases: [_frase('f1', 0, 12000)]),
        ],
        until: (state) => state.scene.step == SceneStep.placesUnknown,
      );
      harness.room
        ..sendRefusalsFirst.add(RefusalCode.sceneRehearsalSent)
        ..sceneRehearsals[0] = _rehearsal(
          sentAt: '2026-10-27T10:00:00+00:00',
          frases: [_frase('f1', 0, 12000)],
        );

      await tester.tap(byLabel('terminei'));
      await pumpUntil(
        tester,
        () => container.read(salaSessionProvider).scene.step == SceneStep.sent,
      );
      await tester.pump(const Duration(milliseconds: 300));

      final strip = tester.widget<SceneStrip>(
        find.descendant(
          of: find.byType(SceneRehearsalView),
          matching: find.byType(SceneStrip),
        ),
      );
      expect(
        strip.envelope?.length,
        const Duration(seconds: 10),
        reason:
            'o ensaio que já tinha ido para a voz desenhava a faixa sem o volume do take',
      );
    },
  );

  testWidgets(
    'a rehearsal being translated, left for a sent one in the list and opened again, keeps its loudness without reading the take again',
    (tester) async {
      final (harness, container) = await _onTheSceneScreen(
        tester,
        rehearsals: [
          _rehearsal(
            sentAt: '2026-10-27T10:00:00+00:00',
            frases: [_frase('f1', 0, 3000)],
          ),
          _rehearsal(n: 2, frases: [_frase('f1', 0, 3000)]),
        ],
        until: (state) =>
            state.scene.step == SceneStep.translate &&
            state.sceneEnvelope != null,
      );
      final notifier = container.read(salaSessionProvider.notifier);

      notifier.openTheListedSceneRehearsal('ensaio-da-cena-1');
      await pumpUntil(
        tester,
        () =>
            container.read(salaSessionProvider).scene.step == SceneStep.sent &&
            container.read(salaSessionProvider).sceneEnvelope != null,
      );
      notifier.openTheListedSceneRehearsal('ensaio-da-cena-2');
      await pumpUntil(
        tester,
        () =>
            container.read(salaSessionProvider).scene.step ==
            SceneStep.translate,
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        harness.envelopesRead,
        hasLength(2),
        reason: 'o take do ensaio reaberto era lido inteiro de novo',
      );
      expect(container.read(salaSessionProvider).sceneEnvelope, isNotNull);
    },
  );
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
    'the row on screen is marked in azul, not dimmed, and a row that cannot be opened while another rehearsal comes down is not dimmed either',
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
      await tester.tap(byLabel(sentRow));
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
    'a row on the list stays live while a frase\'s translation comes down, as hers, not still',
    (tester) async {
      const sentRow =
          'ouvir o ensaio da cena 1, 1 · frases traduzidas, enviado';
      final (harness, _) = await _onTheSceneScreen(
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
      expect(
        tester.widget<Semantics>(byLabel(sentRow)).properties.enabled,
        isNot(isFalse),
      );

      harness.room.holdNextClip();
      await tester.tap(byLabel('ouvir a minha tradução da frase 1'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        tester.widget<Semantics>(byLabel(sentRow)).properties.enabled,
        isNot(isFalse),
        reason: 'a lista parava enquanto a tradução da frase descia',
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
      final fill = find.descendant(
        of: byLabel('frase 1'),
        matching: find.byType(FractionallySizedBox),
      );
      final track = tester
          .getSize(find.ancestor(of: fill, matching: find.byType(Align)).first)
          .width;
      Size bar(int n) => tester.getSize(
        find.descendant(
          of: byLabel('frase $n'),
          matching: find.byType(FractionallySizedBox),
        ),
      );

      expect(
        bar(2).height,
        10,
        reason: 'a barra da frase tinha altura zero e não aparecia',
      );
      expect(bar(2).width, track);
      expect(bar(1).width, track / 2);
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
    'a long list of the session\'s scene rehearsals takes its whole height in the page, not a third of the screen',
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
        greaterThan(700 / 3),
        reason: 'a lista ficava presa num terço da tela e rolava sozinha',
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
      final fill = find.descendant(
        of: byLabel('frase 1'),
        matching: find.byType(FractionallySizedBox),
      );
      final track = tester
          .getSize(find.ancestor(of: fill, matching: find.byType(Align)).first)
          .width;
      Size bar(int n) => tester.getSize(
        find.descendant(
          of: byLabel('frase $n'),
          matching: find.byType(FractionallySizedBox),
        ),
      );

      expect(container.read(salaSessionProvider).scene.length, isNull);
      expect(bar(2).width, track);
      expect(
        bar(1).width,
        track / 2,
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
  for (final (look, areia, digit) in [
    (Brightness.light, const Color(0xFFC5C29F), const Color(0xFF0A0703)),
    (Brightness.dark, const Color(0xFF6E6A57), const Color(0xFFF2EDE1)),
  ]) {
    testWidgets(
      'in the ${look.name} look each frase told carries its number in ink on her areia disc, not white',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = look;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await _onTheSceneScreen(
          tester,
          rehearsals: [
            _rehearsal(frases: [_frase('f1', 0, 3000)]),
          ],
          until: (state) => state.scene.step == SceneStep.translate,
        );

        _numberedDisc(tester, byLabel(_bar(1)), '1', fill: areia, digit: digit);
      },
    );
    testWidgets(
      'in the ${look.name} look each frase of a sent scene rehearsal carries its number in ink on her areia disc',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = look;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await _inListenMode(tester);

        _numberedDisc(
          tester,
          byLabel('frase 1'),
          '1',
          fill: areia,
          digit: digit,
        );
      },
    );
  }
  for (final (look, areia, wash) in [
    (
      Brightness.light,
      const Color(0xFFC5C29F),
      const Color.fromRGBO(255, 255, 255, .4),
    ),
    (
      Brightness.dark,
      const Color(0xFF6E6A57),
      const Color.fromRGBO(236, 234, 220, .05),
    ),
  ]) {
    for (final (step, row, open)
        in <(String, String, Future<void> Function(WidgetTester))>[
          (
            'told',
            _bar(1),
            (tester) => _onTheSceneScreen(
              tester,
              rehearsals: [
                _rehearsal(frases: [_frase('f1', 0, 3000)]),
              ],
              until: (state) => state.scene.step == SceneStep.translate,
            ),
          ),
          ('of a sent scene rehearsal', 'frase 1', _inListenMode),
        ]) {
      testWidgets(
        'in the ${look.name} look each frase $step is her bordered card, its bar over «frase 1», not a flat line',
        (tester) async {
          tester.platformDispatcher.platformBrightnessTestValue = look;
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );
          await open(tester);
          Rect at(Finder finder) => tester.getRect(
            find.descendant(of: byLabel(row), matching: finder),
          );
          final card = find.descendant(
            of: byLabel(row),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is DecoratedBox &&
                  widget.decoration is BoxDecoration &&
                  (widget.decoration as BoxDecoration).border != null,
            ),
          );
          final bar = at(find.byType(FractionallySizedBox));
          final words = at(find.text('frase 1'));

          expect(
            bar.bottom,
            lessThanOrEqualTo(words.top),
            reason: 'a barra corria ao lado de «frase 1», não sobre ela',
          );
          expect(words.left, bar.left);
          expect(bar.left, greaterThan(at(find.text('1')).right));
          expect(card, findsOneWidget, reason: 'a frase era uma linha solta');
          final decoration =
              tester.widget<DecoratedBox>(card).decoration as BoxDecoration;
          expect(decoration.border, Border.all(color: areia, width: 1.2));
          expect(decoration.borderRadius, BorderRadius.circular(12));
          expect(decoration.color, wash);
          expect(tester.getRect(card).contains(bar.center), isTrue);
          expect(tester.getRect(card).contains(words.center), isTrue);
        },
      );
    }
  }
  for (final (look, verdeClaro) in [
    (Brightness.light, const Color(0xFF777D45)),
    (Brightness.dark, const Color(0xFFAAB07E)),
  ]) {
    testWidgets(
      'in the ${look.name} look a frase bar is her verde-claro fill along a pale track, not a red stroke on nothing',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = look;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await _onTheSceneScreen(
          tester,
          rehearsals: [
            _rehearsal(
              frases: [_frase('f1', 0, 2000), _frase('f2', 2000, 6000)],
            ),
          ],
          until: (state) => state.scene.step == SceneStep.translate,
        );

        for (final (n, share) in [(1, 0.5), (2, 1.0)]) {
          final fill = find.descendant(
            of: byLabel(_bar(n)),
            matching: find.byType(FractionallySizedBox),
          );
          final track = find.ancestor(
            of: fill,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is DecoratedBox &&
                  widget.decoration is BoxDecoration &&
                  (widget.decoration as BoxDecoration).color ==
                      const Color.fromRGBO(199, 194, 159, .28),
            ),
          );

          expect(
            track,
            findsOneWidget,
            reason: 'a barra não tinha trilho; só a parte cheia aparecia',
          );
          expect(
            (tester.widget<DecoratedBox>(track).decoration as BoxDecoration)
                .borderRadius,
            BorderRadius.circular(5),
          );
          expect(tester.getSize(track).height, 10);
          expect(
            (tester
                        .widget<DecoratedBox>(
                          find.descendant(
                            of: fill,
                            matching: find.byType(DecoratedBox),
                          ),
                        )
                        .decoration
                    as BoxDecoration)
                .color,
            verdeClaro.withValues(alpha: .85),
            reason: 'a parte cheia era o vermelho do microfone a .6',
          );
          expect(
            tester.getSize(fill).width / tester.getSize(track).width,
            share,
          );
        }
      },
    );
  }
  for (final (look, telha, areia) in [
    (Brightness.light, const Color(0xFFBE4A01), const Color(0xFFC5C29F)),
    (Brightness.dark, const Color(0xFFD6612A), const Color(0xFF6E6A57)),
  ]) {
    testWidgets(
      'in the ${look.name} look the frase being translated again wears telha on its bar and its border, and the others keep theirs',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = look;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final (_, container) = await _onTheSceneScreen(
          tester,
          rehearsals: [
            _rehearsal(
              frases: [_frase('f1', 0, 3000), _frase('f2', 3000, 6000)],
            ),
          ],
          until: (state) => state.scene.step == SceneStep.translate,
        );
        await tester.tap(byLabel(_bar(1)));
        await tester.pump(const Duration(milliseconds: 300));
        BoxDecoration paint(int n, bool Function(BoxDecoration) which) => tester
            .widgetList<DecoratedBox>(
              find.descendant(
                of: byLabel(_bar(n)),
                matching: find.byType(DecoratedBox),
              ),
            )
            .map((box) => box.decoration)
            .whereType<BoxDecoration>()
            .singleWhere(which);
        Color? border(int n) =>
            (paint(n, (box) => box.border != null).border as Border?)
                ?.top
                .color;
        Color? fill(int n) => paint(
          n,
          (box) =>
              box.borderRadius == BorderRadius.circular(5) &&
              box.color != const Color.fromRGBO(199, 194, 159, .28),
        ).color;

        expect(
          container.read(salaSessionProvider).scene.translatingAgain?.fraseId,
          'f1',
        );
        expect(
          border(1),
          telha,
          reason: 'a frase traduzida de novo não se distinguia das outras',
        );
        expect(fill(1), telha.withValues(alpha: .85));
        expect(border(2), areia);
        expect(fill(2), isNot(telha.withValues(alpha: .85)));
      },
    );
  }
  for (final (device, width, left, right) in [
    ('an iPhone SE', 375.0, 16.0, 375.0 - 16),
    ('an iPad', 820.0, (820.0 - 470) / 2, (820.0 + 470) / 2),
  ]) {
    testWidgets(
      'on $device each frase told and its speaker keep her width, 16 points from the edges and at most 470',
      (tester) async {
        await _onTheSceneScreen(
          tester,
          view: Size(width, 2400),
          rehearsals: [
            _rehearsal(frases: [_frase('f1', 0, 3000)]),
          ],
          until: (state) => state.scene.step == SceneStep.translate,
        );

        expect(
          tester.getRect(byLabel(_bar(1))).left,
          left,
          reason: 'a frase tinha a largura do que escrevia, não a dela',
        );
        expect(
          tester.getRect(byLabel('ouvir a minha tradução da frase 1')).right,
          right,
        );
      },
    );
  }
  for (final (device, width, wide) in [
    ('an iPhone SE', 375.0, 375.0 - 2 * 16),
    ('an iPad', 820.0, 470.0),
  ]) {
    testWidgets(
      'on $device a listed scene rehearsal is as wide as the frase told above it, not narrower',
      (tester) async {
        await _onTheSceneScreen(
          tester,
          view: Size(width, 2400),
          rehearsals: [
            _rehearsal(frases: [_frase('f1', 0, 3000)]),
          ],
          until: (state) => state.scene.step == SceneStep.translate,
        );
        final frase =
            tester.getRect(byLabel('ouvir a minha tradução da frase 1')).right -
            tester.getRect(byLabel(_bar(1))).left;

        expect(frase, wide);
        expect(
          tester
              .getSize(
                byLabel('Ensaio da cena 1, 1 · frases traduzidas, não enviado'),
              )
              .width,
          wide,
          reason: 'no iPad a lista tinha 438 pontos e as frases 470',
        );
      },
    );
  }
  for (final (step, line, open)
      in <(String, String, Future<void> Function(WidgetTester))>[
        (
          'record step',
          'Toquem no círculo para gravar o ensaio da cena; toquem de novo '
              'para parar.',
          (tester) => _onTheSceneScreen(
            tester,
            scenesHeld: true,
            until: (state) => state.stage == SalaStage.cena,
          ),
        ),
        (
          'translate step',
          'Ouçam o ensaio da cena; toquem no círculo para pausar onde a frase '
              'acaba, e de novo para traduzir só aquela frase.',
          (tester) => _onTheSceneScreen(
            tester,
            rehearsals: [
              _rehearsal(frases: [_frase('f1', 0, 3000)]),
            ],
            until: (state) => state.scene.step == SceneStep.translate,
          ),
        ),
        ('listen mode', _listenLine, _inListenMode),
      ]) {
    testWidgets(
      'the $step sub line is drawn at her normal letter spacing, not spread by a quarter point',
      (tester) async {
        await open(tester);
        await pumpUntil(tester, () => find.text(line).evaluate().isNotEmpty);

        expect(
          tester
              .renderObject<RenderParagraph>(find.text(line))
              .text
              .style
              ?.letterSpacing,
          0,
          reason: 'a linha herdava o espaçamento de .25 do Material',
        );
      },
    );
  }
  for (final (look, areia) in [
    (Brightness.light, const Color(0xFFC5C29F)),
    (Brightness.dark, const Color(0xFF6E6A57)),
  ]) {
    testWidgets(
      'in the ${look.name} look a listed rehearsal that is not on screen is edged in her areia, not a faint line',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = look;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await _onTheSceneScreen(
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
        final decoration =
            tester
                    .widget<Container>(
                      find.descendant(
                        of: byLabel(
                          'ouvir o ensaio da cena 1, 1 · frases traduzidas, enviado',
                        ),
                        matching: find.byType(Container),
                      ),
                    )
                    .decoration
                as BoxDecoration;

        expect(
          decoration.border,
          Border.all(color: areia, width: 1.2),
          reason: 'a borda da linha era uma linha de 16%; a dela é areia',
        );
      },
    );
  }
  testWidgets(
    'two listed scene rehearsals stand her .3rem apart, not 6 points',
    (tester) async {
      await _onTheSceneScreen(
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

      expect(
        tester
                .getRect(
                  byLabel(
                    'Ensaio da cena 2, 1 · frases traduzidas, não enviado',
                  ),
                )
                .top -
            tester
                .getRect(
                  byLabel(
                    'ouvir o ensaio da cena 1, 1 · frases traduzidas, enviado',
                  ),
                )
                .bottom,
        closeTo(4.8, 1e-9),
        reason: 'as linhas da lista ficavam a 6 pontos; as dela a .3rem',
      );
    },
  );
  testWidgets('two frases told stand her .3rem apart, not 6 points', (
    tester,
  ) async {
    await _onTheSceneScreen(
      tester,
      rehearsals: [
        _rehearsal(frases: [_frase('f1', 0, 3000), _frase('f2', 3000, 6000)]),
      ],
      until: (state) => state.scene.step == SceneStep.translate,
    );

    expect(
      tester.getRect(byLabel(_bar(2))).top -
          tester.getRect(byLabel(_bar(1))).bottom,
      closeTo(4.8, 1e-9),
      reason: 'as frases ficavam a 6 pontos uma da outra; as dela a .3rem',
    );
  });
  testWidgets(
    'a frase that cannot be tapped while another rehearsal comes down keeps its card at full strength, and only its speaker dims',
    (tester) async {
      final (harness, container) = await _onTheSceneScreen(
        tester,
        rehearsals: [
          _rehearsal(
            sentAt: '2026-10-15T14:20:00+00:00',
            frases: [_frase('f9', 0, 3000)],
          ),
          _rehearsal(n: 2, frases: [_frase('f1', 0, 3000)]),
        ],
        until: (state) => state.scene.rehearsal?.n == 2,
      );
      const speaker = 'ouvir a minha tradução da frase 1';

      harness.room.holdNextClip();
      await tester.tap(
        byLabel('ouvir o ensaio da cena 1, 1 · frases traduzidas, enviado'),
      );
      await pumpUntil(
        tester,
        () => container.read(salaSessionProvider).scene.waiting,
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(container.read(salaSessionProvider).scene.waiting, isTrue);
      expect(
        tester.widget<Semantics>(byLabel(_bar(1))).properties.enabled,
        isFalse,
      );
      expect(
        tester
            .widgetList<Opacity>(
              find.descendant(
                of: byLabel(_bar(1)),
                matching: find.byType(Opacity),
              ),
            )
            .map((opacity) => opacity.opacity),
        everyElement(1.0),
        reason: 'a frase que não se toca agora vinha apagada; a dela não',
      );
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.descendant(
                of: byLabel(speaker),
                matching: find.byType(AnimatedOpacity),
              ),
            )
            .opacity,
        0.35,
      );
      harness.room.finishHeldClip();
      await tester.pump(const Duration(milliseconds: 500));
    },
  );
  for (final (look, areia, verdeClaro) in [
    (Brightness.light, const Color(0xFFC5C29F), const Color(0xFF777D45)),
    (Brightness.dark, const Color(0xFF6E6A57), const Color(0xFFAAB07E)),
  ]) {
    for (final (step, open) in <(String, Future<void> Function(WidgetTester))>[
      (
        'told',
        (tester) => _onTheSceneScreen(
          tester,
          rehearsals: [
            _rehearsal(frases: [_frase('f1', 0, 3000)]),
          ],
          until: (state) => state.scene.step == SceneStep.translate,
        ),
      ),
      ('of a sent scene rehearsal', _inListenMode),
    ]) {
      testWidgets(
        'in the ${look.name} look the speaker beside each frase $step is her 38 point areia ring around a verde-claro speaker, not a bare red one',
        (tester) async {
          tester.platformDispatcher.platformBrightnessTestValue = look;
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );
          await open(tester);
          final speaker = byLabel('ouvir a minha tradução da frase 1');
          final ring = find.descendant(
            of: speaker,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Container &&
                  widget.decoration is BoxDecoration &&
                  (widget.decoration as BoxDecoration).shape == BoxShape.circle,
            ),
          );
          final icon = tester.widget<Icon>(
            find.descendant(of: speaker, matching: find.byType(Icon)),
          );

          expect(ring, findsOneWidget);
          expect(tester.getSize(ring), const Size(38, 38));
          final decoration =
              tester.widget<Container>(ring).decoration as BoxDecoration;
          expect(
            decoration.border,
            Border.all(color: areia, width: 1.3),
            reason: 'o alto-falante não tinha o anel de areia dela',
          );
          expect(decoration.color, isNull);
          expect(icon.icon, LucideIcons.volume2);
          expect(icon.size, 18);
          expect(
            icon.color,
            verdeClaro,
            reason: 'o alto-falante era vermelho; o dela é verde-claro',
          );
        },
      );
    }
  }
  for (final (look, verdeClaro) in [
    (Brightness.light, const Color(0xFF777D45)),
    (Brightness.dark, const Color(0xFFAAB07E)),
  ]) {
    testWidgets(
      'in the ${look.name} look the frases heading and the list heading are her small verde-claro capitals, not the 14 point grey',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = look;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await _onTheSceneScreen(
          tester,
          rehearsals: [
            _rehearsal(frases: [_frase('f1', 0, 3000)]),
          ],
          until: (state) => state.scene.step == SceneStep.translate,
        );

        for (final heading in [
          'FRASES TRADUZIDAS',
          'ENSAIOS DA CENA DESTA SESSÃO',
        ]) {
          final style = tester.widget<Text>(find.text(heading)).style;
          expect(
            style?.fontSize,
            closeTo(11.2, 1e-9),
            reason: 'o cabeçalho tinha 14 pontos; o dela tem .7rem',
          );
          expect(style?.color, verdeClaro);
          expect(style?.fontWeight, FontWeight.w600);
          expect(style?.letterSpacing, closeTo(2.016, 1e-9));
        }
      },
    );
  }
  for (final (look, verdeClaro) in [
    (Brightness.light, const Color(0xFF777D45)),
    (Brightness.dark, const Color(0xFFAAB07E)),
  ]) {
    for (final (step, row, open)
        in <(String, String, Future<void> Function(WidgetTester))>[
          (
            'told',
            _bar(1),
            (tester) => _onTheSceneScreen(
              tester,
              rehearsals: [
                _rehearsal(frases: [_frase('f1', 0, 3000)]),
              ],
              until: (state) => state.scene.step == SceneStep.translate,
            ),
          ),
          ('of a sent scene rehearsal', 'frase 1', _inListenMode),
        ]) {
      testWidgets(
        'in the ${look.name} look «frase 1» under the bar of a frase $step is her small verde-claro line, not 16 point ink',
        (tester) async {
          tester.platformDispatcher.platformBrightnessTestValue = look;
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );
          await open(tester);
          final style = tester
              .widget<Text>(
                find.descendant(
                  of: byLabel(row),
                  matching: find.text('frase 1'),
                ),
              )
              .style;

          expect(
            style?.fontSize,
            closeTo(11.2, 1e-9),
            reason: '«frase 1» tinha 16 pontos; o dela tem .7rem',
          );
          expect(style?.color, verdeClaro);
          expect(style?.height, 1.35);
        },
      );
    }
  }
  for (final (look, verdeClaro) in [
    (Brightness.light, const Color(0xFF777D45)),
    (Brightness.dark, const Color(0xFFAAB07E)),
  ]) {
    for (final (step, line, open)
        in <(String, String, Future<void> Function(WidgetTester))>[
          (
            'translate step',
            'Ouçam o ensaio da cena; toquem no círculo para pausar onde a frase '
                'acaba, e de novo para traduzir só aquela frase.',
            (tester) => _onTheSceneScreen(
              tester,
              rehearsals: [
                _rehearsal(frases: [_frase('f1', 0, 3000)]),
              ],
              until: (state) => state.scene.step == SceneStep.translate,
            ),
          ),
          ('listen mode', _listenLine, _inListenMode),
        ]) {
      testWidgets(
        'in the ${look.name} look the $step sub line is her .92rem verde-claro, at most 36 characters wide',
        (tester) async {
          tester.platformDispatcher.platformBrightnessTestValue = look;
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );
          await open(tester);
          final style = tester.widget<Text>(find.text(line)).style;

          expect(
            style?.fontSize,
            closeTo(14.72, 1e-9),
            reason: 'a linha de baixo do título tinha 16 pontos em tinta',
          );
          expect(style?.color, verdeClaro);
          expect(
            tester.getSize(find.text(line)).width,
            lessThanOrEqualTo(36 * 14.72 + .01),
            reason: 'a linha corria a 560 pontos; a dela para em 36ch',
          );
        },
      );
    }
  }
  for (final (look, areia, azul, verdeClaro, digit, ink) in [
    (
      Brightness.light,
      const Color(0xFFC5C29F),
      const Color(0xFF89AAA3),
      const Color(0xFF777D45),
      const Color(0xFFF6F5EB),
      const Color(0xFF0A0703),
    ),
    (
      Brightness.dark,
      const Color(0xFF6E6A57),
      const Color(0xFF8FB1A9),
      const Color(0xFFAAB07E),
      const Color(0xFF1E1B15),
      const Color(0xFFF2EDE1),
    ),
  ]) {
    testWidgets(
      'in the ${look.name} look a listed rehearsal carries its number in her disc, azul on the one on screen and verde-claro once sent',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = look;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await _onTheSceneScreen(
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
        final list = byLabel('ensaios da cena desta sessão');

        _numberedDisc(tester, list, '1', fill: verdeClaro, digit: digit);
        _numberedDisc(tester, list, '2', fill: azul, digit: digit);
      },
    );
    testWidgets(
      'in the ${look.name} look a listed rehearsal neither sent nor on screen is her areia disc numbered in ink, and a sent one on screen stays verde-claro',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = look;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await _inListenMode(
          tester,
          rehearsals: [
            _rehearsal(
              sentAt: '2026-10-15T14:20:00+00:00',
              frases: [_frase('f1', 0, 3000)],
            ),
            _rehearsal(n: 2, frases: [_frase('f2', 0, 3000)]),
          ],
        );
        final list = byLabel('ensaios da cena desta sessão');

        _numberedDisc(tester, list, '1', fill: verdeClaro, digit: digit);
        _numberedDisc(tester, list, '2', fill: areia, digit: ink);
      },
    );
  }
  for (final (look, verdeClaro, verde, telha) in [
    (
      Brightness.light,
      const Color(0xFF777D45),
      const Color(0xFF3F3E20),
      const Color(0xFFBE4A01),
    ),
    (
      Brightness.dark,
      const Color(0xFFAAB07E),
      const Color(0xFFECEADC),
      const Color(0xFFD6612A),
    ),
  ]) {
    testWidgets(
      'in the ${look.name} look a listed rehearsal is written at her .8rem in verde-claro, verde on the one on screen, not 14 point grey and ink',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = look;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await _onTheSceneScreen(
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
        TextStyle? style(String row, String words) => tester
            .widget<Text>(
              find.descendant(of: byLabel(row), matching: find.text(words)),
            )
            .style;
        const sentRow =
            'ouvir o ensaio da cena 1, 1 · frases traduzidas, enviado';
        const rowOnScreen =
            'Ensaio da cena 2, 1 · frases traduzidas, não enviado';

        for (final (row, words, color) in [
          (sentRow, '1 · frases traduzidas', verdeClaro),
          (sentRow, 'enviado', verdeClaro),
          (rowOnScreen, '1 · frases traduzidas', verde),
          (rowOnScreen, 'não enviado', telha),
        ]) {
          expect(
            style(row, words)?.fontSize,
            closeTo(12.8, 1e-9),
            reason: 'a linha da lista tinha 14 pontos; a dela tem .8rem',
          );
          expect(style(row, words)?.color, color);
        }
      },
    );
  }
  for (final (look, azul) in [
    (Brightness.light, const Color(0xFF89AAA3)),
    (Brightness.dark, const Color(0xFF8FB1A9)),
  ]) {
    testWidgets(
      'in the ${look.name} look the listed rehearsal on screen is edged in her ${look.name} azul',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = look;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await _onTheSceneScreen(
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

        expect(
          ((tester
                              .widget<Container>(
                                find.descendant(
                                  of: byLabel(
                                    'Ensaio da cena 2, 1 · frases traduzidas, não enviado',
                                  ),
                                  matching: find.byType(Container),
                                ),
                              )
                              .decoration
                          as BoxDecoration?)
                      ?.border
                  as Border?)
              ?.top
              .color,
          azul,
          reason: 'no escuro a linha da tela tinha a borda azul clara',
        );
      },
    );
  }

  for (final (language, play, terminei, sending) in [
    (
      'pt',
      'Tocar ou pausar a gravação',
      'terminei',
      'enviando a tradução do ensaio da cena para a voz…',
    ),
    (
      'en',
      'Play or pause your recording',
      'done',
      'sending the translation of the scene rehearsal to the voice…',
    ),
  ]) {
    testWidgets(
      '$language: while terminei is in the air the line beside play reads her sending words, not only the button',
      (tester) async {
        final (harness, container) = await _onTheSceneScreen(
          tester,
          rehearsals: [
            _rehearsal(frases: [_frase('f1', 0, 3000)]),
          ],
          until: (state) => state.scene.step == SceneStep.translate,
        );
        container.read(roomLanguageProvider.notifier).choose(language);
        await tester.pump(const Duration(milliseconds: 300));
        harness.room.holdNextTurn();

        await tester.tap(byLabel(terminei));
        await pumpUntil(
          tester,
          () => container.read(salaSessionProvider).theSceneIsSending,
        );
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          _besidePlay(play, sending),
          findsOneWidget,
          reason:
              'só o botão dizia que a tradução ia para a voz; a linha ao lado do play ficava calada',
        );

        harness.room.finishHeldTurn();
        await pumpUntil(
          tester,
          () => container.read(salaSessionProvider).stage == SalaStage.conversa,
        );
        await tester.pump(const Duration(seconds: 2));
      },
    );
  }

  testWidgets(
    'a terminei the room answered gives the line beside play back to the step\'s hint while her went-to-the-voice line shows, not «enviando…»',
    (tester) async {
      final (harness, container) = await _onTheSceneScreen(
        tester,
        rehearsals: [
          _rehearsal(frases: [_frase('f1', 0, 3000)]),
        ],
        until: (state) => state.scene.step == SceneStep.translate,
      );
      const paused =
          'pausado — toque no círculo para marcar onde a frase acaba — 0:07 / 0:10';
      await tester.tap(find.text('traduzir o ensaio da cena'));
      await pumpUntil(
        tester,
        () => container.read(salaSessionProvider).channel is PartPlaying,
      );
      harness.playback.at = const Duration(seconds: 7);
      harness.room.holdNextTurn();
      await tester.tap(byLabel('terminei'));
      await pumpUntil(
        tester,
        () => container.read(salaSessionProvider).theSceneIsSending,
      );

      harness.room.finishHeldTurn();
      await pumpUntil(
        tester,
        () => container.read(salaSessionProvider).scene.wentToTheVoice,
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(container.read(salaSessionProvider).scene.wentToTheVoice, isTrue);
      expect(
        _besidePlay('Tocar ou pausar a gravação', paused),
        findsOneWidget,
        reason:
            'a tradução já tinha ido para a voz e a linha ao lado do play seguia dizendo «enviando…»',
      );
      expect(find.textContaining('enviando'), findsNothing);

      await pumpUntil(
        tester,
        () => container.read(salaSessionProvider).stage == SalaStage.conversa,
      );
      await tester.pump(const Duration(seconds: 2));
    },
  );

  testWidgets(
    'a terminei the room refused gives the line beside play back to the step\'s hint, not «enviando…»',
    (tester) async {
      final (harness, container) = await _onTheSceneScreen(
        tester,
        rehearsals: [
          _rehearsal(frases: [_frase('f1', 0, 3000)]),
        ],
        until: (state) => state.scene.step == SceneStep.translate,
      );
      const paused =
          'pausado — toque no círculo para marcar onde a frase acaba — 0:07 / 0:10';
      await tester.tap(find.text('traduzir o ensaio da cena'));
      await pumpUntil(
        tester,
        () => container.read(salaSessionProvider).channel is PartPlaying,
      );
      harness.playback.at = const Duration(seconds: 7);
      harness.room.holdSceneSends = true;
      await tester.tap(byLabel('terminei'));
      await pumpUntil(tester, () => harness.room.heldSceneSends.isNotEmpty);
      await tester.pump(const Duration(milliseconds: 300));
      expect(container.read(salaSessionProvider).theSceneIsSending, isTrue);

      harness.room.heldSceneSends.single.complete(
        Refused(RefusalCode.unnamed(422)),
      );
      await pumpUntil(
        tester,
        () => !container.read(salaSessionProvider).theSceneIsSending,
      );
      await tester.pump(const Duration(seconds: 1));

      expect(container.read(salaSessionProvider).sceneLine, SceneLine.notSent);
      expect(
        _besidePlay('Tocar ou pausar a gravação', paused),
        findsOneWidget,
        reason:
            'o envio recusado deixava a linha ao lado do play dizendo «enviando…»',
      );
      expect(find.textContaining('enviando'), findsNothing);
    },
  );

  testWidgets(
    'a terminei tapped over the playing take writes her sending words with the clock where the take stopped',
    (tester) async {
      final (harness, container) = await _onTheSceneScreen(
        tester,
        rehearsals: [
          _rehearsal(frases: [_frase('f1', 0, 3000)]),
        ],
        until: (state) => state.scene.step == SceneStep.translate,
      );
      const sending =
          'enviando a tradução do ensaio da cena para a voz… — 0:07 / 0:10';
      await tester.tap(find.text('traduzir o ensaio da cena'));
      await pumpUntil(
        tester,
        () => container.read(salaSessionProvider).channel is PartPlaying,
      );
      harness.playback.at = const Duration(seconds: 7);
      harness.room.holdSceneSends = true;

      await tester.tap(byLabel('terminei'));
      await pumpUntil(tester, () => harness.room.heldSceneSends.isNotEmpty);
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        _besidePlay('Tocar ou pausar a gravação', sending),
        findsOneWidget,
        reason: 'o envio apagava o relógio de onde o take tinha parado',
      );

      harness.room.heldSceneSends.single.complete(null);
      await pumpUntil(
        tester,
        () => container.read(salaSessionProvider).stage == SalaStage.conversa,
      );
      await tester.pump(const Duration(seconds: 2));
    },
  );

  testWidgets(
    'a terminei after the take was heard to its end writes her sending words alone, not a clock at the end',
    (tester) async {
      final (harness, container) = await _onTheSceneScreen(
        tester,
        rehearsals: [
          _rehearsal(frases: [_frase('f1', 0, 3000)]),
        ],
        until: (state) => state.scene.step == SceneStep.translate,
      );
      const sending = 'enviando a tradução do ensaio da cena para a voz…';
      await tester.tap(find.text('traduzir o ensaio da cena'));
      await pumpUntil(
        tester,
        () => container.read(salaSessionProvider).channel is PartPlaying,
      );
      harness.playback.at = const Duration(seconds: 10);
      harness.playback.finishPlayback();
      await pumpUntil(
        tester,
        () => container.read(salaSessionProvider).channel is! PartPlaying,
      );
      await tester.pump(const Duration(milliseconds: 300));
      harness.room.holdSceneSends = true;

      await tester.tap(byLabel('terminei'));
      await pumpUntil(tester, () => harness.room.heldSceneSends.isNotEmpty);
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        _besidePlay('Tocar ou pausar a gravação', sending),
        findsOneWidget,
        reason:
            'o take ouvido até o fim mostrava o relógio no fim, que o dela não mostra',
      );

      harness.room.heldSceneSends.single.complete(null);
      await pumpUntil(
        tester,
        () => container.read(salaSessionProvider).stage == SalaStage.conversa,
      );
      await tester.pump(const Duration(seconds: 2));
    },
  );

  testWidgets(
    'a terminei over a take told to its end, heard again and paused at 0:02, keeps her clock where it stopped, not the words alone',
    (tester) async {
      final (harness, container) = await _onTheSceneScreen(
        tester,
        rehearsals: [
          _rehearsal(frases: [_frase('f1', 0, 10000)]),
        ],
        until: (state) => state.scene.step == SceneStep.translate,
      );
      const sending =
          'enviando a tradução do ensaio da cena para a voz… — 0:02 / 0:10';
      final play = byLabel('Tocar ou pausar a gravação');
      await tester.tap(find.text('traduzir o ensaio da cena'));
      await pumpUntil(
        tester,
        () => container.read(salaSessionProvider).channel is PartPlaying,
      );
      harness.playback.at = const Duration(seconds: 2);
      await tester.tap(play);
      await pumpUntil(
        tester,
        () => container.read(salaSessionProvider).channel is! PartPlaying,
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(container.read(salaSessionProvider).scene.moreToTell, isFalse);
      harness.room.holdSceneSends = true;

      await tester.tap(byLabel('terminei'));
      await pumpUntil(tester, () => harness.room.heldSceneSends.isNotEmpty);
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        _besidePlay('Tocar ou pausar a gravação', sending),
        findsOneWidget,
        reason:
            'o take todo traduzido e parado em 0:02 perdia o relógio no envio; o dela só o tira com o take no fim',
      );

      harness.room.heldSceneSends.single.complete(null);
      await pumpUntil(
        tester,
        () => container.read(salaSessionProvider).stage == SalaStage.conversa,
      );
      await tester.pump(const Duration(seconds: 2));
    },
  );
}

Finder _theButton(String words) => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      widget.properties.label == words &&
      widget.properties.button == true,
);

Finder _besidePlay(String play, String words) => find.descendant(
  of: find.ancestor(of: byLabel(play), matching: find.byType(Row)).first,
  matching: find.text(words),
);

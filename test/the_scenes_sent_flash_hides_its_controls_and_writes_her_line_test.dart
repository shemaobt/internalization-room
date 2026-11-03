import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/scene_strip.dart';

import 'a_scene_room.dart';
import 'a_wav_take.dart';
import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show byLabel;

const _session = 'sessao-1';

const _tell = 'Toque para traduzir esta frase do ensaio da cena';
const _tellEn = 'Tap to translate this phrase of the scene rehearsal';
const _restart = 'recomeçar a tradução';
const _restartEn = 'start the translation over';
const _terminei = 'terminei';
const _doneEn = 'done';
const _again = 'gravar o ensaio da cena de novo';
const _translate = 'traduzir o ensaio da cena';
const _sentLine = 'a tradução do ensaio da cena foi para a voz';
const _sentLineEn = 'the translation of the scene rehearsal went to the voice';
const _frasesHeading = 'frases traduzidas';
const _restartedLine = 'tradução recomeçada — o ensaio da cena ficou';
const _placesUnknownLine =
    'as frases já traduzidas não estão neste computador — toquem em terminei '
    'para enviar, ou recomecem a tradução';

SceneFrase _frase(String id, int startsMs, int endsMs) =>
    SceneFrase(fraseId: id, startsMs: startsMs, endsMs: endsMs);

final _oneFrase = SceneRehearsalRecord(
  rehearsalId: 'ensaio-da-cena-1',
  sessionId: _session,
  n: 1,
  frases: [_frase('f1', 0, 3000)],
);

final _placesCannotBeRead = SceneRehearsalRecord(
  rehearsalId: 'ensaio-da-cena-1',
  sessionId: _session,
  n: 1,
  frases: [_frase('f1', 0, 12000)],
);

Future<void> _sendsAndTheVoiceAnswers(
  WidgetTester tester,
  SalaHarness harness,
  ProviderContainer container,
  String terminei,
) async {
  harness.room.holdNextTurn();
  await tester.tap(byLabel(terminei));
  await tester.pump(const Duration(milliseconds: 300));
  harness.room.finishHeldTurn();
  await pumpUntil(
    tester,
    () => container.read(salaSessionProvider).scene.wentToTheVoice,
    beat: const Duration(milliseconds: 10),
  );
  expect(
    container.read(salaSessionProvider).scene.wentToTheVoice,
    isTrue,
    reason: 'the flash never came',
  );
  await tester.pump(const Duration(milliseconds: 10));
}

Future<(SalaHarness, ProviderContainer)> _flash(
  WidgetTester tester, {
  String language = 'pt',
}) async {
  final (harness, container) = await translateOnScreen(
    tester,
    rehearsal: _oneFrase,
  );
  if (language != 'pt') {
    container.read(roomLanguageProvider.notifier).choose(language);
    await tester.pump(const Duration(milliseconds: 300));
  }
  await _sendsAndTheVoiceAnswers(
    tester,
    harness,
    container,
    language == 'pt' ? _terminei : _doneEn,
  );
  return (harness, container);
}

Future<(SalaHarness, ProviderContainer)> _flashFromPlacesUnknown(
  WidgetTester tester,
) async {
  final harness = SalaHarness(filaEmMemoria: true)
    ..room.passages = const [Passagem(pericope: 'P01', audioUrl: '/voice/p01')]
    ..room.nextMoment = articulation;
  harness.room.sceneRehearsals.add(_placesCannotBeRead);
  harness.room.sceneAudio = aSpokenWav(length: const Duration(seconds: 10));
  harness.playback.measured = const Duration(seconds: 10);
  tester.view
    ..physicalSize = const Size(820, 2400)
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
  await tester.tap(byLabel('ensaio da cena'));
  await pumpUntil(
    tester,
    () =>
        container.read(salaSessionProvider).scene.step ==
        SceneStep.placesUnknown,
  );
  await tester.pump(const Duration(milliseconds: 500));
  expect(
    container.read(salaSessionProvider).scene.step,
    SceneStep.placesUnknown,
  );
  expect(find.text(_placesUnknownLine), findsOneWidget);
  await _sendsAndTheVoiceAnswers(tester, harness, container, _terminei);
  return (harness, container);
}

void flashTest(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(name, (tester) async {
      await body(tester);
      await tester.pump(const Duration(milliseconds: 1500));
    });

void main() {
  group('the sent flash', () {
    flashTest('during the sent flash the translate step draws no circle', (
      tester,
    ) async {
      await _flash(tester);

      expect(byLabel(_tell), findsNothing);
    });

    flashTest(
      'during the sent flash «recomeçar a tradução» is not drawn on a rehearsal with a translated frase',
      (tester) async {
        await _flash(tester);

        expect(find.text(_restart), findsNothing);
        expect(byLabel(_restart), findsNothing);
      },
    );

    flashTest('during the sent flash «terminei» is not drawn', (tester) async {
      await _flash(tester);

      expect(find.text(_terminei), findsNothing);
      expect(byLabel(_terminei), findsNothing);
    });

    flashTest(
      'during the sent flash her line «a tradução do ensaio da cena foi para a voz» is written once, under the strip and above «frases traduzidas»',
      (tester) async {
        await _flash(tester);

        expect(find.text(_sentLine), findsOneWidget);
        final strip = tester.getRect(find.byType(SceneStrip));
        final line = tester.getRect(find.text(_sentLine));
        final heading = tester.getRect(byLabel(_frasesHeading));
        expect(line.top, greaterThanOrEqualTo(strip.bottom));
        expect(line.bottom, lessThanOrEqualTo(heading.top));
      },
    );

    flashTest(
      'a «tradução recomeçada» line still standing at «terminei» is not written with her sent line',
      (tester) async {
        final (harness, container) = await translateOnScreen(
          tester,
          take: Uint8List.fromList(List.filled(4000, 7)),
          length: const Duration(seconds: 20),
          rehearsal: _oneFrase,
          restartLapse: const Duration(minutes: 5),
        );
        await tester.tap(find.text(_restart));
        await tester.pump(const Duration(milliseconds: 700));
        container
            .read(salaSessionProvider.notifier)
            .restartTheSceneTranslation();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(byLabel(_translate));
        await pumpUntil(
          tester,
          () => container.read(salaSessionProvider).channel is PartPlaying,
        );
        await tester.pump(const Duration(milliseconds: 100));
        final posts = harness.room.frasesKept.length;
        harness.playback.at = const Duration(seconds: 3);
        await tester.tap(byLabel(_tell));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(byLabel(_tell));
        await pumpUntil(
          tester,
          () => container.read(salaSessionProvider).channel is Microphone,
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(byLabel(_tell));
        await pumpUntil(
          tester,
          () =>
              harness.room.frasesKept.length > posts &&
              !container.read(salaSessionProvider).scene.waiting,
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text(_restartedLine), findsOneWidget);

        await _sendsAndTheVoiceAnswers(tester, harness, container, _terminei);

        expect(find.text(_sentLine), findsOneWidget);
        expect(find.text(_restartedLine), findsNothing);
        await tester.pump(const Duration(minutes: 5));
      },
    );

    flashTest(
      'during the sent flash «gravar o ensaio da cena de novo» stays drawn, as hers, and a tap on it changes nothing',
      (tester) async {
        final (harness, container) = await _flash(tester);
        final played = harness.playback.played.length;

        expect(find.text(_again), findsOneWidget);
        await tester.tap(find.text(_again), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 300));

        final state = container.read(salaSessionProvider);
        expect(state.scene.step, SceneStep.translate);
        expect(state.channel, isNot(isA<Microphone>()));
        expect(harness.playback.played, hasLength(played));
      },
    );

    flashTest(
      'in English during the sent flash the circle and «start the translation over» are not drawn and «the translation of the scene rehearsal went to the voice» is written',
      (tester) async {
        await _flash(tester, language: 'en');

        expect(byLabel(_tellEn), findsNothing);
        expect(find.text(_restartEn), findsNothing);
        expect(find.text(_doneEn), findsNothing);
        expect(find.text(_sentLineEn), findsOneWidget);
      },
    );

    flashTest(
      'a sent flash from places unknown draws no circle, no «recomeçar a tradução», no «terminei» and no places-unknown line, and writes her sent line',
      (tester) async {
        await _flashFromPlacesUnknown(tester);

        expect(byLabel(_tell), findsNothing);
        expect(find.text(_restart), findsNothing);
        expect(find.text(_terminei), findsNothing);
        expect(find.text(_placesUnknownLine), findsNothing);
        expect(find.text(_sentLine), findsOneWidget);
      },
    );

    testWidgets(
      'before «terminei» is answered the circle and «recomeçar a tradução» stand on a rehearsal with a translated frase',
      (tester) async {
        await translateOnScreen(tester, rehearsal: _oneFrase);

        expect(byLabel(_tell), findsOneWidget);
        expect(find.text(_restart), findsOneWidget);
        expect(find.text(_sentLine), findsNothing);
      },
    );
  });
}

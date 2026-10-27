import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'a_scene_room.dart' show articulation, pumpUntil;
import 'a_wav_take.dart';
import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show byLabel;

const _session = 'sessao-1';

SceneFrase _frase(String id, int startsMs, int endsMs) =>
    SceneFrase(fraseId: id, startsMs: startsMs, endsMs: endsMs);

SceneRehearsalRecord _rehearsal({
  int n = 1,
  String? sentAt,
  List<SceneFrase> frases = const [],
}) => SceneRehearsalRecord(
  rehearsalId: 'ensaio-da-cena-$n',
  sessionId: _session,
  n: n,
  sentAt: sentAt,
  frases: frases,
);

Future<(SalaHarness, ProviderContainer)> _onTheSceneScreen(
  WidgetTester tester, {
  List<SceneRehearsalRecord> rehearsals = const [],
  bool scenesHeld = false,
  required bool Function(SalaSessionState state) until,
}) async {
  final harness = SalaHarness(filaEmMemoria: true)
    ..room.passages = const [Passagem(pericope: 'P01', audioUrl: '/voice/p01')]
    ..room.nextMoment = articulation;
  harness.room.sceneRehearsals.addAll(rehearsals);
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
}

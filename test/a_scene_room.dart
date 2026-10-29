import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/moment.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/scene_question.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'a_wav_take.dart';
import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show byLabel, settle;

const articulation = Moment(at: MomentAt.articulation, part: 1, parts: 3);

const theSE = (name: 'the iPhone SE', size: Size(375, 667), bar: 20.0);
const theIPad = (name: 'the iPad', size: Size(820, 1180), bar: 24.0);

/// A room at rest in the Conversation, for the scene rehearsal's tests to open the red
/// microphone over.
final class SceneRoom {
  final SalaHarness harness;
  final ProviderContainer container;

  SceneRoom(this.harness, this.container);

  SalaSessionNotifier get sala => container.read(salaSessionProvider.notifier);

  SalaSessionState get state => container.read(salaSessionProvider);

  int asked(String call) =>
      harness.room.calls.where((asked) => asked == call).length;
}

Future<SceneRoom> atRest([SalaHarness? given]) async {
  final harness = given ?? SalaHarness();
  harness.room.nextMoment = articulation;
  final container = harness.container();
  addTearDown(container.dispose);
  final room = SceneRoom(harness, container);
  await room.sala.goConversa(book: 'Ruth');
  await waitFor(
    'a sala abrir a conversa e se calar',
    () =>
        room.state.sessionId != null &&
        room.state.stage == SalaStage.conversa &&
        room.state.voice == VoiceState.invite &&
        !room.state.awaitingTheGuide,
  );
  await settle();
  return room;
}

Future<void> theScreenOpens(SceneRoom room) async {
  room.sala.openTheSceneRehearsal();
  await waitFor('a tela do ensaio da cena abrir', () {
    return room.state.stage == SalaStage.cena &&
        room.asked('sceneRehearsalsOf') > 0;
  }, limit: const Duration(seconds: 30));
  await settle();
}

Future<void> theSceneMicrophoneOpens(SceneRoom room) async {
  room.sala.sceneTap();
  await waitFor(
    'o microfone da cena abrir',
    () => switch (room.state.channel) {
      Microphone(owner: MicOwner.scene) => true,
      _ => false,
    },
  );
}

/// «recomeçar a tradução» tapped twice, past the wake that keeps a double tap from
/// firing: the room's harness wakes it at once.
Future<void> restartTheTranslationInTwoTaps(SceneRoom room) async {
  room.sala.restartTheSceneTranslation();
  await settle();
  room.sala.restartTheSceneTranslation();
}

Future<void> translateOpens(SceneRoom room) => waitFor(
  'o ensaio abrir na tradução',
  () => room.state.scene.step == SceneStep.translate,
  limit: const Duration(seconds: 30),
);

/// The scene screen pumped over a session at rest in Articulação, open on the translate
/// step of [rehearsal], whose take is [take] (a spoken one [length] long by default), with
/// [alsoListed] older in the list.
Future<(SalaHarness, ProviderContainer)> translateOnScreen(
  WidgetTester tester, {
  Uint8List? take,
  Duration length = const Duration(seconds: 10),
  required SceneRehearsalRecord rehearsal,
  List<SceneRehearsalRecord> alsoListed = const [],
}) async {
  final harness = SalaHarness(filaEmMemoria: true)
    ..room.passages = const [Passagem(pericope: 'P01', audioUrl: '/voice/p01')]
    ..room.nextMoment = articulation;
  harness.room.sceneRehearsals
    ..addAll(alsoListed)
    ..add(rehearsal);
  harness.room.sceneAudio = take ?? aSpokenWav(length: length);
  harness.playback.measured = length;
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
    () => container.read(salaSessionProvider).scene.step == SceneStep.translate,
  );
  await tester.pump(const Duration(milliseconds: 500));
  return (harness, container);
}

Future<void> withRealLetters() async {
  final fonts =
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  final roboto = FontLoader('Roboto');
  for (final weight in ['Regular', 'Medium', 'Bold']) {
    roboto.addFont(
      File(
        '$fonts/Roboto-$weight.ttf',
      ).readAsBytes().then(ByteData.sublistView),
    );
  }
  await roboto.load();
}

Future<ProviderContainer> onTheSceneStep(
  WidgetTester tester, {
  required Size screen,
  required double bar,
  required SceneStep step,
  required List<SceneRehearsalRecord> rehearsals,
  List<Scene> scenes = const [],
}) async {
  await tester.runAsync(withRealLetters);
  final harness = SalaHarness(filaEmMemoria: true)
    ..room.passages = const [Passagem(pericope: 'P01', audioUrl: '/voice/p01')]
    ..room.nextMoment = articulation
    ..room.passageScenes = scenes;
  harness.room.sceneRehearsals.addAll(rehearsals);
  harness.room.sceneAudio = aSpokenWav(length: const Duration(seconds: 10));
  harness.playback.measured = const Duration(seconds: 10);
  tester.view
    ..physicalSize = screen
    ..devicePixelRatio = 1
    ..padding = FakeViewPadding(top: bar)
    ..viewPadding = FakeViewPadding(top: bar);
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
    () => container.read(salaSessionProvider).sceneRehearsals.isNotEmpty,
  );
  if (step == SceneStep.sent) {
    notifier.openTheListedSceneRehearsal('ensaio-da-cena-1');
  }
  await pumpUntil(
    tester,
    () => container.read(salaSessionProvider).scene.step == step,
  );
  await tester.pump(const Duration(milliseconds: 1500));
  expect(container.read(salaSessionProvider).scene.step, step);
  return container;
}

Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration beat = const Duration(milliseconds: 100),
}) async {
  for (var vez = 0; vez < 40 && !done(); vez++) {
    await tester.pump(beat);
  }
}

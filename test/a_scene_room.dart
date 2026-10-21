import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/moment.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'a_wav_take.dart';
import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show byLabel, settle;

const articulation = Moment(at: MomentAt.articulation, part: 1, parts: 3);

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
  });
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

Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration beat = const Duration(milliseconds: 100),
}) async {
  for (var vez = 0; vez < 40 && !done(); vez++) {
    await tester.pump(beat);
  }
}

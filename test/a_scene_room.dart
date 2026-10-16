import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/moment.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show settle;

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
  await room.sala.goConversa();
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

Future<void> translateOpens(SceneRoom room) => waitFor(
  'o ensaio abrir na tradução',
  () => room.state.scene.step == SceneStep.translate,
);

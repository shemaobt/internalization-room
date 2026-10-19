import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/mic_permission.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/mic_gate_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/scene_rehearsal_view.dart';

import 'a_scene_room.dart';
import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show byLabel, settle;

final _redMicrophone = byLabel('ensaio da cena');
final _circleAtRest = byLabel('Gravar o ensaio da cena');
final _circleRecording = byLabel(
  'gravem o ensaio da cena na língua materna; toquem para parar',
);
final _theWayBack = byLabel('Voltar para a passagem atual');

bool _aMicrophone(Channel channel) => channel is Microphone;

Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var vez = 0; vez < 30 && !done(); vez++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<(SalaHarness, ProviderContainer)> _inArticulation(
  WidgetTester tester,
) async {
  final harness = SalaHarness(filaEmMemoria: true)
    ..room.passages = const [Passagem(pericope: 'P01', audioUrl: '/voice/p01')]
    ..room.nextMoment = articulation;
  final container = await pumpSala(tester, harness);
  addTearDown(() => closeTheRoom(container));
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.abrirEscolha();
  await tester.pump(const Duration(milliseconds: 300));
  unawaited(notifier.goConversa(book: 'Ruth', pericope: 'P01'));
  await _pumpUntil(
    tester,
    () => container.read(salaSessionProvider).voice == VoiceState.invite,
  );
  await tester.pump(const Duration(milliseconds: 1500));
  return (harness, container);
}

Future<(SalaHarness, ProviderContainer)> _onTheSceneRehearsal(
  WidgetTester tester,
) async {
  final (harness, container) = await _inArticulation(tester);
  await tester.tap(_redMicrophone);
  await tester.pump(const Duration(milliseconds: 1500));
  return (harness, container);
}

Future<void> _backToTheApp(WidgetTester tester) async {
  for (final lifecycle in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(lifecycle);
  }
  await tester.pump(const Duration(milliseconds: 500));
}

/// What the room had shown, said and asked when the team tapped.
final class _Before {
  final int lines;
  final int persons;

  _Before(SalaHarness harness)
    : lines = harness.voice.assets.length + harness.voice.played.length,
      persons = harness.room.personsAsked;
}

void _expectNoGateNoLineNoPerson(
  SalaHarness harness,
  ProviderContainer container,
  _Before before,
) {
  expect(
    container.read(micPermissionProvider),
    isNot(MicAccess.denied),
    reason: 'a tela do ensaio da cena não registra o microfone como negado',
  );
  expect(harness.voice.assets, isNot(contains(micBlockedAsset(testLanguage))));
  expect(
    harness.voice.assets.length + harness.voice.played.length,
    before.lines,
    reason: 'nenhuma fala depois do toque',
  );
  expect(container.read(salaSessionProvider).needsPerson, isFalse);
  expect(
    harness.room.personsAsked,
    before.persons,
    reason: 'nenhuma pessoa chamada',
  );
}

Future<void> _tapsTheSceneCircle(SceneRoom room) async {
  room.sala.sceneTap();
  await settle();
}

void main() {
  testWidgets(
    'a refused microphone on the scene rehearsal leaves the circle at rest, with no '
    'gate, no line and no person',
    (tester) async {
      final (harness, container) = await _onTheSceneRehearsal(tester);
      harness.recorder.permitted = false;
      final before = _Before(harness);

      await tester.tap(_circleAtRest);
      await tester.pump(const Duration(milliseconds: 1500));

      final state = container.read(salaSessionProvider);
      expect(find.byType(MicGateView), findsNothing);
      expect(find.byType(SceneRehearsalView), findsOneWidget);
      expect(_circleAtRest, findsOneWidget);
      expect(_aMicrophone(state.channel), isFalse);
      expect(state.scene.step, SceneStep.record);
      expect(state.stage, SalaStage.cena);
      _expectNoGateNoLineNoPerson(harness, container, before);
    },
  );

  test(
    'a tablet with no microphone taps the scene circle and the screen is unchanged',
    () async {
      final room = await atRest();
      await theScreenOpens(room);
      room.harness.recorder.startThrows = true;
      final screen = room.state.scene;
      final before = _Before(room.harness);

      await _tapsTheSceneCircle(room);

      final scene = room.state.scene;
      expect(scene.step, screen.step);
      expect(scene.label, screen.label);
      expect(scene.rehearsal, screen.rehearsal);
      expect(scene.keep, screen.keep);
      expect(room.state.stage, SalaStage.cena);
      expect(_aMicrophone(room.state.channel), isFalse);
      _expectNoGateNoLineNoPerson(room.harness, room.container, before);
    },
  );

  testWidgets(
    'after a refusal, the next tap that opens the microphone records',
    (tester) async {
      final (harness, container) = await _onTheSceneRehearsal(tester);
      harness.recorder.permitted = false;
      await tester.tap(_circleAtRest);
      await tester.pump(const Duration(milliseconds: 1500));

      harness.recorder.permitted = true;
      await tester.tap(_circleAtRest);
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        container.read(salaSessionProvider).channel,
        const Microphone(MicOwner.scene),
      );
      expect(_circleRecording, findsOneWidget);

      await tester.tap(_circleRecording);
      await _pumpUntil(tester, () => harness.room.scenesKept.isNotEmpty);
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        harness.room.calls.where((call) => call == 'keepSceneRehearsal'),
        hasLength(1),
      );
    },
  );

  test(
    'two refused taps in a row on the scene rehearsal show nothing and call no person',
    () async {
      final room = await atRest();
      await theScreenOpens(room);
      room.harness.recorder.permitted = false;
      final before = _Before(room.harness);

      await _tapsTheSceneCircle(room);
      await _tapsTheSceneCircle(room);

      _expectNoGateNoLineNoPerson(room.harness, room.container, before);
    },
  );

  test(
    'two failed starts in a row on the scene rehearsal call no person',
    () async {
      final room = await atRest();
      await theScreenOpens(room);
      room.harness.recorder.startThrows = true;
      final persons = room.harness.room.personsAsked;

      await _tapsTheSceneCircle(room);
      await _tapsTheSceneCircle(room);

      expect(room.state.needsPerson, isFalse);
      expect(room.harness.room.personsAsked, persons);
    },
  );

  test(
    'nothing is recorded, kept or labelled when the scene microphone did not open',
    () async {
      final room = await atRest(SalaHarness(filaEmMemoria: true));
      await theScreenOpens(room);

      room.harness.recorder.permitted = false;
      await _tapsTheSceneCircle(room);
      await _tapsTheSceneCircle(room);
      room.harness.recorder
        ..permitted = true
        ..startThrows = true;
      await _tapsTheSceneCircle(room);
      await _tapsTheSceneCircle(room);

      expect(room.asked('keepSceneRehearsal'), 0);
      expect(
        (await room.harness.takes.entries()).where(
          (row) => row.kind == 'cena' && row.sessionId == room.state.sessionId,
        ),
        isEmpty,
      );
      expect(room.harness.recorder.lastPath, isNull);
    },
  );

  group('a scene start that answers after its microphone was closed', () {
    Future<SceneRoom> tappedTwiceWhileStarting() async {
      final room = await atRest();
      await theScreenOpens(room);
      room.harness.recorder
        ..returnsNothing = true
        ..holdNextStart();
      await theSceneMicrophoneOpens(room);
      await _tapsTheSceneCircle(room);
      return room;
    }

    test('refused, records no refusal', () async {
      final room = await tappedTwiceWhileStarting();
      room.harness.recorder
        ..permitted = false
        ..finishStart();
      await settle();

      expect(
        room.container.read(micPermissionProvider),
        isNot(MicAccess.denied),
      );
    });

    test('failed twice, calls no person', () async {
      final room = await tappedTwiceWhileStarting();
      room.harness.recorder
        ..startThrows = true
        ..finishStart();
      await settle();
      room.harness.recorder.holdNextStart();
      await theSceneMicrophoneOpens(room);
      await _tapsTheSceneCircle(room);
      room.harness.recorder.finishStart();
      await settle();

      expect(room.state.needsPerson, isFalse);
    });
  });

  group('the session screen keeps its own rule', () {
    test('a failed start on the scene rehearsal does not count towards the '
        "Conversation's two", () async {
      final room = await atRest();
      await theScreenOpens(room);
      room.harness.recorder.startThrows = true;
      await _tapsTheSceneCircle(room);
      room.sala.leaveTheSceneRehearsal();
      await waitFor(
        'a conversa voltar',
        () => room.state.stage == SalaStage.conversa,
      );
      await settle();

      room.sala.conversaTap();
      await settle();
      expect(room.state.needsPerson, isFalse);

      room.sala.conversaTap();
      await settle();
      expect(room.state.needsPerson, isTrue);
    });

    test(
      "a scene recording that works does not reset the Conversation's count",
      () async {
        final room = await atRest();
        room.harness.recorder.startThrows = true;
        room.sala.conversaTap();
        await settle();
        room.harness.recorder.startThrows = false;
        await theScreenOpens(room);
        await theSceneMicrophoneOpens(room);
        await _tapsTheSceneCircle(room);
        await translateOpens(room);
        room.sala.leaveTheSceneRehearsal();
        await waitFor(
          'a conversa voltar',
          () => room.state.stage == SalaStage.conversa,
        );
        await settle();

        room.harness.recorder.startThrows = true;
        room.sala.conversaTap();
        await settle();

        expect(room.state.needsPerson, isTrue);
      },
    );

    testWidgets(
      'a refusal on the Conversation still shows the gate and says its line',
      (tester) async {
        final (harness, container) = await _inArticulation(tester);
        harness.recorder.permitted = false;

        container.read(salaSessionProvider.notifier).conversaTap();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(MicGateView), findsOneWidget);
        expect(container.read(micPermissionProvider), MicAccess.denied);

        harness.voice.assets.clear();
        await _backToTheApp(tester);

        expect(harness.voice.assets, contains(micBlockedAsset(testLanguage)));
      },
    );

    test('a refusal on the Rehearsal still shows the gate', () async {
      final room = await atRest();
      room.harness.recorder.permitted = false;

      room.sala.goEnsaio();
      room.sala.ensaioTap();
      await settle();

      expect(room.container.read(micPermissionProvider), MicAccess.denied);
    });
  });

  testWidgets(
    'the permission check on return to the app neither covers nor speaks over the '
    'scene rehearsal',
    (tester) async {
      final (harness, _) = await _onTheSceneRehearsal(tester);
      harness.recorder.permitted = false;

      await _backToTheApp(tester);

      expect(find.byType(SceneRehearsalView), findsOneWidget);
      expect(find.byType(MicGateView), findsNothing);
      expect(
        harness.voice.assets,
        isNot(contains(micBlockedAsset(testLanguage))),
      );

      await tester.tap(_theWayBack);
      await tester.pump(const Duration(milliseconds: 1500));

      expect(find.byType(MicGateView), findsOneWidget);
    },
  );

  test(
    "a dead disk under the scene take's download falls out of reach, never in silence",
    () async {
      final harness = SalaHarness();
      harness.room
        ..sceneRehearsals.add(
          SceneRehearsalRecord(
            rehearsalId: 'ensaio-da-cena-1',
            sessionId: 'sessao-1',
            n: 1,
            recordedAt: DateTime(2026, 10, 15, 14, 5),
            frases: const [],
          ),
        )
        ..sceneAudio = Uint8List.fromList([1, 2, 3]);
      final room = await atRest(harness);
      final persons = harness.room.personsAsked;
      harness.recorder.keepBytesFails = true;

      room.sala.openTheSceneRehearsal();
      await waitFor('a sala cair', () => room.state.unreachable);
      await settle();

      expect(harness.voice.assets, contains(offlineNoticeAsset(testLanguage)));
      expect(room.state.needsPerson, isFalse);
      expect(harness.room.personsAsked, persons);
      expect(room.state.stage, SalaStage.cena);
    },
  );
}

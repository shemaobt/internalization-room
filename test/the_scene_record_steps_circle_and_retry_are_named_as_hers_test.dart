import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/scene_question.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/main.dart';

import 'a_scene_room.dart';
import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel;

const _record = 'Gravar o ensaio da cena';
const _stop = 'Parar';
const _hint = 'gravem o ensaio da cena na língua materna; toquem para parar';
const _keeping = 'guardando o ensaio da cena…';
const _retryName = 'Tentar enviar de novo';
const _retryWords = 'falhou — toque para tentar de novo';

Future<void> _pumpTheRoom(WidgetTester tester, SceneRoom room) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: room.container,
      child: const SalaApp(),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

Future<SceneRoom> _atRest(WidgetTester tester) async {
  late SceneRoom room;
  await tester.runAsync(() async {
    room = await atRest();
    await theScreenOpens(room);
  });
  return room;
}

Future<SceneRoom> _recording(WidgetTester tester) async {
  late SceneRoom room;
  await tester.runAsync(() async {
    room = await atRest();
    await theScreenOpens(room);
    await theSceneMicrophoneOpens(room);
  });
  return room;
}

Future<void> _recordAndHoldTheKeep(SceneRoom room) async {
  room.harness.room.holdNextKeepBeforeTheRoomActs();
  room.harness.recorder.rehearsalSpeaks = Uint8List.fromList([
    for (var i = 0; i < 1200; i++) (i * 7) % 251,
  ]);
  await theSceneMicrophoneOpens(room);
  room.sala.sceneTap();
  await waitFor(
    'o take chegar à sala',
    () => room.asked('keepSceneRehearsal') > 0,
  );
}

Future<SceneRoom> _kept(WidgetTester tester) async {
  late SceneRoom room;
  await tester.runAsync(() async {
    room = await atRest();
    await theScreenOpens(room);
    await _recordAndHoldTheKeep(room);
  });
  return room;
}

Future<void> _failTheHeldKeep(SceneRoom room) async {
  room.harness.room.failSceneWith = const NetworkFailed('sem rede');
  room.harness.room.finishHeldKeep();
  await waitFor(
    'o ensaio ficar esperando',
    () => room.state.scene.keep is NotKept,
  );
}

Future<SceneRoom> _failed(WidgetTester tester) async {
  late SceneRoom room;
  await tester.runAsync(() async {
    room = await atRest();
    await theScreenOpens(room);
    await _recordAndHoldTheKeep(room);
    await _failTheHeldKeep(room);
  });
  return room;
}

void main() {
  testWidgets('at rest the record circle is named «Gravar o ensaio da cena»', (
    tester,
  ) async {
    final room = await _atRest(tester);
    await _pumpTheRoom(tester, room);

    expect(byLabel(_record), findsOneWidget);
  });

  testWidgets(
    'while the team records VoiceOver names the record circle «Parar», not '
    'her hint',
    (tester) async {
      final room = await _recording(tester);
      await _pumpTheRoom(tester, room);

      expect(byLabel(_stop), findsOneWidget);
      expect(byLabel(_hint), findsNothing);
    },
  );

  testWidgets(
    'while the take is kept the record circle is still named «Gravar o '
    'ensaio da cena» and takes no tap',
    (tester) async {
      final room = await _kept(tester);
      await _pumpTheRoom(tester, room);

      expect(byLabel(_record), findsOneWidget);
      final circle = tester.widget<Semantics>(byLabel(_record));
      expect(circle.properties.enabled, isFalse);
      expect(byLabel(_keeping), findsNothing);
    },
  );

  testWidgets('in English the recording circle is named «Stop»', (
    tester,
  ) async {
    final room = await _recording(tester);
    room.container.read(roomLanguageProvider.notifier).choose('en');
    await _pumpTheRoom(tester, room);

    expect(byLabel('Stop'), findsOneWidget);
  });

  testWidgets(
    'in English the kept circle is named «Record the scene rehearsal» and '
    'takes no tap',
    (tester) async {
      final room = await _kept(tester);
      room.container.read(roomLanguageProvider.notifier).choose('en');
      await _pumpTheRoom(tester, room);

      expect(byLabel('Record the scene rehearsal'), findsOneWidget);
      expect(
        tester
            .widget<Semantics>(byLabel('Record the scene rehearsal'))
            .properties
            .enabled,
        isFalse,
      );
    },
  );

  testWidgets(
    "a failed take's retry is a button VoiceOver names «Tentar enviar de "
    'novo», still written «falhou — toque para tentar de novo»',
    (tester) async {
      final room = await _failed(tester);
      await _pumpTheRoom(tester, room);

      expect(byLabel(_retryName), findsOneWidget);
      expect(
        tester.widget<Semantics>(byLabel(_retryName)).properties.button,
        isTrue,
      );
      expect(find.text(_retryWords), findsOneWidget);
      expect(byLabel(_retryWords), findsNothing);
    },
  );

  testWidgets('in English the retry is named «Try sending again»', (
    tester,
  ) async {
    final room = await _failed(tester);
    room.container.read(roomLanguageProvider.notifier).choose('en');
    await _pumpTheRoom(tester, room);

    expect(byLabel('Try sending again'), findsOneWidget);
    expect(find.text('failed — tap to try again'), findsOneWidget);
  });

  testWidgets(
    'a tap on the retry named «Tentar enviar de novo» sends the take again',
    (tester) async {
      final room = await _failed(tester);
      await _pumpTheRoom(tester, room);
      room.harness.room.failSceneWith = null;
      final asked = room.asked('keepSceneRehearsal');

      await tester.tap(byLabel(_retryName));
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
        if (room.asked('keepSceneRehearsal') > asked) break;
      }

      expect(room.asked('keepSceneRehearsal'), asked + 1);
    },
  );

  testWidgets(
    'beside the scene question a failed take\'s retry is named «Tentar '
    'enviar de novo» too',
    (tester) async {
      late SceneRoom room;
      await tester.runAsync(() async {
        final harness = SalaHarness(filaEmMemoria: true)
          ..room.passageScenes = const [
            Scene(sceneId: 'S1', title: 'Ouvir a notícia e partir'),
            Scene(sceneId: 'S2', title: 'Primeiro apelo e recusa'),
          ]
          ..room.sceneAnswersFirst.add(const NetworkFailed('sem rede'));
        await harness.takes.enqueue(
          harness.recorder.aFile('cena-que-espera'),
          sessionId: 'sessao-1',
          kind: 'cena',
          scope: 'cena',
        );
        await harness.takes.flush();
        room = await atRest(harness);
        await theScreenOpens(room);
        await waitFor(
          'o take ficar esperando',
          () => room.state.scene.keep is NotKept,
        );
      });
      await _pumpTheRoom(tester, room);

      expect(byLabel('Qual cena vocês vão ensaiar?'), findsOneWidget);
      expect(byLabel(_retryName), findsOneWidget);
      expect(byLabel(_retryWords), findsNothing);
    },
  );

  testWidgets(
    'at rest VoiceOver hears her hint once, from the line under the circle',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final room = await _atRest(tester);
      await _pumpTheRoom(tester, room);

      expect(find.bySemanticsLabel(_hint), findsOneWidget);
      expect(find.bySemanticsLabel(_record), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets(
    'while the team records VoiceOver hears «gravando · m:ss» from the line '
    'under the circle',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final room = await _recording(tester);
      await _pumpTheRoom(tester, room);
      await tester.pump(const Duration(seconds: 3));

      expect(
        find.bySemanticsLabel(RegExp(r'^gravando · \d:\d\d$')),
        findsOneWidget,
      );
      semantics.dispose();
    },
  );
}

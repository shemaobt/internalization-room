import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/scene_rehearsal_view.dart';
import 'package:internalization_room/main.dart';

import 'a_scene_room.dart';
import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel, enterThePassage, relaunch, settle;

const _saving = 'guardando o ensaio da cena…';
const _saveFailed = 'não deu para guardar o ensaio da cena — gravem de novo';
const _tooLarge = 'grande demais para o servidor — grave em partes menores';
const _retry = 'falhou — toque para tentar de novo';
const _offline = NetworkFailed('sem rede');

Uint8List _aTake(int seed) =>
    Uint8List.fromList([for (var i = 0; i < 1200; i++) (i * seed) % 251]);

Future<Uint8List> _recordAScene(SceneRoom room, {Uint8List? take}) async {
  final bytes = take ?? _aTake(7);
  room.harness.recorder.rehearsalSpeaks = bytes;
  await theSceneMicrophoneOpens(room);
  room.sala.sceneTap();
  await waitFor(
    'o microfone da cena fechar',
    () => room.state.channel is! Microphone,
  );
  return bytes;
}

Future<void> _notKept(SceneRoom room) =>
    waitFor('o ensaio ficar esperando', () => room.state.scene.keep is NotKept);

Future<void> _theRetry(SceneRoom room) async {
  room.sala.sendTheSceneTakeAgain();
  await settle();
}

Future<void> _pumpTheRoom(WidgetTester tester, SceneRoom room) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: room.container,
      child: const SalaApp(),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets(
    'a scene take recorded with the network off shows «guardando o ensaio da '
    'cena…» while it is kept, then her failure words with «falhou — toque '
    'para tentar de novo»',
    (tester) async {
      late SceneRoom room;
      await tester.runAsync(() async {
        room = await atRest();
        await theScreenOpens(room);
        room.harness.room.holdNextKeep();
        await _recordAScene(room);
        await waitFor(
          'o take chegar à sala',
          () => room.asked('keepSceneRehearsal') > 0,
        );
      });
      await _pumpTheRoom(tester, room);

      expect(byLabel(_saving), findsOneWidget);

      await tester.runAsync(() async {
        room.harness.room.failSceneWith = _offline;
        room.harness.room.finishHeldKeep();
        await _notKept(room);
      });
      await tester.pump(const Duration(milliseconds: 100));

      expect(byLabel(_saveFailed), findsOneWidget);
      expect(byLabel(_retry), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SceneRehearsalView),
          matching: find.byType(Text),
        ),
        findsNothing,
        reason: 'a sala não tem texto; as palavras dela são só do VoiceOver',
      );
    },
  );

  test(
    'after the network returns, one tap sends the same take with the same '
    'label, and it opens on translate as the room\'s next rehearsal',
    () async {
      final room = await atRest();
      await theScreenOpens(room);
      room.harness.room.failSceneWith = _offline;
      final recorded = await _recordAScene(room);
      await _notKept(room);

      room.harness.room.failSceneWith = null;
      await _theRetry(room);
      await translateOpens(room);

      expect(room.harness.room.sceneTakesSent.single, recorded);
      expect(
        room.harness.room.sceneLabels.single,
        isNull,
        reason: 'o rótulo com que foi gravado, nenhum nesta fatia',
      );
      expect(room.state.scene.rehearsal?.n, 1);
      expect(room.harness.room.sceneRehearsals.single.sentAt, isNull);
    },
  );

  test(
    'a double tap on «falhou — toque para tentar de novo» sends the take once',
    () async {
      final room = await atRest();
      await theScreenOpens(room);
      room.harness.room.failSceneWith = _offline;
      await _recordAScene(room);
      await _notKept(room);
      room.harness.room.failSceneWith = null;
      final asked = room.asked('keepSceneRehearsal');

      room.sala.sendTheSceneTakeAgain();
      room.sala.sendTheSceneTakeAgain();
      await translateOpens(room);
      await settle();

      expect(room.asked('keepSceneRehearsal'), asked + 1);
    },
  );

  test('the circle does nothing while the take is being kept', () async {
    final room = await atRest();
    await theScreenOpens(room);
    room.harness.room.holdNextKeep();
    await _recordAScene(room);
    await waitFor(
      'o take chegar à sala',
      () => room.asked('keepSceneRehearsal') > 0,
    );
    final before = room.harness.sounds.length;

    room.sala.sceneTap();
    await settle();

    expect(room.harness.sounds.skip(before), isNot(contains('recorder:start')));
    room.harness.room.finishHeldKeep();
  });

  testWidgets('a take too large for the room shows her too-large words', (
    tester,
  ) async {
    late SceneRoom room;
    await tester.runAsync(() async {
      room = await atRest();
      await theScreenOpens(room);
      await _recordAScene(room, take: Uint8List(25 * 1024 * 1024 + 1));
      await _notKept(room);
    });
    await _pumpTheRoom(tester, room);

    expect(
      room.asked('keepSceneRehearsal'),
      0,
      reason: 'a sala recusaria acima de 25 MiB; nada sobe',
    );
    expect(byLabel(_tooLarge), findsOneWidget);
    expect(byLabel(_retry), findsOneWidget);
  });

  test(
    'two scene takes with a failed upload between them reach the room in the '
    'order recorded, each its own rehearsal',
    () async {
      final room = await atRest();
      await theScreenOpens(room);
      await _recordAScene(room, take: _aTake(1));
      await translateOpens(room);
      room.sala.recordTheSceneAgain();
      await settle();
      room.harness.room.failSceneWith = _offline;
      final second = await _recordAScene(room, take: _aTake(2));
      await _notKept(room);
      final third = await _recordAScene(room, take: _aTake(3));
      await _notKept(room);

      room.harness.room.failSceneWith = null;
      await _theRetry(room);
      await translateOpens(room);

      expect(room.harness.room.sceneTakesSent.skip(1), [second, third]);
      expect(
        room.state.scene.rehearsal?.n,
        room.harness.room.sceneRehearsals.last.n,
        reason: 'a tela fica na mais nova, com o número que a sala deu',
      );
    },
  );

  test('the tablet closed before the room confirmed a take: on reopening, the '
      'take is still waiting to be sent', () async {
    final home = Directory.systemTemp.createTempSync('sala-sessao-atual');
    addTearDown(() => home.deleteSync(recursive: true));
    final harness = SalaHarness(
      currentSession: LedgerThatReadsLate(home: () async => home),
    );
    harness.room.nextMoment = articulation;
    final room = SceneRoom(harness, harness.container());
    await enterThePassage(room.sala, () => room.state, 'P01');
    await waitFor(
      'a abertura ser dita',
      () =>
          room.state.voice == VoiceState.invite && room.state.sessionId != null,
    );
    await settle();
    final session = room.state.sessionId;
    await theScreenOpens(room);
    room.harness.room.failSceneWith = _offline;
    final recorded = await _recordAScene(room);
    await _notKept(room);

    final (again, next) = await relaunch(harness, room.container);
    final reopened = SceneRoom(again, next);
    await reopened.sala.openTheRoom();
    await waitFor(
      'a equipe pousar na sessão',
      () =>
          reopened.state.sessionId == session &&
          reopened.state.voice == VoiceState.invite,
    );
    final waiting = [
      for (final row in await again.takes.entries())
        if (row.kind == 'cena' && row.sessionId == session) row,
    ];
    expect(waiting, hasLength(1));
    expect(waiting.single.scene, isNull);

    reopened.sala.openTheSceneRehearsal();
    await _notKept(reopened);
    again.room.failSceneWith = null;
    await _theRetry(reopened);
    await translateOpens(reopened);

    expect(again.room.sceneTakesSent.single, recorded);
  });

  test(
    'a scene take the room confirmed leaves fila.json and stays on the tablet '
    'under the rehearsal\'s name',
    () async {
      final room = await atRest();
      await theScreenOpens(room);
      final recorded = await _recordAScene(room);
      await translateOpens(room);
      final rehearsalId = room.state.scene.rehearsal!.rehearsalId;

      expect(
        (await room.harness.takes.entries()).where((row) => row.kind == 'cena'),
        isEmpty,
      );
      expect(
        Directory(
          '${room.harness.takesHome.path}/guardadas',
        ).listSync().where((file) => file.path.contains('cena')),
        isEmpty,
        reason: 'a sala tem a gravação; a cópia da fila sai',
      );
      final held = await room.harness.recorder.heldAs('cena-$rehearsalId');
      expect(held, isNotNull);
      expect(File(held!).readAsBytesSync(), recorded);

      room.sala.leaveTheSceneRehearsal();
      await settle();
      room.sala.openTheSceneRehearsal();
      await translateOpens(room);
      expect(
        room.harness.room.clipsFetched.where(
          (url) => url.contains('/scene-rehearsals/'),
        ),
        isEmpty,
      );
    },
  );

  test('a scene take is never deleted by the app', () async {
    final home = Directory.systemTemp.createTempSync('sala-sessao-atual');
    addTearDown(() => home.deleteSync(recursive: true));
    final harness = SalaHarness(
      currentSession: LedgerThatReadsLate(home: () async => home),
    );
    final room = await atRest(harness);
    await theScreenOpens(room);
    room.harness.room.failSceneWith = _offline;
    await _recordAScene(room);
    final take = room.harness.recorder.lastPath!;
    await _notKept(room);
    room.harness.room.failSceneWith = const Refused('BAD_REQUEST');
    await _theRetry(room);
    await _notKept(room);
    room.harness.room.holdNextKeep();
    room.sala.sendTheSceneTakeAgain();
    await waitFor(
      'o take chegar à sala',
      () => room.asked('keepSceneRehearsal') > 2,
    );
    room.sala.leaveTheSceneRehearsal();
    room.harness.room.finishHeldKeep();
    await settle();
    room.harness.room.forgetTheSession(room.state.sessionId!);

    final (again, next) = await relaunch(harness, room.container);
    await SceneRoom(again, next).sala.openTheRoom();
    await settle();

    expect(harness.recorder.deleted, isNot(contains(take)));
    expect(again.recorder.deleted, isNot(contains(take)));
    expect(File(take).existsSync(), isTrue);
  });

  test('a keep answered after the team left never moves the screen, and the '
      'rehearsal reopens on translate without a download', () async {
    final room = await atRest();
    await theScreenOpens(room);
    room.harness.room.holdNextKeep();
    await _recordAScene(room);
    await waitFor(
      'o take chegar à sala',
      () => room.asked('keepSceneRehearsal') > 0,
    );

    room.sala.leaveTheSceneRehearsal();
    room.harness.room.finishHeldKeep();
    await settle();

    expect(room.state.stage, SalaStage.conversa);
    expect(room.state.scene.step, SceneStep.record);
    expect(room.state.scene.keep, isNull, reason: 'nada aparece');

    room.sala.openTheSceneRehearsal();
    await translateOpens(room);
    expect(
      room.harness.room.clipsFetched.where(
        (url) => url.contains('/scene-rehearsals/'),
      ),
      isEmpty,
    );
  });

  test('a keep that fails, again and again, never calls a person', () async {
    final room = await atRest();
    final personsBefore = room.harness.room.personsAsked;
    await theScreenOpens(room);
    room.harness.room.failSceneWith = _offline;
    await _recordAScene(room);
    await _notKept(room);

    for (var vez = 0; vez < 3; vez++) {
      await _theRetry(room);
      await _notKept(room);
    }

    expect(room.state.needsPerson, isFalse);
    expect(room.harness.room.personsAsked, personsBefore);
    expect(room.state.stage, SalaStage.cena);
  });

  test(
    'a gone session while the take waits leaves for the Choice, and the take '
    'stays on the tablet',
    () async {
      final room = await atRest();
      await theScreenOpens(room);
      room.harness.room.forgetTheSession(room.state.sessionId!);
      await _recordAScene(room);
      final take = room.harness.recorder.lastPath!;

      await waitFor(
        'a sala voltar à Escolha',
        () => room.state.stage == SalaStage.escolha,
      );

      expect(room.harness.recorder.deleted, isNot(contains(take)));
      expect(File(take).existsSync(), isTrue);
    },
  );
}

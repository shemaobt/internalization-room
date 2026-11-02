import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/take_upload_queue.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/scene_question.dart';
import 'package:internalization_room/features/sala/domain/scene_rehearsal.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/scene_rehearsal_view.dart';
import 'package:internalization_room/main.dart';

import 'a_scene_room.dart';
import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel, enterThePassage, relaunch, settle;
import 'support/temp.dart';

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

Future<void> _theOutboxLetsGo(SceneRoom room) {
  final session = room.state.sessionId!;
  return waitFor(
    'o tablet guardar o take que a sala confirmou',
    () async => await room.harness.takes.sceneWaitingIn(session) == null,
    limit: const Duration(seconds: 30),
  );
}

Future<void> _theRetry(SceneRoom room) async {
  room.sala.sendTheSceneTakeAgain();
  await settle();
}

/// The team comes back to the passage, which opens in a session other than [gone], and
/// opens the scene screen over the take still waiting.
Future<void> _theNextSessionOfThePassage(SceneRoom room, String gone) async {
  await settle();
  await room.sala.goConversa(book: 'Ruth');
  await waitFor(
    'a passagem abrir numa sessão nova',
    () =>
        room.state.sessionId != null &&
        room.state.sessionId != gone &&
        room.state.stage == SalaStage.conversa &&
        !room.state.awaitingTheGuide,
  );
  await settle();
  await theScreenOpens(room);
  await _notKept(room);
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
        room.harness.room.holdNextKeepBeforeTheRoomActs();
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

      expect(find.text(_saveFailed), findsOneWidget);
      expect(find.text(_retry), findsOneWidget);
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
          'Toquem no círculo para gravar o ensaio da cena; toquem de novo '
              'para parar.',
          'gravem o ensaio da cena na língua materna; toquem para parar',
          _saveFailed,
          _retry,
        ],
        reason:
            'com a gravação parada, a instrução e a dica dela ficavam só no '
            'VoiceOver ao lado das palavras da falha',
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
    expect(find.text(_tooLarge), findsOneWidget);
    expect(find.text(_retry), findsOneWidget);
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
    final home = aTempDir('sala-sessao-atual');
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
    final home = aTempDir('sala-sessao-atual');
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
    room.harness.room.holdNextKeepBeforeTheRoomActs();
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
    await _theOutboxLetsGo(room);

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
  test(
    'a take refused for good never covers a newer rehearsal the room kept',
    () async {
      final room = await atRest();
      await theScreenOpens(room);
      room.harness.room.failSceneWith = const Refused('BAD_REQUEST');
      await _recordAScene(room, take: _aTake(1));
      await _notKept(room);
      room.harness.room.failSceneWith = null;
      await _recordAScene(room, take: _aTake(2));
      await translateOpens(room);

      room.sala.leaveTheSceneRehearsal();
      await settle();
      room.sala.openTheSceneRehearsal();
      await translateOpens(room);

      expect(room.state.scene.keep, isNull);
      expect(
        room.state.scene.rehearsal?.rehearsalId,
        room.harness.room.sceneRehearsals.single.rehearsalId,
      );
    },
  );

  test(
    'a take still waiting shows before the room\'s unsent rehearsal',
    () async {
      final room = await atRest();
      room.harness.room.sceneRehearsals.add(
        SceneRehearsalRecord(
          rehearsalId: 'ensaio-da-cena-1',
          sessionId: room.state.sessionId!,
          n: 1,
        ),
      );
      room.sala.openTheSceneRehearsal();
      await translateOpens(room);
      room.sala.recordTheSceneAgain();
      await settle();
      room.harness.room.failSceneWith = _offline;
      await _recordAScene(room);
      await _notKept(room);

      room.sala.leaveTheSceneRehearsal();
      await settle();
      room.sala.openTheSceneRehearsal();

      await _notKept(room);
      expect(room.state.scene.step, SceneStep.record);
    },
  );
  test(
    'a take waiting with its label goes up with it, and a take recorded over '
    'it carries the same label',
    () async {
      final room = await atRest();
      room.harness.room.passageScenes = const [
        Scene(sceneId: 'S1', title: 'Ouvir a notícia e partir'),
        Scene(sceneId: 'S2', title: 'Primeiro apelo e recusa'),
        Scene(sceneId: 'S3', title: 'Segundo apelo e a separação'),
      ];
      final session = room.state.sessionId!;
      await room.harness.takes.enqueue(
        room.harness.recorder.aFile('cena-rotulada'),
        sessionId: session,
        kind: 'cena',
        scope: 'cena',
        scene: 'S2',
      );
      room.harness.room.failSceneWith = _offline;
      room.sala.openTheSceneRehearsal();
      await _notKept(room);
      expect(room.state.scene.label, 'S2');

      room.harness.room.failSceneWith = null;
      await _recordAScene(room);
      await translateOpens(room);

      expect(room.harness.room.sceneLabels, ['S2', 'S2']);
    },
  );

  test('a scene take the room refused stays on the tablet, not kept on the '
      'scene screen', () async {
    final room = await atRest();
    await theScreenOpens(room);
    room.harness.room.failSceneWith = const Refused('BAD_REQUEST');

    await _recordAScene(room);
    await _notKept(room);

    expect([
      for (final row in await room.harness.takes.entries())
        if (row.kind == sceneTakeKind) row,
    ], hasLength(1));
  });

  test(
    'a full disk shows her save-failed words and holds the take for the retry',
    () async {
      late _DiskThatRefusesTheScene disk;
      final room = await atRest(
        SalaHarness(
          takesOverride: (room, home, recordings) =>
              disk = _DiskThatRefusesTheScene(
                room: room,
                home: () async => home,
                recordings: recordings,
              ),
        ),
      );
      await theScreenOpens(room);
      final recorded = await _recordAScene(room);
      await _notKept(room);
      final waiting = room.state.scene.keep! as NotKept;

      expect(waiting.why, SendFailure.failed);
      expect(waiting.take, room.harness.recorder.lastPath);

      disk.full = false;
      await _theRetry(room);
      await translateOpens(room);
      expect(room.harness.room.sceneTakesSent.single, recorded);
    },
  );

  test(
    'a scene take closed after the room forgot the session asks nothing of it',
    () async {
      final room = await atRest();
      final session = room.state.sessionId!;
      await theScreenOpens(room);
      await room.harness.takes.enqueue(
        room.harness.recorder.aFile('parte-esquecida'),
        sessionId: session,
        kind: 'ensaio',
        scope: 'parte-1',
      );
      room.harness.room.forgetTheSession(session);
      await theSceneMicrophoneOpens(room);
      room.harness.recorder.holdNextStop();
      room.sala.sceneTap();
      await settle();

      await room.harness.takes.flush();
      await waitFor(
        'a sala voltar à Escolha',
        () => room.state.stage == SalaStage.escolha,
      );
      room.harness.recorder.finishStop();
      await settle();

      expect(
        room.harness.room.askedOfTheForgotten,
        isNot(contains('keepSceneRehearsal')),
      );
    },
  );

  test(
    'a scene take kept after the room forgot the session stays on the tablet, '
    "and the passage's next session offers it and sends it there at its tap",
    () async {
      final room = await atRest();
      final perdida = room.state.sessionId!;
      await theScreenOpens(room);
      await room.harness.takes.enqueue(
        room.harness.recorder.aFile('parte-esquecida'),
        sessionId: perdida,
        kind: 'ensaio',
        scope: 'parte-1',
      );
      room.harness.room.forgetTheSession(perdida);
      await theSceneMicrophoneOpens(room);
      room.harness.recorder.holdNextStop();
      room.sala.sceneTap();
      await settle();
      await room.harness.takes.flush();
      await waitFor(
        'a sala voltar à Escolha',
        () => room.state.stage == SalaStage.escolha,
      );
      room.harness.recorder.finishStop();
      await settle();

      await _theNextSessionOfThePassage(room, perdida);

      expect(room.harness.room.scenesKept, isEmpty);
      await _theRetry(room);
      await waitFor(
        'o take chegar à sala',
        () => room.harness.room.scenesKept.isNotEmpty,
      );
      expect(room.harness.room.scenesKept, [room.state.sessionId]);
    },
  );

  test("a scene take waiting when its session goes is offered by the passage's "
      'next session and sent there at its tap', () async {
    final room = await atRest();
    final perdida = room.state.sessionId!;
    await theScreenOpens(room);
    room.harness.room.failSceneWith = _offline;
    await _recordAScene(room);
    await _notKept(room);
    room.harness.room
      ..failSceneWith = null
      ..forgetTheSession(perdida);
    await _theRetry(room);
    await waitFor(
      'a sala voltar à Escolha',
      () => room.state.stage == SalaStage.escolha,
    );

    await _theNextSessionOfThePassage(room, perdida);

    expect(room.harness.room.scenesKept, isEmpty);
    await _theRetry(room);
    await waitFor(
      'o take chegar à sala',
      () => room.harness.room.scenesKept.isNotEmpty,
    );
    expect(room.harness.room.scenesKept, [room.state.sessionId]);
  });

  test('a confirmed scene take counts the Outbox again', () async {
    final room = await atRest(SalaHarness(filaEmMemoria: true));
    await theScreenOpens(room);
    final queue = room.harness.takes as FakeTakeQueue;
    room.harness.recorder.rehearsalSpeaks = _aTake(7);
    await theSceneMicrophoneOpens(room);
    final countsBefore = queue.unsentAtEachTally.length;

    room.sala.sceneTap();
    await translateOpens(room);
    await settle();

    expect(queue.unsentAtEachTally.length, greaterThan(countsBefore));
  });

  test('a take whose file cannot be measured never sticks the screen on '
      '«guardando…»', () async {
    var unreadable = false;
    late _AnOutboxSlowToTakeIt queue;
    await IOOverrides.runZoned(
      () async {
        final room = await atRest(
          SalaHarness(
            takesOverride: (room, home, recordings) =>
                queue = _AnOutboxSlowToTakeIt(
                  room: room,
                  home: () async => home,
                  recordings: recordings,
                ),
          ),
        );
        await theScreenOpens(room);
        queue.takesToCopy = const Duration(milliseconds: 400);
        room.harness.recorder.rehearsalSpeaks = _aTake(7);
        await theSceneMicrophoneOpens(room);
        unreadable = true;

        room.sala.sceneTap();
        await waitFor(
          'o microfone da cena fechar',
          () => room.state.channel is! Microphone,
        );
        await _notKept(room);

        expect(
          room.state.scene.keep,
          isA<NotKept>(),
          reason: 'o take sem medida voltava para a equipe tentar de novo',
        );
      },
      createFile: (path) => unreadable && path.contains('/cena_')
          ? _UnmeasurableTake(path)
          : _realFile(path),
    );
  });
}

final class _Plain extends IOOverrides {}

File _realFile(String path) =>
    IOOverrides.runWithIOOverrides(() => File(path), _Plain());

class _UnmeasurableTake implements File {
  final File _real;

  _UnmeasurableTake(String path) : _real = _realFile(path);

  @override
  String get path => _real.path;

  @override
  bool existsSync() => true;

  @override
  Future<bool> exists() async => true;

  @override
  int lengthSync() => throw FileSystemException('o take sumiu', _real.path);

  @override
  void writeAsBytesSync(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) => _real.writeAsBytesSync(bytes, mode: mode, flush: flush);

  @override
  Future<int> length() async =>
      throw FileSystemException('o take sumiu', _real.path);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AnOutboxSlowToTakeIt extends TakeUploadQueue {
  _AnOutboxSlowToTakeIt({
    required super.room,
    super.home,
    required super.recordings,
  });

  Duration takesToCopy = Duration.zero;

  @override
  Future<PendingTake> enqueue(
    File audio, {
    required String? sessionId,
    String? passage,
    required String kind,
    required String scope,
    int? passNumber,
    int? chunkIndex,
    String? scene,
  }) async {
    await Future<void>.delayed(takesToCopy);
    return super.enqueue(
      audio,
      sessionId: sessionId,
      passage: passage,
      kind: kind,
      scope: scope,
      passNumber: passNumber,
      chunkIndex: chunkIndex,
      scene: scene,
    );
  }
}

class _DiskThatRefusesTheScene extends TakeUploadQueue {
  _DiskThatRefusesTheScene({
    required super.room,
    super.home,
    required super.recordings,
  });

  bool full = true;

  @override
  Future<PendingTake> enqueue(
    File audio, {
    required String? sessionId,
    String? passage,
    required String kind,
    required String scope,
    int? passNumber,
    int? chunkIndex,
    String? scene,
  }) async {
    if (kind == 'cena' && full) {
      throw const FileSystemException('disco cheio');
    }
    return super.enqueue(
      audio,
      sessionId: sessionId,
      passage: passage,
      kind: kind,
      scope: scope,
      passNumber: passNumber,
      chunkIndex: chunkIndex,
      scene: scene,
    );
  }
}

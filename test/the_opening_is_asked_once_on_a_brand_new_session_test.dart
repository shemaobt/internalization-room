import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';

const _rememberedSession = 'sessao-lembrada';

void _aCanvasRow(SalaHarness harness, {required bool opened}) {
  harness.emAberto.rows['Ruth/P01/pt'] = const ResumePoint(
    sessionId: _rememberedSession,
    stage: SalaStage.conversa,
  );
  if (opened) harness.room.openedSessions.add(_rememberedSession);
}

int _opensAsked(SalaHarness harness) =>
    harness.room.calls.where((call) => call == 'openSession').length;

void main() {
  test('a passage opened for the first time from the Choice speaks its opening '
      'with no tap', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await enterThePassage(notifier, read, 'P01');
    await waitFor(
      'the opening to be said',
      () => harness.voice.played.contains(turnoUrl),
    );

    expect(harness.room.sessionsSpokenTo, [harness.room.sessionIds.single]);
    expect(harness.room.turnIdsAsked, hasLength(1));
  });

  group('a passage the team talked in, left and entered again', () {
    late SalaHarness harness;
    late SalaSessionNotifier notifier;
    late SalaSessionState Function() read;
    late String session;
    late int playedBeforeTheReturn;

    setUp(() async {
      harness = SalaHarness();
      final container = harness.container();
      addTearDown(container.dispose);
      notifier = container.read(salaSessionProvider.notifier);
      read = () => container.read(salaSessionProvider);
      await enterThePassage(notifier, read, 'P01');
      await waitFor(
        'the opening to be said',
        () =>
            harness.voice.played.contains(turnoUrl) &&
            read().voice == VoiceState.invite,
      );
      session = read().sessionId!;
      await waitFor(
        'the passage to keep its place',
        () => harness.emAberto.rows.containsKey('Ruth/P01/pt'),
      );

      notifier.leaveThePassage();
      await enterThePassage(notifier, read, 'P01');
      playedBeforeTheReturn = harness.voice.played.length;
      await waitFor(
        'the passage to be back',
        () =>
            read().sessionId == session &&
            read().stage == SalaStage.conversa &&
            read().voice == VoiceState.invite,
      );
      await settle();
    });

    test('coming back plays nothing', () {
      expect(_opensAsked(harness), 1);
      expect(harness.voice.played.skip(playedBeforeTheReturn), isEmpty);
      expect(read().voice, VoiceState.invite);
      expect(read().sessionId, session);
    });

    test(
      '«Ouvir de novo» after coming back plays the clip held, asking the room '
      'for nothing',
      () async {
        expect(read().canHearAgain, isTrue);
        final asked = harness.room.turnIdsAsked.length;
        final played = harness.voice.played.length;

        await notifier.hearAgain();
        await waitFor(
          'the clip to be played again',
          () => harness.voice.played.length == played + 1,
        );

        expect(harness.voice.played.last, turnoUrl);
        await waitFor(
          'the room to rest again',
          () => read().voice == VoiceState.invite,
        );
        await notifier.hearAgain();
        await waitFor(
          'the clip to be played from memory again',
          () => harness.voice.played.length == played + 2,
        );

        expect(harness.voice.played.last, turnoUrl);
        expect(harness.room.sessionsSaidAgain, isEmpty);
        expect(harness.room.turnIdsAsked, hasLength(asked));
      },
    );
  });

  test(
    'a passage reopened from the Choice before any conversation asks its opening',
    () async {
      final harness = SalaHarness();
      _aCanvasRow(harness, opened: false);
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      await enterThePassage(notifier, read, 'P01');
      await waitFor(
        'the opening to be said',
        () => harness.voice.played.contains(turnoUrl),
      );

      expect(harness.room.sessionsSpokenTo, [_rememberedSession]);
      expect(harness.room.sessionIds, isEmpty);
    },
  );

  test(
    'a passage the team already talked in on another tablet asks no opening',
    () async {
      final harness = SalaHarness()..room.createdOpened = true;
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      await enterThePassage(notifier, read, 'P01');
      final playedBeforeTheEntry = harness.voice.played.length;
      await waitFor(
        'the passage to land',
        () => read().sessionId != null && read().voice == VoiceState.invite,
      );
      await settle();

      expect(_opensAsked(harness), 0);
      expect(harness.voice.played.skip(playedBeforeTheEntry), isEmpty);
      expect(read().voice, VoiceState.invite);
      expect(read().canHearAgain, isTrue);
    },
  );

  test('a resumed passage gets its beads back from the session read without a '
      'turn, and a read that says a person is needed raises no sign', () async {
    final harness = SalaHarness();
    _aCanvasRow(harness, opened: true);
    harness.room
      ..nextCoverage = coverage(engaged: 3)
      ..serverStatus = 'needs_person'
      ..serverHalt = HaltKind.blocking;
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await enterThePassage(notifier, read, 'P01');
    await waitFor('the beads to be back', () => read().coverage.engaged == 3);
    await settle();

    expect(read().needsPerson, isFalse);
    expect(_opensAsked(harness), 0);
  });

  group('a resumed passage whose ask to the room fell with the network', () {
    Future<(SalaHarness, SalaSessionNotifier, SalaSessionState Function())>
    theReadFalls({required bool opened}) async {
      final harness = SalaHarness();
      _aCanvasRow(harness, opened: opened);
      harness.room.failCreateOnceWith = const NetworkFailed('sem rede');
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);
      await enterThePassage(notifier, read, 'P01');
      await waitFor('the room to be asked', () => _roomAsks(harness) > 0);
      await settle();
      return (harness, notifier, read);
    }

    test('goes back to the Choice calmly and keeps its session', () async {
      final (harness, _, read) = await theReadFalls(opened: true);

      expect(read().stage, SalaStage.escolha);
      expect(read().needsPerson, isFalse);
      expect(
        harness.emAberto.rows['Ruth/P01/pt']?.sessionId,
        _rememberedSession,
      );
    });

    test('opened again, enters and lands quiet', () async {
      final (harness, notifier, read) = await theReadFalls(opened: true);

      await enterThePassage(notifier, read, 'P01');
      await waitFor('the passage to land at rest', () => read().canHearAgain);
      await settle();

      expect(read().sessionId, _rememberedSession);
      expect(read().voice, VoiceState.invite);
      expect(_opensAsked(harness), 0);
    });

    test('opened again, asks its opening if the session was never '
        'opened', () async {
      final (harness, notifier, read) = await theReadFalls(opened: false);

      await enterThePassage(notifier, read, 'P01');
      await waitFor(
        'the opening to be said',
        () => harness.voice.played.contains(turnoUrl),
      );

      expect(harness.room.sessionsSpokenTo, [_rememberedSession]);
    });
  });

  test('a passage another tablet opened, which the room has halted, lands '
      'with no sign', () async {
    final harness = SalaHarness()
      ..room.createdOpened = true
      ..room.serverStatus = 'needs_person'
      ..room.serverHalt = HaltKind.blocking;
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await enterThePassage(notifier, read, 'P01');
    await waitFor(
      'the passage to land',
      () => read().sessionId != null && read().voice == VoiceState.invite,
    );
    await settle();

    expect(read().needsPerson, isFalse);
  });

  test('a line the room said again is kept as the last line, so the next '
      '«Ouvir de novo» says it again without asking the room', () async {
    final harness = SalaHarness();
    _aCanvasRow(harness, opened: true);
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);
    await enterThePassage(notifier, read, 'P01');
    await waitFor('the passage to land at rest', () => read().canHearAgain);

    await notifier.hearAgain();
    await waitFor(
      'the room to rest again',
      () => read().voice == VoiceState.invite && read().canHearAgain,
    );
    await notifier.hearAgain();
    await settle();

    expect(
      harness.room.sessionsSaidAgain,
      [_rememberedSession],
      reason:
          'a linha dita de novo não era guardada, e o toque seguinte '
          'perguntava à sala outra vez',
    );
    expect(harness.voice.played.where((url) => url == deNovoUrl), hasLength(2));
  });

  test(
    'a stored Rehearsal whose ask to the room fell with the network goes back to '
    'the Choice, and opened again lands on its conversation',
    () async {
      final home = Directory.systemTemp.createTempSync('sala-ensaio-lembrado');
      addTearDown(() => home.deleteSync(recursive: true));
      final part = File('${home.path}/p1.m4a')..writeAsBytesSync([1, 2, 3]);
      final harness = SalaHarness();
      harness.emAberto.rows['Ruth/P01/pt'] = ResumePoint(
        sessionId: _rememberedSession,
        stage: SalaStage.ensaio,
        takes: [KeptTake(scopeId: KeptScope.parte(1), path: part.path)],
      );
      harness.room.failCreateOnceWith = const NetworkFailed('sem rede');
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);
      await enterThePassage(notifier, read, 'P01');
      await waitFor('the room to be asked', () => _roomAsks(harness) == 1);
      await settle();
      expect(read().stage, SalaStage.escolha);

      await enterThePassage(notifier, read, 'P01');
      await waitFor(
        'the entry to ask the room again',
        () => _roomAsks(harness) == 2,
      );
      await settle();
      expect(read().stage, SalaStage.conversa);
      expect(read().sessionId, _rememberedSession);
    },
  );
}

int _roomAsks(SalaHarness harness) =>
    harness.room.calls.where((call) => call == 'createSession').length;

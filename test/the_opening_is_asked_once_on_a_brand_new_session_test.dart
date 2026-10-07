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
  harness.emAberto.rows['Ruth/P01'] = const ResumePoint(
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
        () => harness.emAberto.rows.containsKey('Ruth/P01'),
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
      '«Ouvir de novo» after coming back plays the room\'s last line said again',
      () async {
        expect(read().canHearAgain, isTrue);

        await notifier.hearAgain();
        await waitFor(
          'the last line to be said again',
          () => harness.voice.played.contains(deNovoUrl),
        );

        expect(harness.room.sessionsSaidAgain, [session]);
        expect(harness.room.turnIdsAsked.last, isNull);

        await waitFor(
          'the room to rest again',
          () => read().voice == VoiceState.invite,
        );
        await notifier.hearAgain();
        await waitFor(
          'the line to be said again from memory',
          () =>
              harness.voice.played.where((url) => url == deNovoUrl).length == 2,
        );

        expect(harness.room.sessionsSaidAgain, [session]);
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

  test(
    'a resumed passage gets its beads and its halt back from the session read '
    'without a turn',
    () async {
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
      await waitFor('the halt to be back', () => read().needsPerson);

      expect(read().coverage.engaged, 3);
      expect(_opensAsked(harness), 0);
    },
  );

  group('a resumed passage entered while out of reach', () {
    Future<(SalaHarness, SalaSessionState Function(), int)> enterOutOfReach({
      required bool opened,
    }) async {
      final harness = SalaHarness();
      _aCanvasRow(harness, opened: opened);
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);
      await notifier.abrirEscolha();
      await waitFor('the Wheel to load', () => read().naRoda != null);
      notifier.apontarPassagem(
        read().naRoda!.indexWhere((entry) => entry.pericope == 'P01'),
      );
      await waitFor(
        'the Wheel to offer P01',
        () =>
            read().oferecida?.pericope == 'P01' &&
            read().voice == VoiceState.invite,
      );
      harness.network.reachable = false;
      harness.room.reachable = false;
      notifier.entrarNaOferecida();
      await waitFor('the room to be out of reach', () => read().offline);
      final played = harness.voice.played.length;

      harness.network.reachable = true;
      harness.room.reachable = true;
      notifier.retryNow();
      return (harness, read, played);
    }

    test('stays silent when the room comes back', () async {
      final (harness, read, played) = await enterOutOfReach(opened: true);
      await waitFor(
        'the session to be read',
        () => stateReads(harness) > 0 && read().voice == VoiceState.invite,
      );
      await settle();

      expect(_opensAsked(harness), 0);
      expect(harness.voice.played.skip(played), isEmpty);
    });

    test('asks its opening when the room comes back if the session was never '
        'opened', () async {
      final (harness, _, _) = await enterOutOfReach(opened: false);
      await waitFor(
        'the opening to be said',
        () => harness.voice.played.contains(turnoUrl),
      );

      expect(harness.room.sessionsSpokenTo, [_rememberedSession]);
    });
  });

  group(
    'a resumed passage whose last line is an Opening told in two movements',
    () {
      late SalaHarness harness;
      late SalaSessionNotifier notifier;
      late SalaSessionState Function() read;
      late int playedBeforeTheReplay;

      setUp(() async {
        harness = SalaHarness()..room.opensInTwoMovements = true;
        _aCanvasRow(harness, opened: true);
        final container = harness.container();
        addTearDown(container.dispose);
        notifier = container.read(salaSessionProvider.notifier);
        read = () => container.read(salaSessionProvider);
        await enterThePassage(notifier, read, 'P01');
        await waitFor('the passage to land at rest', () => read().canHearAgain);
        playedBeforeTheReplay = harness.voice.played.length;
        await notifier.hearAgain();
        await waitFor(
          'the room to rest again',
          () => read().voice == VoiceState.invite && read().canHearAgain,
        );
      });

      test('«Ouvir de novo» says its scene again', () {
        expect(harness.voice.played.skip(playedBeforeTheReplay), [sceneUrl]);
      });

      test('the long press says both movements', () async {
        final playedBeforeThePress = harness.voice.played.length;

        await notifier.hearTheWholeOpening();
        await waitFor(
          'both movements to be said',
          () => harness.voice.played.length == playedBeforeThePress + 2,
        );

        expect(harness.voice.played.skip(playedBeforeThePress), [
          panoramaUrl,
          sceneUrl,
        ]);
      });
    },
  );

  group('a resumed passage whose session read fell with the network', () {
    Future<(SalaHarness, SalaSessionState Function())> theRoomComesBack({
      required bool opened,
    }) async {
      final harness = SalaHarness();
      _aCanvasRow(harness, opened: opened);
      harness.room.failStateOnceWith = const NetworkFailed('sem rede');
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);
      await enterThePassage(notifier, read, 'P01');
      await waitFor('the room to be out of reach', () => read().offline);

      notifier.retryNow();
      return (harness, read);
    }

    test('enters again when the room comes back and lands quiet', () async {
      final (harness, read) = await theRoomComesBack(opened: true);
      await waitFor('the passage to land at rest', () => read().canHearAgain);
      await settle();

      expect(read().sessionId, _rememberedSession);
      expect(read().voice, VoiceState.invite);
      expect(_opensAsked(harness), 0);
    });

    test('enters again when the room comes back and asks its opening if the '
        'session was never opened', () async {
      final (harness, _) = await theRoomComesBack(opened: false);
      await waitFor(
        'the opening to be said',
        () => harness.voice.played.contains(turnoUrl),
      );

      expect(harness.room.sessionsSpokenTo, [_rememberedSession]);
    });
  });

  test('a passage another tablet opened, which the room has halted, shows the '
      'person sign at once', () async {
    final harness = SalaHarness()
      ..room.createdOpened = true
      ..room.serverStatus = 'needs_person'
      ..room.serverHalt = HaltKind.blocking;
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);

    await enterThePassage(notifier, read, 'P01');

    await waitFor('the person sign', () => read().needsPerson);
  });

  test(
    'a fail-safe the room said again is not kept as the last line, and the next '
    '«Ouvir de novo» asks the room again',
    () async {
      final harness = SalaHarness()..room.turnsAreCanned = true;
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
      await waitFor(
        'the room to be asked again',
        () => harness.room.sessionsSaidAgain.length == 2,
      );

      expect(read().lastSpoken, isNull);
    },
  );

  test(
    'a stored Rehearsal whose session read fell with the network enters again '
    'when the room comes back and lands on the Rehearsal',
    () async {
      final home = Directory.systemTemp.createTempSync('sala-ensaio-lembrado');
      addTearDown(() => home.deleteSync(recursive: true));
      final part = File('${home.path}/p1.m4a')..writeAsBytesSync([1, 2, 3]);
      final harness = SalaHarness();
      harness.emAberto.rows['Ruth/P01'] = ResumePoint(
        sessionId: _rememberedSession,
        stage: SalaStage.ensaio,
        takes: [KeptTake(scopeId: KeptScope.parte(1), path: part.path)],
      );
      harness.room.failStateOnceWith = const NetworkFailed('sem rede');
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);
      await enterThePassage(notifier, read, 'P01');
      await waitFor('the room to be out of reach', () => read().offline);

      notifier.retryNow();

      await waitFor(
        'the entry to read the session again',
        () => stateReads(harness) == 3,
      );
      await settle();
      expect(
        stateReads(harness),
        3,
        reason:
            'the read that fell, the probe that finds the room back, and '
            'the entry that reads the session again',
      );
      expect(read().stage, SalaStage.ensaio);
      expect(read().sessionId, _rememberedSession);
    },
  );
}

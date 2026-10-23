import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'session_notifier_test.dart' show inConversa;

const _theReply = '/api/internalization-room/voice/a-resposta';
const _theNextReply = '/api/internalization-room/voice/a-proxima';

class _Room {
  final SalaHarness harness;
  final ProviderContainer container;

  _Room(this.harness, this.container);

  SalaSessionNotifier get sala => container.read(salaSessionProvider.notifier);

  SalaSessionState get state => container.read(salaSessionProvider);

  int timesPlayed(String url) =>
      harness.voice.played.where((played) => played == url).length;

  int timesSaid(String fixedLine) =>
      harness.voice.fixedLines.where((said) => said.$1 == fixedLine).length;
}

Future<_Room> _onTheCanvas(SalaHarness harness) async {
  final container = await inConversa(harness);
  addTearDown(container.dispose);
  final room = _Room(harness, container);
  await _theRoomRests(room);
  return room;
}

Future<void> _theTeamSpeaks(_Room room) async {
  room.sala.conversaTap();
  await waitFor(
    'o microfone abrir na conversa',
    () => room.state.voice == VoiceState.listening,
  );
  room.sala.conversaTap();
}

Future<void> _theRoomRests(_Room room) async {
  await waitFor(
    'a sala descansar',
    () =>
        room.state.voice == VoiceState.invite &&
        !room.state.awaitingTheGuide &&
        room.state.machine.inFlight == null,
  );
  await settle();
}

Future<void> _theSignRises(_Room room) =>
    waitFor('o sinal da pessoa', () => room.state.needsPerson);

Future<void> _theSignIsCleared(_Room room) async {
  room.sala.teamTapped();
  await waitFor('o sinal sair', () => !room.state.needsPerson);
  await _theRoomRests(room);
}

List<String> _theLog() {
  final logged = <String>[];
  final print = debugPrint;
  debugPrint = (message, {wrapWidth}) => logged.add(message ?? '');
  addTearDown(() => debugPrint = print);
  return logged;
}

void main() {
  test('a reply whose sound fails to load once plays about 1.5 s later and '
      'nothing else shows', () {
    fakeAsync((clock) {
      final harness = SalaHarness(soundReload: null);
      ProviderContainer? container;
      unawaited(inConversa(harness).then((opened) => container = opened));
      clock.elapse(const Duration(seconds: 1));
      addTearDown(() => container?.dispose());
      final room = _Room(harness, container!);
      harness.room.replyUrl = _theReply;
      harness.voice.failsToLoad[_theReply] = 1;

      room.sala.conversaTap();
      clock.elapse(const Duration(milliseconds: 100));
      room.sala.conversaTap();
      for (var waited = 0; room.timesPlayed(_theReply) == 0; waited++) {
        expect(waited, lessThan(500), reason: 'a resposta nunca foi tentada');
        clock.elapse(const Duration(milliseconds: 10));
      }

      clock.elapse(const Duration(milliseconds: 1400));
      expect(room.timesPlayed(_theReply), 1, reason: 'cedo demais');
      expect(room.state.needsPerson, isFalse);

      clock.elapse(const Duration(milliseconds: 200));
      expect(room.timesPlayed(_theReply), 2);
      clock.elapse(const Duration(seconds: 1));
      expect(room.state.needsPerson, isFalse);
      expect(room.state.voice, VoiceState.invite);
    });
  });

  test('a reply whose sound fails to load twice raises the person sign with '
      '«Ouvir de novo» lit for that reply', () async {
    final harness = SalaHarness();
    final room = await _onTheCanvas(harness);
    harness.room.replyUrl = _theReply;
    harness.voice.refuses.add(_theReply);

    await _theTeamSpeaks(room);
    await _theSignRises(room);
    expect(room.timesPlayed(_theReply), 2);

    await _theSignIsCleared(room);
    expect(room.state.canHearAgain, isTrue);
  });

  test('once the person sign is cleared, «Ouvir de novo» plays the reply whose '
      'sound failed, once its sound loads', () async {
    final harness = SalaHarness();
    final room = await _onTheCanvas(harness);
    harness.room.replyUrl = _theReply;
    harness.voice.refuses.add(_theReply);
    await _theTeamSpeaks(room);
    await _theSignRises(room);
    await _theSignIsCleared(room);
    harness.voice.refuses.clear();

    await room.sala.hearAgain();
    await _theRoomRests(room);

    expect(room.timesPlayed(_theReply), 3);
    expect(room.state.needsPerson, isFalse);
  });

  test('a reply whose sound never loads keeps the turn, and the team is never '
      'asked to speak again', () async {
    final harness = SalaHarness();
    final room = await _onTheCanvas(harness);
    harness.room.replyUrl = _theReply;
    harness.voice.roomFailsWith = const NetworkFailed('sem rede');

    await _theTeamSpeaks(room);
    await _theSignRises(room);
    await _theSignIsCleared(room);
    await settle(const Duration(milliseconds: 300));

    expect(harness.room.turnsSent, 1);
    expect(harness.room.turnIdsLookedAt, isEmpty);
    expect(room.state.canHearAgain, isTrue);
  });

  test(
    '«Ouvir de novo» after a fail-safe line plays that fail-safe line',
    () async {
      final harness = SalaHarness();
      final room = await _onTheCanvas(harness);
      harness.room
        ..turnsAreCanned = true
        ..fixedLine = 'A2';
      await _theTeamSpeaks(room);
      await _theRoomRests(room);
      expect(room.timesSaid('A2'), 1);

      await room.sala.hearAgain();
      await _theRoomRests(room);

      expect(room.timesSaid('A2'), 2);
    },
  );

  test(
    '«Ouvir de novo» after a reload, when the reply\'s sound had failed, asks '
    'the room to say the stored reply again',
    () async {
      final harness = SalaHarness();
      final container = harness.container();
      addTearDown(container.dispose);
      final first = _Room(harness, container);
      await enterThePassage(first.sala, () => first.state, 'P01');
      await _theRoomRests(first);
      harness.room.replyUrl = _theReply;
      harness.voice.refuses.add(_theReply);
      await _theTeamSpeaks(first);
      await _theSignRises(first);
      final session = first.state.sessionId!;

      final (again, reopened) = await relaunch(harness, container);
      final room = _Room(again, reopened);
      await room.sala.openTheRoom();
      await waitFor('a sessão voltar', () => room.state.sessionId == session);
      await _theRoomRests(room);
      expect(room.state.canHearAgain, isTrue);

      await room.sala.hearAgain();
      await waitFor(
        'a sala dizer de novo',
        () => again.voice.played.contains(deNovoUrl),
      );

      expect(again.room.sessionsSaidAgain, [session]);
    },
  );

  test('a clip download that fails on the network never takes the room '
      'offline', () async {
    final logged = _theLog();
    final harness = SalaHarness();
    final room = await _onTheCanvas(harness);
    harness.room.replyUrl = _theReply;
    harness.voice.roomFailsWith = const NetworkFailed('sem rede');

    await _theTeamSpeaks(room);
    await _theSignRises(room);
    await settle(const Duration(milliseconds: 300));

    expect(logged, isNot(contains(contains('NetworkFailedAt'))));
    expect(logged, isNot(contains(contains('TurnGivenUp'))));
  });

  test('one failed load of a reply and one failed load of the next never raise '
      'the person sign', () async {
    final harness = SalaHarness();
    final room = await _onTheCanvas(harness);
    harness.room.replyUrl = _theReply;
    harness.voice.failsToLoad[_theReply] = 1;
    await _theTeamSpeaks(room);
    await _theRoomRests(room);
    harness.room.replyUrl = _theNextReply;
    harness.voice.failsToLoad[_theNextReply] = 1;

    await _theTeamSpeaks(room);
    await _theRoomRests(room);

    expect(room.state.needsPerson, isFalse);
    expect(room.timesPlayed(_theReply), 2);
    expect(room.timesPlayed(_theNextReply), 2);
  });

  test(
    'a replay whose sound fails to load is loaded once more, then raises the '
    'person sign with «Ouvir de novo» lit',
    () async {
      final harness = SalaHarness();
      final room = await _onTheCanvas(harness);
      harness.room.replyUrl = _theReply;
      await _theTeamSpeaks(room);
      await _theRoomRests(room);
      expect(room.timesPlayed(_theReply), 1);
      harness.voice.refuses.add(_theReply);

      unawaited(room.sala.hearAgain());
      await _theSignRises(room);
      expect(room.timesPlayed(_theReply), 3);

      await _theSignIsCleared(room);
      expect(room.state.canHearAgain, isTrue);
    },
  );
}

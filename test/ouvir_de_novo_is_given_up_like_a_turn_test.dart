import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';

const _theNetworkDrops = NetworkFailed('a rede caiu');
const _theCeiling = Duration(milliseconds: 400);
const _lookAgain = Duration(milliseconds: 50);

class _Tablet {
  final SalaHarness harness;
  final ProviderContainer container;
  _Tablet(this.harness, this.container);

  SalaSessionNotifier get notifier =>
      container.read(salaSessionProvider.notifier);

  SalaSessionState get state => container.read(salaSessionProvider);

  FakeRoom get room => harness.room;

  String? get saidAgainUnder => room.turnIdsAsked.last;
}

Future<_Tablet> _aTablet() async {
  final home = Directory.systemTemp.createTempSync('sala-de-novo');
  addTearDown(() => home.deleteSync(recursive: true));
  final harness = SalaHarness(
    currentSession: LedgerThatReadsLate(home: () async => home),
  );
  final container = harness.container();
  addTearDown(container.dispose);
  return _Tablet(harness, container);
}

Future<_Tablet> _relaunched(_Tablet first) async {
  final session = first.state.sessionId!;
  final (harness, container) = await relaunch(
    first.harness,
    first.container,
    busyCeiling: _theCeiling,
    lookAgain: _lookAgain,
  );
  final again = _Tablet(harness, container);
  await again.notifier.openTheRoom();
  await waitFor(
    'the team to land on the session',
    () =>
        again.state.sessionId == session &&
        !again.state.awaitingTheGuide &&
        again.state.voice == VoiceState.invite,
  );
  await settle();
  return again;
}

/// A session with a reply heard, relaunched, landed silent.
Future<_Tablet> _relaunchedAfterAReply() async {
  final first = await _aTablet();
  await enterThePassage(first.notifier, () => first.state, 'P01');
  await waitFor(
    'the opening to be said',
    () =>
        first.harness.voice.played.contains(turnoUrl) &&
        first.state.voice == VoiceState.invite,
  );
  await settle();
  first.notifier.conversaTap();
  await settle();
  first.notifier.conversaTap();
  await waitFor(
    'the turn to be answered',
    () =>
        first.room.turnIdsSent.isNotEmpty &&
        first.state.voice == VoiceState.invite &&
        !first.state.awaitingTheGuide,
  );
  await settle();
  return _relaunched(first);
}

void main() {
  test(
    '«Ouvir de novo» the room takes longer than the watchdog to answer is looked at once and calls nobody',
    () async {
      final again = await _relaunchedAfterAReply();
      again.room.holdTheLineSaidAgain();
      addTearDown(again.room.finishTheLineSaidAgain);

      unawaited(again.notifier.hearAgain());
      await Future<void>.delayed(_theCeiling * 2);
      await settle();

      expect(again.saidAgainUnder, isNotNull);
      expect(again.room.turnIdsLookedAt, [again.saidAgainUnder]);
      expect(again.state.needsPerson, isFalse);
      expect(again.state.voice, VoiceState.invite);
      expect(again.state.awaitingTheGuide, isFalse);
      expect(again.state.canHearAgain, isTrue);

      final first = again.saidAgainUnder;
      unawaited(again.notifier.hearAgain());
      await settle();

      expect(again.saidAgainUnder, isNot(first));
    },
  );

  test('«Ouvir de novo» whose answer the network loses is looked at', () async {
    final again = await _relaunchedAfterAReply();
    again.room.failTheLineSaidAgainWith = _theNetworkDrops;

    unawaited(again.notifier.hearAgain());
    await Future<void>.delayed(_lookAgain * 4);
    await settle();

    expect(again.saidAgainUnder, isNotNull);
    expect(again.room.turnIdsLookedAt, [again.saidAgainUnder]);
    expect(again.state.needsPerson, isFalse);
    expect(again.state.voice, VoiceState.invite);
    expect(again.state.awaitingTheGuide, isFalse);
    expect(again.state.canHearAgain, isTrue);
  });

  test(
    '«Ouvir de novo» the room refuses is decided as a refusal of a request, not as a turn',
    () async {
      final again = await _relaunchedAfterAReply();
      again.room.failTheLineSaidAgainWith = const Refused('BAD_REQUEST');
      final asked = again.room.turnIdsAsked.length;

      unawaited(again.notifier.hearAgain());
      await Future<void>.delayed(_lookAgain * 4);
      await settle();

      expect(again.room.turnIdsAsked, hasLength(asked + 1));
      expect(again.state.needsPerson, isFalse);
      expect(again.room.turnIdsLookedAt, isEmpty);
    },
  );

  test(
    '«Ouvir de novo» on a relaunch in the middle of the Opening plays the Opening once it lands',
    () async {
      final first = await _aTablet();
      first.room.holdNextTurn();
      addTearDown(first.room.finishHeldTurn);
      await enterThePassage(first.notifier, () => first.state, 'P01');
      await waitFor(
        'the Opening to be asked',
        () => first.room.turnIdsAsked.length == 1,
      );
      await settle();
      final again = await _relaunched(first);
      again.room
        ..failTurnsWith = _theNetworkDrops
        ..turnsLandBeforeTheyFail = true
        ..looksStillAnswering = 1;

      unawaited(again.notifier.hearAgain());
      await settle();
      again.room.finishHeldTurn();
      await waitFor(
        'the line said again to be looked at twice',
        () => again.room.turnIdsLookedAt.length == 2,
      );
      await Future<void>.delayed(_lookAgain * 4);
      await settle();

      expect(again.room.turnIdsLookedAt, [
        again.saidAgainUnder,
        again.saidAgainUnder,
      ]);
      expect(
        again.harness.voice.played.where((url) => url == turnoUrl),
        hasLength(1),
      );
      expect(again.state.needsPerson, isFalse);
    },
  );
}

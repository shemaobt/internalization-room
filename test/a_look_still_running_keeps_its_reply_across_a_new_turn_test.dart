import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show settle;
import 'session_notifier_test.dart' show inConversa;

const _t0Url = '/api/internalization-room/voice/t0';
const _t1Url = '/api/internalization-room/voice/t1';

typedef _Room = ({
  SalaSessionNotifier sala,
  SalaSessionState Function() state,
  FakeRoom room,
  FakeVoice voice,
});

Future<void> _theTeamSpeaks(_Room it, String replyUrl) async {
  it.room.replyUrl = replyUrl;
  it.sala.conversaTap();
  await settle();
  it.sala.conversaTap();
  await waitFor(
    'the team to hear the reply to its turn',
    () =>
        it.voice.played.contains(replyUrl) &&
        it.state().voice == VoiceState.invite &&
        !it.state().awaitingTheGuide,
  );
  await settle();
}

Future<_Room> _theTeamHeard(String replyUrl) async {
  final harness = SalaHarness();
  final container = await inConversa(harness);
  addTearDown(container.dispose);
  final _Room it = (
    sala: container.read(salaSessionProvider.notifier),
    state: () => container.read(salaSessionProvider),
    room: harness.room,
    voice: harness.voice,
  );
  await _theTeamSpeaks(it, replyUrl);
  return it;
}

void main() {
  test(
    'a turn the team spoke while «ouvir de novo» checked the tablet plays its reply when its look lands, and «ouvir de novo» asks the room nothing',
    () async {
      final it = await _theTeamHeard(_t0Url);
      final (:sala, :state, :room, :voice) = it;

      voice.missing.add(_t0Url);
      room
        ..replyUrl = _t1Url
        ..failTurnsWith = const NetworkFailed('a rede caiu')
        ..turnsLandBeforeTheyFail = true;
      addTearDown(room.finishTheLooks);
      room.holdTheLooks();
      addTearDown(room.finishTheLineSaidAgain);
      room.holdTheLineSaidAgain();
      addTearDown(voice.finishHeldLook);
      voice.holdNextLook();
      final askedBefore = room.turnIdsAsked.length;

      unawaited(sala.hearAgain());
      await waitFor(
        '«ouvir de novo» to check the tablet for the line',
        () => voice.aLookIsPending,
      );
      sala.conversaTap();
      await settle();
      sala.conversaTap();
      await waitFor(
        'the lost turn to be looked at',
        () =>
            room.turnIdsSent.length == 2 &&
            room.turnIdsLookedAt.contains(room.turnIdsSent.last),
      );
      voice.finishHeldLook();
      await settle();
      room.finishTheLooks();
      await waitFor('the look to land', () => state().machine.look == null);
      await settle();

      expect(
        voice.played.where((url) => url == _t1Url),
        hasLength(1),
        reason: 'the reply the look found plays once',
      );
      expect(
        room.turnIdsAsked,
        hasLength(askedBefore),
        reason: '«ouvir de novo» sends nothing over the team’s newer turn',
      );
    },
  );

  test(
    'a turn the team spoke and heard whole while «ouvir de novo» checked the tablet is not followed by the older line',
    () async {
      final it = await _theTeamHeard(_t0Url);
      final (:sala, :room, :voice, state: _) = it;
      addTearDown(voice.finishHeldLook);
      voice.holdNextLook();
      final askedBefore = room.turnIdsAsked.length;

      unawaited(sala.hearAgain());
      await waitFor(
        '«ouvir de novo» to check the tablet for the line',
        () => voice.aLookIsPending,
      );
      await _theTeamSpeaks(it, _t1Url);
      voice.finishHeldLook();
      await waitFor(
        'the tablet to answer the check',
        () => !voice.aLookIsPending,
      );
      await settle();

      expect(
        voice.played.where((url) => url == _t0Url),
        hasLength(1),
        reason: 'the older line is not replayed over the team’s newer turn',
      );
      expect(
        room.turnIdsAsked,
        hasLength(askedBefore),
        reason: '«ouvir de novo» asks the room nothing',
      );
    },
  );
}

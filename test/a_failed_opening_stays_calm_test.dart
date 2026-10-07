import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';

typedef _Room = ({
  SalaHarness harness,
  SalaSessionNotifier notifier,
  SalaSessionState Function() read,
  List<VoiceState> voices,
});

Future<_Room> _enterP01(SalaHarness harness) async {
  final container = harness.container();
  addTearDown(container.dispose);
  final notifier = container.read(salaSessionProvider.notifier);
  SalaSessionState read() => container.read(salaSessionProvider);
  final voices = <VoiceState>[];
  container.listen<SalaSessionState>(
    salaSessionProvider,
    (_, next) => voices.add(next.voice),
    fireImmediately: true,
  );
  await enterThePassage(notifier, read, 'P01');
  return (harness: harness, notifier: notifier, read: read, voices: voices);
}

Future<void> _theOpeningIsAsked(_Room room) => waitFor(
  'the opening to be asked',
  () => room.harness.room.turnIdsAsked.isNotEmpty,
);

Future<void> _theRoomRests(_Room room) async {
  await waitFor(
    'the room to rest at the invite',
    () =>
        room.read().voice == VoiceState.invite && !room.read().awaitingTheGuide,
  );
  await settle();
}

void main() {
  test('an opening the network lost that landed on the server plays when it is '
      'looked at', () async {
    final room = await _enterP01(
      SalaHarness()
        ..room.turnsLandBeforeTheyFail = true
        ..room.failHeldTurnWith = const NetworkFailed('a rede caiu'),
    );
    await waitFor(
      'the opening to play',
      () => room.harness.voice.played.contains(turnoUrl),
    );

    expect(room.harness.room.turnIdsLookedAt, [
      room.harness.room.turnIdsAsked.single,
    ]);
    expect(room.read().needsPerson, isFalse);
  });

  test('an opening the network lost that the look did not find rests at the '
      'invite with no sign and no sound', () async {
    final room = await _enterP01(
      SalaHarness()..room.failHeldTurnWith = const NetworkFailed('timeout'),
    );
    await _theOpeningIsAsked(room);
    await waitFor(
      'the opening to be looked at',
      () => room.harness.room.turnIdsLookedAt.isNotEmpty,
    );
    await _theRoomRests(room);

    expect(room.harness.room.turnIdsLookedAt, hasLength(1));
    expect(room.read().voice, VoiceState.invite);
    expect(room.read().needsPerson, isFalse);
    expect(room.harness.voice.played, isNot(contains(turnoUrl)));
    expect(room.voices, isNot(contains(VoiceState.offline)));
  });

  test(
    'an opening the room refused rests at the invite with no sign',
    () async {
      final room = await _enterP01(
        SalaHarness()..room.failHeldTurnWith = const Refused('BAD_REQUEST'),
      );
      await _theOpeningIsAsked(room);
      await _theRoomRests(room);

      expect(room.read().voice, VoiceState.invite);
      expect(room.read().needsPerson, isFalse);
      expect(room.harness.voice.played, isNot(contains(turnoUrl)));
    },
  );

  test(
    'an opening refused with a code that stops the room still calls a person',
    () async {
      final room = await _enterP01(
        SalaHarness()
          ..room.failHeldTurnWith = const Refused(RefusalCode.deviceRevoked),
      );
      await _theOpeningIsAsked(room);

      await waitFor('a person to be called', () => room.read().needsPerson);
    },
  );

  test('after an opening whose clip will not play, the next tap records a team '
      'turn', () async {
    final harness = SalaHarness();
    harness.voice.refuses.add(turnoUrl);
    final room = await _enterP01(harness);
    await waitFor(
      'the opening to be tried',
      () => harness.voice.played.contains(turnoUrl),
    );
    await _theRoomRests(room);
    expect(room.read().needsPerson, isFalse);
    harness.voice.refuses.clear();

    room.notifier.conversaTap();
    await waitFor(
      'the team to be heard',
      () => room.read().voice == VoiceState.listening,
    );
    room.notifier.conversaTap();
    await waitFor(
      'the team turn to be sent',
      () => harness.room.turnsSent == 1,
    );

    expect(harness.room.turnIdsAsked, hasLength(1));
  });

  test(
    'after a failed opening, opening the passage again from the Menu asks it '
    'again',
    () async {
      final room = await _enterP01(
        SalaHarness()..room.failHeldTurnWith = const Refused('BAD_REQUEST'),
      );
      await _theOpeningIsAsked(room);
      await _theRoomRests(room);
      final session = room.read().sessionId;

      room.notifier.leaveThePassage();
      await enterThePassage(room.notifier, room.read, 'P01');
      await waitFor(
        'the opening to be said',
        () => room.harness.voice.played.contains(turnoUrl),
      );

      expect(room.harness.room.sessionsSpokenTo, [session, session]);
      expect(room.harness.room.turnIdsAsked, hasLength(2));
      expect(
        room.harness.room.turnIdsAsked.last,
        isNot(room.harness.room.turnIdsAsked.first),
      );
    },
  );
}

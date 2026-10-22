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
});

Future<_Room> _enterP01(SalaHarness harness) async {
  final container = harness.container();
  addTearDown(container.dispose);
  final notifier = container.read(salaSessionProvider.notifier);
  SalaSessionState read() => container.read(salaSessionProvider);
  await enterThePassage(notifier, read, 'P01');
  return (harness: harness, notifier: notifier, read: read);
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

Future<void> _theTeamSpeaks(_Room room) async {
  final sent = room.harness.room.turnsSent;
  room.notifier.conversaTap();
  await waitFor(
    'the team to be heard',
    () => room.read().voice == VoiceState.listening,
  );
  room.notifier.conversaTap();
  await waitFor(
    'the team turn to be sent',
    () => room.harness.room.turnsSent == sent + 1,
  );
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

  test('an opening refused with a code that stops the room rests at the invite '
      'with no sign', () async {
    final room = await _enterP01(
      SalaHarness()
        ..room.failHeldTurnWith = const Refused(RefusalCode.deviceRevoked),
    );
    await _theOpeningIsAsked(room);
    await _theRoomRests(room);

    expect(room.read().voice, VoiceState.invite);
    expect(room.read().needsPerson, isFalse);
  });

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

    await _theTeamSpeaks(room);

    expect(harness.room.turnIdsAsked, hasLength(1));
  });

  test(
    'after a failed opening, opening the passage again from the Choice asks it '
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

  test(
    'an opening whose clip would not play is not asked again from the Choice, '
    'and «Ouvir de novo» has the room say it',
    () async {
      final harness = SalaHarness();
      harness.voice.refuses.add(turnoUrl);
      final room = await _enterP01(harness);
      await waitFor(
        'the opening to be tried',
        () => harness.voice.played.contains(turnoUrl),
      );
      await _theRoomRests(room);
      harness.voice.refuses.clear();
      final session = room.read().sessionId;

      room.notifier.leaveThePassage();
      await enterThePassage(room.notifier, room.read, 'P01');
      await waitFor(
        'the passage to land at rest',
        () => room.read().sessionId == session && room.read().canHearAgain,
      );
      await room.notifier.hearAgain();
      await waitFor(
        'the room to say it',
        () => harness.voice.played.contains(deNovoUrl),
      );

      expect(
        harness.room.turnIdsAsked,
        hasLength(2),
        reason: 'a abertura uma vez, e o dito de novo sob um id próprio',
      );
      expect(harness.room.sessionsSaidAgain, [session]);
    },
  );

  test('after an opening whose clip would not play, a refused team turn still '
      'calls a person', () async {
    final harness = SalaHarness();
    harness.voice.refuses.add(turnoUrl);
    final room = await _enterP01(harness);
    await waitFor(
      'the opening to be tried',
      () => harness.voice.played.contains(turnoUrl),
    );
    await _theRoomRests(room);
    harness.voice.refuses.clear();
    harness.room.failHeldTurnWith = const Refused('BAD_REQUEST');

    await _theTeamSpeaks(room);

    await waitFor('a person to be called', () => room.read().needsPerson);
  });

  test('after an opening the room refused, the next tap records a team turn '
      'whose reply plays, and the opening is not asked again', () async {
    final room = await _enterP01(
      SalaHarness()..room.failHeldTurnWith = const Refused('BAD_REQUEST'),
    );
    await _theOpeningIsAsked(room);
    await _theRoomRests(room);

    await _theTeamSpeaks(room);
    await waitFor(
      'the reply to play',
      () => room.harness.voice.played.contains(turnoUrl),
    );

    expect(room.harness.voice.played, [turnoUrl]);
    expect(room.harness.room.turnsSent, 1);
    expect(room.harness.room.turnIdsAsked, hasLength(1));
  });

  test('after an opening the network lost and the look did not find, the next '
      'tap records a team turn whose reply plays, and the opening is not asked '
      'again', () async {
    final room = await _enterP01(
      SalaHarness()..room.failHeldTurnWith = const NetworkFailed('timeout'),
    );
    await waitFor(
      'the opening to be looked at',
      () => room.harness.room.turnIdsLookedAt.isNotEmpty,
    );
    await _theRoomRests(room);

    await _theTeamSpeaks(room);
    await waitFor(
      'the reply to play',
      () => room.harness.voice.played.contains(turnoUrl),
    );

    expect(room.harness.voice.played, [turnoUrl]);
    expect(room.harness.room.turnsSent, 1);
    expect(room.harness.room.turnIdsAsked, hasLength(1));
  });

  test('an opening whose sound fails, then a reply whose sound fails, brings '
      'the person sign, and the team\'s tap clears it', () async {
    final harness = SalaHarness();
    harness.voice.refuses.add(turnoUrl);
    final room = await _enterP01(harness);
    await waitFor(
      'the opening to be tried',
      () => harness.voice.played.contains(turnoUrl),
    );
    await _theRoomRests(room);
    expect(room.read().needsPerson, isFalse);

    await _theTeamSpeaks(room);
    await waitFor('a person to be called', () => room.read().needsPerson);

    room.notifier.teamTapped();
    await waitFor('the sign to clear', () => !room.read().needsPerson);
    expect(room.read().voice, VoiceState.invite);
  });

  test('an opening the busy watchdog gave up on while its sound was being '
      'readied leaves the next team turn an ordinary one: refused, it calls a '
      'person', () async {
    final harness = SalaHarness(busyCeiling: const Duration(milliseconds: 300));
    harness.voice.holdNextFetch();
    final room = await _enterP01(harness);
    await _theRoomRests(room);
    expect(room.read().needsPerson, isFalse);
    harness.room.failHeldTurnWith = const Refused('BAD_REQUEST');

    await _theTeamSpeaks(room);

    await waitFor('a person to be called', () => room.read().needsPerson);
  });
}

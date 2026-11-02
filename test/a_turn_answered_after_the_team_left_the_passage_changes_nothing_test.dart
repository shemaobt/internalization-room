import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'session_notifier_test.dart' show inConversa;

void main() {
  test(
    'a turn answered after the team left the passage changes nothing',
    () async {
      final harness = SalaHarness();
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      harness.room.holdNextTurn();
      notifier.conversaTap();
      await settle();
      notifier.conversaTap();
      await waitFor('a vez ficar no ar', () => harness.room.turnsSent > 0);

      notifier.leaveThePassage();
      await settle();
      final left = read();
      final heardBefore = [...harness.sounds];
      expect(left.stage, SalaStage.escolha);

      harness.room.finishHeldTurn();
      await settle();

      final now = read();
      expect(now.stage, left.stage);
      expect(now.voice, left.voice);
      expect(now.awaitingTheGuide, left.awaitingTheGuide);
      expect(now.sessionId, left.sessionId);
      expect(now.lastSpoken, left.lastSpoken);
      expect(now.coverage, left.coverage);
      expect(now.channel, left.channel);
      expect(
        harness.sounds
            .sublist(heardBefore.length)
            .where((sound) => sound.startsWith('voice:line')),
        isEmpty,
      );
    },
  );

  for (final (name, failure) in <(String, RoomFailure)>[
    ('fails', const NetworkFailed('a rede caiu')),
    ('is refused', const Refused('BAD_REQUEST')),
  ]) {
    test(
      'a turn the team left and that then $name leaves the end it found',
      () async {
        final harness = SalaHarness();
        final container = await inConversa(harness);
        addTearDown(container.dispose);
        final notifier = container.read(salaSessionProvider.notifier);
        final session = container.read(salaSessionProvider).sessionId!;
        final ledger = harness.currentSession;
        final before = await ledger.endOf(session);
        expect(before?.line, isNotNull, reason: 'the Guide spoke last');

        harness.room
          ..holdNextTurn()
          ..failHeldTurnWith = failure;
        notifier.conversaTap();
        await settle();
        notifier.conversaTap();
        await waitFor('a vez ficar no ar', () => harness.room.turnsSent > 0);
        notifier.leaveThePassage();
        await settle();

        harness.room.finishHeldTurn();
        await settle();

        expect((await ledger.endOf(session))?.line, before!.line);
      },
    );
  }
}

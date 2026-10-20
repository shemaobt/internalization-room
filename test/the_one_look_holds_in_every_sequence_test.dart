import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/turn_result.dart';

import 'machine_generator.dart';

typedef _Room = ({Machine machine, Map<Turn, int> looked});

final _machine = MachineUnderTest<_Room>(
  start: (machine: const Machine(), looked: const {}),
  step: (room, event) {
    final (machine, effects) = reduce(room.machine, event);
    final looked = {...room.looked, if (event is TurnSent) event.turn: 0};
    for (final look in effects.whereType<LookAtTheSession>()) {
      looked[look.turn] = (looked[look.turn] ?? 0) + 1;
    }
    return ((machine: machine, looked: looked), effects);
  },
  draw: (_, world, random) => drawAnEvent(world, random),
  show: (room) => describeMachine(room.machine),
);

final _oneSeed = int.tryParse(Platform.environment['MACHINE_SEED'] ?? '');
final Iterable<int> _seeds = switch (_oneSeed) {
  final seed? => [seed],
  null => List.generate(500, (seed) => seed),
};

bool _theOfflineFace(Effect effect) =>
    effect is SayTheOfflineNotice || effect is ArmTheRetry;

final _oneTakeIsNeverLookedAtTwice = Invariant<_Room>(
  'one take is never looked at twice',
  (before, event, after, effects, world) {
    for (final MapEntry(key: turn, value: looks) in after.looked.entries) {
      if (looks > 1) return '${turn.turnId} looked at $looks times';
    }
    return null;
  },
);

final _aGivenUpTurnNeverFallsOutOfReach = Invariant<_Room>(
  'a turn given up never falls out of reach',
  (before, event, after, effects, world) {
    if (event is! TurnGivenUp) return null;
    if (effects.any(_theOfflineFace) ||
        after.machine.reach != before.machine.reach) {
      return 'a given-up turn showed the offline face';
    }
    return null;
  },
);

final _anEmptyLookShowsThePersonSign = Invariant<_Room>(
  'an empty look shows the person sign, unless it looked for an opening or a line said again',
  (before, event, after, effects, world) {
    if (event is! LookEmpty) return null;
    if (event.sounding is TheOpening) {
      if (after.machine.halt != before.machine.halt) {
        return 'a look for an opening changed the halt';
      }
      if (!effects.contains(const LetTheOpeningGo())) {
        return 'a look for an opening did not let it go';
      }
      return null;
    }
    if (event.sounding is TheLineSaidAgain) {
      if (after.machine.halt != before.machine.halt) {
        return 'a look for a line said again changed the halt';
      }
      if (!effects.contains(const LetTheLineGo())) {
        return 'a look for a line said again did not let it go';
      }
      return null;
    }
    if (after.machine.halt is! Blocking) {
      return 'no person sign after an empty look';
    }
    if (!effects.contains(const CallForAPerson())) return 'no person called';
    if (effects.any(_theOfflineFace)) return 'an empty look went offline';
    return null;
  },
);

final _aFoundReplyPlaysAsIfOnTime = Invariant<_Room>(
  'a reply the look found plays as if it had arrived on time, unless it is an Opening the room was still answering',
  (before, event, after, effects, world) {
    if (event is! LookFound) return null;
    final plays = effects.whereType<PlayTheReply>().length;
    final kept = effects.whereType<KeepTheReply>().length;
    final waited = before.machine.pendingLook;
    if (waited != null &&
        waited.turn == event.turn &&
        waited.sounding is TheOpening) {
      if (plays != 0 || kept != 1) return 'played $plays, kept $kept';
      return null;
    }
    if (plays != 1 || kept != 0) return 'played $plays times, kept $kept';
    return null;
  },
);

final _aLookStillAnsweredLooksAgainUntilDecided = Invariant<_Room>(
  'a look the room is still answering looks again until it is decided',
  (before, event, after, effects, world) {
    if (event is LookPending &&
        (event.generation ?? before.machine.generation) >=
            before.machine.generation) {
      if (!effects.contains(LookAgain(event.turn, sounding: event.sounding))) {
        return 'a look still answered did not look again';
      }
      if (after.machine.pendingLook == null) return 'nothing pending';
      return null;
    }
    if ((event is LookFound || event is LookEmpty) &&
        after.machine.pendingLook != null) {
      return 'a decided look is still pending';
    }
    return null;
  },
);

void main() {
  test('The generator\'s invariants hold with the one look.', () {
    expectEverySeedHolds(_machine, [
      _oneTakeIsNeverLookedAtTwice,
      _aGivenUpTurnNeverFallsOutOfReach,
      _anEmptyLookShowsThePersonSign,
      _aFoundReplyPlaysAsIfOnTime,
      _aLookStillAnsweredLooksAgainUntilDecided,
    ], seeds: _seeds);
  });

  test('a give-up for a turn the room has already left looks at nothing', () {
    const turn = Turn('sessao-1', 'turno-7');
    final (sent, _) = reduce(const Machine(), const TurnSent(turn));
    final left = moveTheGeneration(sent);

    final (_, effects) = reduce(
      left,
      TurnGivenUp(turn, generation: left.generation),
    );

    expect(effects.whereType<LookAtTheSession>(), isEmpty);
  });

  group(
    'the machine answers «still answering» by looking again, and only the watchdog ends it',
    () {
      const turn = Turn('sessao-1', 'turno-7');
      const reply = TurnResult(
        sessionId: 'sessao-1',
        audioUrl: '/voice/turno-7',
        fixedLine: '',
        transcript: '',
        peerCue: false,
        usedFailSafe: false,
        degraded: false,
        coverage: null,
        done: false,
      );

      test('a look still answered is held and looked at again', () {
        final (pending, effects) = reduce(
          const Machine(),
          const LookPending(turn, sounding: TheOpening('turno-7')),
        );

        expect(pending.pendingLook, (
          turn: turn,
          sounding: const TheOpening('turno-7'),
        ));
        expect(effects, [
          const LookAgain(turn, sounding: TheOpening('turno-7')),
        ]);
      });

      test('an Opening found after the wait is kept, not played', () {
        final (pending, _) = reduce(
          const Machine(),
          const LookPending(turn, sounding: TheOpening('turno-7')),
        );

        final (found, effects) = reduce(pending, const LookFound(turn, reply));

        expect(effects.whereType<KeepTheReply>(), hasLength(1));
        expect(effects.whereType<PlayTheReply>(), isEmpty);
        expect(found.pendingLook, isNull);
      });

      test('a team turn found after the wait plays', () {
        final (pending, _) = reduce(const Machine(), const LookPending(turn));

        final (_, effects) = reduce(pending, const LookFound(turn, reply));

        expect(effects.whereType<PlayTheReply>(), hasLength(1));
        expect(effects.whereType<KeepTheReply>(), isEmpty);
      });

      test(
        'a line said again the look did not find is let go, with no halt',
        () {
          final (pending, _) = reduce(
            const Machine(),
            const LookPending(turn, sounding: TheLineSaidAgain()),
          );

          final (empty, effects) = reduce(
            pending,
            const LookEmpty(sounding: TheLineSaidAgain()),
          );

          expect(effects, [const LetTheLineGo()]);
          expect(empty.halt, isA<NoHalt>());
          expect(empty.pendingLook, isNull);
        },
      );

      test(
        'a look still answered from an older generation changes nothing',
        () {
          final machine = moveTheGeneration(const Machine());

          final (after, effects) = reduce(
            machine,
            const LookPending(turn, generation: 0),
          );

          expect(effects, isEmpty);
          expect(after.pendingLook, isNull);
        },
      );
    },
  );
}

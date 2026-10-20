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

bool _decides(Machine before, LookEmpty event) => switch (before.look) {
  (turn: final turn, stillAnswering: final waits, sounding: _) =>
    turn == event.turn && (!waits || event.theWaitRanOut),
  null => false,
};

final _anEmptyLookShowsThePersonSign = Invariant<_Room>(
  'an empty look that decides shows the person sign, unless it looked for an opening or a line said again',
  (before, event, after, effects, world) {
    if (event is! LookEmpty || !_decides(before.machine, event)) return null;
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
    if (event is! LookFound || before.machine.look?.turn != event.turn) {
      return null;
    }
    final plays = effects.whereType<PlayTheReply>().length;
    final kept = effects.whereType<KeepTheReply>().length;
    if (before.machine.look case (
      stillAnswering: true,
      sounding: TheOpening(),
      turn: _,
    )) {
      if (plays != 0 || kept != 1) return 'played $plays, kept $kept';
      return null;
    }
    if (plays != 1 || kept != 0) return 'played $plays times, kept $kept';
    return null;
  },
);

final _aLookAnswersOnlyTheTurnItReads = Invariant<_Room>(
  'a look answers only the turn the machine still reads',
  (before, event, after, effects, world) {
    final turn = switch (event) {
      LookFound(:final turn) || LookPending(:final turn) => turn,
      LookEmpty(:final turn) => turn,
      _ => null,
    };
    if (turn == null) return null;
    if ((event as AnsweringEvent).generation case final stamp?
        when stamp < before.machine.generation) {
      return null;
    }
    if (before.machine.look?.turn != turn) {
      if (effects.isNotEmpty || after.machine.look != before.machine.look) {
        return 'a look at ${turn.turnId}, no longer read, changed the room';
      }
    }
    return null;
  },
);

final _aWaitIsDecidedOnlyByALandedAnswerOrTheWatchdog = Invariant<_Room>(
  'once the room said it is still answering, only a landed answer or the watchdog decides',
  (before, event, after, effects, world) {
    final look = before.machine.look;
    if (look == null) return null;
    if (event case LookPending(:final turn) || LookEmpty(:final turn)
        when turn == look.turn &&
            (look.stillAnswering || event is LookPending) &&
            !(event is LookEmpty && event.theWaitRanOut)) {
      if (!effects.contains(LookAgain(turn, sounding: look.sounding))) {
        return 'a wait still open did not look again';
      }
      if (after.machine.look?.turn != turn) return 'the wait was dropped';
      if (after.machine.halt != before.machine.halt) {
        return 'a wait still open changed the halt';
      }
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
      _aLookAnswersOnlyTheTurnItReads,
      _aWaitIsDecidedOnlyByALandedAnswerOrTheWatchdog,
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
    'the machine answers «still answering» by looking again, and only a landed answer or the watchdog ends it',
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

      Machine givenUp(Kept sounding) {
        final (sent, _) = reduce(const Machine(), const TurnSent(turn));
        return reduce(sent, TurnGivenUp(turn, sounding: sounding)).$1;
      }

      Machine stillAnswering(Kept sounding) =>
          reduce(givenUp(sounding), LookPending(turn, sounding: sounding)).$1;

      test('a look still answered is looked at again', () {
        final (_, effects) = reduce(
          givenUp(const TheOpening('turno-7')),
          const LookPending(turn, sounding: TheOpening('turno-7')),
        );

        expect(effects, [
          const LookAgain(turn, sounding: TheOpening('turno-7')),
        ]);
      });

      test('an Opening found after the wait is kept, not played', () {
        final (_, effects) = reduce(
          stillAnswering(const TheOpening('turno-7')),
          const LookFound(turn, reply),
        );

        expect(effects.whereType<KeepTheReply>(), hasLength(1));
        expect(effects.whereType<PlayTheReply>(), isEmpty);
      });

      test('a team turn found after the wait plays', () {
        final (_, effects) = reduce(
          stillAnswering(const NothingKept()),
          const LookFound(turn, reply),
        );

        expect(effects.whereType<PlayTheReply>(), hasLength(1));
        expect(effects.whereType<KeepTheReply>(), isEmpty);
      });

      test('an empty or failed look after the wait looks again', () {
        final (still, effects) = reduce(
          stillAnswering(const NothingKept()),
          const LookEmpty(turn),
        );

        expect(effects, [const LookAgain(turn)]);
        expect(still.halt, isA<NoHalt>());
        final (_, found) = reduce(still, const LookFound(turn, reply));
        expect(found.whereType<PlayTheReply>(), hasLength(1));
      });

      test(
        'a line said again the watchdog decides is let go, with no halt',
        () {
          final (empty, effects) = reduce(
            stillAnswering(const TheLineSaidAgain()),
            const LookEmpty(
              turn,
              sounding: TheLineSaidAgain(),
              theWaitRanOut: true,
            ),
          );

          expect(effects, contains(const LetTheLineGo()));
          expect(effects, contains(const StopLooking()));
          expect(empty.halt, isA<NoHalt>());
        },
      );

      test('a look answered after a halt was raised changes nothing', () {
        final (halted, effects) = reduce(
          givenUp(const NothingKept()),
          const RoomRaisedAHalt(),
        );
        expect(effects, contains(const StopLooking()));

        final (after, answered) = reduce(halted, const LookPending(turn));

        expect(answered, isEmpty);
        expect(after.halt, halted.halt);
        expect(reduce(after, const LookPending(turn)).$2, isEmpty);
      });

      test(
        'a look still answered from an older generation changes nothing',
        () {
          final machine = moveTheGeneration(givenUp(const NothingKept()));

          final (_, effects) = reduce(
            machine,
            const LookPending(turn, generation: 0),
          );

          expect(effects, isEmpty);
        },
      );
    },
  );
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';

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
  'an empty look shows the person sign, unless it looked for an opening',
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
    if (after.machine.halt is! Blocking) {
      return 'no person sign after an empty look';
    }
    if (!effects.contains(const CallForAPerson())) return 'no person called';
    if (effects.any(_theOfflineFace)) return 'an empty look went offline';
    return null;
  },
);

final _aFoundReplyPlaysAsIfOnTime = Invariant<_Room>(
  'a reply the look found plays as if it had arrived on time',
  (before, event, after, effects, world) {
    if (event is! LookFound) return null;
    final plays = effects.whereType<PlayTheReply>().length;
    if (plays != 1) return 'played $plays times';
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
}

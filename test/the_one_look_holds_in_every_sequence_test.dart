import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';

import 'machine_generator.dart';

final _machine = MachineUnderTest<Machine>(
  start: const Machine(),
  step: reduce,
  draw: (_, world, random) => drawAnEvent(world, random),
  show: describeMachine,
);

final _oneSeed = int.tryParse(Platform.environment['MACHINE_SEED'] ?? '');
final Iterable<int> _seeds = switch (_oneSeed) {
  final seed? => [seed],
  null => List.generate(500, (seed) => seed),
};

bool _theOfflineFace(Effect effect) =>
    effect is SayTheOfflineNotice || effect is ArmTheRetry;

final _aGivenUpTurnIsLookedAtOnce = Invariant<Machine>(
  'a turn given up is looked at once and never falls out of reach',
  (before, event, after, effects, world) {
    if (event is! TurnGivenUp) return null;
    final looks = effects.whereType<LookAtTheSession>().toList();
    if (looks.length != 1 || looks.single.turn != event.turn) {
      return 'looked ${looks.length} times';
    }
    if (effects.any(_theOfflineFace) || after.reach != before.reach) {
      return 'a given-up turn showed the offline face';
    }
    return null;
  },
);

final _anEmptyLookShowsThePersonSign = Invariant<Machine>(
  'an empty look shows the person sign',
  (before, event, after, effects, world) {
    if (event is! LookEmpty) return null;
    if (after.halt is! Blocking) return 'no person sign after an empty look';
    if (!effects.contains(const CallForAPerson())) return 'no person called';
    if (effects.any(_theOfflineFace)) return 'an empty look went offline';
    return null;
  },
);

final _aFoundReplyPlaysAsIfOnTime = Invariant<Machine>(
  'a reply the look found plays as if it had arrived on time',
  (before, event, after, effects, world) {
    if (event is! LookFound) return null;
    final plays = effects.whereType<PlayTheReply>().length;
    if (plays != 1) return 'played $plays times';
    if (after.halt != before.halt) return 'a found reply moved the halt';
    return null;
  },
);

void main() {
  test('The generator\'s invariants hold with the one look.', () {
    expectEverySeedHolds(_machine, [
      _aGivenUpTurnIsLookedAtOnce,
      _anEmptyLookShowsThePersonSign,
      _aFoundReplyPlaysAsIfOnTime,
    ], seeds: _seeds);
  });
}

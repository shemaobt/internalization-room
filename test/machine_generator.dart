import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';

class World {
  final bool watchArmed;
  final bool callOutstanding;
  final bool reachable;

  const World({
    this.watchArmed = true,
    this.callOutstanding = false,
    this.reachable = true,
  });

  World after(MachineEvent event, List<Effect> effects) {
    var armed = watchArmed && event is! WatchFired;
    var calling = callOutstanding && event is! TheCallLanded;
    for (final effect in effects) {
      switch (effect) {
        case ArmTheWatch():
          armed = true;
        case CallForAPerson():
          calling = true;
        case StopCallingForAPerson():
          calling = false;
        default:
          break;
      }
    }
    return World(
      watchArmed: armed,
      callOutstanding: calling,
      reachable: event is ReachChanged ? event.reachable : reachable,
    );
  }
}

class Machine<S> {
  final S start;
  final (S, List<Effect>) Function(S state, MachineEvent event) step;
  final MachineEvent Function(S state, World world, Random random) draw;
  final String Function(S state) show;

  const Machine({
    required this.start,
    required this.step,
    required this.draw,
    required this.show,
  });
}

class Invariant<S> {
  final String name;
  final String? Function(
    S before,
    MachineEvent event,
    S after,
    List<Effect> effects,
    World world,
  )
  check;

  const Invariant(this.name, this.check);
}

class Entry<S> {
  final World worldBefore;
  final MachineEvent event;
  final S after;
  final List<Effect> effects;

  const Entry(this.worldBefore, this.event, this.after, this.effects);
}

class Trace<S> {
  final int seed;
  final List<Entry<S>> entries;
  final String? violation;

  const Trace(this.seed, this.entries, this.violation);
}

Trace<S> runSequence<S>(
  Machine<S> machine,
  List<Invariant<S>> invariants,
  int seed, {
  int steps = 40,
}) {
  final random = Random(seed);
  var state = machine.start;
  var world = const World();
  final entries = <Entry<S>>[];
  for (var i = 0; i < steps; i++) {
    final event = machine.draw(state, world, random);
    final (next, effects) = machine.step(state, event);
    final nextWorld = world.after(event, effects);
    entries.add(Entry(world, event, next, effects));
    for (final invariant in invariants) {
      final problem = invariant.check(state, event, next, effects, nextWorld);
      if (problem != null) {
        return Trace(seed, entries, '${invariant.name}: $problem');
      }
    }
    state = next;
    world = nextWorld;
  }
  return Trace(seed, entries, null);
}

void expectEverySeedHolds<S>(
  Machine<S> machine,
  List<Invariant<S>> invariants, {
  required Iterable<int> seeds,
  int steps = 40,
}) {
  for (final seed in seeds) {
    final trace = runSequence(machine, invariants, seed, steps: steps);
    if (trace.violation != null) {
      throw TestFailure(describeFailure(machine, trace));
    }
  }
}

String describeFailure<S>(Machine<S> machine, Trace<S> trace) {
  final lines = [
    'seed ${trace.seed} broke ${trace.violation}',
    'Re-run it alone with MACHINE_SEED=${trace.seed}',
    for (final (index, entry) in trace.entries.indexed)
      '${index + 1}. ${describeEvent(entry.event)} -> '
          '${machine.show(entry.after)} | '
          '${entry.effects.map(describeEffect).join(', ')}',
  ];
  return lines.join('\n');
}

String describeKept(Kept kept) => switch (kept) {
  NothingKept() => 'NothingKept',
  ThePart() => 'ThePart',
  TheOpening(:final failedTurnId) => 'TheOpening($failedTurnId)',
  TheResume() => 'TheResume',
  TheWheel() => 'TheWheel',
};

String describeHalt(Halt halt) => switch (halt) {
  NoHalt() => 'NoHalt',
  Warning() => 'Warning',
  Blocking(:final kept, :final warningBeneath, :final serverKnows) =>
    'Blocking(${describeKept(kept)}, warningBeneath: $warningBeneath, '
        'serverKnows: $serverKnows)',
};

String describeEvent(MachineEvent event) => switch (event) {
  SessionRead(
    :final snapshot,
    :final sounding,
    :final sentBeforeTheCallLanded,
    :final at,
  ) =>
    'SessionRead(status: ${snapshot.status}, halt: ${snapshot.halt.name}, '
        'sounding: ${describeKept(sounding)}, '
        'sentBeforeTheCallLanded: $sentBeforeTheCallLanded, at: $at)',
  RoomRaisedAHalt(:final sounding, :final callsForAPerson) =>
    'RoomRaisedAHalt(${describeKept(sounding)}, '
        'callsForAPerson: $callsForAPerson)',
  TheCallLanded() => 'TheCallLanded',
  TheAnswerWarned() => 'TheAnswerWarned',
  LongPress(:final somebodyToAsk, :final at) =>
    'LongPress(somebodyToAsk: $somebodyToAsk, at: $at)',
  WatchFired() => 'WatchFired',
  ReachChanged(:final reachable) => 'ReachChanged(reachable: $reachable)',
};

String describeEffect(Effect effect) => switch (effect) {
  ReplayTheSound(:final kept) => 'ReplayTheSound(${describeKept(kept)})',
  AskTheOpeningAgain(:final freshTurnId) => 'AskTheOpeningAgain($freshTurnId)',
  _ => effect.runtimeType.toString(),
};

final _at = DateTime.utc(2026, 9, 30, 12);

Kept _drawKept(Random random) => switch (random.nextInt(5)) {
  0 => const NothingKept(),
  1 => const ThePart(),
  2 => TheOpening('turn-${random.nextInt(3)}'),
  3 => const TheResume(),
  _ => const TheWheel(),
};

SessionRead _drawARead(Random random) => SessionRead(
  SessionSnapshot(
    sessionId: 'sessao-1',
    pericope: 'rute-1',
    status: random.nextBool() ? 'needs_person' : 'in_progress',
    coverage: null,
    done: false,
    halt: HaltKind.values[random.nextInt(HaltKind.values.length)],
  ),
  at: _at.add(Duration(milliseconds: random.nextInt(3))),
  sounding: _drawKept(random),
  sentBeforeTheCallLanded: random.nextBool(),
);

MachineEvent drawAnEvent(World world, Random random) {
  final allowed = <MachineEvent Function()>[
    () => _drawARead(random),
    () => RoomRaisedAHalt(
      sounding: _drawKept(random),
      callsForAPerson: random.nextBool(),
    ),
    () => const TheAnswerWarned(),
    () => LongPress(
      somebodyToAsk: random.nextBool(),
      at: _at.add(Duration(milliseconds: random.nextInt(3))),
    ),
    () => ReachChanged(reachable: !world.reachable),
    if (world.watchArmed) () => const WatchFired(),
    if (world.callOutstanding) () => const TheCallLanded(),
  ];
  return allowed[random.nextInt(allowed.length)]();
}

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';

class World {
  final bool watchArmed;
  final bool callOutstanding;
  final bool reachable;
  final bool serverHoldsAWarning;
  final bool playerBusy;
  final bool micOpen;

  const World({
    this.watchArmed = true,
    this.callOutstanding = false,
    this.reachable = true,
    this.serverHoldsAWarning = false,
    this.playerBusy = false,
    this.micOpen = false,
  });

  World after(MachineEvent event, List<Effect> effects) {
    var armed = watchArmed && event is! WatchFired;
    var calling = callOutstanding && event is! TheCallLanded;
    var busy =
        playerBusy &&
        event is! PlayerEnded &&
        event is! PlayerFailed &&
        event is! GestureSilenced;
    var mic = micOpen && event is! MicClosed;
    for (final effect in effects) {
      switch (effect) {
        case ArmTheWatch():
          armed = true;
        case CallForAPerson():
          calling = true;
        case StopCallingForAPerson():
          calling = false;
        case PlayLine() || PlayPart() || PlayStretch():
          busy = true;
        case SilenceTheRoom() || StopTheSound():
          busy = false;
        case OpenTheMic():
          mic = true;
        case CloseAndDiscardTheMic():
          mic = false;
        default:
          break;
      }
    }
    return World(
      watchArmed: armed,
      callOutstanding: calling,
      reachable: event is ReachChanged ? event.reachable : reachable,
      playerBusy: busy,
      micOpen: mic,
      serverHoldsAWarning: switch (event) {
        TheAnswerWarned() => true,
        SessionRead(:final snapshot) when !snapshot.needsPerson =>
          snapshot.halt == HaltKind.warning,
        _ => serverHoldsAWarning,
      },
    );
  }
}

class MachineUnderTest<S> {
  final S start;
  final (S, List<Effect>) Function(S state, MachineEvent event) step;
  final MachineEvent Function(S state, World world, Random random) draw;
  final String Function(S state) show;

  const MachineUnderTest({
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
  MachineUnderTest<S> machine,
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
  MachineUnderTest<S> machine,
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

String describeFailure<S>(MachineUnderTest<S> machine, Trace<S> trace) {
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
  LineArrived(:final line) => 'LineArrived(${describeLine(line)})',
  PlayerOpened() => 'PlayerOpened',
  PlayerEnded() => 'PlayerEnded',
  PlayerFailed(:final source, :final sounding) =>
    'PlayerFailed(${source.key}, ${describeKept(sounding)})',
  MicOpened(:final owner) => 'MicOpened(${owner.name})',
  MicClosed(:final outcome) => 'MicClosed(${outcome.name})',
  BeadTapped(:final sounds, :final beneath) =>
    'BeadTapped(${sounds.map(describeSound).join(', ')}'
        '${beneath == null ? '' : ', beneath: ${describeChannel(beneath)}'})',
  PauseTapped() => 'PauseTapped',
  GestureSilenced(:final keepingTheHold) =>
    'GestureSilenced(keepingTheHold: $keepingTheHold)',
  GestureDone() => 'GestureDone',
  LeftThePassage() => 'LeftThePassage',
};

String describeLine(Line line) => '${line.kind.name}#${line.id}';

String describeSound(Sound sound) => switch (sound) {
  PartSound(:final part, :final from) => 'part $part from ${from.inSeconds}s',
  StretchSound(:final segment, :final telling) =>
    'stretch $segment${telling ? ' told' : ''}',
};

String describeChannel(Channel channel) => switch (channel) {
  Silence() => 'Silence',
  Microphone(:final owner) => 'Microphone(${owner.name})',
  GuideSpeaking(:final line) => 'GuideSpeaking(${describeLine(line)})',
  final Playing playing =>
    'Playing(${describeSound(playing.sound)}, opened: ${playing.opened})',
  Paused(:final what, :final started, :final opened) =>
    'Paused(${describeSound(what)}, started: $started, opened: $opened)',
};

String describeMachine(Machine machine) =>
    '${describeHalt(machine.halt)} / ${describeChannel(machine.channel)} / '
    'queue [${machine.queue.map(describeLine).join(', ')}]';

String describeEffect(Effect effect) => switch (effect) {
  ReplayTheSound(:final kept) => 'ReplayTheSound(${describeKept(kept)})',
  PlayLine(:final line) => 'PlayLine(${describeLine(line)})',
  PlayPart(:final part) => 'PlayPart(${describeSound(part)})',
  PlayStretch(:final stretch) => 'PlayStretch(${describeSound(stretch)})',
  OpenTheMic(:final owner) => 'OpenTheMic(${owner.name})',
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

SessionRead _drawARead(World world, Random random) => SessionRead(
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
  sentBeforeTheCallLanded: world.callOutstanding && random.nextBool(),
);

enum EventKind {
  sessionRead,
  roomRaisedAHalt,
  theCallLanded,
  theAnswerWarned,
  longPress,
  watchFired,
  reachChanged,
  lineArrived,
  playerOpened,
  playerEnded,
  playerFailed,
  micOpened,
  micClosed,
  beadTapped,
  pauseTapped,
  gestureSilenced,
  gestureDone,
  leftThePassage,
}

EventKind kindOf(MachineEvent event) => switch (event) {
  SessionRead() => EventKind.sessionRead,
  RoomRaisedAHalt() => EventKind.roomRaisedAHalt,
  TheCallLanded() => EventKind.theCallLanded,
  TheAnswerWarned() => EventKind.theAnswerWarned,
  LongPress() => EventKind.longPress,
  WatchFired() => EventKind.watchFired,
  ReachChanged() => EventKind.reachChanged,
  LineArrived() => EventKind.lineArrived,
  PlayerOpened() => EventKind.playerOpened,
  PlayerEnded() => EventKind.playerEnded,
  PlayerFailed() => EventKind.playerFailed,
  MicOpened() => EventKind.micOpened,
  MicClosed() => EventKind.micClosed,
  BeadTapped() => EventKind.beadTapped,
  PauseTapped() => EventKind.pauseTapped,
  GestureSilenced() => EventKind.gestureSilenced,
  GestureDone() => EventKind.gestureDone,
  LeftThePassage() => EventKind.leftThePassage,
};

bool _theWorldAllows(EventKind kind, World world) => switch (kind) {
  EventKind.watchFired => world.watchArmed,
  EventKind.theCallLanded => world.callOutstanding,
  EventKind.playerOpened ||
  EventKind.playerEnded ||
  EventKind.playerFailed => world.playerBusy,
  EventKind.micClosed => world.micOpen,
  EventKind.sessionRead ||
  EventKind.roomRaisedAHalt ||
  EventKind.theAnswerWarned ||
  EventKind.longPress ||
  EventKind.reachChanged ||
  EventKind.lineArrived ||
  EventKind.micOpened ||
  EventKind.beadTapped ||
  EventKind.pauseTapped ||
  EventKind.gestureSilenced ||
  EventKind.gestureDone ||
  EventKind.leftThePassage => true,
};

Source _drawASource(Random random) => switch (random.nextInt(4)) {
  0 => Source.guide,
  1 => Source.take('parte-${random.nextInt(2)}.m4a'),
  2 => Source.segment('trecho-${random.nextInt(2)}'),
  _ => Source.reply('resposta-${random.nextInt(2)}'),
};

Sound _drawASound(Random random) => random.nextBool()
    ? PartSound(
        random.nextInt(2),
        'parte-${random.nextInt(2)}.m4a',
        from: Duration(seconds: random.nextInt(20)),
      )
    : StretchSound(
        'trecho-${random.nextInt(2)}',
        'parte-${random.nextInt(2)}.m4a',
        from: Duration(seconds: random.nextInt(10)),
        to: Duration(seconds: 10 + random.nextInt(10)),
        telling: random.nextBool(),
      );

MachineEvent _draw(EventKind kind, World world, Random random) =>
    switch (kind) {
      EventKind.sessionRead => _drawARead(world, random),
      EventKind.roomRaisedAHalt => RoomRaisedAHalt(
        sounding: _drawKept(random),
        callsForAPerson: random.nextBool(),
      ),
      EventKind.theCallLanded => const TheCallLanded(),
      EventKind.theAnswerWarned => const TheAnswerWarned(),
      EventKind.longPress => LongPress(
        somebodyToAsk: random.nextBool(),
        at: _at.add(Duration(milliseconds: random.nextInt(3))),
      ),
      EventKind.watchFired => const WatchFired(),
      EventKind.reachChanged => ReachChanged(reachable: !world.reachable),
      EventKind.lineArrived => LineArrived(
        Line(
          LineKind.values[random.nextInt(LineKind.values.length)],
          random.nextInt(1 << 20),
          source: _drawASource(random),
        ),
      ),
      EventKind.playerOpened => const PlayerOpened(),
      EventKind.playerEnded => const PlayerEnded(),
      EventKind.playerFailed => PlayerFailed(
        _drawASource(random),
        sounding: _drawKept(random),
      ),
      EventKind.micOpened => MicOpened(
        MicOwner.values[random.nextInt(MicOwner.values.length)],
      ),
      EventKind.micClosed => MicClosed(
        MicOutcome.values[random.nextInt(MicOutcome.values.length)],
      ),
      EventKind.beadTapped => BeadTapped([
        for (var i = 0; i <= random.nextInt(3); i++) _drawASound(random),
      ]),
      EventKind.pauseTapped => const PauseTapped(),
      EventKind.gestureSilenced => GestureSilenced(
        keepingTheHold: random.nextBool(),
      ),
      EventKind.gestureDone => const GestureDone(),
      EventKind.leftThePassage => const LeftThePassage(),
    };

MachineEvent drawAnEvent(World world, Random random) {
  final allowed = [
    for (final kind in EventKind.values)
      if (_theWorldAllows(kind, world)) kind,
  ];
  final kind = allowed[random.nextInt(allowed.length)];
  final event = _draw(kind, world, random);
  assert(kindOf(event) == kind);
  return event;
}

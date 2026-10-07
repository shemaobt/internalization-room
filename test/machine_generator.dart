import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/cut_point.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/room_reach.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/turn_result.dart';

class World {
  final bool watchArmed;
  final bool callOutstanding;
  final bool reachable;
  final bool serverHoldsAWarning;
  final bool playerBusy;
  final bool micOpen;
  final bool retryArmed;
  final bool draining;
  final bool probing;
  final bool looking;

  const World({
    this.watchArmed = true,
    this.callOutstanding = false,
    this.reachable = true,
    this.serverHoldsAWarning = false,
    this.playerBusy = false,
    this.micOpen = false,
    this.retryArmed = false,
    this.draining = false,
    this.probing = false,
    this.looking = false,
  });

  World after(MachineEvent event, List<Effect> effects) {
    var armed = watchArmed && event is! WatchFired;
    var calling = callOutstanding && event is! TheCallLanded;
    var busy =
        playerBusy &&
        event is! PlayerEnded &&
        event is! PlayerFailed &&
        event is! GestureSilenced;
    var mic =
        micOpen &&
        event is! MicClosed &&
        event is! MicDiscarded &&
        !(event is MicAnswered &&
            event.generation == null &&
            event.answer != MicAnswer.started &&
            event.because == null);
    var retry = retryArmed && event is! RetryFired;
    var drains = draining && event is! OutboxChanged;
    var probes =
        probing &&
        event is! NetworkReturned &&
        !(event is NetworkFailedAt && event.door == Door.probe);
    var looks = looking && event is! LookFound && event is! LookEmpty;
    var reach = switch (event) {
      NetworkFailedAt() => false,
      NetworkReturned() => true,
      _ => reachable,
    };
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
        case ArmTheRetry():
          retry = true;
        case CancelTheRetry():
          retry = false;
        case DrainTheOutbox():
          drains = true;
        case ProbeTheRoom():
          probes = true;
        case LookAtTheSession():
          looks = true;
        default:
          break;
      }
    }
    return World(
      watchArmed: armed,
      callOutstanding: calling,
      reachable: reach,
      playerBusy: busy,
      micOpen: mic,
      retryArmed: retry,
      draining: drains,
      probing: probes,
      looking: looks,
      serverHoldsAWarning: switch (event) {
        TheAnswerWarned() => true,
        TheSessionIsGone() || ThePassageClosed() => false,
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
  ) =>
    'SessionRead(status: ${snapshot.status}, halt: ${snapshot.halt.name}, '
        'sounding: ${describeKept(sounding)}, '
        'sentBeforeTheCallLanded: $sentBeforeTheCallLanded)',
  RoomRaisedAHalt(:final sounding, :final callsForAPerson) =>
    'RoomRaisedAHalt(${describeKept(sounding)}, '
        'callsForAPerson: $callsForAPerson)',
  TheCallLanded() => 'TheCallLanded',
  TheAnswerWarned() => 'TheAnswerWarned',
  LongPress(:final somebodyToAsk) => 'LongPress(somebodyToAsk: $somebodyToAsk)',
  WatchFired() => 'WatchFired',
  NetworkFailedAt(:final door, :final why) =>
    'NetworkFailedAt(${door.name}, ${why.name})',
  NetworkReturned() => 'NetworkReturned',
  RetryFired() => 'RetryFired',
  TheRoomAnswered() => 'TheRoomAnswered',
  OutboxChanged(:final parts, :final due) =>
    'OutboxChanged(${parts.entries.map((part) => '${part.key}: ${part.value.name}').join(', ')}, '
        'due: ${due.inSeconds}s)',
  LineArrived(:final line) => 'LineArrived(${describeLine(line)})',
  PlayerOpened() => 'PlayerOpened',
  PlayerEnded() => 'PlayerEnded',
  PlayerFailed(:final source, :final sounding) =>
    'PlayerFailed(${source.key}, ${describeKept(sounding)})',
  MicOpened(:final owner) => 'MicOpened(${owner.name})',
  MicClosed() => 'MicClosed',
  MicAnswered(:final answer) => 'MicAnswered(${answer.name})',
  MicClosing() => 'MicClosing',
  MicDiscarded() => 'MicDiscarded',
  BeadTapped(:final sounds, :final beneath) =>
    'BeadTapped(${sounds.map(describeSound).join(', ')}'
        '${beneath == null ? '' : ', beneath: ${describeChannel(beneath)}'})',
  PauseTapped() => 'PauseTapped',
  TheHeldPartReturns(:final held) =>
    'TheHeldPartReturns(${describeChannel(held)})',
  GestureSilenced(:final keepingTheHold) =>
    'GestureSilenced(keepingTheHold: $keepingTheHold)',
  Interrupted(:final cut) =>
    'Interrupted(at: ${cut.at.inMilliseconds}ms, of: ${cut.of?.inMilliseconds}ms)',
  GestureStarted(:final gesture) => 'GestureStarted($gesture)',
  GestureEnded(:final gesture) => 'GestureEnded($gesture)',
  NothingReplayed() => 'NothingReplayed',
  LineNotSaid(:final line) => 'LineNotSaid(${describeLine(line)})',
  StepLeft() => 'StepLeft',
  LeftThePassage() => 'LeftThePassage',
  TheSessionIsGone() => 'TheSessionIsGone',
  ThePassageClosed() => 'ThePassageClosed',
  TurnGivenUp(:final turn, :final sounding) =>
    'TurnGivenUp(${turn.turnId}, ${describeKept(sounding)})',
  LookFound(:final turn) => 'LookFound(${turn.turnId})',
  TurnSent(:final turn) => 'TurnSent(${turn.turnId})',
  TurnAnswered(:final turn) => 'TurnAnswered(${turn.turnId})',
  TurnFailed(:final turn) => 'TurnFailed(${turn.turnId})',
  TheRefusalPassed() => 'TheRefusalPassed',
  TheCallWasRefused() => 'TheCallWasRefused',
  TheCallMetAClosedPassage() => 'TheCallMetAClosedPassage',
  LookEmpty(:final sounding) => 'LookEmpty(${describeKept(sounding)})',
  TheOpeningMissed() => 'TheOpeningMissed',
  TheRoomRefused(:final third, :final sounding) =>
    'TheRoomRefused(third: $third, ${describeKept(sounding)})',
  ThePassageCannotOpen() => 'ThePassageCannotOpen',
  TheTellingCameBackEmpty() => 'TheTellingCameBackEmpty',
  TheVerdictAsked() => 'TheVerdictAsked',
  TheChoiceOpened() => 'TheChoiceOpened',
  PassageChosen() => 'PassageChosen',
  TheRehearsalOpened() => 'TheRehearsalOpened',
  TheBackTranslationOpened() => 'TheBackTranslationOpened',
  TheNecklaceClosed() => 'TheNecklaceClosed',
  TheRoomStartedOver() => 'TheRoomStartedOver',
  ThePanoramaChosen() => 'ThePanoramaChosen',
};

String describeLine(Line line) => '${line.kind.name}#${line.id}';

String describeSound(Sound sound) => switch (sound) {
  PartSound(:final part, :final from) => 'part $part from ${from.inSeconds}s',
  final StretchSound stretch =>
    'stretch ${stretch.key}${stretch.telling ? ' told' : ''}',
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
    'queue [${machine.queue.map(describeLine).join(', ')}] / '
    '${machine.reach.name}${machine.somethingPending ? ', a part pending' : ''}'
    '${machine.draining ? ', draining' : ''}';

String describeEffect(Effect effect) => switch (effect) {
  ReplayTheSound(:final kept) => 'ReplayTheSound(${describeKept(kept)})',
  PlayLine(:final line) => 'PlayLine(${describeLine(line)})',
  PlayPart(:final part) => 'PlayPart(${describeSound(part)})',
  PlayStretch(:final stretch) => 'PlayStretch(${describeSound(stretch)})',
  OpenTheMic(:final owner) => 'OpenTheMic(${owner.name})',
  ArmTheRetry(:final step, :final due) =>
    'ArmTheRetry(${due == null ? 'step $step' : 'due ${due.inSeconds}s'})',
  _ => effect.runtimeType.toString(),
};

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
  networkFailedAt,
  networkReturned,
  retryFired,
  theRoomAnswered,
  outboxChanged,
  lineArrived,
  playerOpened,
  playerEnded,
  playerFailed,
  micOpened,
  micClosed,
  micAnswered,
  micClosing,
  micDiscarded,
  beadTapped,
  pauseTapped,
  theHeldPartReturns,
  gestureSilenced,
  interrupted,
  gestureStarted,
  gestureEnded,
  nothingReplayed,
  lineNotSaid,
  stepLeft,
  leftThePassage,
  sessionGone,
  passageClosed,
  turnGivenUp,
  lookFound,
  lookEmpty,
  theOpeningMissed,
  theRoomRefused,
  thePassageCannotOpen,
  theTellingCameBackEmpty,
  theVerdictAsked,
  turnSent,
  turnAnswered,
  theRefusalPassed,
  theCallWasRefused,
  theCallMetAClosedPassage,
  turnFailed,
  theChoiceOpened,
  passageChosen,
  theRehearsalOpened,
  theBackTranslationOpened,
  theNecklaceClosed,
  theRoomStartedOver,
  thePanoramaChosen,
}

EventKind kindOf(MachineEvent event) => switch (event) {
  SessionRead() => EventKind.sessionRead,
  RoomRaisedAHalt() => EventKind.roomRaisedAHalt,
  TheCallLanded() => EventKind.theCallLanded,
  TheAnswerWarned() => EventKind.theAnswerWarned,
  LongPress() => EventKind.longPress,
  WatchFired() => EventKind.watchFired,
  NetworkFailedAt() => EventKind.networkFailedAt,
  NetworkReturned() => EventKind.networkReturned,
  RetryFired() => EventKind.retryFired,
  TheRoomAnswered() => EventKind.theRoomAnswered,
  OutboxChanged() => EventKind.outboxChanged,
  LineArrived() => EventKind.lineArrived,
  PlayerOpened() => EventKind.playerOpened,
  PlayerEnded() => EventKind.playerEnded,
  PlayerFailed() => EventKind.playerFailed,
  MicOpened() => EventKind.micOpened,
  MicClosed() => EventKind.micClosed,
  MicAnswered() => EventKind.micAnswered,
  MicClosing() => EventKind.micClosing,
  MicDiscarded() => EventKind.micDiscarded,
  BeadTapped() => EventKind.beadTapped,
  PauseTapped() => EventKind.pauseTapped,
  TheHeldPartReturns() => EventKind.theHeldPartReturns,
  GestureSilenced() => EventKind.gestureSilenced,
  Interrupted() => EventKind.interrupted,
  GestureStarted() => EventKind.gestureStarted,
  GestureEnded() => EventKind.gestureEnded,
  NothingReplayed() => EventKind.nothingReplayed,
  LineNotSaid() => EventKind.lineNotSaid,
  StepLeft() => EventKind.stepLeft,
  LeftThePassage() => EventKind.leftThePassage,
  TheSessionIsGone() => EventKind.sessionGone,
  ThePassageClosed() => EventKind.passageClosed,
  TurnGivenUp() => EventKind.turnGivenUp,
  LookFound() => EventKind.lookFound,
  LookEmpty() => EventKind.lookEmpty,
  TheOpeningMissed() => EventKind.theOpeningMissed,
  TheRoomRefused() => EventKind.theRoomRefused,
  ThePassageCannotOpen() => EventKind.thePassageCannotOpen,
  TheTellingCameBackEmpty() => EventKind.theTellingCameBackEmpty,
  TheVerdictAsked() => EventKind.theVerdictAsked,
  TurnSent() => EventKind.turnSent,
  TurnAnswered() => EventKind.turnAnswered,
  TheRefusalPassed() => EventKind.theRefusalPassed,
  TheCallWasRefused() => EventKind.theCallWasRefused,
  TheCallMetAClosedPassage() => EventKind.theCallMetAClosedPassage,
  TurnFailed() => EventKind.turnFailed,
  TheChoiceOpened() => EventKind.theChoiceOpened,
  PassageChosen() => EventKind.passageChosen,
  TheRehearsalOpened() => EventKind.theRehearsalOpened,
  TheBackTranslationOpened() => EventKind.theBackTranslationOpened,
  TheNecklaceClosed() => EventKind.theNecklaceClosed,
  TheRoomStartedOver() => EventKind.theRoomStartedOver,
  ThePanoramaChosen() => EventKind.thePanoramaChosen,
};

bool _theWorldAllows(EventKind kind, World world) => switch (kind) {
  EventKind.watchFired => world.watchArmed,
  EventKind.retryFired => world.retryArmed,
  EventKind.theCallLanded => world.callOutstanding,
  EventKind.playerOpened ||
  EventKind.playerEnded ||
  EventKind.playerFailed => world.playerBusy,
  EventKind.micClosed ||
  EventKind.micAnswered ||
  EventKind.micClosing => world.micOpen,
  EventKind.lookFound || EventKind.lookEmpty => world.looking,
  EventKind.sessionRead ||
  EventKind.roomRaisedAHalt ||
  EventKind.theAnswerWarned ||
  EventKind.longPress ||
  EventKind.networkFailedAt ||
  EventKind.networkReturned ||
  EventKind.theRoomAnswered ||
  EventKind.outboxChanged ||
  EventKind.lineArrived ||
  EventKind.micOpened ||
  EventKind.micDiscarded ||
  EventKind.beadTapped ||
  EventKind.pauseTapped ||
  EventKind.theHeldPartReturns ||
  EventKind.gestureSilenced ||
  EventKind.interrupted ||
  EventKind.gestureStarted ||
  EventKind.gestureEnded ||
  EventKind.nothingReplayed ||
  EventKind.lineNotSaid ||
  EventKind.stepLeft ||
  EventKind.leftThePassage ||
  EventKind.sessionGone ||
  EventKind.passageClosed ||
  EventKind.turnGivenUp ||
  EventKind.theOpeningMissed ||
  EventKind.theRoomRefused ||
  EventKind.thePassageCannotOpen ||
  EventKind.theTellingCameBackEmpty ||
  EventKind.theVerdictAsked ||
  EventKind.turnSent ||
  EventKind.turnAnswered ||
  EventKind.theRefusalPassed ||
  EventKind.theCallWasRefused ||
  EventKind.theCallMetAClosedPassage ||
  EventKind.turnFailed ||
  EventKind.theChoiceOpened ||
  EventKind.passageChosen ||
  EventKind.theRehearsalOpened ||
  EventKind.theBackTranslationOpened ||
  EventKind.theNecklaceClosed ||
  EventKind.theRoomStartedOver ||
  EventKind.thePanoramaChosen => true,
};

Source _drawASource(Random random) => switch (random.nextInt(4)) {
  0 => Source.guide,
  1 => Source.take('parte-${random.nextInt(2)}.m4a'),
  2 => Source.stretch('trecho-${random.nextInt(2)}'),
  _ => Source.reply('resposta-${random.nextInt(2)}'),
};

Sound _drawASound(Random random) => random.nextBool()
    ? PartSound(
        random.nextInt(2),
        'parte-${random.nextInt(2)}.m4a',
        from: Duration(seconds: random.nextInt(20)),
      )
    : StretchSound(
        'parte-${random.nextInt(2)}.m4a',
        named: 'trecho-${random.nextInt(2)}',
        from: Duration(seconds: random.nextInt(10)),
        to: Duration(seconds: 10 + random.nextInt(10)),
        telling: random.nextBool(),
      );

/// Unstamped is the generation the machine holds; -1 is always an older one.
MicAnswered _drawAMicAnswer(Random random) {
  final answer = MicAnswer.values[random.nextInt(MicAnswer.values.length)];
  final closed = answer == MicAnswer.closed;
  final failed = closed && random.nextInt(4) == 0;
  return MicAnswered(
    answer,
    take: closed && !failed && random.nextBool() ? 'tomada.m4a' : null,
    because: failed ? Exception('the recorder failed to stop') : null,
    generation: random.nextInt(4) == 0 ? -1 : null,
  );
}

MachineEvent _draw(EventKind kind, World world, Random random) =>
    switch (kind) {
      EventKind.sessionRead => _drawARead(world, random),
      EventKind.roomRaisedAHalt => RoomRaisedAHalt(
        sounding: _drawKept(random),
        callsForAPerson: random.nextBool(),
      ),
      EventKind.theCallLanded => const TheCallLanded(),
      EventKind.theAnswerWarned => const TheAnswerWarned(),
      EventKind.longPress => LongPress(somebodyToAsk: random.nextBool()),
      EventKind.watchFired => const WatchFired(),
      EventKind.networkFailedAt => NetworkFailedAt(
        world.probing && random.nextBool()
            ? Door.probe
            : Door.values[random.nextInt(Door.values.length)],
        why: RoomReach.values[1 + random.nextInt(RoomReach.values.length - 1)],
      ),
      EventKind.networkReturned => const NetworkReturned(),
      EventKind.retryFired => const RetryFired(),
      EventKind.theRoomAnswered => const TheRoomAnswered(),
      EventKind.outboxChanged => OutboxChanged({
        for (var part = 0, parts = random.nextInt(3); part < parts; part++)
          'parte-$part':
              PartFact.values[random.nextInt(PartFact.values.length)],
      }, due: Duration(seconds: random.nextInt(3) * 30)),
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
      EventKind.micClosed => const MicClosed(),
      EventKind.micAnswered => _drawAMicAnswer(random),
      EventKind.micClosing => const MicClosing(),
      EventKind.micDiscarded => const MicDiscarded(),
      EventKind.beadTapped => BeadTapped([
        for (var i = 0; i <= random.nextInt(3); i++) _drawASound(random),
      ]),
      EventKind.pauseTapped => const PauseTapped(),
      EventKind.theHeldPartReturns => TheHeldPartReturns(
        Paused(
          PartSound(
            random.nextInt(2),
            'parte-${random.nextInt(2)}.m4a',
            from: Duration(seconds: random.nextInt(20)),
          ),
          started: false,
          opened: false,
        ),
      ),
      EventKind.gestureSilenced => GestureSilenced(
        keepingTheHold: random.nextBool(),
      ),
      EventKind.interrupted => Interrupted(
        take: 'conversa-${random.nextInt(3)}',
        cut: CutPoint(
          Duration(milliseconds: random.nextInt(9000)),
          of: random.nextBool()
              ? Duration(milliseconds: 9000 + random.nextInt(9000))
              : null,
        ),
      ),
      EventKind.gestureStarted => GestureStarted(random.nextInt(3)),
      EventKind.gestureEnded => GestureEnded(random.nextInt(3)),
      EventKind.nothingReplayed => const NothingReplayed(),
      EventKind.lineNotSaid => LineNotSaid(
        Line(
          LineKind.values[random.nextInt(LineKind.values.length)],
          random.nextInt(1 << 20),
          source: _drawASource(random),
        ),
      ),
      EventKind.stepLeft => const StepLeft(),
      EventKind.leftThePassage => const LeftThePassage(),
      EventKind.sessionGone => const TheSessionIsGone(),
      EventKind.passageClosed => const ThePassageClosed(),
      EventKind.turnGivenUp => TurnGivenUp(
        _drawATurn(random),
        sounding: _drawKept(random),
      ),
      EventKind.lookFound => LookFound(
        _drawATurn(random),
        TurnResult(
          sessionId: 'sessao-1',
          audioUrl: '/voice/turn-${random.nextInt(3)}',
          fixedLine: '',
          transcript: '',
          peerCue: false,
          usedFailSafe: false,
          degraded: false,
          coverage: null,
          done: false,
          turnId: 'turn-${random.nextInt(3)}',
        ),
      ),
      EventKind.lookEmpty => LookEmpty(sounding: _drawKept(random)),
      EventKind.theOpeningMissed => const TheOpeningMissed(),
      EventKind.theRoomRefused => TheRoomRefused(
        third: random.nextBool(),
        sounding: _drawKept(random),
      ),
      EventKind.thePassageCannotOpen => const ThePassageCannotOpen(),
      EventKind.theTellingCameBackEmpty => const TheTellingCameBackEmpty(),
      EventKind.theVerdictAsked => const TheVerdictAsked(),
      EventKind.turnSent => TurnSent(_drawATurn(random)),
      EventKind.turnAnswered => TurnAnswered(_drawATurn(random)),
      EventKind.theRefusalPassed => const TheRefusalPassed(),
      EventKind.theCallWasRefused => const TheCallWasRefused(),
      EventKind.theCallMetAClosedPassage => const TheCallMetAClosedPassage(),
      EventKind.turnFailed => TurnFailed(_drawATurn(random)),
      EventKind.theChoiceOpened => const TheChoiceOpened(),
      EventKind.passageChosen => const PassageChosen(),
      EventKind.theRehearsalOpened => const TheRehearsalOpened(),
      EventKind.theBackTranslationOpened => const TheBackTranslationOpened(),
      EventKind.theNecklaceClosed => const TheNecklaceClosed(),
      EventKind.theRoomStartedOver => const TheRoomStartedOver(),
      EventKind.thePanoramaChosen => const ThePanoramaChosen(),
    };

Turn _drawATurn(Random random) => Turn('sessao-1', 'turn-${random.nextInt(3)}');

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

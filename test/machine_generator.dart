import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/cut_point.dart';
import 'package:internalization_room/features/sala/domain/failure_policy.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/left_entry.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/refusal_code.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/turn_result.dart';

class World {
  final bool watchArmed;
  final bool callOutstanding;
  final bool serverHoldsAWarning;
  final bool playerBusy;
  final bool micOpen;
  final MicOwner? micOwner;
  final bool looking;

  const World({
    this.watchArmed = true,
    this.callOutstanding = false,
    this.serverHoldsAWarning = false,
    this.playerBusy = false,
    this.micOpen = false,
    this.micOwner,
    this.looking = false,
  });

  World after(MachineEvent event, List<Effect> effects) {
    var armed = watchArmed && event is! WatchFired;
    var calling = callOutstanding;
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
            event.generation != theOlderGeneration &&
            event.answer != MicAnswer.started &&
            event.because == null &&
            (event.answer != MicAnswer.closed ||
                event.owner == null ||
                event.owner == micOwner));
    var owner = micOwner;
    var looks =
        looking &&
        event is! LookFound &&
        event is! RoomRaisedAHalt &&
        event is! TheOpeningMissed &&
        event is! TheSceneTurnFoundNothing;
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
        case OpenTheMic(owner: final opened):
          mic = true;
          owner = opened;
        case CloseAndDiscardTheMic():
          mic = false;
        case LookAtTheSession() || LookAgain():
          looks = true;
        default:
          break;
      }
    }
    return World(
      watchArmed: armed,
      callOutstanding: calling,
      playerBusy: busy,
      micOpen: mic,
      micOwner: mic ? owner : null,
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
  TheOpening() => 'TheOpening',
  TheLineSaidAgain() => 'TheLineSaidAgain',
};

String describeHalt(Halt halt) => switch (halt) {
  NoHalt() => 'NoHalt',
  Warning() => 'Warning',
  Blocking(:final warningBeneath, :final callsNobody) =>
    'Blocking(warningBeneath: $warningBeneath, callsNobody: $callsNobody)',
};

String describeEvent(MachineEvent event) => switch (event) {
  SessionRead(:final snapshot) =>
    'SessionRead(status: ${snapshot.status}, halt: ${snapshot.halt.name})',
  RoomRaisedAHalt(:final callsForAPerson) =>
    'RoomRaisedAHalt(callsForAPerson: $callsForAPerson)',
  TheAnswerWarned() => 'TheAnswerWarned',
  TeamTapped() => 'TeamTapped',
  WatchFired() => 'WatchFired',
  NetworkFailedAt(:final door) => 'NetworkFailedAt(${door.name})',
  ATakeLeft(:final take) =>
    'ATakeLeft(${take.row}, ${take.keep.kind}, ${take.keep.session}, '
        '${take.keep.scope})',
  ATakeSettled(:final row) => 'ATakeSettled($row)',
  AKeepBegan(:final part) => 'AKeepBegan(${part.session}, ${part.scope})',
  AKeepEnded(:final part, :final row) =>
    'AKeepEnded(${part.session}, ${part.scope}, $row)',
  TheTapSent(:final part, :final row) =>
    'TheTapSent(${part.session}, ${part.scope}, $row)',
  StopTapped(:final keep) =>
    'StopTapped(${keep.session}, ${keep.kind}, ${keep.scope})',
  TheRoomAnswered() => 'TheRoomAnswered',
  OutboxChanged(:final parts) =>
    'OutboxChanged(${parts.entries.map((part) => '${part.key}: ${part.value.name}').join(', ')})',
  LineArrived(:final line) => 'LineArrived(${describeLine(line)})',
  PlayerOpened() => 'PlayerOpened',
  PlayerEnded() => 'PlayerEnded',
  PlayerFailed(:final source) => 'PlayerFailed(${source.key})',
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
  LineNotSaid(:final line) => 'LineNotSaid(${describeLine(line)})',
  StepLeft(:final ended) => 'StepLeft(ended: $ended)',
  LeftThePassage() => 'LeftThePassage',
  TheSessionIsGone() => 'TheSessionIsGone',
  ThePassageClosed() => 'ThePassageClosed',
  TurnGivenUp(:final turn, :final sounding) =>
    'TurnGivenUp(${turn.turnId}, ${describeKept(sounding)})',
  LookFound(:final turn) => 'LookFound(${turn.turnId})',
  LookPending(:final turn, :final sounding) =>
    'LookPending(${turn.turnId}, ${describeKept(sounding)})',
  TurnSent(:final turn, :final keeps) =>
    'TurnSent(${turn.turnId}, ${describeKept(keeps)})',
  TurnAnswered(:final turn) => 'TurnAnswered(${turn.turnId})',
  TurnFailed(:final turn) => 'TurnFailed(${turn.turnId})',
  TheRefusalPassed() => 'TheRefusalPassed',
  TheHandFailed() => 'TheHandFailed',
  TheScenesMissed() => 'TheScenesMissed',
  TheSceneRehearsalsListed(:final listed) =>
    'TheSceneRehearsalsListed(${listed.length})',
  TheSceneDoorFailed(:final readAgain) =>
    'TheSceneDoorFailed(readAgain: $readAgain)',
  TheSceneDiskFailed() => 'TheSceneDiskFailed',
  TheSceneWentAlready() => 'TheSceneWentAlready',
  TheSceneSendRefused() => 'TheSceneSendRefused',
  TheCallWasRefused() => 'TheCallWasRefused',
  TheCallMetAClosedPassage() => 'TheCallMetAClosedPassage',
  LookEmpty(:final turn, :final sounding, :final theWaitRanOut) =>
    'LookEmpty(${turn.turnId}, ${describeKept(sounding)}'
        '${theWaitRanOut ? ', the wait ran out' : ''})',
  LookFailed(:final turn, :final result, :final sounding) =>
    'LookFailed(${turn.turnId}, ${result.runtimeType}, '
        '${describeKept(sounding)})',
  TheOpeningMissed() => 'TheOpeningMissed',
  TheReplyFailedToLoad(:final load, :final because, :final sounding) =>
    'TheReplyFailedToLoad(load $load, ${because.runtimeType}, '
        '${describeKept(sounding)})',
  ThePassageCannotOpen() => 'ThePassageCannotOpen',
  TheTellingCameBackEmpty(:final readAgain) =>
    'TheTellingCameBackEmpty(readAgain: $readAgain)',
  TheStepFailed() => 'TheStepFailed',
  TheResumeFailed() => 'TheResumeFailed',
  TheSceneTurnFoundNothing() => 'TheSceneTurnFoundNothing',
  TheVerdictAsked() => 'TheVerdictAsked',
  TheTranslationStartedOver() => 'TheTranslationStartedOver',
  TheChoiceOpened() => 'TheChoiceOpened',
  PassageChosen() => 'PassageChosen',
  TheRehearsalOpened() => 'TheRehearsalOpened',
  ThePlanOpened() => 'ThePlanOpened',
  TheBackTranslationOpened() => 'TheBackTranslationOpened',
  TheRoomStartedOver() => 'TheRoomStartedOver',
  ThePanoramaChosen(:final id) => 'ThePanoramaChosen($id)',
  TheSceneRehearsalOpened() => 'TheSceneRehearsalOpened',
  TheSceneRehearsalLeft() => 'TheSceneRehearsalLeft',
  TheExternalCheckOpened(:final version) => 'TheExternalCheckOpened($version)',
  TheExternalCheckLeft() => 'TheExternalCheckLeft',
  TheRecordingLeft() => 'TheRecordingLeft',
  TheLanguageChosen() => 'TheLanguageChosen',
  ThePanoramaAsked(:final id, :final language) =>
    'ThePanoramaAsked($id, $language)',
  TheSessionOpened(:final session, :final generation) =>
    'TheSessionOpened($session, generation: $generation)',
  ThePanoramaFound(:final session, :final opened, :final generation) =>
    'ThePanoramaFound($session, opened: $opened, generation: $generation)',
  TheSessionLetGo(:final session) => 'TheSessionLetGo($session)',
  TheWayBackTaken(:final left) =>
    'TheWayBackTaken(${left.panorama ? 'Panorama' : 'passage'} ${left.pericope}, '
        'session: ${left.session}, said: ${left.said})',
  TheRehearsalWeighed(:final everySceneHasItsPart, :final everyPartIsSent) =>
    'TheRehearsalWeighed($everySceneHasItsPart, $everyPartIsSent)',
  TheLeftPassageReturns(:final session, :final warned) =>
    'TheLeftPassageReturns($session, warned: $warned)',
  TheEntryWaits(:final left) =>
    'TheEntryWaits(${left.panorama ? 'Panorama' : 'passage'} ${left.pericope}, '
        'session: ${left.session}, said: ${left.said})',
  TheOpenBroughtNoSession() => 'TheOpenBroughtNoSession',
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
    '${machine.parts.containsValue(PartFact.pending) ? 'a part pending' : 'nothing pending'}';

String describeEffect(Effect effect) => switch (effect) {
  PlayLine(:final line) => 'PlayLine(${describeLine(line)})',
  PlayPart(:final part) => 'PlayPart(${describeSound(part)})',
  PlayStretch(:final stretch) => 'PlayStretch(${describeSound(stretch)})',
  OpenTheMic(:final owner) => 'OpenTheMic(${owner.name})',
  _ => effect.runtimeType.toString(),
};

Kept _drawKept(Random random) => switch (random.nextInt(4)) {
  0 => const NothingKept(),
  1 => const ThePart(),
  2 => TheOpening(),
  _ => const TheLineSaidAgain(),
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
);

enum EventKind {
  sessionRead,
  roomRaisedAHalt,
  theAnswerWarned,
  teamTapped,
  watchFired,
  networkFailedAt,
  aTakeLeft,
  aTakeSettled,
  aKeepBegan,
  aKeepEnded,
  theTapSent,
  stopTapped,
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
  lineNotSaid,
  stepLeft,
  leftThePassage,
  sessionGone,
  passageClosed,
  turnGivenUp,
  lookFound,
  lookEmpty,
  lookFailed,
  lookPending,
  theOpeningMissed,
  theReplyFailedToLoad,
  thePassageCannotOpen,
  theTellingCameBackEmpty,
  theStepFailed,
  theResumeFailed,
  theSceneTurnFoundNothing,
  theVerdictAsked,
  theTranslationStartedOver,
  turnSent,
  turnAnswered,
  theRefusalPassed,
  theHandFailed,
  theScenesMissed,
  theSceneDoorFailed,
  theSceneDiskFailed,
  theSceneWentAlready,
  theSceneSendRefused,
  theSceneRehearsalsListed,
  theCallWasRefused,
  theCallMetAClosedPassage,
  turnFailed,
  theChoiceOpened,
  passageChosen,
  theRehearsalOpened,
  thePlanOpened,
  theBackTranslationOpened,
  theRoomStartedOver,
  thePanoramaChosen,
  theSceneRehearsalOpened,
  theSceneRehearsalLeft,
  theExternalCheckOpened,
  theExternalCheckLeft,
  theRecordingLeft,
  theLanguageChosen,
  thePanoramaAsked,
  theSessionOpened,
  thePanoramaFound,
  theSessionLetGo,
  theWayBackTaken,
  theRehearsalWeighed,
  theLeftPassageReturns,
  theEntryWaits,
  theOpenBroughtNoSession,
}

EventKind kindOf(MachineEvent event) => switch (event) {
  SessionRead() => EventKind.sessionRead,
  RoomRaisedAHalt() => EventKind.roomRaisedAHalt,
  TheAnswerWarned() => EventKind.theAnswerWarned,
  TeamTapped() => EventKind.teamTapped,
  WatchFired() => EventKind.watchFired,
  NetworkFailedAt() => EventKind.networkFailedAt,
  ATakeLeft() => EventKind.aTakeLeft,
  ATakeSettled() => EventKind.aTakeSettled,
  AKeepBegan() => EventKind.aKeepBegan,
  AKeepEnded() => EventKind.aKeepEnded,
  TheTapSent() => EventKind.theTapSent,
  StopTapped() => EventKind.stopTapped,
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
  LineNotSaid() => EventKind.lineNotSaid,
  StepLeft() => EventKind.stepLeft,
  LeftThePassage() => EventKind.leftThePassage,
  TheSessionIsGone() => EventKind.sessionGone,
  ThePassageClosed() => EventKind.passageClosed,
  TurnGivenUp() => EventKind.turnGivenUp,
  LookFound() => EventKind.lookFound,
  LookEmpty() => EventKind.lookEmpty,
  LookFailed() => EventKind.lookFailed,
  LookPending() => EventKind.lookPending,
  TheOpeningMissed() => EventKind.theOpeningMissed,
  TheReplyFailedToLoad() => EventKind.theReplyFailedToLoad,
  ThePassageCannotOpen() => EventKind.thePassageCannotOpen,
  TheTellingCameBackEmpty() => EventKind.theTellingCameBackEmpty,
  TheStepFailed() => EventKind.theStepFailed,
  TheResumeFailed() => EventKind.theResumeFailed,
  TheSceneTurnFoundNothing() => EventKind.theSceneTurnFoundNothing,
  TheVerdictAsked() => EventKind.theVerdictAsked,
  TheTranslationStartedOver() => EventKind.theTranslationStartedOver,
  TurnSent() => EventKind.turnSent,
  TurnAnswered() => EventKind.turnAnswered,
  TheRefusalPassed() => EventKind.theRefusalPassed,
  TheHandFailed() => EventKind.theHandFailed,
  TheScenesMissed() => EventKind.theScenesMissed,
  TheSceneDoorFailed() => EventKind.theSceneDoorFailed,
  TheSceneDiskFailed() => EventKind.theSceneDiskFailed,
  TheSceneWentAlready() => EventKind.theSceneWentAlready,
  TheSceneSendRefused() => EventKind.theSceneSendRefused,
  TheSceneRehearsalsListed() => EventKind.theSceneRehearsalsListed,
  TheCallWasRefused() => EventKind.theCallWasRefused,
  TheCallMetAClosedPassage() => EventKind.theCallMetAClosedPassage,
  TurnFailed() => EventKind.turnFailed,
  TheChoiceOpened() => EventKind.theChoiceOpened,
  PassageChosen() => EventKind.passageChosen,
  TheRehearsalOpened() => EventKind.theRehearsalOpened,
  ThePlanOpened() => EventKind.thePlanOpened,
  TheBackTranslationOpened() => EventKind.theBackTranslationOpened,
  TheRoomStartedOver() => EventKind.theRoomStartedOver,
  ThePanoramaChosen() => EventKind.thePanoramaChosen,
  TheSceneRehearsalOpened() => EventKind.theSceneRehearsalOpened,
  TheSceneRehearsalLeft() => EventKind.theSceneRehearsalLeft,
  TheExternalCheckOpened() => EventKind.theExternalCheckOpened,
  TheExternalCheckLeft() => EventKind.theExternalCheckLeft,
  TheRecordingLeft() => EventKind.theRecordingLeft,
  TheLanguageChosen() => EventKind.theLanguageChosen,
  ThePanoramaAsked() => EventKind.thePanoramaAsked,
  TheSessionOpened() => EventKind.theSessionOpened,
  ThePanoramaFound() => EventKind.thePanoramaFound,
  TheSessionLetGo() => EventKind.theSessionLetGo,
  TheWayBackTaken() => EventKind.theWayBackTaken,
  TheLeftPassageReturns() => EventKind.theLeftPassageReturns,
  TheEntryWaits() => EventKind.theEntryWaits,
  TheOpenBroughtNoSession() => EventKind.theOpenBroughtNoSession,
  TheRehearsalWeighed() => EventKind.theRehearsalWeighed,
};

bool _theWorldAllows(EventKind kind, World world) => switch (kind) {
  EventKind.watchFired => world.watchArmed,
  EventKind.playerOpened ||
  EventKind.playerEnded ||
  EventKind.playerFailed => world.playerBusy,
  EventKind.micClosed || EventKind.micClosing => world.micOpen,
  EventKind.micAnswered => true,
  EventKind.lookFound ||
  EventKind.lookEmpty ||
  EventKind.lookFailed ||
  EventKind.lookPending => world.looking,
  EventKind.sessionRead ||
  EventKind.roomRaisedAHalt ||
  EventKind.theAnswerWarned ||
  EventKind.teamTapped ||
  EventKind.networkFailedAt ||
  EventKind.theRoomAnswered ||
  EventKind.outboxChanged ||
  EventKind.aTakeLeft ||
  EventKind.aTakeSettled ||
  EventKind.aKeepBegan ||
  EventKind.aKeepEnded ||
  EventKind.theTapSent ||
  EventKind.stopTapped ||
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
  EventKind.lineNotSaid ||
  EventKind.stepLeft ||
  EventKind.leftThePassage ||
  EventKind.sessionGone ||
  EventKind.passageClosed ||
  EventKind.turnGivenUp ||
  EventKind.theOpeningMissed ||
  EventKind.theReplyFailedToLoad ||
  EventKind.thePassageCannotOpen ||
  EventKind.theTellingCameBackEmpty ||
  EventKind.theStepFailed ||
  EventKind.theResumeFailed ||
  EventKind.theSceneTurnFoundNothing ||
  EventKind.theVerdictAsked ||
  EventKind.theTranslationStartedOver ||
  EventKind.turnSent ||
  EventKind.turnAnswered ||
  EventKind.theRefusalPassed ||
  EventKind.theHandFailed ||
  EventKind.theScenesMissed ||
  EventKind.theSceneDoorFailed ||
  EventKind.theSceneDiskFailed ||
  EventKind.theSceneWentAlready ||
  EventKind.theSceneSendRefused ||
  EventKind.theSceneRehearsalsListed ||
  EventKind.theCallWasRefused ||
  EventKind.theCallMetAClosedPassage ||
  EventKind.turnFailed ||
  EventKind.theChoiceOpened ||
  EventKind.passageChosen ||
  EventKind.theRehearsalOpened ||
  EventKind.thePlanOpened ||
  EventKind.theBackTranslationOpened ||
  EventKind.theRoomStartedOver ||
  EventKind.thePanoramaChosen ||
  EventKind.theSceneRehearsalOpened ||
  EventKind.theSceneRehearsalLeft ||
  EventKind.theExternalCheckOpened ||
  EventKind.theExternalCheckLeft ||
  EventKind.theRecordingLeft => true,
  EventKind.theLanguageChosen ||
  EventKind.thePanoramaAsked ||
  EventKind.theSessionOpened ||
  EventKind.thePanoramaFound ||
  EventKind.theSessionLetGo ||
  EventKind.theWayBackTaken ||
  EventKind.theRehearsalWeighed ||
  EventKind.theLeftPassageReturns ||
  EventKind.theEntryWaits ||
  EventKind.theOpenBroughtNoSession => true,
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

/// The stamp the generator gives an answer that is always from an older generation.
const theOlderGeneration = -1;

/// Unstamped is the generation the machine holds; [theOlderGeneration] is always an older one.
MicAnswered _drawAMicAnswer(Random random) {
  final answer = MicAnswer.values[random.nextInt(MicAnswer.values.length)];
  final closed = answer == MicAnswer.closed;
  final failed = closed && random.nextInt(4) == 0;
  return MicAnswered(
    answer,
    take: closed && !failed && random.nextBool() ? 'tomada.m4a' : null,
    because: failed ? Exception('the recorder failed to stop') : null,
    owner: random.nextBool()
        ? MicOwner.values[random.nextInt(MicOwner.values.length)]
        : null,
    generation: random.nextInt(4) == 0 ? theOlderGeneration : null,
  );
}

MachineEvent _draw(
  EventKind kind,
  World world,
  Random random,
) => switch (kind) {
  EventKind.sessionRead => _drawARead(world, random),
  EventKind.roomRaisedAHalt => RoomRaisedAHalt(
    callsForAPerson: random.nextBool(),
  ),
  EventKind.theAnswerWarned => const TheAnswerWarned(),
  EventKind.teamTapped => const TeamTapped(),
  EventKind.watchFired => const WatchFired(),
  EventKind.networkFailedAt => NetworkFailedAt(
    Door.values[random.nextInt(Door.values.length)],
  ),
  EventKind.aTakeLeft => ATakeLeft(
    TakeInTheAir(
      row: 'linha-${random.nextInt(3)}',
      keep: (
        session: _drawASession(random),
        kind: const ['ensaio', 'cena'][random.nextInt(2)],
        scope: 'parte-${random.nextInt(3) + 1}',
        since: DateTime.utc(2026, 10, 22, 9, 0, random.nextInt(60)),
      ),
    ),
  ),
  EventKind.aTakeSettled => ATakeSettled('linha-${random.nextInt(3)}'),
  EventKind.aKeepBegan => AKeepBegan((
    session: _drawASession(random),
    scope: _drawAScope(random),
  )),
  EventKind.aKeepEnded => AKeepEnded((
    session: _drawASession(random),
    scope: _drawAScope(random),
  ), row: random.nextBool() ? 'linha-${random.nextInt(3)}' : null),
  EventKind.theTapSent => TheTapSent((
    session: _drawASession(random),
    scope: _drawAScope(random),
  ), 'linha-${random.nextInt(3)}'),
  EventKind.stopTapped => StopTapped((
    session: _drawASession(random),
    kind: const ['ensaio', 'cena'][random.nextInt(2)],
    scope: 'parte-${random.nextInt(3) + 1}',
    since: DateTime.utc(2026, 10, 22, 9, 0, random.nextInt(60)),
  )),
  EventKind.theRoomAnswered => const TheRoomAnswered(),
  EventKind.outboxChanged => OutboxChanged({
    for (var part = 0, parts = random.nextInt(3); part < parts; part++)
      'parte-$part': PartFact.values[random.nextInt(PartFact.values.length)],
  }),
  EventKind.lineArrived => LineArrived(
    Line(
      LineKind.values[random.nextInt(LineKind.values.length)],
      random.nextInt(1 << 20),
      source: _drawASource(random),
    ),
  ),
  EventKind.playerOpened => const PlayerOpened(),
  EventKind.playerEnded => const PlayerEnded(),
  EventKind.playerFailed => PlayerFailed(_drawASource(random)),
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
  EventKind.lineNotSaid => LineNotSaid(
    Line(
      LineKind.values[random.nextInt(LineKind.values.length)],
      random.nextInt(1 << 20),
      source: _drawASource(random),
    ),
  ),
  EventKind.stepLeft => StepLeft(ended: random.nextBool()),
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
      degraded: false,
      coverage: null,
      done: false,
      turnId: 'turn-${random.nextInt(3)}',
    ),
  ),
  EventKind.lookEmpty => LookEmpty(
    _drawATurn(random),
    sounding: _drawKept(random),
    theWaitRanOut: random.nextInt(4) == 0,
  ),
  EventKind.lookFailed => LookFailed(
    _drawATurn(random),
    random.nextBool()
        ? const RoomNetworkFailed()
        : const RoomRefused(RefusalCode.unauthorized),
    sounding: _drawKept(random),
  ),
  EventKind.lookPending => LookPending(
    _drawATurn(random),
    sounding: _drawKept(random),
  ),
  EventKind.theOpeningMissed => const TheOpeningMissed(),
  EventKind.theReplyFailedToLoad => TheReplyFailedToLoad(
    1 + random.nextInt(2),
    answered: _unheard,
    because: random.nextBool() ? null : const RoomNetworkFailed(),
    sounding: _drawKept(random),
  ),
  EventKind.thePassageCannotOpen => const ThePassageCannotOpen(),
  EventKind.theTellingCameBackEmpty => TheTellingCameBackEmpty(
    readAgain: random.nextBool(),
  ),
  EventKind.theStepFailed => const TheStepFailed(),
  EventKind.theResumeFailed => const TheResumeFailed(),
  EventKind.theSceneTurnFoundNothing => const TheSceneTurnFoundNothing(),
  EventKind.theVerdictAsked => const TheVerdictAsked(),
  EventKind.theTranslationStartedOver => const TheTranslationStartedOver(),
  EventKind.turnSent => TurnSent(
    _drawATurn(random),
    keeps: random.nextBool() ? const TheLineSaidAgain() : const NothingKept(),
  ),
  EventKind.turnAnswered => TurnAnswered(_drawATurn(random)),
  EventKind.theRefusalPassed => const TheRefusalPassed(),
  EventKind.theHandFailed => const TheHandFailed(),
  EventKind.theScenesMissed => const TheScenesMissed(),
  EventKind.theSceneRehearsalsListed => const TheSceneRehearsalsListed([]),
  EventKind.theSceneDoorFailed => TheSceneDoorFailed(
    readAgain: random.nextBool(),
  ),
  EventKind.theSceneDiskFailed => const TheSceneDiskFailed(),
  EventKind.theSceneWentAlready => const TheSceneWentAlready(),
  EventKind.theSceneSendRefused => const TheSceneSendRefused(),
  EventKind.theCallWasRefused => const TheCallWasRefused(),
  EventKind.theCallMetAClosedPassage => const TheCallMetAClosedPassage(),
  EventKind.turnFailed => TurnFailed(_drawATurn(random)),
  EventKind.theChoiceOpened => const TheChoiceOpened(),
  EventKind.passageChosen => const PassageChosen(),
  EventKind.theRehearsalOpened => const TheRehearsalOpened(),
  EventKind.thePlanOpened => const ThePlanOpened(),
  EventKind.theBackTranslationOpened => const TheBackTranslationOpened(),
  EventKind.theRoomStartedOver => const TheRoomStartedOver(),
  EventKind.thePanoramaChosen => ThePanoramaChosen(
    _servedPanoramas[random.nextInt(_servedPanoramas.length)],
  ),
  EventKind.theSceneRehearsalOpened => const TheSceneRehearsalOpened(),
  EventKind.theSceneRehearsalLeft => const TheSceneRehearsalLeft(),
  EventKind.theExternalCheckOpened => TheExternalCheckOpened(
    1 + random.nextInt(3),
  ),
  EventKind.theExternalCheckLeft => const TheExternalCheckLeft(),
  EventKind.theRecordingLeft => const TheRecordingLeft(),
  EventKind.theLanguageChosen => const TheLanguageChosen(),
  EventKind.thePanoramaAsked => ThePanoramaAsked(
    _drawAPanorama(random),
    _drawALanguage(random),
  ),
  EventKind.theSessionOpened => TheSessionOpened(
    _drawASession(random),
    generation: random.nextInt(4) == 0 ? theOlderGeneration : null,
  ),
  EventKind.thePanoramaFound => ThePanoramaFound(
    _drawASession(random),
    opened: random.nextBool(),
    generation: random.nextInt(4) == 0 ? theOlderGeneration : null,
  ),
  EventKind.theSessionLetGo => TheSessionLetGo(_drawASession(random)),
  EventKind.theWayBackTaken => TheWayBackTaken(_drawAnEntryLeft(random)),
  EventKind.theEntryWaits => TheEntryWaits(_drawAnEntryLeft(random)),
  EventKind.theOpenBroughtNoSession => const TheOpenBroughtNoSession(),
  EventKind.theLeftPassageReturns => TheLeftPassageReturns(
    _drawASession(random),
    warned: world.serverHoldsAWarning,
  ),
  EventKind.theRehearsalWeighed => TheRehearsalWeighed(
    everySceneHasItsPart: random.nextBool(),
    everyPartIsSent: random.nextBool(),
  ),
};

const _servedPanoramas = ['OV-Esther', 'OV-Jonah', 'OV-Ruth'];

String _drawAPanorama(Random random) =>
    _servedPanoramas[random.nextInt(_servedPanoramas.length)];

String _drawALanguage(Random random) => random.nextBool() ? 'pt' : 'en';

String _drawASession(Random random) => 'sessao-${random.nextInt(3)}';

String _drawAScope(Random random) => switch (random.nextInt(4)) {
  0 => 'passagem-inteira',
  final n => 'parte-$n',
};

/// A Panorama left said or unsaid, on a session the machine may or may not still hold,
/// or a passage left.
LeftEntry _drawAnEntryLeft(Random random) => random.nextBool()
    ? LeftEntry(
        pericope: _drawAPanorama(random),
        panorama: true,
        session: _drawASession(random),
        language: _drawALanguage(random),
        said: random.nextBool(),
      )
    : LeftEntry(
        book: 'Ruth',
        pericope: 'P01',
        session: _drawASession(random),
        language: _drawALanguage(random),
      );

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

void _unheard(bool loadAgain) {}

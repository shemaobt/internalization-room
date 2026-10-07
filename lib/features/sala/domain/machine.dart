import 'channel.dart';
import 'halt.dart';
import 'room_reach.dart';
import 'session_snapshot.dart';
import 'station.dart';
import 'turn_result.dart';

sealed class MachineEvent {
  const MachineEvent();
}

/// An event that answers work the machine asked for. [generation] is the generation the
/// answer was stamped with: the one a flow captured, where it checked it just before; the
/// current one everywhere else; and, for the Watch and the retry, the one at the moment
/// they fire, so that both survive a generation move. Null is read as the current one.
sealed class AnsweringEvent extends MachineEvent {
  final int? generation;

  const AnsweringEvent({this.generation});
}

final class SessionRead extends AnsweringEvent {
  final SessionSnapshot snapshot;
  final Kept sounding;
  final bool sentBeforeTheCallLanded;

  const SessionRead(
    this.snapshot, {
    this.sounding = const NothingKept(),
    this.sentBeforeTheCallLanded = false,
    super.generation,
  });
}

final class RoomRaisedAHalt extends AnsweringEvent {
  final Kept sounding;
  final bool callsForAPerson;

  const RoomRaisedAHalt({
    this.sounding = const NothingKept(),
    this.callsForAPerson = true,
    super.generation,
  });
}

final class TheCallLanded extends AnsweringEvent {
  const TheCallLanded({super.generation});
}

final class TheAnswerWarned extends AnsweringEvent {
  const TheAnswerWarned({super.generation});
}

final class LongPress extends MachineEvent {
  final bool somebodyToAsk;

  const LongPress({required this.somebodyToAsk});
}

final class WatchFired extends AnsweringEvent {
  const WatchFired({super.generation});
}

enum Reach { reachable, outOfReach }

enum Door {
  probe,
  outbox,
  watch,
  inbox,
  coverage,
  person,
  resume,
  reply,
  stretches,
  question,
  step,
}

enum PartFact { sent, pending, stranded }

final class NetworkFailedAt extends AnsweringEvent {
  final Door door;
  final RoomReach why;

  const NetworkFailedAt(
    this.door, {
    this.why = RoomReach.noNetwork,
    super.generation,
  });
}

final class NetworkReturned extends MachineEvent {
  const NetworkReturned();
}

final class RetryFired extends AnsweringEvent {
  const RetryFired({super.generation});
}

final class TheRoomAnswered extends AnsweringEvent {
  const TheRoomAnswered({super.generation});
}

final class OutboxChanged extends MachineEvent {
  final Map<String, PartFact> parts;
  final Duration due;

  const OutboxChanged(this.parts, {this.due = Duration.zero});
}

final class LineArrived extends AnsweringEvent {
  final Line line;
  final List<int> by;

  const LineArrived(this.line, {this.by = const [], super.generation});
}

final class PlayerOpened extends AnsweringEvent {
  const PlayerOpened({super.generation});
}

/// [line] or [sound] names what ended; neither is read as whatever is sounding.
final class PlayerEnded extends AnsweringEvent {
  final Line? line;
  final Sound? sound;

  const PlayerEnded({this.line, this.sound, super.generation});
}

final class PlayerFailed extends AnsweringEvent {
  final Source source;
  final Kept sounding;
  final Line? line;
  final Sound? sound;

  const PlayerFailed(
    this.source, {
    this.sounding = const NothingKept(),
    this.line,
    this.sound,
    super.generation,
  });
}

final class MicOpened extends AnsweringEvent {
  final MicOwner owner;
  final String take;

  const MicOpened(this.owner, {this.take = '', super.generation});
}

final class MicClosed extends AnsweringEvent {
  const MicClosed({super.generation});
}

/// How the recorder answered the microphone: [started], [refused] or [failed] for an
/// opening; [closed] with the take, or none; [discarded] by the room; [abandoned] when a
/// start that had started came back after the generation moved.
enum MicAnswer { started, refused, failed, closed, discarded, abandoned }

final class MicAnswered extends AnsweringEvent {
  final MicAnswer answer;
  final String? take;
  final Object? because;

  const MicAnswered(this.answer, {this.take, this.because, super.generation});
}

/// A gesture asks for its take: the Microphone stays open until the recorder answers.
final class MicClosing extends MachineEvent {
  const MicClosing();
}

final class MicDiscarded extends MachineEvent {
  const MicDiscarded();
}

final class BeadTapped extends MachineEvent {
  final List<Sound> sounds;
  final Paused? beneath;

  const BeadTapped(this.sounds, {this.beneath});
}

final class PauseTapped extends MachineEvent {
  const PauseTapped();
}

final class TheHeldPartReturns extends MachineEvent {
  final Paused held;

  const TheHeldPartReturns(this.held);
}

final class GestureSilenced extends MachineEvent {
  final bool keepingTheHold;

  const GestureSilenced({this.keepingTheHold = false});
}

final class GestureStarted extends MachineEvent {
  final int gesture;

  const GestureStarted(this.gesture);
}

final class GestureEnded extends MachineEvent {
  final int gesture;

  const GestureEnded(this.gesture);
}

final class NothingReplayed extends AnsweringEvent {
  const NothingReplayed({super.generation});
}

final class LineNotSaid extends AnsweringEvent {
  final Line line;
  final Exception? because;

  const LineNotSaid(this.line, {this.because, super.generation});
}

final class StepLeft extends MachineEvent {
  const StepLeft();
}

final class LeftThePassage extends MachineEvent {
  const LeftThePassage();
}

/// The team arrives at a Station; the Station held answers it after the cross-cutting
/// regions, and it is never stale.
sealed class StationEvent extends MachineEvent {
  const StationEvent();
}

final class TheChoiceOpened extends StationEvent {
  const TheChoiceOpened();
}

final class PassageChosen extends StationEvent {
  const PassageChosen();
}

final class TheRehearsalOpened extends StationEvent {
  const TheRehearsalOpened();
}

final class TheBackTranslationOpened extends StationEvent {
  const TheBackTranslationOpened();
}

final class TheNecklaceClosed extends StationEvent {
  const TheNecklaceClosed();
}

final class TheRoomStartedOver extends StationEvent {
  const TheRoomStartedOver();
}

final class ThePanoramaChosen extends StationEvent {
  const ThePanoramaChosen();
}

final class TheSessionIsGone extends AnsweringEvent {
  const TheSessionIsGone({super.generation});
}

final class ThePassageClosed extends AnsweringEvent {
  const ThePassageClosed({super.generation});
}

/// One turn: the session it was spoken into and the id it keeps.
final class Turn {
  final String sessionId;
  final String turnId;

  const Turn(this.sessionId, this.turnId);

  @override
  bool operator ==(Object other) =>
      other is Turn && other.sessionId == sessionId && other.turnId == turnId;

  @override
  int get hashCode => Object.hash(sessionId, turnId);
}

final class TurnSent extends MachineEvent {
  final Turn turn;

  const TurnSent(this.turn);
}

final class TurnAnswered extends AnsweringEvent {
  final Turn turn;

  const TurnAnswered(this.turn, {super.generation});
}

/// The turn came back refused or with its session gone: it is no longer in flight, and
/// what it was owed stays owed.
final class TurnFailed extends AnsweringEvent {
  final Turn turn;

  const TurnFailed(this.turn, {super.generation});
}

final class TurnGivenUp extends AnsweringEvent {
  final Turn turn;
  final Kept sounding;

  const TurnGivenUp(
    this.turn, {
    this.sounding = const NothingKept(),
    super.generation,
  });
}

final class LookFound extends AnsweringEvent {
  final Turn turn;
  final TurnResult reply;

  const LookFound(this.turn, this.reply, {super.generation});
}

final class LookEmpty extends AnsweringEvent {
  final Kept sounding;

  const LookEmpty({this.sounding = const NothingKept(), super.generation});
}

final class TheOpeningMissed extends AnsweringEvent {
  const TheOpeningMissed({super.generation});
}

final class TheRoomRefused extends AnsweringEvent {
  final bool third;
  final Kept sounding;

  const TheRoomRefused({
    this.third = false,
    this.sounding = const NothingKept(),
    super.generation,
  });
}

final class ThePassageCannotOpen extends AnsweringEvent {
  const ThePassageCannotOpen({super.generation});
}

final class TheRefusalPassed extends AnsweringEvent {
  const TheRefusalPassed({super.generation});
}

final class TheCallWasRefused extends AnsweringEvent {
  const TheCallWasRefused({super.generation});
}

final class TheCallMetAClosedPassage extends AnsweringEvent {
  const TheCallMetAClosedPassage({super.generation});
}

sealed class Effect {
  const Effect();
}

/// An effect whose work is the Station's own lifecycle, handed over to it through one
/// narrow callback (ENG-1444).
sealed class LifecycleHandOff extends Effect {
  const LifecycleHandOff();
}

final class SilenceTheRoom extends LifecycleHandOff {
  const SilenceTheRoom();
}

final class CloseAndDiscardTheMic extends Effect {
  const CloseAndDiscardTheMic();
}

final class CloseTheMic extends Effect {
  const CloseTheMic();
}

final class DiscardTheMic extends Effect {
  const DiscardTheMic();
}

final class ArmTheWatch extends Effect {
  const ArmTheWatch();
}

final class CallForAPerson extends Effect {
  const CallForAPerson();
}

final class StopCallingForAPerson extends Effect {
  const StopCallingForAPerson();
}

final class TellAPersonArrived extends Effect {
  const TellAPersonArrived();
}

final class ReadTheState extends Effect {
  const ReadTheState();
}

final class ReplayTheSound extends Effect {
  final Kept kept;

  const ReplayTheSound(this.kept);

  @override
  bool operator ==(Object other) =>
      other is ReplayTheSound && other.kept == kept;

  @override
  int get hashCode => kept.hashCode;
}

final class LetTheOpeningGo extends Effect {
  const LetTheOpeningGo();
}

final class PlayLine extends Effect {
  final Line line;

  const PlayLine(this.line);

  @override
  bool operator ==(Object other) => other is PlayLine && other.line == line;

  @override
  int get hashCode => line.hashCode;
}

final class PlayPart extends Effect {
  final PartSound part;

  const PlayPart(this.part);

  @override
  bool operator ==(Object other) => other is PlayPart && other.part == part;

  @override
  int get hashCode => part.hashCode;
}

final class PlayStretch extends Effect {
  final StretchSound stretch;

  const PlayStretch(this.stretch);

  @override
  bool operator ==(Object other) =>
      other is PlayStretch && other.stretch == stretch;

  @override
  int get hashCode => stretch.hashCode;
}

final class OpenTheMic extends Effect {
  final MicOwner owner;
  final String take;

  const OpenTheMic(this.owner, {this.take = ''});

  @override
  bool operator ==(Object other) =>
      other is OpenTheMic && other.owner == owner && other.take == take;

  @override
  int get hashCode => Object.hash(owner, take);
}

/// Stops the voice; [line] names the line it cuts, when one is speaking.
final class StopTheLine extends Effect {
  final Line? line;

  const StopTheLine([this.line]);

  @override
  bool operator ==(Object other) => other is StopTheLine && other.line == line;

  @override
  int get hashCode => line.hashCode;
}

final class DropTheLine extends Effect {
  final Line line;

  const DropTheLine(this.line);

  @override
  bool operator ==(Object other) => other is DropTheLine && other.line == line;

  @override
  int get hashCode => line.hashCode;
}

/// The part's ceiling, once the machine has taken the part's opening.
final class ArmTheCeiling extends Effect {
  const ArmTheCeiling();
}

final class StopTheSound extends Effect {
  const StopTheSound();
}

final class HoldTheSound extends Effect {
  const HoldTheSound();
}

final class LetTheSoundRun extends Effect {
  const LetTheSoundRun();
}

final class ArmTheRetry extends Effect {
  final int step;
  final Duration? due;

  const ArmTheRetry({this.step = 0, this.due});

  @override
  bool operator ==(Object other) =>
      other is ArmTheRetry && other.step == step && other.due == due;

  @override
  int get hashCode => Object.hash(step, due);
}

final class CancelTheRetry extends Effect {
  const CancelTheRetry();
}

final class DrainTheOutbox extends Effect {
  const DrainTheOutbox();
}

final class ResendPending extends LifecycleHandOff {
  const ResendPending();
}

final class ProbeTheRoom extends Effect {
  const ProbeTheRoom();
}

final class SayTheOfflineNotice extends Effect {
  const SayTheOfflineNotice();
}

final class DiscardTheSession extends LifecycleHandOff {
  const DiscardTheSession();
}

final class OpenTheChoice extends LifecycleHandOff {
  const OpenTheChoice();
}

final class LookAtTheSession extends Effect {
  final Turn turn;
  final Kept sounding;

  const LookAtTheSession(this.turn, {this.sounding = const NothingKept()});

  @override
  bool operator ==(Object other) =>
      other is LookAtTheSession &&
      other.turn == turn &&
      other.sounding == sounding;

  @override
  int get hashCode => Object.hash(turn, sounding);
}

final class PlayTheReply extends Effect {
  final Turn turn;
  final TurnResult reply;

  const PlayTheReply(this.turn, this.reply);
}

final class LetTheTurnGo extends Effect {
  final Turn turn;

  const LetTheTurnGo(this.turn);

  @override
  bool operator ==(Object other) => other is LetTheTurnGo && other.turn == turn;

  @override
  int get hashCode => turn.hashCode;
}

final class FellAt extends Effect {
  final Door door;
  final RoomReach why;

  const FellAt(this.door, {this.why = RoomReach.noNetwork});

  @override
  bool operator ==(Object other) =>
      other is FellAt && other.door == door && other.why == why;

  @override
  int get hashCode => Object.hash(door, why);
}

final class AskForAPersonAgain extends Effect {
  const AskForAPersonAgain();
}

final class MarkThePassageClosed extends Effect {
  const MarkThePassageClosed();
}

final class CountTheRefusal extends Effect {
  const CountTheRefusal();
}

final class RefuseThePassage extends Effect {
  const RefuseThePassage();
}

enum Said { said, failed, unsaid }

/// How the last line the room answered for ended, for the gesture that waits on it.
final class LineOutcome {
  final Line line;
  final Said said;
  final Exception? because;

  const LineOutcome(this.line, this.said, {this.because});
}

/// How the microphone last answered, for the Station and the gesture waiting on its take.
final class MicOutcome {
  final MicAnswer answer;
  final String? take;
  final Object? because;

  const MicOutcome(this.answer, {this.take, this.because});
}

final class Machine {
  final Halt halt;
  final Channel channel;
  final List<Line> queue;
  final Source? failing;
  final int failures;
  final Set<int> onTheirWay;
  final Map<Line, Set<int>> owners;
  final Reach reach;
  final Map<String, PartFact> parts;
  final bool draining;
  final int fallen;
  final bool noticeSaid;
  final int generation;

  /// The turn whose POST is in the air: sent, and neither answered nor given up.
  final Turn? inFlight;

  final LineOutcome? lastLine;

  final MicOutcome? lastMic;

  final Station station;

  const Machine({
    this.halt = const NoHalt(),
    this.channel = const Silence(),
    this.queue = const [],
    this.failing,
    this.failures = 0,
    this.onTheirWay = const {},
    this.owners = const {},
    this.reach = Reach.reachable,
    this.parts = const {},
    this.draining = false,
    this.fallen = 0,
    this.noticeSaid = false,
    this.generation = 0,
    this.inFlight,
    this.lastLine,
    this.lastMic,
    this.station = const Menu(),
  });

  bool get reachable => reach == Reach.reachable;

  bool get somethingPending => parts.values.contains(PartFact.pending);

  Machine withNoPassage(Set<int> onTheirWay) => Machine(
    onTheirWay: onTheirWay,
    reach: reach,
    parts: parts,
    draining: draining,
    fallen: fallen,
    noticeSaid: noticeSaid,
    generation: generation,
    station: station,
  );

  Machine copyWith({
    Halt? halt,
    Channel? channel,
    List<Line>? queue,
    Source? failing,
    int? failures,
    bool forgetTheFailures = false,
    Set<int>? onTheirWay,
    Map<Line, Set<int>>? owners,
    Reach? reach,
    Map<String, PartFact>? parts,
    bool? draining,
    int? fallen,
    bool? noticeSaid,
    int? generation,
    Turn? inFlight,
    bool landTheTurn = false,
    LineOutcome? lastLine,
    MicOutcome? lastMic,
    Station? station,
  }) => Machine(
    halt: halt ?? this.halt,
    channel: channel ?? this.channel,
    queue: queue ?? this.queue,
    failing: forgetTheFailures ? null : (failing ?? this.failing),
    failures: forgetTheFailures ? 0 : (failures ?? this.failures),
    onTheirWay: onTheirWay ?? this.onTheirWay,
    owners: owners ?? this.owners,
    reach: reach ?? this.reach,
    parts: parts ?? this.parts,
    draining: draining ?? this.draining,
    fallen: fallen ?? this.fallen,
    noticeSaid: noticeSaid ?? this.noticeSaid,
    generation: generation ?? this.generation,
    inFlight: landTheTurn ? null : (inFlight ?? this.inFlight),
    lastLine: lastLine ?? this.lastLine,
    lastMic: lastMic ?? this.lastMic,
    station: station ?? this.station,
  );
}

Machine moveTheGeneration(Machine machine) =>
    machine.copyWith(generation: machine.generation + 1, landTheTurn: true);

const _enter = [SilenceTheRoom(), CloseAndDiscardTheMic()];
const _watch = ArmTheWatch();

(Machine, List<Effect>) reduce(
  Machine machine,
  MachineEvent event,
) => switch (event) {
  AnsweringEvent(:final generation?) when generation < machine.generation => (
    machine,
    const [],
  ),
  LineArrived(:final line, :final by) => _arrive(machine, line, by),
  PlayerOpened() => (
    _opened(machine),
    [if (machine.channel is Playing) const ArmTheCeiling()],
  ),
  PlayerEnded(:final line?) => _answer(
    machine,
    line,
    Said.said,
    heard: () => _ended(machine),
  ),
  PlayerFailed(:final line?, :final source, :final sounding) => _answer(
    machine,
    line,
    Said.failed,
    heard: () => _failed(machine, source, sounding),
  ),
  PlayerEnded(:final sound?) when !_sounds(machine, sound, orHeld: true) => (
    machine,
    const [],
  ),
  PlayerFailed(:final sound?) when !_sounds(machine, sound) => (
    machine,
    const [],
  ),
  PlayerEnded() => _ended(machine),
  PlayerFailed(:final source, :final sounding) => _failed(
    machine,
    source,
    sounding,
  ),
  MicOpened(:final owner, :final take) => _openTheMic(machine, owner, take),
  MicClosed() => _closeTheMic(machine),
  MicAnswered(:final answer, :final take, :final because) => _heard(
    machine,
    answer,
    take,
    because,
  ),
  MicClosing() => (machine, const [CloseTheMic()]),
  MicDiscarded() => _discardTheMic(machine),
  BeadTapped(:final sounds, :final beneath) => _tapped(
    machine,
    sounds,
    beneath,
  ),
  PauseTapped() => _pause(machine),
  TheHeldPartReturns(:final held) => (
    machine.channel is Silence && machine.halt is! Blocking
        ? machine.copyWith(channel: held)
        : machine,
    const [],
  ),
  GestureSilenced(:final keepingTheHold) => (
    _silenced(machine, keepingTheHold),
    keepingTheHold
        ? [StopTheLine(_speaking(machine.channel))]
        : const [StopTheSound()],
  ),
  GestureStarted(:final gesture) => (
    machine.copyWith(onTheirWay: {...machine.onTheirWay, gesture}),
    const [],
  ),
  GestureEnded(:final gesture) => _drain(
    machine.copyWith(onTheirWay: {...machine.onTheirWay}..remove(gesture)),
  ),
  NothingReplayed() => _drain(machine),
  LineNotSaid(:final line, :final because) => _answer(
    machine,
    line,
    because == null ? Said.unsaid : Said.failed,
    because: because,
    heard: () => _notSaid(machine, line),
    unheard: () => _notSaid(machine, line),
  ),
  StepLeft() => _leaveTheQueue(machine, _answersItsStep),
  LeftThePassage() => (
    machine.copyWith(
      channel: const Silence(),
      queue: const [],
      forgetTheFailures: true,
      owners: const {},
    ),
    [const StopTheSound(), for (final line in machine.queue) DropTheLine(line)],
  ),
  TheSessionIsGone() || ThePassageClosed() => _theSessionGone(machine),
  TheCallMetAClosedPassage() => (machine, const [MarkThePassageClosed()]),
  TurnSent(:final turn) => (machine.copyWith(inFlight: turn), const []),
  TurnAnswered(:final turn) => (
    _settleTheOpening(_land(machine, turn), turn),
    const [],
  ),
  TurnFailed(:final turn) => (_land(machine, turn), const []),
  TurnGivenUp(:final turn, :final sounding) => _giveUp(machine, turn, sounding),
  LookFound(:final turn, :final reply) => (
    _settleTheOpening(machine, turn),
    [PlayTheReply(turn, reply)],
  ),
  TheRefusalPassed() => (machine, const []),
  TheCallWasRefused() => (machine, const [AskForAPersonAgain()]),
  LookEmpty(sounding: TheOpening()) ||
  TheOpeningMissed() => (machine, const [LetTheOpeningGo()]),
  LookEmpty(:final sounding) => _theHalt(
    machine,
    RoomRaisedAHalt(sounding: sounding),
  ),
  TheRoomRefused(:final third, :final sounding) => _refused(
    machine,
    third,
    sounding,
  ),
  ThePassageCannotOpen() => (machine, const [RefuseThePassage()]),
  NetworkFailedAt(:final door, :final why) => _fall(machine, door, why),
  NetworkReturned() => _return(machine),
  RetryFired() => _retry(machine),
  TheRoomAnswered() => (_answered(machine), const []),
  OutboxChanged(:final parts, :final due) => _tally(machine, parts, due),
  SessionRead() => _theHalt(_answered(machine), event),
  RoomRaisedAHalt() ||
  TheCallLanded() ||
  TheAnswerWarned() ||
  LongPress() ||
  WatchFired() => _theHalt(machine, event),
  StationEvent() => (_reachTheStation(machine, event), const []),
};

Machine _reachTheStation(Machine machine, StationEvent event) {
  final next = machine.station.answer(event);
  if (next == machine.station) return machine;
  return moveTheGeneration(machine).copyWith(station: next);
}

bool _silent(Machine machine) =>
    machine.halt is! Blocking &&
    (machine.channel is Silence || machine.channel is Paused);

bool _own(Machine machine, Line line) =>
    (machine.owners[line] ?? const <int>{}).any(machine.onTheirWay.contains);

Line? _nextLine(Machine machine) {
  if (!_silent(machine)) return null;
  for (final line in machine.queue) {
    if (_own(machine, line)) return line;
  }
  if (machine.onTheirWay.isNotEmpty || machine.queue.isEmpty) return null;
  return machine.queue.first;
}

Paused? _heldBy(Channel channel) => switch (channel) {
  final Paused paused => paused,
  Microphone(:final held) || GuideSpeaking(:final held) => held,
  _ => null,
};

(Machine, List<Effect>) _say(Machine machine, Line line) => (
  machine.copyWith(
    channel: GuideSpeaking(line, held: _heldBy(machine.channel)),
    queue: [...machine.queue.where((waiting) => waiting != line)],
    owners: {...machine.owners}..remove(line),
  ),
  [PlayLine(line)],
);

(Machine, List<Effect>) _drain(
  Machine machine, [
  List<Effect> before = const [],
]) {
  final next = _nextLine(machine);
  if (next == null) return (machine, before);
  final (said, effects) = _say(machine, next);
  return (said, [...before, ...effects]);
}

(Machine, List<Effect>) _arrive(Machine machine, Line line, List<int> by) {
  final own = by.any(machine.onTheirWay.contains);
  if (!own &&
      machine.queue.any(
        (waiting) => waiting.kind == line.kind && !_own(machine, waiting),
      )) {
    return (machine, [DropTheLine(line)]);
  }
  return _drain(
    machine.copyWith(
      queue: [...machine.queue, line],
      owners: own ? {...machine.owners, line: by.toSet()} : null,
    ),
  );
}

bool _answersItsStep(Line line) => line.kind.answersAStep;

bool _aboutTheFall(Line line) => line.kind == LineKind.offlineNotice;

(Machine, List<Effect>) _leaveTheQueue(
  Machine machine,
  bool Function(Line) leaves,
) => (
  machine.copyWith(queue: [...machine.queue.where((line) => !leaves(line))]),
  [
    for (final line in machine.queue)
      if (leaves(line)) DropTheLine(line),
  ],
);

Line? _speaking(Channel channel) => switch (channel) {
  GuideSpeaking(:final line) => line,
  _ => null,
};

bool _speaks(Machine machine, Line line) => _speaking(machine.channel) == line;

bool _sounds(Machine machine, Sound sound, {bool orHeld = false}) =>
    switch (machine.channel) {
      Playing(sound: final playing) => playing == sound,
      Paused(:final what) => orHeld && what == sound,
      _ => false,
    };

/// A line's answer reaches the Channel only while that line is the one speaking; the
/// gesture that waits on it is told how it ended either way.
(Machine, List<Effect>) _answer(
  Machine machine,
  Line line,
  Said said, {
  Exception? because,
  required (Machine, List<Effect>) Function() heard,
  (Machine, List<Effect>) Function()? unheard,
}) {
  final speaking = _speaks(machine, line);
  final (next, effects) = speaking
      ? heard()
      : unheard?.call() ?? (machine, const <Effect>[]);
  return (
    next.copyWith(
      lastLine: speaking
          ? LineOutcome(line, said, because: because)
          : LineOutcome(line, said == Said.said ? Said.said : Said.unsaid),
    ),
    effects,
  );
}

(Machine, List<Effect>) _notSaid(Machine machine, Line line) =>
    switch (machine.channel) {
      GuideSpeaking(line: final speaking, :final held) when speaking == line =>
        _drain(machine.copyWith(channel: held ?? const Silence())),
      _ => _leaveTheQueue(machine, (waiting) => waiting == line),
    };

Machine _opened(Machine machine) => switch (machine.channel) {
  final Playing playing => machine.copyWith(
    channel: _playing(
      playing.sound,
      opened: true,
      next: playing.next,
      held: playing.held,
    ),
  ),
  final Paused paused => machine.copyWith(channel: _openedUnder(paused)),
  GuideSpeaking(:final line, :final held) => machine.copyWith(
    channel: GuideSpeaking(line, held: _openedUnder(held)),
  ),
  Microphone(:final owner, :final held) => machine.copyWith(
    channel: Microphone(owner, held: _openedUnder(held)),
  ),
  _ => machine,
};

Paused? _openedUnder(Paused? paused) => switch (paused) {
  Paused(:final what, :final next, :final held, started: true, opened: false) =>
    Paused(what, next: next, held: held),
  _ => paused,
};

Machine _succeeded(Machine machine, Source source) => machine.failing == source
    ? machine.copyWith(forgetTheFailures: true)
    : machine;

(Machine, List<Effect>) _ended(Machine machine) {
  switch (machine.channel) {
    case GuideSpeaking(:final line, :final held):
      return _drain(
        _succeeded(
          machine,
          line.source,
        ).copyWith(channel: held ?? const Silence()),
      );
    case final Playing playing:
      final heard = _succeeded(machine, playing.sound.source);
      if (playing.next.isNotEmpty) {
        return _start(heard, playing.next, playing.held);
      }
      return _drain(heard.copyWith(channel: playing.held ?? const Silence()));
    case Paused(:final next, :final held) when next.isNotEmpty:
      return (
        machine.copyWith(
          channel: Paused(
            next.first,
            next: next.skip(1).toList(),
            started: false,
            held: held,
          ),
        ),
        const [],
      );
    case Paused(:final held):
      return _drain(machine.copyWith(channel: held ?? const Silence()));
    default:
      return (machine, const []);
  }
}

Machine _silenced(Machine machine, bool keepingTheHold) =>
    switch (machine.channel) {
      Microphone() => machine,
      Paused() when keepingTheHold => machine,
      GuideSpeaking(:final held) when keepingTheHold => machine.copyWith(
        channel: held ?? const Silence(),
      ),
      _ => machine.copyWith(channel: const Silence()),
    };

(Machine, List<Effect>) _failed(Machine machine, Source source, Kept sounding) {
  final channel = machine.channel;
  final silent = machine.copyWith(
    channel: switch (channel) {
      GuideSpeaking(:final held) => held ?? const Silence(),
      Playing(:final held) => held ?? const Silence(),
      _ => channel,
    },
  );
  if (!source.counts) return _drain(silent);
  final failures = machine.failing == source ? machine.failures + 1 : 1;
  final counted = silent.copyWith(failing: source, failures: failures);
  if (failures < 2) return _drain(counted);
  return _theHalt(
    counted,
    RoomRaisedAHalt(sounding: channel is Playing ? const ThePart() : sounding),
  );
}

(Machine, List<Effect>) _openTheMic(
  Machine machine,
  MicOwner owner,
  String take,
) {
  if (!_silent(machine)) return (machine, const []);
  final held = machine.channel;
  return (
    machine.copyWith(
      channel: Microphone(
        owner,
        held: switch (held) {
          Paused(what: PartSound()) => held,
          Paused(held: final part) => part,
          _ => null,
        },
      ),
    ),
    [OpenTheMic(owner, take: take)],
  );
}

(Machine, List<Effect>) _closeTheMic(Machine machine) =>
    switch (machine.channel) {
      Microphone(:final held) => _drain(
        machine.copyWith(channel: held ?? const Silence()),
      ),
      _ => (machine, const []),
    };

/// Every answer but a start, or a recorder that failed to stop, gives the Channel back, as
/// a closed microphone does.
(Machine, List<Effect>) _heard(
  Machine machine,
  MicAnswer answer,
  String? take,
  Object? because,
) {
  final (answered, effects) = answer == MicAnswer.started || because != null
      ? (machine, const <Effect>[])
      : _closeTheMic(machine);
  return (
    answered.copyWith(
      lastMic: MicOutcome(answer, take: take, because: because),
    ),
    effects,
  );
}

(Machine, List<Effect>) _discardTheMic(Machine machine) {
  final (closed, effects) = _closeTheMic(machine);
  return (closed, [const DiscardTheMic(), ...effects]);
}

(Machine, List<Effect>) _tapped(
  Machine machine,
  List<Sound> sounds,
  Paused? beneath,
) {
  if (machine.halt is Blocking ||
      machine.channel is Microphone ||
      sounds.isEmpty) {
    return (machine, const []);
  }
  final (started, effects) = _start(machine, sounds, beneath);
  return (started, [..._stopTheLineIn(machine.channel), ...effects]);
}

(Machine, List<Effect>) _start(
  Machine machine,
  List<Sound> sounds, [
  Paused? held,
]) {
  final sound = sounds.first;
  return (
    machine.copyWith(
      channel: _playing(sound, next: sounds.skip(1).toList(), held: held),
    ),
    [_play(sound)],
  );
}

Effect _play(Sound sound) => switch (sound) {
  final PartSound part => PlayPart(part),
  final StretchSound stretch => PlayStretch(stretch),
};

Playing _playing(
  Sound sound, {
  bool opened = false,
  List<Sound> next = const [],
  Paused? held,
}) => switch (sound) {
  final PartSound part => PartPlaying(
    part,
    opened: opened,
    next: next,
    held: held,
  ),
  final StretchSound stretch => StretchPlaying(
    stretch,
    opened: opened,
    next: next,
    held: held,
  ),
};

(Machine, List<Effect>) _resumeFromUnder(Machine paused, Line line) {
  final (resumed, effects) = _pause(paused);
  return (resumed, [StopTheLine(line), ...effects]);
}

List<Effect> _stopTheLineIn(Channel channel) => switch (channel) {
  GuideSpeaking(:final line) => [StopTheLine(line)],
  _ => const [],
};

(Machine, List<Effect>) _pause(Machine machine) => switch (machine.channel) {
  GuideSpeaking(:final line, held: final Paused paused) => _resumeFromUnder(
    machine.copyWith(channel: paused),
    line,
  ),
  final Playing playing => (
    machine.copyWith(
      channel: Paused(
        playing.sound,
        next: playing.next,
        held: playing.held,
        opened: playing.opened,
      ),
    ),
    const [HoldTheSound()],
  ),
  Paused(:final what, :final next, :final held, :final opened, started: true) =>
    (
      machine.copyWith(
        channel: _playing(what, opened: opened, next: next, held: held),
      ),
      const [LetTheSoundRun()],
    ),
  Paused(:final what, :final next, :final held) => (
    machine.copyWith(
      channel: _playing(what, next: next, held: held),
    ),
    [_play(what)],
  ),
  _ => (machine, const []),
};

(Machine, List<Effect>) _theHalt(Machine machine, MachineEvent event) {
  final (halt, effects) = _reduceTheHalt(machine.halt, event);
  final next = machine.copyWith(halt: halt);
  if (halt is Blocking && machine.halt is! Blocking) {
    return (next.copyWith(channel: const Silence()), effects);
  }
  if (halt is! Blocking && machine.halt is Blocking) {
    final lifted = next.copyWith(forgetTheFailures: true);
    final resent = [...effects, if (machine.reachable) const ResendPending()];
    if (effects.contains(const ReplayTheSound(ThePart()))) {
      return (lifted, resent);
    }
    return _drain(lifted, resent);
  }
  return (next, effects);
}

Machine _land(Machine machine, Turn turn) =>
    machine.inFlight == turn ? machine.copyWith(landTheTurn: true) : machine;

(Machine, List<Effect>) _giveUp(Machine machine, Turn turn, Kept sounding) {
  if (machine.inFlight != turn) return (machine, const []);
  return (
    machine.copyWith(landTheTurn: true),
    [LetTheTurnGo(turn), LookAtTheSession(turn, sounding: sounding)],
  );
}

/// An opening that was answered, on time or by the one look, is no longer owed: the
/// halt that kept it plays what is queued when it lifts and never asks again.
Machine _settleTheOpening(Machine machine, Turn turn) => switch (machine.halt) {
  Blocking(
    kept: TheOpening(:final failedTurnId),
    :final warningBeneath,
    :final serverKnows,
  )
      when failedTurnId == turn.turnId =>
    machine.copyWith(
      halt: Blocking(
        const NothingKept(),
        warningBeneath: warningBeneath,
        serverKnows: serverKnows,
      ),
    ),
  _ => machine,
};

(Machine, List<Effect>) _refused(Machine machine, bool third, Kept sounding) {
  if (!third) return (machine, const [CountTheRefusal()]);
  final (halted, effects) = _theHalt(
    machine,
    RoomRaisedAHalt(sounding: sounding),
  );
  return (halted, [const CountTheRefusal(), ...effects]);
}

(Machine, List<Effect>) _theSessionGone(Machine machine) => (
  machine.copyWith(
    halt: const NoHalt(),
    channel: const Silence(),
    queue: const [],
    owners: const {},
    forgetTheFailures: true,
  ),
  [
    const StopTheSound(),
    const CloseAndDiscardTheMic(),
    for (final line in machine.queue) DropTheLine(line),
    const DiscardTheSession(),
    const OpenTheChoice(),
  ],
);

(Machine, List<Effect>) _fall(Machine machine, Door door, RoomReach why) {
  final fell = FellAt(door, why: why);
  if (machine.reachable) {
    final fallen = machine.noticeSaid ? machine.fallen + 1 : 0;
    return (
      machine.copyWith(
        reach: Reach.outOfReach,
        fallen: fallen,
        noticeSaid: true,
      ),
      [
        fell,
        ArmTheRetry(step: fallen),
        if (!machine.noticeSaid) const SayTheOfflineNotice(),
      ],
    );
  }
  if (door != Door.probe) return (machine, [fell]);
  final fallen = machine.fallen + 1;
  return (machine.copyWith(fallen: fallen), [fell, ArmTheRetry(step: fallen)]);
}

(Machine, List<Effect>) _return(Machine machine) {
  if (machine.reachable) return (machine, const []);
  final (kept, dropped) = _leaveTheQueue(machine, _aboutTheFall);
  final halt = machine.halt;
  return (
    kept.copyWith(reach: Reach.reachable, draining: true),
    [
      ...dropped,
      const CancelTheRetry(),
      const DrainTheOutbox(),
      if (halt is! Blocking) const ResendPending(),
      const ReadTheState(),
      if (halt is Blocking && !halt.serverKnows) const CallForAPerson(),
      _watch,
    ],
  );
}

Machine _answered(Machine machine) =>
    machine.reachable ? machine.copyWith(noticeSaid: false) : machine;

(Machine, List<Effect>) _retry(Machine machine) {
  if (!machine.reachable) return (machine, const [ProbeTheRoom()]);
  if (!machine.somethingPending || machine.draining) {
    return (machine, const []);
  }
  return (machine.copyWith(draining: true), const [DrainTheOutbox()]);
}

(Machine, List<Effect>) _tally(
  Machine machine,
  Map<String, PartFact> parts,
  Duration due,
) {
  final landed = parts.entries.any(
    (part) =>
        part.value == PartFact.sent &&
        machine.parts[part.key] == PartFact.pending,
  );
  final told = (landed ? _answered(machine) : machine).copyWith(
    parts: parts,
    draining: false,
  );
  if (!told.reachable) return (told, const []);
  if (!told.somethingPending) return (told, const [CancelTheRetry()]);
  return (told, [ArmTheRetry(due: due)]);
}

(Halt, List<Effect>) _reduceTheHalt(
  Halt halt,
  MachineEvent event,
) => switch (event) {
  SessionRead() => _read(halt, event),
  RoomRaisedAHalt(:final sounding, :final callsForAPerson) => switch (halt) {
    Blocking() => (halt, [if (callsForAPerson) const CallForAPerson(), _watch]),
    _ => (
      Blocking(sounding, warningBeneath: halt is Warning),
      [..._enter, if (callsForAPerson) const CallForAPerson(), _watch],
    ),
  },
  TheCallLanded() => switch (halt) {
    Blocking(:final kept, :final warningBeneath) => (
      Blocking(kept, warningBeneath: warningBeneath, serverKnows: true),
      const [],
    ),
    _ => (halt, const []),
  },
  TheAnswerWarned() => switch (halt) {
    Blocking(:final kept, :final serverKnows) => (
      Blocking(kept, warningBeneath: true, serverKnows: serverKnows),
      const [_watch],
    ),
    _ => (const Warning(), const [_watch]),
  },
  LongPress(:final somebodyToAsk) => switch (halt) {
    Blocking(serverKnows: true) when somebodyToAsk => (
      halt,
      const [TellAPersonArrived(), ReadTheState()],
    ),
    Blocking(:final warningBeneath) => _lift(
      halt,
      warningBeneath ? const Warning() : const NoHalt(),
    ),
    _ => (halt, const []),
  },
  WatchFired() => (halt, const [ReadTheState(), _watch]),
  NetworkFailedAt() ||
  NetworkReturned() ||
  RetryFired() ||
  TheRoomAnswered() ||
  OutboxChanged() ||
  LineArrived() ||
  PlayerOpened() ||
  PlayerEnded() ||
  PlayerFailed() ||
  MicOpened() ||
  MicClosed() ||
  MicAnswered() ||
  MicClosing() ||
  MicDiscarded() ||
  BeadTapped() ||
  PauseTapped() ||
  TheHeldPartReturns() ||
  GestureSilenced() ||
  GestureStarted() ||
  GestureEnded() ||
  NothingReplayed() ||
  LineNotSaid() ||
  StepLeft() ||
  LeftThePassage() ||
  TheSessionIsGone() ||
  ThePassageClosed() ||
  TurnGivenUp() ||
  LookFound() ||
  LookEmpty() ||
  TheOpeningMissed() ||
  TheRoomRefused() ||
  ThePassageCannotOpen() ||
  TurnSent() ||
  TurnAnswered() ||
  TurnFailed() ||
  TheRefusalPassed() ||
  TheCallWasRefused() ||
  TheCallMetAClosedPassage() ||
  StationEvent() => (halt, const []),
};

(Halt, List<Effect>) _read(Halt halt, SessionRead read) {
  final snapshot = read.snapshot;
  final Halt told = snapshot.needsPerson
      ? const Blocking(NothingKept())
      : snapshot.halt == HaltKind.warning
      ? const Warning()
      : const NoHalt();
  return switch ((halt, told)) {
    (Blocking(:final kept, :final warningBeneath), Blocking()) => (
      Blocking(kept, warningBeneath: warningBeneath, serverKnows: true),
      const [_watch],
    ),
    (Blocking(:final kept, :final serverKnows), _)
        when !serverKnows || read.sentBeforeTheCallLanded =>
      (
        Blocking(
          kept,
          warningBeneath: told is Warning,
          serverKnows: serverKnows,
        ),
        const [_watch],
      ),
    (final Blocking blocking, _) => _lift(blocking, told),
    (_, Blocking()) => (
      Blocking(
        read.sounding,
        warningBeneath: halt is Warning,
        serverKnows: true,
      ),
      const [..._enter, _watch],
    ),
    (NoHalt(), NoHalt()) => (halt, const []),
    _ => (told, const [_watch]),
  };
}

(Halt, List<Effect>) _lift(Blocking halt, Halt next) =>
    (next, [const StopCallingForAPerson(), ReplayTheSound(halt.kept), _watch]);

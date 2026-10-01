import 'channel.dart';
import 'halt.dart';
import 'session_snapshot.dart';

sealed class MachineEvent {
  const MachineEvent();
}

final class SessionRead extends MachineEvent {
  final SessionSnapshot snapshot;
  final Kept sounding;
  final DateTime at;
  final bool sentBeforeTheCallLanded;

  const SessionRead(
    this.snapshot, {
    required this.at,
    this.sounding = const NothingKept(),
    this.sentBeforeTheCallLanded = false,
  });
}

final class RoomRaisedAHalt extends MachineEvent {
  final Kept sounding;
  final bool callsForAPerson;

  const RoomRaisedAHalt({
    this.sounding = const NothingKept(),
    this.callsForAPerson = true,
  });
}

final class TheCallLanded extends MachineEvent {
  const TheCallLanded();
}

final class TheAnswerWarned extends MachineEvent {
  const TheAnswerWarned();
}

final class LongPress extends MachineEvent {
  final bool somebodyToAsk;
  final DateTime at;

  const LongPress({required this.somebodyToAsk, required this.at});
}

final class WatchFired extends MachineEvent {
  const WatchFired();
}

final class ReachChanged extends MachineEvent {
  final bool reachable;

  const ReachChanged({required this.reachable});
}

final class LineArrived extends MachineEvent {
  final Line line;
  final List<int> by;

  const LineArrived(this.line, {this.by = const []});
}

final class PlayerOpened extends MachineEvent {
  const PlayerOpened();
}

final class PlayerEnded extends MachineEvent {
  const PlayerEnded();
}

final class PlayerFailed extends MachineEvent {
  final Source source;
  final Kept sounding;

  const PlayerFailed(this.source, {this.sounding = const NothingKept()});
}

final class MicOpened extends MachineEvent {
  final MicOwner owner;
  final String take;
  final List<int> by;

  const MicOpened(this.owner, {this.take = '', this.by = const []});
}

final class MicClosed extends MachineEvent {
  const MicClosed();
}

final class BeadTapped extends MachineEvent {
  final List<Sound> sounds;
  final Paused? beneath;
  final List<int> by;

  const BeadTapped(this.sounds, {this.beneath, this.by = const []});
}

final class PauseTapped extends MachineEvent {
  const PauseTapped();
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

final class NothingReplayed extends MachineEvent {
  const NothingReplayed();
}

final class LineNotSaid extends MachineEvent {
  final Line line;

  const LineNotSaid(this.line);
}

final class StepLeft extends MachineEvent {
  const StepLeft();
}

final class LeftThePassage extends MachineEvent {
  const LeftThePassage();
}

sealed class Effect {
  const Effect();
}

final class SilenceTheRoom extends Effect {
  const SilenceTheRoom();
}

final class CloseAndDiscardTheMic extends Effect {
  const CloseAndDiscardTheMic();
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

final class AskTheOpeningAgain extends Effect {
  final String freshTurnId;

  const AskTheOpeningAgain(this.freshTurnId);

  @override
  bool operator ==(Object other) =>
      other is AskTheOpeningAgain && other.freshTurnId == freshTurnId;

  @override
  int get hashCode => freshTurnId.hashCode;
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

final class StopTheLine extends Effect {
  final Line line;

  const StopTheLine(this.line);

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

final class StopTheSound extends Effect {
  const StopTheSound();
}

final class HoldTheSound extends Effect {
  const HoldTheSound();
}

final class LetTheSoundRun extends Effect {
  const LetTheSoundRun();
}

final class Machine {
  final Halt halt;
  final Channel channel;
  final List<Line> queue;
  final Source? failing;
  final int failures;
  final Set<int> onTheirWay;

  const Machine({
    this.halt = const NoHalt(),
    this.channel = const Silence(),
    this.queue = const [],
    this.failing,
    this.failures = 0,
    this.onTheirWay = const {},
  });

  Machine copyWith({
    Halt? halt,
    Channel? channel,
    List<Line>? queue,
    Source? failing,
    int? failures,
    bool forgetTheFailures = false,
    Set<int>? onTheirWay,
  }) => Machine(
    halt: halt ?? this.halt,
    channel: channel ?? this.channel,
    queue: queue ?? this.queue,
    failing: forgetTheFailures ? null : (failing ?? this.failing),
    failures: forgetTheFailures ? 0 : (failures ?? this.failures),
    onTheirWay: onTheirWay ?? this.onTheirWay,
  );
}

const _enter = [SilenceTheRoom(), CloseAndDiscardTheMic()];
const _watch = ArmTheWatch();

(Machine, List<Effect>) reduce(
  Machine machine,
  MachineEvent event,
) => switch (event) {
  LineArrived(:final line, :final by) => _arrive(_arrived(machine, by), line),
  PlayerOpened() => (_opened(machine), const []),
  PlayerEnded() => _ended(machine),
  PlayerFailed(:final source, :final sounding) => _failed(
    machine,
    source,
    sounding,
  ),
  MicOpened(:final owner, :final take, :final by) => _openTheMic(
    _arrived(machine, by),
    owner,
    take,
  ),
  MicClosed() => _closeTheMic(machine),
  BeadTapped(:final sounds, :final beneath, :final by) => _tapped(
    _arrived(machine, by),
    sounds,
    beneath,
  ),
  PauseTapped() => _pause(machine),
  GestureSilenced(:final keepingTheHold) => (
    _silenced(machine, keepingTheHold),
    const [],
  ),
  GestureStarted(:final gesture) => (
    machine.copyWith(onTheirWay: {...machine.onTheirWay, gesture}),
    const [],
  ),
  GestureEnded(:final gesture) => _drain(_arrived(machine, [gesture])),
  NothingReplayed() => _drain(machine),
  LineNotSaid(:final line) => _notSaid(machine, line),
  StepLeft() => _leaveTheQueue(machine, _answersItsStep),
  LeftThePassage() => (
    machine.copyWith(
      channel: const Silence(),
      queue: const [],
      forgetTheFailures: true,
    ),
    [const StopTheSound(), for (final line in machine.queue) DropTheLine(line)],
  ),
  SessionRead() ||
  RoomRaisedAHalt() ||
  TheCallLanded() ||
  TheAnswerWarned() ||
  LongPress() ||
  WatchFired() ||
  ReachChanged() => _theHalt(machine, event),
};

bool _silent(Machine machine) =>
    machine.halt is! Blocking &&
    (machine.channel is Silence || machine.channel is Paused);

bool _free(Machine machine) => _silent(machine) && machine.onTheirWay.isEmpty;

Machine _arrived(Machine machine, List<int> gestures) => gestures.isEmpty
    ? machine
    : machine.copyWith(
        onTheirWay: machine.onTheirWay.difference(gestures.toSet()),
      );

Paused? _heldBy(Channel channel) => switch (channel) {
  final Paused paused => paused,
  Microphone(:final held) || GuideSpeaking(:final held) => held,
  _ => null,
};

(Machine, List<Effect>) _say(Machine machine, Line line, List<Line> queue) => (
  machine.copyWith(
    channel: GuideSpeaking(line, held: _heldBy(machine.channel)),
    queue: queue,
  ),
  [PlayLine(line)],
);

(Machine, List<Effect>) _drain(
  Machine machine, [
  List<Effect> before = const [],
]) {
  if (!_free(machine) || machine.queue.isEmpty) return (machine, before);
  final (next, effects) = _say(
    machine,
    machine.queue.first,
    machine.queue.skip(1).toList(),
  );
  return (next, [...before, ...effects]);
}

(Machine, List<Effect>) _arrive(Machine machine, Line line) {
  if (machine.queue.any((waiting) => waiting.kind == line.kind)) {
    return (machine, [DropTheLine(line)]);
  }
  final queue = [...machine.queue, line];
  if (!_free(machine)) return (machine.copyWith(queue: queue), const []);
  return _say(machine, queue.first, queue.skip(1).toList());
}

bool _answersItsStep(Line line) => switch (line.kind) {
  LineKind.guide ||
  LineKind.acknowledgement ||
  LineKind.approved ||
  LineKind.reply => true,
  LineKind.offlineNotice || LineKind.stranded || LineKind.micBlocked => false,
};

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
  if (event is ReachChanged && event.reachable) {
    final (kept, dropped) = _leaveTheQueue(machine, _aboutTheFall);
    final (halt, effects) = _reduceTheHalt(machine.halt, event);
    return (kept.copyWith(halt: halt), [...dropped, ...effects]);
  }
  final (halt, effects) = _reduceTheHalt(machine.halt, event);
  final next = machine.copyWith(halt: halt);
  if (halt is Blocking && machine.halt is! Blocking) {
    return (next.copyWith(channel: const Silence()), effects);
  }
  if (halt is! Blocking && machine.halt is Blocking) {
    final lifted = next.copyWith(forgetTheFailures: true);
    if (effects.contains(const ReplayTheSound(ThePart()))) {
      return (lifted, effects);
    }
    return _drain(lifted, effects);
  }
  return (next, effects);
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
  LongPress(:final somebodyToAsk, :final at) => switch (halt) {
    Blocking(serverKnows: true) when somebodyToAsk => (
      halt,
      const [TellAPersonArrived(), ReadTheState()],
    ),
    Blocking(:final warningBeneath) => _lift(
      halt,
      warningBeneath ? const Warning() : const NoHalt(),
      at,
    ),
    _ => (halt, const []),
  },
  WatchFired() => (halt, const [ReadTheState(), _watch]),
  ReachChanged(:final reachable) => (
    halt,
    [
      if (reachable && halt is Blocking && !halt.serverKnows)
        const CallForAPerson(),
      if (reachable) _watch,
    ],
  ),
  LineArrived() ||
  PlayerOpened() ||
  PlayerEnded() ||
  PlayerFailed() ||
  MicOpened() ||
  MicClosed() ||
  BeadTapped() ||
  PauseTapped() ||
  GestureSilenced() ||
  GestureStarted() ||
  GestureEnded() ||
  NothingReplayed() ||
  LineNotSaid() ||
  StepLeft() ||
  LeftThePassage() => (halt, const []),
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
    (final Blocking blocking, _) => _lift(blocking, told, read.at),
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

(Halt, List<Effect>) _lift(Blocking halt, Halt next, DateTime at) => (
  next,
  [
    const StopCallingForAPerson(),
    switch (halt.kept) {
      TheOpening(:final failedTurnId) => AskTheOpeningAgain(
        _freshTurnId(failedTurnId, at),
      ),
      final kept => ReplayTheSound(kept),
    },
    _watch,
  ],
);

String _freshTurnId(String failed, DateTime at) {
  final stamp = at.millisecondsSinceEpoch.toString();
  return stamp == failed ? '$stamp-1' : stamp;
}

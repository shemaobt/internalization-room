import 'halt.dart';
import 'session_snapshot.dart';

sealed class MachineEvent {
  const MachineEvent();
}

final class SessionRead extends MachineEvent {
  final SessionSnapshot snapshot;
  final Kept sounding;
  final DateTime at;

  const SessionRead(
    this.snapshot, {
    required this.at,
    this.sounding = const NothingKept(),
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

const _enter = [SilenceTheRoom(), CloseAndDiscardTheMic()];
const _watch = ArmTheWatch();

(Halt, List<Effect>) reduce(Halt halt, MachineEvent event) => switch (event) {
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
  ReachChanged(:final reachable) => (halt, [if (reachable) _watch]),
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
    (Blocking(serverKnows: false, :final kept), _) => (
      Blocking(kept, warningBeneath: told is Warning),
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

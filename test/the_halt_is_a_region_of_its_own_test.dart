import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';

final _at = DateTime.utc(2026, 9, 30, 12);

SessionRead _read({
  String status = 'in_progress',
  HaltKind halt = HaltKind.unnamed,
  Kept sounding = const NothingKept(),
}) => SessionRead(
  SessionSnapshot(
    sessionId: 'sessao-1',
    pericope: 'rute-1',
    status: status,
    coverage: null,
    done: false,
    halt: halt,
  ),
  at: _at,
  sounding: sounding,
);

SessionRead get _nothingStands => _read();
SessionRead get _nothingStoodBeforeTheCall => SessionRead(
  _nothingStands.snapshot,
  at: _at,
  sentBeforeTheCallLanded: true,
);
SessionRead get _aWarningStands =>
    _read(status: 'needs_person', halt: HaltKind.warning);
SessionRead _aBlockingHalt({Kept sounding = const NothingKept()}) =>
    _read(status: 'needs_person', halt: HaltKind.blocking, sounding: sounding);

const _entering = [SilenceTheRoom(), CloseAndDiscardTheMic()];

(Halt, List<Effect>) _reduce(Halt halt, MachineEvent event) {
  final (machine, effects) = reduce(Machine(halt: halt), event);
  return (machine.halt, effects);
}

Matcher _to(Halt next, List<Effect> effects) => isA<(Halt, List<Effect>)>()
    .having((result) => result.$1, 'the halt', next)
    .having((result) => result.$2, 'the effects', effects);

void main() {
  group('from no halt', () {
    const none = NoHalt();

    test('a read with nothing standing changes nothing', () {
      expect(_reduce(none, _nothingStands), _to(none, const <Effect>[]));
    });

    test('a read warning marks the room and arms the Watch', () {
      expect(
        _reduce(none, _aWarningStands),
        _to(const Warning(), const [ArmTheWatch()]),
      );
    });

    test('a read blocking halt enters without a call for a person', () {
      expect(
        _reduce(none, _aBlockingHalt(sounding: const ThePart())),
        _to(const Blocking(ThePart(), serverKnows: true), const [
          ..._entering,
          ArmTheWatch(),
        ]),
      );
    });

    test('a raised halt calls for a person and arms the Watch', () {
      expect(
        _reduce(none, const RoomRaisedAHalt(sounding: ThePart())),
        _to(const Blocking(ThePart()), const [
          ..._entering,
          CallForAPerson(),
          ArmTheWatch(),
        ]),
      );
    });

    test('a raised halt that cannot call still arms the Watch', () {
      expect(
        _reduce(none, const RoomRaisedAHalt(callsForAPerson: false)),
        _to(const Blocking(NothingKept()), const [..._entering, ArmTheWatch()]),
      );
    });

    test('the Watch firing reads the state and beats again', () {
      expect(
        _reduce(none, const WatchFired()),
        _to(none, const [ReadTheState(), ArmTheWatch()]),
      );
    });

    test('coming back within reach arms the Watch again', () {
      expect(
        _reduce(none, const ReachChanged(reachable: true)),
        _to(none, const [ArmTheWatch()]),
      );
    });

    test('a long press, going offline and a landed call change nothing', () {
      for (final event in [
        LongPress(somebodyToAsk: true, at: _at),
        LongPress(somebodyToAsk: false, at: _at),
        const ReachChanged(reachable: false),
        const TheCallLanded(),
      ]) {
        expect(
          _reduce(none, event),
          _to(none, const <Effect>[]),
          reason: '$event',
        );
      }
    });
  });

  group('a warning told in an answer rather than a read', () {
    test('marks a room with no halt and arms the Watch', () {
      expect(
        _reduce(const NoHalt(), const TheAnswerWarned()),
        _to(const Warning(), const [ArmTheWatch()]),
      );
    });

    test('keeps a standing warning', () {
      expect(
        _reduce(const Warning(), const TheAnswerWarned()),
        _to(const Warning(), const [ArmTheWatch()]),
      );
    });

    test('stands beneath a blocking halt', () {
      expect(
        _reduce(
          const Blocking(ThePart(), serverKnows: true),
          const TheAnswerWarned(),
        ),
        _to(
          const Blocking(ThePart(), warningBeneath: true, serverKnows: true),
          const [ArmTheWatch()],
        ),
      );
    });
  });

  group('from a warning', () {
    const warning = Warning();

    test('a read with nothing standing ends it, and the Watch beats on', () {
      expect(
        _reduce(warning, _nothingStands),
        _to(const NoHalt(), const [ArmTheWatch()]),
      );
    });

    test('a read warning keeps it and the Watch', () {
      expect(
        _reduce(warning, _aWarningStands),
        _to(warning, const [ArmTheWatch()]),
      );
    });

    test('a read blocking halt wins over it and remembers the warning', () {
      expect(
        _reduce(warning, _aBlockingHalt()),
        _to(
          const Blocking(
            NothingKept(),
            warningBeneath: true,
            serverKnows: true,
          ),
          const [..._entering, ArmTheWatch()],
        ),
      );
    });

    test('a raised halt wins over it and remembers the warning', () {
      expect(
        _reduce(warning, const RoomRaisedAHalt()),
        _to(const Blocking(NothingKept(), warningBeneath: true), const [
          ..._entering,
          CallForAPerson(),
          ArmTheWatch(),
        ]),
      );
    });

    test('a raised halt that cannot call wins over it without a call', () {
      expect(
        _reduce(warning, const RoomRaisedAHalt(callsForAPerson: false)),
        _to(const Blocking(NothingKept(), warningBeneath: true), const [
          ..._entering,
          ArmTheWatch(),
        ]),
      );
    });

    test('a landed call changes nothing', () {
      expect(
        _reduce(warning, const TheCallLanded()),
        _to(warning, const <Effect>[]),
      );
    });

    test('the Watch firing reads the state and beats again', () {
      expect(
        _reduce(warning, const WatchFired()),
        _to(warning, const [ReadTheState(), ArmTheWatch()]),
      );
    });

    test('a long press refuses the team nothing and lifts nothing', () {
      expect(
        _reduce(warning, LongPress(somebodyToAsk: true, at: _at)),
        _to(warning, const <Effect>[]),
      );
      expect(
        _reduce(warning, LongPress(somebodyToAsk: false, at: _at)),
        _to(warning, const <Effect>[]),
      );
    });

    test('going offline keeps it; coming back arms the Watch again', () {
      expect(
        _reduce(warning, const ReachChanged(reachable: false)),
        _to(warning, const <Effect>[]),
      );
      expect(
        _reduce(warning, const ReachChanged(reachable: true)),
        _to(warning, const [ArmTheWatch()]),
      );
    });
  });

  group('from a blocking halt', () {
    const known = Blocking(ThePart(), serverKnows: true);
    const overAWarning = Blocking(
      ThePart(),
      warningBeneath: true,
      serverKnows: true,
    );
    const unknown = Blocking(ThePart());

    test('a read with nothing standing lifts it: the kept sound replays and '
        'the Watch beats on', () {
      expect(
        _reduce(known, _nothingStands),
        _to(const NoHalt(), const [
          StopCallingForAPerson(),
          ReplayTheSound(ThePart()),
          ArmTheWatch(),
        ]),
      );
    });

    test('a read warning lifts it into the warning, still watched', () {
      expect(
        _reduce(known, _aWarningStands),
        _to(const Warning(), const [
          StopCallingForAPerson(),
          ReplayTheSound(ThePart()),
          ArmTheWatch(),
        ]),
      );
    });

    test(
      'a read blocking halt keeps it as it was, and the server knows it',
      () {
        expect(
          _reduce(unknown, _aBlockingHalt(sounding: const NothingKept())),
          _to(known, const [ArmTheWatch()]),
        );
        expect(
          _reduce(overAWarning, _aBlockingHalt()),
          _to(overAWarning, const [ArmTheWatch()]),
        );
      },
    );

    test('a read with nothing standing does not lift a halt the server has not '
        'heard of yet', () {
      expect(
        _reduce(unknown, _nothingStands),
        _to(unknown, const [ArmTheWatch()]),
      );
    });

    test('a read warning over a halt the server has not heard of yet keeps '
        'the halt and remembers the warning', () {
      expect(
        _reduce(unknown, _aWarningStands),
        _to(const Blocking(ThePart(), warningBeneath: true), const [
          ArmTheWatch(),
        ]),
      );
    });

    test('a landed call tells the halt the server knows it', () {
      expect(
        _reduce(unknown, const TheCallLanded()),
        _to(known, const <Effect>[]),
      );
    });

    test('another raised halt keeps the first halt\'s sound and calls', () {
      expect(
        _reduce(known, const RoomRaisedAHalt(sounding: NothingKept())),
        _to(known, const [CallForAPerson(), ArmTheWatch()]),
      );
    });

    test('another raised halt that cannot call only keeps the Watch', () {
      expect(
        _reduce(known, const RoomRaisedAHalt(callsForAPerson: false)),
        _to(known, const [ArmTheWatch()]),
      );
    });

    test('going offline keeps a halt the server has not heard of', () {
      expect(
        _reduce(unknown, const ReachChanged(reachable: false)),
        _to(unknown, const <Effect>[]),
      );
    });

    test('a read that went out before the call landed never lifts it', () {
      expect(
        _reduce(known, _nothingStoodBeforeTheCall),
        _to(known, const [ArmTheWatch()]),
      );
    });

    test('the Watch firing reads the state and beats again', () {
      expect(
        _reduce(known, const WatchFired()),
        _to(known, const [ReadTheState(), ArmTheWatch()]),
      );
    });

    test('a long press with somebody to ask tells a person arrived and reads '
        'the state', () {
      expect(
        _reduce(known, LongPress(somebodyToAsk: true, at: _at)),
        _to(known, const [TellAPersonArrived(), ReadTheState()]),
      );
    });

    test('a long press with nobody to ask releases it locally', () {
      expect(
        _reduce(known, LongPress(somebodyToAsk: false, at: _at)),
        _to(const NoHalt(), const [
          StopCallingForAPerson(),
          ReplayTheSound(ThePart()),
          ArmTheWatch(),
        ]),
      );
    });

    test('a long press on a halt the server never heard of releases it '
        'locally', () {
      expect(
        _reduce(unknown, LongPress(somebodyToAsk: true, at: _at)),
        _to(const NoHalt(), const [
          StopCallingForAPerson(),
          ReplayTheSound(ThePart()),
          ArmTheWatch(),
        ]),
      );
    });

    test('lifted over a warning, the warning stands again, still watched', () {
      expect(
        _reduce(overAWarning, LongPress(somebodyToAsk: false, at: _at)),
        _to(const Warning(), const [
          StopCallingForAPerson(),
          ReplayTheSound(ThePart()),
          ArmTheWatch(),
        ]),
      );
    });

    test('going offline keeps it; coming back arms the Watch again', () {
      expect(
        _reduce(known, const ReachChanged(reachable: false)),
        _to(known, const <Effect>[]),
      );
      expect(
        _reduce(known, const ReachChanged(reachable: true)),
        _to(known, const [ArmTheWatch()]),
      );
    });

    test('coming back within reach calls again for a halt the server has not '
        'heard of', () {
      expect(
        _reduce(unknown, const ReachChanged(reachable: true)),
        _to(unknown, const [CallForAPerson(), ArmTheWatch()]),
      );
    });

    test('a halt over an opening that could not be fetched is lifted by asking '
        'the opening again with a fresh turn id', () {
      const failed = '1727700000000';
      final (next, effects) = _reduce(
        const Blocking(TheOpening(failed), serverKnows: true),
        _nothingStands,
      );

      expect(next, const NoHalt());
      expect(effects.first, const StopCallingForAPerson());
      expect(effects.last, const ArmTheWatch());
      final ask = effects.whereType<AskTheOpeningAgain>().single;
      expect(ask.freshTurnId, isNot(failed));
      expect(effects.whereType<ReplayTheSound>(), isEmpty);
    });
  });
}

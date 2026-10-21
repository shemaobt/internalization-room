import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

SessionRead _read({
  String status = 'in_progress',
  HaltKind halt = HaltKind.unnamed,
}) => SessionRead(
  SessionSnapshot(
    sessionId: 'sessao-1',
    pericope: 'rute-1',
    status: status,
    coverage: null,
    done: false,
    halt: halt,
  ),
);

SessionRead get _nothingStands => _read();
SessionRead get _aWarningStands =>
    _read(status: 'needs_person', halt: HaltKind.warning);
SessionRead _aBlockingHalt() =>
    _read(status: 'needs_person', halt: HaltKind.blocking);

const _entering = [SilenceTheRoom(), CloseAndDiscardTheMic()];

(Halt, List<Effect>) _reduce(Halt halt, MachineEvent event) {
  final (machine, effects) = reduce(Machine(halt: halt), event);
  return (
    machine.halt,
    effects.where((effect) => effect is! ResendPending).toList(),
  );
}

bool _ofTheHalt(Effect effect) => switch (effect) {
  SilenceTheRoom() ||
  CloseAndDiscardTheMic() ||
  ArmTheWatch() ||
  CallForAPerson() ||
  StopCallingForAPerson() ||
  GoOnAfterTheSign() => true,
  _ => false,
};

(Halt, List<Effect>) _acrossTheReach(Halt halt, MachineEvent event) {
  final (machine, effects) = reduce(
    Machine(
      halt: halt,
      reach: event is NetworkReturned ? Reach.outOfReach : Reach.reachable,
    ),
    event,
  );
  return (machine.halt, effects.where(_ofTheHalt).toList());
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

    test('an opening missed lets the opening go and raises no halt', () {
      const opening = TheOpeningMissed();
      expect(_reduce(none, opening), _to(none, const [LetTheOpeningGo()]));
      expect(
        _reduce(const Blocking(), opening),
        _to(const Blocking(), const [LetTheOpeningGo()]),
      );
    });

    test(
      'a look that finds no opening lets the opening go and raises no halt',
      () {
        const turn = Turn('sessao-1', 'turno-7');
        const opening = LookEmpty(turn, sounding: TheOpening('turno-7'));
        (Halt, List<Effect>) looked(Halt halt) {
          final (machine, effects) = reduce(
            Machine(
              halt: halt,
              look: const TheLook(turn, sounding: TheOpening('turno-7')),
            ),
            opening,
          );
          return (machine.halt, effects);
        }

        expect(looked(none), _to(none, const [LetTheOpeningGo()]));
        expect(
          looked(const Blocking()),
          _to(const Blocking(), const [LetTheOpeningGo()]),
        );
      },
    );

    test('a read warning marks the room and arms the Watch', () {
      expect(
        _reduce(none, _aWarningStands),
        _to(const Warning(), const [ArmTheWatch()]),
      );
    });

    test('a Session read that says the room needs a person raises no sign', () {
      expect(
        _reduce(none, _aBlockingHalt()),
        isA<(Halt, List<Effect>)>()
            .having((result) => result.$1, 'the halt', none)
            .having(
              (result) => result.$2,
              'the effects',
              isNot(contains(const CallForAPerson())),
            ),
      );
    });

    test('a rehearsal part\'s sound failing twice brings no sign', () {
      var machine = const Machine(
        station: Retro(),
        channel: PartPlaying(PartSound(0, 'parte-0.m4a')),
      );
      for (var failure = 0; failure < 2; failure++) {
        (machine, _) = reduce(
          machine.copyWith(
            channel: const PartPlaying(PartSound(0, 'parte-0.m4a')),
          ),
          const PlayerFailed(Source.take('parte-0.m4a')),
        );
      }
      expect(machine.halt, isNot(isA<Blocking>()));

      var guide = const Machine();
      for (var failure = 0; failure < 2; failure++) {
        (guide, _) = reduce(guide, const PlayerFailed(Source.guide));
      }
      expect(guide.halt, isA<Blocking>());
    });

    test('a raised halt calls for a person and arms the Watch', () {
      expect(
        _reduce(none, const RoomRaisedAHalt()),
        _to(const Blocking(), const [
          ..._entering,
          CallForAPerson(),
          ArmTheWatch(),
        ]),
      );
    });

    test('a raised halt that cannot call still arms the Watch', () {
      expect(
        _reduce(none, const RoomRaisedAHalt(callsForAPerson: false)),
        _to(const Blocking(), const [..._entering, ArmTheWatch()]),
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
        _acrossTheReach(none, const NetworkReturned()),
        _to(none, const [ArmTheWatch()]),
      );
    });

    test('a tap and going offline change nothing', () {
      for (final event in [
        const TeamTapped(),
        const NetworkFailedAt(Door.watch),
      ]) {
        expect(
          _acrossTheReach(none, event),
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
        _reduce(const Blocking(), const TheAnswerWarned()),
        _to(const Blocking(warningBeneath: true), const [ArmTheWatch()]),
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

    test('a Session read that says the room needs a person raises no sign '
        'over it', () {
      expect(
        _reduce(warning, _aBlockingHalt()),
        isA<(Halt, List<Effect>)>()
            .having((result) => result.$1, 'the halt', warning)
            .having(
              (result) => result.$2,
              'the effects',
              isNot(contains(const CallForAPerson())),
            ),
      );
    });

    test('a raised halt wins over it and remembers the warning', () {
      expect(
        _reduce(warning, const RoomRaisedAHalt()),
        _to(const Blocking(warningBeneath: true), const [
          ..._entering,
          CallForAPerson(),
          ArmTheWatch(),
        ]),
      );
    });

    test('a raised halt that cannot call wins over it without a call', () {
      expect(
        _reduce(warning, const RoomRaisedAHalt(callsForAPerson: false)),
        _to(const Blocking(warningBeneath: true), const [
          ..._entering,
          ArmTheWatch(),
        ]),
      );
    });

    test('the Watch firing reads the state and beats again', () {
      expect(
        _reduce(warning, const WatchFired()),
        _to(warning, const [ReadTheState(), ArmTheWatch()]),
      );
    });

    test('a tap refuses the team nothing and lifts nothing', () {
      expect(
        _reduce(warning, const TeamTapped()),
        _to(warning, const <Effect>[]),
      );
    });

    test('going offline keeps it; coming back arms the Watch again', () {
      expect(
        _acrossTheReach(warning, const NetworkFailedAt(Door.watch)),
        _to(warning, const <Effect>[]),
      );
      expect(
        _acrossTheReach(warning, const NetworkReturned()),
        _to(warning, const [ArmTheWatch()]),
      );
    });
  });

  group('from a blocking halt', () {
    const sign = Blocking();
    const overAWarning = Blocking(warningBeneath: true);

    test('a read with nothing standing keeps it, and the Watch beats on', () {
      expect(_reduce(sign, _nothingStands), _to(sign, const [ArmTheWatch()]));
      expect(
        _reduce(overAWarning, _nothingStands),
        _to(sign, const [ArmTheWatch()]),
      );
    });

    test('a read warning keeps it and remembers the warning beneath', () {
      expect(
        _reduce(sign, _aWarningStands),
        _to(overAWarning, const [ArmTheWatch()]),
      );
    });

    test('a read blocking halt keeps it as it was', () {
      expect(_reduce(sign, _aBlockingHalt()), _to(sign, const [ArmTheWatch()]));
      expect(
        _reduce(overAWarning, _aBlockingHalt()),
        _to(overAWarning, const [ArmTheWatch()]),
      );
    });

    test('another raised halt keeps it and calls', () {
      expect(
        _reduce(sign, const RoomRaisedAHalt()),
        _to(sign, const [CallForAPerson(), ArmTheWatch()]),
      );
    });

    test('another raised halt that cannot call only keeps the Watch', () {
      expect(
        _reduce(sign, const RoomRaisedAHalt(callsForAPerson: false)),
        _to(sign, const [ArmTheWatch()]),
      );
    });

    test('the Watch firing reads the state and beats again', () {
      expect(
        _reduce(sign, const WatchFired()),
        _to(sign, const [ReadTheState(), ArmTheWatch()]),
      );
    });

    test('the team\'s tap clears it and the Watch beats on', () {
      expect(
        _reduce(sign, const TeamTapped()),
        _to(const NoHalt(), const [
          StopCallingForAPerson(),
          GoOnAfterTheSign(),
          ArmTheWatch(),
        ]),
      );
    });

    test('tapped over a warning, the warning stands again, still watched', () {
      expect(
        _reduce(overAWarning, const TeamTapped()),
        _to(const Warning(), const [
          StopCallingForAPerson(),
          GoOnAfterTheSign(),
          ArmTheWatch(),
        ]),
      );
    });

    test(
      'going offline keeps it; coming back calls again and arms the Watch',
      () {
        expect(
          _acrossTheReach(sign, const NetworkFailedAt(Door.watch)),
          _to(sign, const <Effect>[]),
        );
        expect(
          _acrossTheReach(sign, const NetworkReturned()),
          _to(sign, const [CallForAPerson(), ArmTheWatch()]),
        );
      },
    );
  });
}

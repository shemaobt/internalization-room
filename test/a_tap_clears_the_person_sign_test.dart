import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/failure_policy.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

const _turn = Turn('sessao-1', 'turno-1');

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

SessionRead get _theDeskStillHasIt =>
    _read(status: 'needs_person', halt: HaltKind.blocking);

SessionRead get _theDeskMarkedAPersonArrived => _read();

(Machine, List<Effect>) _refused(
  Machine machine, {
  Kept sounding = const NothingKept(),
}) => reduce(
  machine,
  FailurePolicy.decide(
    const RoomRefused('X'),
    FailureContext(
      station: machine.station,
      generation: machine.generation,
      turn: _turn,
      rule: RefusalRule.aSpokenTurn,
      sounding: sounding,
    ),
  ),
);

(Machine, List<Effect>) _aTurnTheRoomRefused() =>
    _refused(const Machine(station: Canvas(), inFlight: _turn));

bool _sounds(Effect effect) =>
    effect is PlayLine || effect is PlayPart || effect is PlayStretch;

void main() {
  test(
    'a turn the room refuses shows the sign, and a tap brings the room to rest',
    () {
      final (signed, _) = _aTurnTheRoomRefused();

      expect(signed.halt, isA<Blocking>());

      final (rested, effects) = reduce(signed, const TeamTapped());

      expect(rested.halt, const NoHalt());
      expect(rested.channel, const Silence());
      expect(effects, contains(const StopCallingForAPerson()));
    },
  );

  test(
    'nothing waits for the desk: ten minutes of reads that still say needs_person never bring the sign back after the tap',
    () {
      final (signed, _) = _aTurnTheRoomRefused();

      var held = signed;
      for (var beat = 0; beat < 20; beat++) {
        (held, _) = reduce(held, const WatchFired());
        (held, _) = reduce(held, _theDeskStillHasIt);
        expect(
          held.halt,
          isA<Blocking>(),
          reason: 'beat $beat, before the tap',
        );
      }

      var rested = reduce(signed, const TeamTapped()).$1;
      for (var beat = 0; beat < 20; beat++) {
        (rested, _) = reduce(rested, const WatchFired());
        (rested, _) = reduce(rested, _theDeskStillHasIt);
        expect(
          rested.halt,
          const NoHalt(),
          reason: 'beat $beat, after the tap',
        );
      }
    },
  );

  test('the sign plays nothing', () {
    final (signed, raising) = _refused(
      const Machine(station: Canvas(), inFlight: _turn),
      sounding: const TheLineSaidAgain(),
    );
    final (rested, tapping) = reduce(signed, const TeamTapped());

    expect(rested.halt, const NoHalt());
    expect([...raising, ...tapping].where(_sounds), isEmpty);
  });

  test('the tap replays nothing and resends nothing', () {
    const part = PartSound(1, '/parte-1.m4a');
    final (signed, _) = _refused(
      const Machine(
        station: Retro(),
        inFlight: _turn,
        channel: PartPlaying(part),
      ),
      sounding: const ThePart(),
    );
    final (rested, effects) = reduce(signed, const TeamTapped());

    expect(rested.halt, const NoHalt());
    expect(effects.whereType<PlayPart>(), isEmpty);
    expect(effects.whereType<ResendPending>(), isEmpty);
    expect(effects.whereType<LookAtTheSession>(), isEmpty);
    expect(effects.whereType<DrainTheOutbox>(), isEmpty);
  });

  test('a tap restores the warning beneath', () {
    final (rested, _) = reduce(
      const Machine(halt: Blocking(warningBeneath: true)),
      const TeamTapped(),
    );

    expect(rested.halt, const Warning());
  });

  test('the Desk marking a person arrived later changes nothing', () {
    final (signed, _) = _aTurnTheRoomRefused();

    final (stillSigned, _) = reduce(signed, _theDeskMarkedAPersonArrived);
    expect(stillSigned.halt, isA<Blocking>());

    final (rested, _) = reduce(signed, const TeamTapped());
    final (afterTheMark, effects) = reduce(
      rested,
      _theDeskMarkedAPersonArrived,
    );
    expect(afterTheMark.halt, const NoHalt());
    expect(effects, isEmpty);
  });

  test('a look the sign held resumes on the tap', () {
    final (_, effects) = reduce(
      const Machine(
        halt: Blocking(),
        look: TheLook(_turn, stillAnswering: true, suspended: true),
      ),
      const TeamTapped(),
    );

    expect(effects, contains(const LookAgain(_turn)));
    expect(effects, contains(const ResumeTheWait()));
  });

  test('a tap with no sign does nothing', () {
    const warned = Machine(station: Canvas(), halt: Warning());

    final (after, effects) = reduce(warned, const TeamTapped());

    expect(after.halt, const Warning());
    expect(after.channel, const Silence());
    expect(effects, isEmpty);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';

const _reachable = Machine();
const _outOfReach = Machine(reach: Reach.outOfReach, noticeSaid: true);
const _onePartPending = {'linha-1': PartFact.pending};
const _notice = Line(LineKind.offlineNotice, 1, source: Source.guide);

(Machine, List<Effect>) _run(Machine from, List<MachineEvent> events) {
  var machine = from;
  final effects = <Effect>[];
  for (final event in events) {
    final (next, said) = reduce(machine, event);
    machine = next;
    effects.addAll(said);
  }
  return (machine, effects);
}

void main() {
  group('2 (b): reachable with a part pending, the retry is armed by the '
      'Outbox\'s own backoff', () {
    test('a tally with a part pending arms the retry when it is due', () {
      final (machine, effects) = reduce(
        _reachable,
        const OutboxChanged(_onePartPending, due: Duration(seconds: 30)),
      );

      expect(machine.reachable, isTrue);
      expect(effects, contains(const ArmTheRetry(due: Duration(seconds: 30))));
    });

    test('the retry firing drains the Outbox', () {
      final (machine, effects) = _run(_reachable, const [
        OutboxChanged(_onePartPending, due: Duration(seconds: 30)),
        RetryFired(),
      ]);

      expect(effects.last, const DrainTheOutbox());
      expect(machine.draining, isTrue);
    });

    test('a tally with nothing pending cancels the retry', () {
      final (_, effects) = _run(_reachable, const [
        OutboxChanged(_onePartPending, due: Duration(seconds: 30)),
        OutboxChanged({'linha-1': PartFact.sent}),
      ]);

      expect(effects.last, const CancelTheRetry());
    });
  });

  group('5: a network failure at any door takes the room out of reach', () {
    for (final door in Door.values) {
      test('the ${door.name} door', () {
        final (machine, effects) = reduce(_reachable, NetworkFailedAt(door));

        expect(machine.reach, Reach.outOfReach);
        expect(effects, contains(const ArmTheRetry()));
      });
    }

    test('out of reach, the retry probes the room', () {
      final (_, effects) = reduce(_outOfReach, const RetryFired());

      expect(effects, [const ProbeTheRoom()]);
    });

    test('a return the room never answered climbs the ladder too', () {
      final (_, effects) = _run(_reachable, const [
        NetworkFailedAt(Door.watch),
        NetworkReturned(),
        NetworkFailedAt(Door.watch),
        NetworkReturned(),
        NetworkFailedAt(Door.watch),
      ]);

      expect(effects.whereType<ArmTheRetry>().map((arm) => arm.step), [
        0,
        1,
        2,
      ]);
    });

    test('an answer after the return starts the ladder over', () {
      final (_, effects) = _run(_reachable, const [
        NetworkFailedAt(Door.watch),
        NetworkReturned(),
        NetworkFailedAt(Door.watch),
        NetworkReturned(),
        TheRoomAnswered(),
        NetworkFailedAt(Door.watch),
      ]);

      expect(effects.whereType<ArmTheRetry>().map((arm) => arm.step), [
        0,
        1,
        0,
      ]);
    });

    test('a probe that fails climbs the ladder', () {
      final (machine, effects) = _run(_outOfReach, const [
        NetworkFailedAt(Door.probe),
        NetworkFailedAt(Door.probe),
      ]);

      expect(machine.reach, Reach.outOfReach);
      expect(effects.whereType<ArmTheRetry>(), [
        const ArmTheRetry(step: 1),
        const ArmTheRetry(step: 2),
      ]);
    });
  });

  test('8: the return drains the Outbox and re-sends the pending request '
      'exactly once', () {
    final (machine, effects) = _run(_outOfReach, const [
      NetworkReturned(),
      NetworkReturned(),
    ]);

    expect(machine.reach, Reach.reachable);
    expect(effects.whereType<ResendPending>(), hasLength(1));
    expect(effects.whereType<DrainTheOutbox>(), hasLength(1));
    expect(effects, contains(const CancelTheRetry()));
  });

  test('8: under a blocking halt the return re-sends nothing, and the lift '
      're-sends once', () {
    final (_, returned) = reduce(
      _outOfReach.copyWith(halt: const Blocking(NothingKept())),
      const NetworkReturned(),
    );
    final (_, lifted) = _run(
      _outOfReach.copyWith(halt: const Blocking(NothingKept())),
      [const NetworkReturned(), const LongPress(somebodyToAsk: false)],
    );

    expect(returned.whereType<ResendPending>(), isEmpty);
    expect(lifted.whereType<ResendPending>(), hasLength(1));
  });

  test('4 (d): the return reads the session at once and arms the Watch '
      'again', () {
    final (_, effects) = reduce(_outOfReach, const NetworkReturned());

    expect(effects, containsAllInOrder(const [ReadTheState(), ArmTheWatch()]));
  });

  group('10: the offline notice is said once per outage', () {
    test('two falls in one outage ask for it once', () {
      final (_, effects) = _run(_reachable, const [
        NetworkFailedAt(Door.watch),
        NetworkFailedAt(Door.inbox),
        NetworkReturned(),
        NetworkFailedAt(Door.watch),
      ]);

      expect(effects.whereType<SayTheOfflineNotice>(), hasLength(1));
    });

    test('a second outage, after the room answered, asks for it again', () {
      final (_, effects) = _run(_reachable, const [
        NetworkFailedAt(Door.watch),
        NetworkReturned(),
        TheRoomAnswered(),
        NetworkFailedAt(Door.outbox),
      ]);

      expect(effects.whereType<SayTheOfflineNotice>(), hasLength(2));
    });

    test('a return the room never answered is still the same outage', () {
      final (_, effects) = _run(_reachable, const [
        NetworkFailedAt(Door.watch),
        NetworkReturned(),
        NetworkFailedAt(Door.watch),
      ]);

      expect(effects.whereType<SayTheOfflineNotice>(), hasLength(1));
    });

    test('a notice still waiting leaves the queue when the reach returns', () {
      final (machine, effects) = _run(
        _outOfReach.copyWith(channel: const Microphone(MicOwner.conversation)),
        const [LineArrived(_notice), NetworkReturned()],
      );

      expect(machine.queue, isEmpty);
      expect(effects, contains(const DropTheLine(_notice)));
      expect(effects, isNot(contains(const PlayLine(_notice))));
    });
  });
}

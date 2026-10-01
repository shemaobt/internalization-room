import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';

import 'machine_generator.dart';

Halt _haltOf(Halt halt) => halt;

final _machine = Machine<Halt>(
  start: const NoHalt(),
  step: reduce,
  draw: (_, world, random) => drawAnEvent(world, random),
  show: describeHalt,
);

final _oneSeed = int.tryParse(Platform.environment['MACHINE_SEED'] ?? '');
final Iterable<int> _seeds = switch (_oneSeed) {
  final seed? => [seed],
  null => List.generate(500, (seed) => seed),
};

String _kind(Halt halt) => switch (halt) {
  NoHalt() => 'none',
  Warning() => 'warning',
  Blocking() => 'blocking',
};

Halt _whatTheSessionReadTells(SessionSnapshot snapshot) => snapshot.needsPerson
    ? const Blocking(NothingKept())
    : snapshot.halt == HaltKind.warning
    ? const Warning()
    : const NoHalt();

Invariant<S> enteringABlockingHaltClosesTheMicrophone<S>(
  Halt Function(S) haltOf,
) => Invariant(
  'ADR invariant 2, entering a blocking halt closes the microphone',
  (before, event, after, effects, world) {
    if (haltOf(before) is Blocking || haltOf(after) is! Blocking) return null;
    final closes =
        effects.contains(const CloseAndDiscardTheMic()) &&
        effects.contains(const SilenceTheRoom());
    return closes
        ? null
        : 'entered a blocking halt without closing the microphone';
  },
);

Invariant<S> aHaltNeverStandsWithoutTheWatch<S>(Halt Function(S) haltOf) =>
    Invariant('ADR invariant 3, a halt never stands without the Watch', (
      before,
      event,
      after,
      effects,
      world,
    ) {
      final halt = haltOf(after);
      if (halt is NoHalt || world.watchArmed) return null;
      return '${_kind(halt)} halt stands with the Watch unarmed';
    });

Invariant<S> aSessionReadIsAppliedWholeOrNotAtAll<S>(Halt Function(S) haltOf) =>
    Invariant(
      'ADR invariant 5, a Session read is applied whole or not at all',
      (before, event, after, effects, world) {
        if (event is! SessionRead) return null;
        final was = haltOf(before);
        final now = haltOf(after);
        final told = _whatTheSessionReadTells(event.snapshot);
        final applied =
            _kind(now) == _kind(told) && (now is! Blocking || now.serverKnows);
        final refusedWhole =
            was is Blocking &&
            now is Blocking &&
            now.kept == was.kept &&
            now.serverKnows == was.serverKnows &&
            (!was.serverKnows || event.sentBeforeTheCallLanded);
        if (applied || refusedWhole) return null;
        return 'the Session read told ${_kind(told)} over ${_kind(was)}, '
            'the halt became ${describeHalt(now)}';
      },
    );

bool _tellsThePersonOrBringsTheSoundBack(Effect effect) => switch (effect) {
  TellAPersonArrived() || ReplayTheSound() || AskTheOpeningAgain() => true,
  _ => false,
};

Invariant<S> aLongPressOnABlockingHaltNeverVanishesInSilence<S>(
  Halt Function(S) haltOf,
) => Invariant(
  'ADR invariant 11, a long press on a blocking halt is answered',
  (before, event, after, effects, world) {
    if (event is! LongPress || haltOf(before) is! Blocking) return null;
    if (_kind(haltOf(after)) != _kind(haltOf(before)) ||
        effects.any(_tellsThePersonOrBringsTheSoundBack)) {
      return null;
    }
    return 'a long press under ${describeHalt(haltOf(before))} answered '
        'with neither a lift nor a person told nor the sound back: '
        '${effects.map(describeEffect).join(', ')}';
  },
);

Invariant<S> theWarningIsTheOneTheServerTold<S>(
  Halt Function(S) haltOf,
) => Invariant(
  'ADR invariant 15, the warning the tablet holds is the one the server told',
  (before, event, after, effects, world) {
    final now = haltOf(after);
    final tabletHolds = switch (now) {
      Warning() => true,
      Blocking(:final warningBeneath) => warningBeneath,
      NoHalt() => false,
    };
    if (tabletHolds == world.serverHoldsAWarning) return null;
    return 'the server holds a warning: ${world.serverHoldsAWarning}, '
        'the halt is ${describeHalt(now)}';
  },
);

List<Invariant<S>> theAdrInvariants<S>(Halt Function(S) haltOf) => [
  enteringABlockingHaltClosesTheMicrophone(haltOf),
  aHaltNeverStandsWithoutTheWatch(haltOf),
  aSessionReadIsAppliedWholeOrNotAtAll(haltOf),
  aLongPressOnABlockingHaltNeverVanishesInSilence(haltOf),
  theWarningIsTheOneTheServerTold(haltOf),
];

void _holds(Invariant<Halt> invariant) =>
    expectEverySeedHolds(_machine, [invariant], seeds: _seeds);

void main() {
  group('the machine holds, on every seeded sequence', () {
    test('ADR invariant 2: entering a blocking halt closes the microphone', () {
      _holds(enteringABlockingHaltClosesTheMicrophone(_haltOf));
    });

    test('ADR invariant 3: a halt never stands without the Watch', () {
      _holds(aHaltNeverStandsWithoutTheWatch(_haltOf));
    });

    test('ADR invariant 5: a Session read is applied whole or not at all', () {
      _holds(aSessionReadIsAppliedWholeOrNotAtAll(_haltOf));
    });

    test('ADR invariant 11: a long press on a blocking halt never '
        'vanishes in silence', () {
      _holds(aLongPressOnABlockingHaltNeverVanishesInSilence(_haltOf));
    });

    test('ADR invariant 15: the warning the tablet holds is the one the '
        'server told, after every event', () {
      _holds(theWarningIsTheOneTheServerTold(_haltOf));
    });

    test('ADR invariants 2, 3, 5, 11 and 15 hold over the default run', () {
      expectEverySeedHolds(
        _machine,
        theAdrInvariants<Halt>(_haltOf),
        seeds: _seeds,
      );
    });
  });

  group('the generator', () {
    test('generator invariant 1: every drawn event is valid for its world', () {
      for (final seed in _seeds) {
        final trace = runSequence(_machine, const <Invariant<Halt>>[], seed);
        for (final entry in trace.entries) {
          if (entry.event is WatchFired) {
            expect(
              entry.worldBefore.watchArmed,
              isTrue,
              reason: 'seed $seed drew WatchFired with the Watch unarmed',
            );
          }
          final event = entry.event;
          if (event is SessionRead && event.sentBeforeTheCallLanded) {
            expect(
              entry.worldBefore.callOutstanding,
              isTrue,
              reason:
                  'seed $seed drew a Session read sent before the call '
                  'landed with no call outstanding',
            );
          }
          if (entry.event is TheCallLanded) {
            expect(
              entry.worldBefore.callOutstanding,
              isTrue,
              reason: 'seed $seed drew TheCallLanded with no call outstanding',
            );
          }
        }
      }
    });

    test('generator invariant 2: the same seed yields the same sequence', () {
      List<String> eventsOf(int seed) => [
        for (final entry in runSequence(
          _machine,
          const <Invariant<Halt>>[],
          seed,
        ).entries)
          describeEvent(entry.event),
      ];

      expect(eventsOf(42), equals(eventsOf(42)));
      expect(eventsOf(42), isNot(equals(eventsOf(43))));
    });

    test('generator invariant 3: a failing sequence names its seed and '
        'its trace', () {
      final aHaltNeverStands = Invariant<Halt>(
        'a halt never stands',
        (before, event, after, effects, world) =>
            after is NoHalt ? null : 'a halt stands: ${describeHalt(after)}',
      );
      final events = [
        for (final entry in runSequence(_machine, [
          aHaltNeverStands,
        ], 7).entries)
          describeEvent(entry.event),
      ];

      expect(
        () => expectEverySeedHolds(_machine, [aHaltNeverStands], seeds: [7]),
        throwsA(
          isA<TestFailure>()
              .having(
                (failure) => failure.message,
                'message',
                startsWith('seed 7 broke'),
              )
              .having(
                (failure) => failure.message,
                'message',
                contains('a halt never stands'),
              )
              .having(
                (failure) => failure.message,
                'message',
                allOf([for (final event in events) contains(event)]),
              ),
        ),
      );
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/cut_point.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

import 'machine_generator.dart';

Halt _haltOf(Machine machine) => machine.halt;

final _machine = MachineUnderTest<Machine>(
  start: const Machine(),
  step: reduce,
  draw: (_, world, random) => drawAnEvent(world, random),
  show: describeMachine,
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
  TellAPersonArrived() || ReplayTheSound() => true,
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

bool _sounds(Channel channel) => channel is Playing || channel is GuideSpeaking;

final theMicrophoneOpensOverASoundOnlyAfterAStop = Invariant<Machine>(
  'ADR invariant 1, the microphone opens over a sound only after a stop in the '
  'same step',
  (before, event, after, effects, world) {
    final opens = effects.indexWhere((effect) => effect is OpenTheMic);
    final stops = effects.indexWhere((effect) => effect is StopTheSound);
    if (opens >= 0 &&
        _sounds(before.channel) &&
        !(stops >= 0 && stops < opens)) {
      return 'the microphone opened over ${describeChannel(before.channel)}';
    }
    final starts = effects.any(
      (effect) =>
          effect is PlayLine || effect is PlayPart || effect is PlayStretch,
    );
    if (starts && after.channel is Microphone) {
      return 'a sound started under ${describeChannel(after.channel)}';
    }
    return null;
  },
);

final theHeadNeverReadsAnotherSound = Invariant<Machine>(
  'ADR invariant 8, the Head never reads another part\'s or stretch\'s position',
  (before, event, after, effects, world) {
    final now = after.channel;
    if (now is! Playing || event is PlayerOpened) return null;
    final was = before.channel;
    final sameSound = switch (was) {
      final Playing playing => identical(playing.sound, now.sound),
      Paused(:final what) => identical(what, now.sound),
      GuideSpeaking(held: Paused(:final what)) => identical(what, now.sound),
      _ => false,
    };
    if (sameSound || now.head != null) return null;
    return 'the Head of ${describeSound(now.sound)} reads the player before '
        'its opening, after ${describeChannel(was)}';
  },
);

final theScreenNeverShowsASoundTheChannelDoesNotHold = Invariant<Machine>(
  'ADR invariant 13, the screen never shows a sound the Channel does not hold',
  (before, event, after, effects, world) {
    for (final stage in SalaStage.values) {
      final screen = SalaSessionState(
        machine: after.copyWith(station: Station.stored(stage)),
      );
      final playing =
          screen.btClipRodando ||
          screen.btTrechoTocando ||
          screen.btRetroTocando ||
          screen.playPing;
      if (playing && after.channel is! Playing) {
        return '${stage.name} shows a sound over '
            '${describeChannel(after.channel)}';
      }
      if (screen.voice == VoiceState.speaking &&
          after.channel is! GuideSpeaking) {
        return '${stage.name} shows the Guide speaking over '
            '${describeChannel(after.channel)}';
      }
      if (screen.voice == VoiceState.listening &&
          after.channel is! Microphone) {
        return '${stage.name} shows an open microphone over '
            '${describeChannel(after.channel)}';
      }
    }
    return null;
  },
);

final theOutboxNeverIdlesReachableWithAPartPending = Invariant<Machine>(
  'ADR invariant 12, the Outbox never idles reachable with a part pending',
  (before, event, after, effects, world) {
    if (!after.reachable || !after.somethingPending) return null;
    if (world.retryArmed || world.draining) return null;
    return 'reachable with a part pending, no retry armed and no drain in '
        'flight';
  },
);

bool _callsOrStopsCallingAPerson(Effect effect) => switch (effect) {
  CallForAPerson() || TellAPersonArrived() => true,
  _ => false,
};

final nothingOfAGoneSessionSurvives = _nothingOfTheSessionSurvives(
  'ADR invariant 6, nothing of a gone session survives',
  (event) => event is TheSessionIsGone,
);

final nothingOfAClosedPassageSurvives = _nothingOfTheSessionSurvives(
  'ADR invariant 6, nothing of a closed passage survives',
  (event) => event is ThePassageClosed,
);

Invariant<Machine> _nothingOfTheSessionSurvives(
  String name,
  bool Function(MachineEvent event) leaves,
) => Invariant<Machine>(name, (before, event, after, effects, world) {
  if (!leaves(event)) return null;
  if (!effects.contains(const DiscardTheSession())) {
    return 'the session gone did not discard the session';
  }
  if (!effects.contains(const OpenTheChoice())) {
    return 'the session gone did not open the Choice';
  }
  if (!effects.contains(const CloseAndDiscardTheMic())) {
    return 'the session gone did not close and discard the microphone';
  }
  if (effects.contains(const CancelTheRetry())) {
    return 'the session gone cancelled the retry';
  }
  if (effects.any(_callsOrStopsCallingAPerson)) {
    return 'the session gone called or stopped calling a person: '
        '${effects.map(describeEffect).join(', ')}';
  }
  if (after.halt is! NoHalt) {
    return 'a ${describeHalt(after.halt)} stands after the session gone';
  }
  if (after.channel is! Silence) {
    return '${describeChannel(after.channel)} after the session gone';
  }
  final undropped = [
    for (final line in before.queue)
      if (!effects.contains(DropTheLine(line))) line,
  ];
  if (after.queue.isNotEmpty || undropped.isNotEmpty) {
    return 'lines of the session outlived it: '
        '${[...after.queue, ...undropped].map(describeLine).join(', ')}';
  }
  if (after.reach != before.reach) {
    return 'the session gone moved the Reach from ${before.reach.name} to '
        '${after.reach.name}';
  }
  return null;
});

void _holds(Invariant<Machine> invariant) =>
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

    test('ADR invariant 1: the microphone opens over a sound only after a stop '
        'in the same step', () {
      _holds(theMicrophoneOpensOverASoundOnlyAfterAStop);
    });

    test('ADR invariant 1 reads a microphone opened over a sound with no stop '
        'before it', () {
      const speaking = Machine(channel: GuideSpeaking(Line(LineKind.guide, 1)));
      const listening = Machine(channel: Microphone(MicOwner.conversation));
      const open = OpenTheMic(MicOwner.conversation, take: 'conversa');
      const cut = Interrupted(take: 'conversa', cut: CutPoint(Duration.zero));
      String? check(List<Effect> effects) =>
          theMicrophoneOpensOverASoundOnlyAfterAStop.check(
            speaking,
            cut,
            listening,
            effects,
            const World(),
          );

      expect(check(const [open]), isNotNull);
      expect(check(const [open, StopTheSound()]), isNotNull);
      expect(check(const [StopTheSound(), open]), isNull);
    });

    test('ADR invariant 8: the Head never reads another part\'s or '
        'stretch\'s position', () {
      _holds(theHeadNeverReadsAnotherSound);
    });

    test('ADR invariant 13: the screen never shows a sound the Channel does '
        'not hold', () {
      _holds(theScreenNeverShowsASoundTheChannelDoesNotHold);
    });

    test('ADR invariant 12: the Outbox never idles reachable with a part '
        'pending', () {
      _holds(theOutboxNeverIdlesReachableWithAPartPending);
    });

    test('ADR invariant 6: nothing of a gone session survives', () {
      _holds(nothingOfAGoneSessionSurvives);
    });

    test('the machine holds its invariants with the closed passage among its '
        'events', () {
      _holds(nothingOfAClosedPassageSurvives);
    });

    test('ADR invariants 1, 2, 3, 5, 6, 8, 11, 12, 13 and 15 hold over the '
        'default run', () {
      expectEverySeedHolds(_machine, [
        nothingOfAGoneSessionSurvives,
        nothingOfAClosedPassageSurvives,
        ...theAdrInvariants<Machine>(_haltOf),
        theMicrophoneOpensOverASoundOnlyAfterAStop,
        theHeadNeverReadsAnotherSound,
        theOutboxNeverIdlesReachableWithAPartPending,
        theScreenNeverShowsASoundTheChannelDoesNotHold,
      ], seeds: _seeds);
    });
  });

  group('the generator', () {
    test('generator invariant 1: every drawn event is valid for its world', () {
      for (final seed in _seeds) {
        final trace = runSequence(_machine, const <Invariant<Machine>>[], seed);
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

    test('generator invariant 4: the run reaches the room reachable with a '
        'part pending', () {
      final reached = [
        for (final seed in _seeds)
          for (final entry in runSequence(
            _machine,
            const <Invariant<Machine>>[],
            seed,
          ).entries)
            if (entry.after.reachable && entry.after.somethingPending) seed,
      ];

      expect(reached, isNotEmpty);
    });

    test('generator invariant 2: the same seed yields the same sequence', () {
      List<String> eventsOf(int seed) => [
        for (final entry in runSequence(
          _machine,
          const <Invariant<Machine>>[],
          seed,
        ).entries)
          describeEvent(entry.event),
      ];

      expect(eventsOf(42), equals(eventsOf(42)));
      expect(eventsOf(42), isNot(equals(eventsOf(43))));
    });

    test('generator invariant 3: a failing sequence names its seed and '
        'its trace', () {
      final aHaltNeverStands = Invariant<Machine>(
        'a halt never stands',
        (before, event, after, effects, world) => after.halt is NoHalt
            ? null
            : 'a halt stands: ${describeHalt(after.halt)}',
      );
      final events = [
        for (final entry in runSequence(_machine, [
          aHaltNeverStands,
        ], 0).entries)
          describeEvent(entry.event),
      ];

      expect(
        () => expectEverySeedHolds(_machine, [aHaltNeverStands], seeds: [0]),
        throwsA(
          isA<TestFailure>()
              .having(
                (failure) => failure.message,
                'message',
                startsWith('seed 0 broke'),
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

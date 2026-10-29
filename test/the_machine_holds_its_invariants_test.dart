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
    ? const Blocking()
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
        if (was is! Blocking) {
          final warns = event.snapshot.needsPerson
              ? was
              : _whatTheSessionReadTells(event.snapshot);
          if (_kind(now) == _kind(warns)) return null;
          return 'the Session read over ${_kind(was)} told '
              '${_kind(warns)}, the halt became ${describeHalt(now)}';
        }
        if (now is! Blocking) return null;
        final beneath = event.snapshot.needsPerson
            ? was.warningBeneath
            : event.snapshot.halt == HaltKind.warning;
        if (now.warningBeneath == beneath) return null;
        return 'the Session read told a warning beneath: $beneath, '
            'the halt became ${describeHalt(now)}';
      },
    );

Invariant<S> aSessionReadNeverClearsTheSign<S>(Halt Function(S) haltOf) =>
    Invariant('ADR 0107, a Session read never clears the sign', (
      before,
      event,
      after,
      effects,
      world,
    ) {
      if (event is! SessionRead || haltOf(before) is! Blocking) return null;
      if (haltOf(after) is Blocking) return null;
      return 'the Session read '
          '${describeEvent(event)} cleared the sign into '
          '${describeHalt(haltOf(after))}';
    });

bool _bringsSomethingBack(Effect effect) => switch (effect) {
  PlayPart() || PlayStretch() || DrainTheOutbox() => true,
  _ => false,
};

Invariant<S> aTapOnTheSignClearsItPlaysNothingAndResendsNothing<S>(
  Halt Function(S) haltOf,
) => Invariant(
  'ADR 0107, a tap on the sign clears it, plays nothing and resends nothing',
  (before, event, after, effects, world) {
    if (event is! TeamTapped || haltOf(before) is! Blocking) return null;
    if (haltOf(after) is! Blocking && !effects.any(_bringsSomethingBack)) {
      return null;
    }
    return 'a tap under ${describeHalt(haltOf(before))} left '
        '${describeHalt(haltOf(after))} with '
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
  aSessionReadNeverClearsTheSign(haltOf),
  aTapOnTheSignClearsItPlaysNothingAndResendsNothing(haltOf),
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

final aStopNamesThisSessionsTakeInTheAir = Invariant<Machine>(
  "a stop names this session's take in the air",
  (before, event, after, effects, world) {
    for (final StopTheSend(:row) in effects.whereType<StopTheSend>()) {
      final inTheAir = before.inTheAir;
      if (inTheAir == null ||
          inTheAir.row != row ||
          inTheAir.keep.session != before.session) {
        return 'stopped $row with ${inTheAir?.row} in the air';
      }
    }
    return null;
  },
);

final aLineOfTheVoiceStopsAPlayingReply = Invariant<Machine>(
  'a line of the voice that arrives over a playing reply stops it',
  (before, event, after, effects, world) {
    if (event is! LineArrived || event.line.kind == LineKind.reply) return null;
    if (before.channel case GuideSpeaking(line: final reply)
        when reply.kind == LineKind.reply &&
            !effects.contains(DropTheLine(event.line))) {
      final stillSpeaks = switch (after.channel) {
        GuideSpeaking(:final line) => line == reply,
        _ => false,
      };
      final stopped = effects.contains(StopTheLine(reply)) && !stillSpeaks;
      return stopped ? null : '${describeEvent(event)} waited behind a reply';
    }
    return null;
  },
);

final aMicrophoneAnswerWithNoMicrophoneOpenLeavesTheChannelAsItWas =
    Invariant<Machine>(
      'a microphone answer with no microphone open leaves the Channel as it was',
      (before, event, after, effects, world) {
        if (event is! MicAnswered || before.channel is Microphone) return null;
        if (identical(after.channel, before.channel)) return null;
        return '${describeEvent(event)} changed '
            '${describeChannel(before.channel)} into '
            '${describeChannel(after.channel)}';
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

final theOutboxNeverIdlesWithAPartPending = Invariant<Machine>(
  'ADR invariant 12, the Outbox never idles with a part pending',
  (before, event, after, effects, world) {
    if (!after.somethingPending) return null;
    if (world.retryArmed || world.draining) return null;
    return 'a part pending, no retry armed and no drain in '
        'flight';
  },
);

final aLanguageChosenReadsTheWheelOnlyOnTheChoice = Invariant<Machine>(
  'ADR 0077, a language chosen reads the Wheel again on the Choice and nowhere else',
  (before, event, after, effects, world) {
    if (event is! TheLanguageChosen) return null;
    final reads = effects.contains(const ReadTheWheel());
    if (before.station is! Menu) {
      return reads ? 'a language chosen off the Choice read the Wheel' : null;
    }
    if (!reads) return 'a language chosen on the Choice did not read the Wheel';
    if (after.generation <= before.generation) {
      return 'a language chosen on the Choice left the earlier read standing';
    }
    return null;
  },
);

bool _callsOrStopsCallingAPerson(Effect effect) => switch (effect) {
  CallForAPerson() => true,
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
  return null;
});

final nothingButHerSixCasesEntersThePersonSign = Invariant<Machine>(
  'ADR 0093, nothing but her six cases enters the person sign',
  (before, event, after, effects, world) {
    if (before.halt is Blocking || after.halt is! Blocking) return null;
    final herCase = switch (event) {
      RoomRaisedAHalt() ||
      TheSceneTurnFoundNothing() ||
      LookEmpty() ||
      LookFailed() => true,
      TheReplyFailedToLoad(:final load) => load >= 2,
      StationEvent() =>
        before.aHaltWaitsForTheCanvas && after.station is Canvas,
      _ => false,
    };
    if (herCase) return null;
    return '${describeEvent(event)} entered the person sign over '
        '${describeHalt(before.halt)}';
  },
);

final noHaltIsEnteredOverTheSceneOrTheCheck = Invariant<Machine>(
  'ADR 0158, no halt is entered over the scene rehearsal or the external '
  'check; it waits for the Canvas',
  (before, event, after, effects, world) {
    if (before.halt is Blocking || after.halt is! Blocking) return null;
    if (after.station is! SceneRehearsal && after.station is! ChecagemExterna) {
      return null;
    }
    return '${describeEvent(event)} entered the person sign over '
        '${after.station.stage.name}';
  },
);

final everyFailedLoadOfAReplyEndsInOneAnswer = Invariant<Machine>(
  'ADR 0152, every failed load of a reply ends in exactly one answer, a reload '
  'or a let-go',
  (before, event, after, effects, world) {
    if (event is! TheReplyFailedToLoad) return null;
    final answers = [
      for (final effect in effects)
        if (effect
            case LoadTheReplyAgain(:final answered) ||
                LetTheReplyGo(:final answered) when answered == event.answered)
          effect,
    ];
    if (answers.length == 1) return null;
    return '${describeEvent(event)} over ${describeMachine(before)} ended in '
        '${answers.length} answers: ${effects.map(describeEffect).join(', ')}';
  },
);

final onlyAStepLeftFromTheCanvasMovesItsEnd = Invariant<Machine>(
  'ENG-1946, only a step left from the Canvas moves the end it keeps',
  (before, event, after, effects, world) {
    final kept = switch (event) {
      StepLeft(:final ended) when before.station is Canvas => ended,
      _ => before.theCanvasEnded,
    };
    if (after.theCanvasEnded == kept) return null;
    return '${describeEvent(event)} on ${before.station.runtimeType} moved the '
        'Canvas\'s end to ${after.theCanvasEnded}';
  },
);

final aStationsSessionNeverOpensWithoutTheWatch = Invariant<Machine>(
  'ADR 0092, a Station\'s session never opens without the Watch',
  (before, event, after, effects, world) {
    final opened = after.stationSession;
    if (opened == null ||
        opened == before.stationSession ||
        after.station != before.station) {
      return null;
    }
    if (effects.contains(const ArmTheWatch())) return null;
    return '${describeEvent(event)} opened $opened without arming the Watch';
  },
);

var _opensOverAPartUnsent = 0;

final _atTheRehearsal = MachineUnderTest<Machine>(
  start: const Machine(station: Ensaio()),
  step: reduce,
  draw: (_, world, random) => switch (random.nextInt(4)) {
    0 => const TheRehearsalOpened(),
    1 => TheRehearsalWeighed(
      everySceneHasItsPart: random.nextBool(),
      everyPartIsHere: random.nextBool(),
      everyPartIsSent: random.nextBool(),
    ),
    2 => const TheBackTranslationOpened(),
    _ => drawAnEvent(world, random),
  },
  show: describeMachine,
);

final theBackTranslationNeverOpensOverAPartUnsent = Invariant<Machine>(
  'ADR 0154, the Back-translation never opens from a Rehearsal weighed with a '
  'part still in the Outbox',
  (before, event, after, effects, world) {
    if (event is! TheBackTranslationOpened) return null;
    if (before.station case Ensaio(everyPartIsSent: false)) {
      _opensOverAPartUnsent++;
      if (after.station is Retro) {
        return 'the Back-translation opened with a part still in the Outbox';
      }
    }
    return null;
  },
);

final noEventMakesTheMachineSpeakAFailure = Invariant<Machine>(
  'ENG-1356, no event ever makes the machine emit a spoken failure line',
  (before, event, after, effects, world) {
    final handed = {
      ...before.queue,
      if (event is LineArrived) event.line,
      if (before.channel case GuideSpeaking(:final line)) line,
    };
    for (final effect in effects) {
      if (effect case PlayLine(:final line) when !handed.contains(line)) {
        return '${describeEvent(event)} played ${describeLine(line)}, which '
            'nobody handed the room';
      }
    }
    return null;
  },
);

final aNetworkFailureOnlyLetsItsStepGo = Invariant<Machine>(
  'ENG-1356, a network failure that is no turn\'s never halts and never '
  'schedules anything but the Step\'s release',
  (before, event, after, effects, world) {
    if (event is! NetworkFailedAt) return null;
    if (after.halt != before.halt) {
      return '${describeEvent(event)} moved ${describeHalt(before.halt)} to '
          '${describeHalt(after.halt)}';
    }
    final others = effects.where((effect) => effect != const LetTheStepGo());
    if (others.isEmpty) return null;
    return '${describeEvent(event)} scheduled '
        '${others.map(describeEffect).join(', ')}';
  },
);

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

    test('invariant: a tap on the sign clears it, plays nothing and resends '
        'nothing', () {
      _holds(aTapOnTheSignClearsItPlaysNothingAndResendsNothing(_haltOf));
    });

    test('invariant: a Session read never clears the sign', () {
      _holds(aSessionReadNeverClearsTheSign(_haltOf));
    });

    test('ADR invariant 15: the warning the tablet holds is the one the '
        'server told, after every event', () {
      _holds(theWarningIsTheOneTheServerTold(_haltOf));
    });

    test('ADR 0152: every failed load of a reply ends in exactly one answer, '
        'a reload or a let-go', () {
      _holds(everyFailedLoadOfAReplyEndsInOneAnswer);
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

    test('a microphone answer with no microphone open leaves the Channel as it '
        'was', () {
      _holds(aMicrophoneAnswerWithNoMicrophoneOpenLeavesTheChannelAsItWas);
    });

    test('a microphone answer with no microphone open reads a Channel that '
        'changed', () {
      const playing = Machine(channel: GuideSpeaking(Line(LineKind.guide, 1)));
      const silent = Machine();
      const listening = Machine(channel: Microphone(MicOwner.conversation));
      String? check(Machine before, Machine after) =>
          aMicrophoneAnswerWithNoMicrophoneOpenLeavesTheChannelAsItWas.check(
            before,
            const MicAnswered(MicAnswer.closed),
            after,
            const [],
            const World(),
          );

      expect(check(playing, silent), isNotNull);
      expect(check(playing, playing), isNull);
      expect(check(listening, silent), isNull);
    });

    test('ADR invariant 8: the Head never reads another part\'s or '
        'stretch\'s position', () {
      _holds(theHeadNeverReadsAnotherSound);
    });

    test('ADR invariant 13: the screen never shows a sound the Channel does '
        'not hold', () {
      _holds(theScreenNeverShowsASoundTheChannelDoesNotHold);
    });

    test('ADR invariant 12: the Outbox never idles with a part '
        'pending', () {
      _holds(theOutboxNeverIdlesWithAPartPending);
    });

    test('ADR invariant 6: nothing of a gone session survives', () {
      _holds(nothingOfAGoneSessionSurvives);
    });

    test('the machine holds its invariants with the closed passage among its '
        'events', () {
      _holds(nothingOfAClosedPassageSurvives);
    });

    test(
      'ADR invariants 1, 2, 3, 5, 6, 8, 12, 13 and 15, the tap and the read on the sign, a microphone '
      'answer with no microphone open, and a line of the voice over a playing '
      'reply, hold over the default run',
      () {
        expectEverySeedHolds(_machine, [
          nothingOfAGoneSessionSurvives,
          nothingOfAClosedPassageSurvives,
          ...theAdrInvariants<Machine>(_haltOf),
          theMicrophoneOpensOverASoundOnlyAfterAStop,
          aMicrophoneAnswerWithNoMicrophoneOpenLeavesTheChannelAsItWas,
          aLineOfTheVoiceStopsAPlayingReply,
          aStopNamesThisSessionsTakeInTheAir,
          theHeadNeverReadsAnotherSound,
          theOutboxNeverIdlesWithAPartPending,
          theScreenNeverShowsASoundTheChannelDoesNotHold,
          aLanguageChosenReadsTheWheelOnlyOnTheChoice,
          aStationsSessionNeverOpensWithoutTheWatch,
          nothingButHerSixCasesEntersThePersonSign,
        ], seeds: _seeds);
      },
    );
  });

  test('invariant: no event ever makes the machine emit a spoken failure '
      'line', () {
    _holds(noEventMakesTheMachineSpeakAFailure);
  });

  test('invariant: a network failure that is no turn\'s never halts and never '
      'schedules anything but the Step\'s release', () {
    _holds(aNetworkFailureOnlyLetsItsStepGo);
  });

  test('generator invariant: nothing but her six cases enters the person '
      'sign', () {
    _holds(nothingButHerSixCasesEntersThePersonSign);
  });

  test('generator invariant: no halt is entered over the scene rehearsal or '
      'the external check', () {
    _holds(noHaltIsEnteredOverTheSceneOrTheCheck);
  });

  test('generator invariant: only a step left from the Canvas moves the end '
      'it keeps', () {
    _holds(onlyAStepLeftFromTheCanvasMovesItsEnd);
  });

  test('ADR 0092: a Station\'s session never opens without the Watch', () {
    _holds(aStationsSessionNeverOpensWithoutTheWatch);
  });

  test('ADR 0154: the Back-translation never opens from a Rehearsal weighed '
      'with a part still in the Outbox', () {
    expectEverySeedHolds(_atTheRehearsal, [
      theBackTranslationNeverOpensOverAPartUnsent,
    ], seeds: _seeds);
    expect(
      _opensOverAPartUnsent,
      greaterThan(0),
      reason: 'nenhuma sequência pedia a tradução com uma parte na fila',
    );
  });

  test('ADR 0077: a language chosen reads the Wheel again on the Choice and '
      'nowhere else', () {
    _holds(aLanguageChosenReadsTheWheelOnlyOnTheChoice);
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
        }
      }
    });

    test('generator invariant 4: the run reaches the room with a '
        'part pending', () {
      final reached = [
        for (final seed in _seeds)
          for (final entry in runSequence(
            _machine,
            const <Invariant<Machine>>[],
            seed,
          ).entries)
            if (entry.after.somethingPending) seed,
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
      final nothingEverHappens = Invariant<Machine>(
        'nothing ever happens',
        (before, event, after, effects, world) =>
            'it happened: ${describeEvent(event)}',
      );
      final events = [
        for (final entry in runSequence(_machine, [
          nothingEverHappens,
        ], 0).entries)
          describeEvent(entry.event),
      ];

      expect(
        () => expectEverySeedHolds(_machine, [nothingEverHappens], seeds: [0]),
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
                contains('nothing ever happens'),
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

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

final _at = DateTime.utc(2026, 9, 30, 12);

const _part1 = PartSound(0, 'parte-1.m4a', from: Duration(seconds: 12));
const _part2 = PartSound(1, 'parte-2.m4a');
const _guide1 = Line(LineKind.guide, 1);
const _guide2 = Line(LineKind.guide, 2);
const _notice = Line(LineKind.offlineNotice, 3);
const _reply = Line(LineKind.reply, 4, source: Source.reply('resposta-1'));

const _part1Playing = Machine(channel: PartPlaying(_part1, opened: true));

(Machine, List<Effect>) _run(Machine from, List<MachineEvent> events) {
  var machine = from;
  var effects = <Effect>[];
  for (final event in events) {
    (machine, effects) = reduce(machine, event);
  }
  return (machine, effects);
}

bool _silences(List<Effect> effects) =>
    effects.any((effect) => effect is SilenceTheRoom || effect is StopTheSound);

void main() {
  test(
    'a line that arrives while a part plays waits, and plays when the part ends',
    () {
      final (waiting, arrived) = reduce(
        _part1Playing,
        const LineArrived(_guide1),
      );

      expect(waiting.channel, _part1Playing.channel);
      expect(waiting.queue, [_guide1]);
      expect(arrived, isEmpty);

      final (afterThePart, ended) = reduce(waiting, const PlayerEnded());

      expect(ended, [const PlayLine(_guide1)]);
      expect(afterThePart.channel, const GuideSpeaking(_guide1));
      expect(afterThePart.queue, isEmpty);
    },
  );

  group('the queue holds one line per kind, in arrival order', () {
    test('a second line of a kind already queued adds nothing', () {
      final (machine, effects) = _run(_part1Playing, const [
        LineArrived(_guide1),
        LineArrived(_guide2),
      ]);

      expect(machine.queue, [_guide1]);
      expect(effects, [const DropTheLine(_guide2)]);
    });

    test('two kinds play in the order they arrived', () {
      final (queued, _) = _run(_part1Playing, const [
        LineArrived(_notice),
        LineArrived(_reply),
      ]);
      final (first, firstEffects) = reduce(queued, const PlayerEnded());
      final (_, secondEffects) = reduce(first, const PlayerEnded());

      expect(firstEffects, [const PlayLine(_notice)]);
      expect(secondEffects, [const PlayLine(_reply)]);
    });
  });

  group('the microphone never opens under a sound', () {
    test('a microphone asked for while a part plays is not opened', () {
      final (machine, effects) = reduce(
        _part1Playing,
        const MicOpened(MicOwner.capture),
      );

      expect(machine.channel, _part1Playing.channel);
      expect(effects, isEmpty);
    });

    test('a microphone asked for while the Guide speaks is not opened', () {
      const speaking = Machine(channel: GuideSpeaking(_guide1));

      final (machine, effects) = reduce(
        speaking,
        const MicOpened(MicOwner.conversation),
      );

      expect(machine.channel, speaking.channel);
      expect(effects, isEmpty);
    });

    test(
      'a line that arrives under an open microphone plays after it closes',
      () {
        final (open, opening) = reduce(
          const Machine(),
          const MicOpened(MicOwner.question),
        );
        final (waiting, arriving) = reduce(open, const LineArrived(_reply));
        final (closed, closing) = reduce(waiting, const MicClosed());

        expect(opening, [const OpenTheMic(MicOwner.question)]);
        expect(open.channel, const Microphone(MicOwner.question));
        expect(waiting.channel, const Microphone(MicOwner.question));
        expect(arriving, isEmpty);
        expect(closing, [const PlayLine(_reply)]);
        expect(closed.channel, const GuideSpeaking(_reply));
      },
    );
  });

  group('between PlayPart and PlayerOpened the Head is the Cursor', () {
    test('a part asked for from silence reads its own Cursor', () {
      final (machine, effects) = reduce(
        const Machine(),
        const BeadTapped([_part2]),
      );

      expect(effects, [const PlayPart(_part2)]);
      expect((machine.channel as Playing).head, _part2.from);
    });

    test('a part asked for over another part never reads the one before', () {
      final (machine, _) = reduce(_part1Playing, const BeadTapped([_part2]));

      expect((machine.channel as Playing).head, Duration.zero);
    });

    test('an opening that lands while the held part waits under a line '
        'releases its Head', () {
      final (machine, _) = _run(const Machine(), const [
        BeadTapped([_part2]),
        PauseTapped(),
        LineArrived(_notice),
        PlayerOpened(),
        PlayerEnded(),
      ]);

      expect((machine.channel as Paused).head, isNull);
    });

    test(
      'once the player confirms the opening the Head is no longer pinned',
      () {
        final (machine, _) = _run(const Machine(), const [
          BeadTapped([_part2]),
          PlayerOpened(),
        ]);

        expect((machine.channel as Playing).head, isNull);
      },
    );
  });

  group('a failure leaves silence, keeps the Cursor and calls nobody', () {
    test('the first failure of a part is silence and no call', () {
      final (machine, effects) = reduce(
        _part1Playing,
        PlayerFailed(_part1.source),
      );

      expect(machine.channel, const Silence());
      expect(machine.halt, const NoHalt());
      expect(effects, isEmpty);
    });

    test('the second failure in a row on the same part calls a person', () {
      final (machine, effects) = _run(_part1Playing, [
        PlayerFailed(_part1.source),
        const BeadTapped([_part1]),
        PlayerFailed(_part1.source),
      ]);

      expect(effects, contains(const CallForAPerson()));
      expect(machine.halt, isA<Blocking>());
    });

    test('a success on that source in between resets the count', () {
      final (machine, effects) = _run(_part1Playing, [
        PlayerFailed(_part1.source),
        const BeadTapped([_part1]),
        const PlayerOpened(),
        const PlayerEnded(),
        const BeadTapped([_part1]),
        PlayerFailed(_part1.source),
      ]);

      expect(effects, isNot(contains(const CallForAPerson())));
      expect(machine.halt, const NoHalt());
    });

    test('a failure on another source in between resets the count', () {
      final (machine, effects) = _run(_part1Playing, [
        PlayerFailed(_part1.source),
        const BeadTapped([_part2]),
        PlayerFailed(_part2.source),
        const BeadTapped([_part1]),
        PlayerFailed(_part1.source),
      ]);

      expect(effects, isNot(contains(const CallForAPerson())));
      expect(machine.halt, const NoHalt());
    });
  });

  test('a Guide line that fails twice in a row calls a person', () {
    final (once, first) = reduce(
      const Machine(channel: GuideSpeaking(_guide1)),
      const PlayerFailed(Source.guide),
    );
    final (twice, second) = _run(once, const [
      LineArrived(_guide2),
      PlayerFailed(Source.guide),
    ]);

    expect(first, isNot(contains(const CallForAPerson())));
    expect(once.halt, const NoHalt());
    expect(second, contains(const CallForAPerson()));
    expect(twice.halt, isA<Blocking>());
  });

  group(
    'a halt silences what is sounding, and so does leaving the passage',
    () {
      test('a halt the room raises silences the part in the air', () {
        final (machine, effects) = reduce(
          _part1Playing,
          const RoomRaisedAHalt(sounding: ThePart()),
        );

        expect(machine.channel, const Silence());
        expect(effects, contains(const SilenceTheRoom()));
      });

      test('a halt a Session read brings silences the Guide', () {
        final (machine, effects) = reduce(
          const Machine(channel: GuideSpeaking(_guide1)),
          SessionRead(
            const SessionSnapshot(
              sessionId: 'sessao-1',
              pericope: 'rute-1',
              status: 'needs_person',
              coverage: null,
              done: false,
              halt: HaltKind.blocking,
            ),
            at: _at,
          ),
        );

        expect(machine.channel, const Silence());
        expect(effects, contains(const SilenceTheRoom()));
      });

      test('leaving the passage silences the part and forgets the queue', () {
        final (machine, effects) = _run(_part1Playing, const [
          LineArrived(_guide1),
          LeftThePassage(),
        ]);

        expect(machine.channel, const Silence());
        expect(machine.queue, isEmpty);
        expect(effects, contains(const StopTheSound()));
      });

      for (final (name, event) in <(String, MachineEvent)>[
        ('a line arriving', const LineArrived(_guide1)),
        ('the player opening', const PlayerOpened()),
        ('a microphone asked for', const MicOpened(MicOwner.capture)),
        ('a microphone closing', const MicClosed()),
        ('a pause', const PauseTapped()),
        ('a warning', const TheAnswerWarned()),
        ('a beat of the Watch', const WatchFired()),
        ('the reach falling', const NetworkFailedAt(Door.watch)),
        ('the reach coming back', const NetworkReturned()),
      ]) {
        test('$name does not silence what is sounding', () {
          final (_, effects) = reduce(_part1Playing, event);

          expect(_silences(effects), isFalse);
        });
      }
    },
  );

  group('a waiting line never plays while a gesture is on its way', () {
    test('a line waiting behind a sound a gesture stopped plays once the '
        'gesture ends', () {
      final (machine, effects) = _run(_part1Playing, const [
        GestureStarted(1),
        LineArrived(_notice),
        GestureSilenced(),
        GestureEnded(1),
      ]);

      expect(effects, [const PlayLine(_notice)]);
      expect(machine.channel, const GuideSpeaking(_notice));
    });

    test(
      'a background line that arrives while a gesture is on its way waits',
      () {
        final (machine, effects) = _run(const Machine(), const [
          GestureStarted(1),
          LineArrived(_notice),
        ]);

        expect(effects, isEmpty);
        expect(machine.queue, [_notice]);
      },
    );

    test("the gesture's own line enters", () {
      final (machine, effects) = _run(const Machine(), const [
        GestureStarted(1),
        LineArrived(_guide1, by: [1]),
      ]);

      expect(effects, [const PlayLine(_guide1)]);
      expect(machine.channel, const GuideSpeaking(_guide1));
    });

    test("the gesture's own part enters, and a waiting line waits until the "
        'gesture ends', () {
      final (playing, effects) = _run(const Machine(), const [
        GestureStarted(1),
        LineArrived(_notice),
        BeadTapped([_part2]),
      ]);
      final (ended, afterThePart) = reduce(playing, const PlayerEnded());
      final (_, afterTheGesture) = reduce(ended, const GestureEnded(1));

      expect(effects, [const PlayPart(_part2)]);
      expect(afterThePart, isEmpty);
      expect(afterTheGesture, [const PlayLine(_notice)]);
    });

    test("every sound of a gesture on its way passes, and the background line "
        'waits between them', () {
      final (speaking, first) = _run(const Machine(), const [
        GestureStarted(1),
        LineArrived(_guide1, by: [1]),
      ]);
      final (waiting, _) = reduce(speaking, const LineArrived(_notice));
      final (between, ended) = reduce(waiting, const PlayerEnded());
      final (_, second) = reduce(between, const LineArrived(_guide2, by: [1]));

      expect(first, [const PlayLine(_guide1)]);
      expect(ended, isEmpty);
      expect(second, [const PlayLine(_guide2)]);
    });

    test(
      "a gesture's own line queued behind its own sound plays when that sound "
      'ends',
      () {
        final (speaking, _) = _run(const Machine(), const [
          GestureStarted(1),
          LineArrived(_guide1, by: [1]),
          LineArrived(_notice),
          LineArrived(_reply, by: [1]),
        ]);
        final (_, ended) = reduce(speaking, const PlayerEnded());

        expect(ended, [const PlayLine(_reply)]);
      },
    );

    test("a gesture's own line is never dropped for a background line of its "
        'kind already waiting', () {
      const background = Line(LineKind.guide, 7, source: Source.aside('x'));
      final (machine, effects) = _run(_part1Playing, const [
        GestureStarted(1),
        LineArrived(background),
        LineArrived(_guide1, by: [1]),
      ]);

      expect(effects, isNot(contains(const DropTheLine(_guide1))));
      expect(machine.queue, contains(_guide1));
    });

    test(
      'a gesture that goes on to open the microphone keeps the line waiting',
      () {
        final (machine, effects) = _run(_part1Playing, const [
          GestureStarted(1),
          LineArrived(_notice),
          GestureSilenced(),
          MicOpened(MicOwner.conversation),
          GestureEnded(1),
        ]);

        expect(effects, isEmpty);
        expect(machine.channel, const Microphone(MicOwner.conversation));
        expect(machine.queue, [_notice]);
      },
    );

    test(
      "the gesture's own line enters ahead of the background lines waiting",
      () {
        final (machine, effects) = _run(const Machine(), const [
          GestureStarted(1),
          LineArrived(_notice),
          LineArrived(_guide1, by: [1]),
        ]);

        expect(effects, [const PlayLine(_guide1)]);
        expect(machine.queue, [_notice]);
      },
    );

    test('a line tagged by a gesture that already ended never ends a later '
        "gesture's wait", () {
      final (machine, effects) = _run(const Machine(), const [
        GestureStarted(1),
        GestureEnded(1),
        GestureStarted(2),
        LineArrived(_notice, by: [1]),
      ]);

      expect(effects, isEmpty);
      expect(machine.queue, [_notice]);
    });

    test('a waiting line plays only after every gesture on its way ended', () {
      final (stillWaiting, first) = _run(const Machine(), const [
        GestureStarted(1),
        GestureStarted(2),
        LineArrived(_notice),
        GestureEnded(2),
      ]);
      final (_, last) = reduce(stillWaiting, const GestureEnded(1));

      expect(first, isEmpty);
      expect(last, [const PlayLine(_notice)]);
    });
  });

  test('leaving the passage forgets the failures', () {
    final (machine, effects) = _run(const Machine(), const [
      LineArrived(_guide1),
      PlayerFailed(Source.guide),
      LeftThePassage(),
      LineArrived(_guide2),
      PlayerFailed(Source.guide),
    ]);

    expect(effects, isNot(contains(const CallForAPerson())));
    expect(machine.halt, const NoHalt());
  });

  test('an offline notice waiting under a halt leaves the queue when the Reach '
      'comes back', () {
    final (machine, effects) = _run(const Machine(), [
      const RoomRaisedAHalt(),
      const NetworkFailedAt(Door.watch),
      const LineArrived(_notice),
      const NetworkReturned(),
      LongPress(somebodyToAsk: false, at: _at),
    ]);

    expect(effects, isNot(contains(const PlayLine(_notice))));
    expect(machine.queue, isEmpty);
  });

  group('a paused sound held beneath a line stays paused and resumable', () {
    const part = PartSound(0, 'parte-1.m4a', from: Duration(seconds: 5));
    const next = PartSound(1, 'parte-2.m4a');
    const courtesy = Line(
      LineKind.stranded,
      9,
      source: Source.aside('stranded'),
    );
    Machine underTheLine() => _run(const Machine(), const [
      BeadTapped([part, next]),
      PlayerOpened(),
      PauseTapped(),
      LineArrived(courtesy),
    ]).$1;

    test('the rehearsal reads paused while the line speaks', () {
      final screen = SalaSessionState(
        machine: underTheLine().copyWith(
          station: Station.stored(SalaStage.ensaio),
        ),
      );

      expect(screen.takePaused, isTrue);
    });

    test('the play tap stops the line and resumes the part where it was', () {
      final (machine, effects) = reduce(underTheLine(), const PauseTapped());

      expect(effects, [const StopTheLine(courtesy), const LetTheSoundRun()]);
      expect(
        machine.channel,
        const PartPlaying(part, opened: true, next: [next]),
      );
    });

    test('a bead tapped over the line stops the line before it plays', () {
      final (_, effects) = reduce(underTheLine(), const BeadTapped([next]));

      expect(effects, [const StopTheLine(courtesy), const PlayPart(next)]);
    });
  });

  test('a line that arrives under a blocking halt waits for the lift', () {
    final (halted, _) = reduce(const Machine(), const RoomRaisedAHalt());
    final (waiting, arriving) = reduce(halted, const LineArrived(_notice));
    final (lifted, lifting) = reduce(
      waiting,
      LongPress(somebodyToAsk: false, at: _at),
    );

    expect(arriving, isEmpty);
    expect(waiting.queue, [_notice]);
    expect(lifting, contains(const PlayLine(_notice)));
    expect(lifted.channel, const GuideSpeaking(_notice));
  });
}

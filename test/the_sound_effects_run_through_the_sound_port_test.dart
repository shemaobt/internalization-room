import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/effect_runner.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';

import 'a_room_host_double.dart';
import 'fake_ports.dart';

const _line = Line(LineKind.guide, 1, url: 'scene.mp3');
const _part = PartSound(0, 'part.m4a');
const _next = PartSound(1, 'next.m4a');
const _grace = Duration(seconds: 2);
const _stretch = StretchSound('part.m4a', to: Duration(seconds: 4));

void main() {
  late ASoundPort sound;
  late ARoomHost host;
  late EffectRunner runner;
  late Machine machine;

  void reduceAndRun(MachineEvent event) {
    final (next, effects) = reduce(machine, event);
    machine = next;
    runner.run(effects);
  }

  setUp(() {
    sound = ASoundPort();
    host = ARoomHost();
    runner = runnerOver(fakePorts(sound), host, clipGrace: _grace);
  });

  test(
    'a line the machine plays reaches the sound port and its end comes back to the machine',
    () async {
      runner.run(const [PlayLine(_line)]);
      sound.endTheLine();
      await pumpEventQueue();

      expect(sound.heard, ['line:scene.mp3']);
      expect(
        host.answers.single,
        isA<PlayerEnded>().having((ended) => ended.line, 'line', _line),
      );
    },
  );

  test(
    'a line that fails to play comes back to the machine as a failed sound',
    () async {
      runner.run(const [PlayLine(_line)]);
      sound.endTheLine(whole: false);
      await pumpEventQueue();

      expect(
        host.answers.single,
        isA<PlayerFailed>()
            .having((failed) => failed.line, 'line', _line)
            .having((failed) => failed.source, 'source', _line.source),
      );
    },
  );

  test(
    'a part the machine plays reaches the sound port and its end comes back to the machine',
    () async {
      runner.run(const [PlayPart(_part)]);
      sound.endThePart();
      await pumpEventQueue();

      expect(sound.heard, ['part:part.m4a']);
      expect(
        host.answers.single,
        isA<PlayerEnded>().having((ended) => ended.sound, 'sound', _part),
      );
    },
  );

  test(
    'a part whose end never comes is released at what is left of it plus the grace',
    () {
      fakeAsync((time) {
        machine = const Machine();
        host.onAnswer = reduceAndRun;
        reduceAndRun(const BeadTapped([_part]));
        sound.openThePart(
          length: const Duration(seconds: 10),
          at: const Duration(seconds: 4),
        );

        time.elapse(const Duration(milliseconds: 7999));
        expect(host.answers.whereType<PlayerEnded>(), isEmpty);
        time.elapse(const Duration(milliseconds: 1));
        expect(host.answers.whereType<PlayerEnded>(), hasLength(1));
      });
    },
  );

  test(
    'holding the sound pauses the sound port, and letting it run resumes it',
    () async {
      runner.run(const [HoldTheSound()]);
      runner.run(const [LetTheSoundRun()]);
      await pumpEventQueue();

      expect(sound.heard, ['pause', 'resume']);
    },
  );

  test('a dropped line never plays', () async {
    runner.run(const [DropTheLine(_line)]);
    await pumpEventQueue();

    expect(sound.heard, isEmpty);
    expect(
      host.answers.single,
      isA<LineNotSaid>().having((notSaid) => notSaid.line, 'line', _line),
    );
  });

  test(
    'an end that comes back after the generation moved is stamped with the generation it was played under',
    () async {
      var generation = 3;
      runner = runnerOver(fakePorts(sound), host, generation: () => generation);

      runner.run(const [PlayPart(_part)]);
      generation = 4;
      sound.endThePart();
      await pumpEventQueue();

      expect(
        host.answers.single,
        isA<PlayerEnded>().having((ended) => ended.generation, 'generation', 3),
      );
    },
  );

  test(
    'the Station hears a part end before the machine, and a part it starts then plays on',
    () {
      var machine = reduce(const Machine(), const BeadTapped([_part])).$1;
      Channel? heardOver;
      host.onAnswer = (event) => machine = reduce(machine, event).$1;
      host.onPartEnd = () {
        heardOver = machine.channel;
        final (next, effects) = reduce(machine, const BeadTapped([_next]));
        machine = next;
        runner.run(effects);
      };

      runner.run(const [PlayPart(_part)]);
      sound.endThePart();

      expect(heardOver, const PartPlaying(_part));
      expect(machine.channel, const PartPlaying(_next));
    },
  );

  test(
    'a stretch that ends back onto the part held beneath it is not heard as a hold',
    () {
      machine = const Machine(channel: Paused(_part));
      host.onAnswer = reduceAndRun;
      reduceAndRun(const BeadTapped([_stretch], beneath: Paused(_part)));

      sound.endThePart();

      expect(machine.channel, const Paused(_part));
      expect(host.asked, isNot(contains('hearTheHold')));
    },
  );

  test('a bead that replays the paused part is not heard as a run', () {
    machine = const Machine(channel: Paused(_part));
    host.onAnswer = reduceAndRun;

    reduceAndRun(const BeadTapped([_part]));

    expect(machine.channel, const PartPlaying(_part));
    expect(host.asked, isNot(contains('hearTheRun')));
  });

  test('a part stopped while it opens arms no ceiling', () {
    fakeAsync((time) {
      machine = const Machine();
      host.onAnswer = reduceAndRun;
      reduceAndRun(const BeadTapped([_part]));
      reduceAndRun(const GestureSilenced());

      sound.openThePart(length: const Duration(seconds: 10));
      time.elapse(const Duration(minutes: 5));

      expect(host.answers.whereType<PlayerEnded>(), isEmpty);
    });
  });
}

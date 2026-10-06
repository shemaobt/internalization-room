import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/effect_runner.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'a_room_host_double.dart';
import 'fake_ports.dart';
import 'fakes.dart';
import 'scenario_helpers.dart' show settle;

const _take = 'conversa_1';
const _file = '/recordings/conversa_1.m4a';
const _line = Line(LineKind.guide, 1, url: 'scene.mp3');
const _part = PartSound(0, 'part.m4a');

class _ARecorderThatFailsToStopOnce extends FakeRecorder {
  _ARecorderThatFailsToStopOnce({super.sounds});

  Object? failsTheNextStop;

  @override
  Future<String?> stop() async {
    final failure = failsTheNextStop;
    failsTheNextStop = null;
    if (failure != null) throw failure;
    return super.stop();
  }
}

class _AHarnessWhoseRecorderFailsToStop extends SalaHarness {
  late final _failing = _ARecorderThatFailsToStopOnce(sounds: sounds);

  @override
  _ARecorderThatFailsToStopOnce get recorder => _failing;
}

void main() {
  late ARecorderPort recorder;
  late ARoomHost host;
  late EffectRunner runner;
  var generation = 3;

  setUp(() {
    generation = 3;
    recorder = ARecorderPort();
    host = ARoomHost();
    runner = runnerOver(
      fakePorts(ASoundPort(), recorder: recorder),
      host,
      generation: () => generation,
    );
  });

  Iterable<MicAnswered> answered() => host.answers.whereType<MicAnswered>();

  test(
    'a microphone the machine opens reaches the recorder port with its take and its owner',
    () {
      runner.run(const [OpenTheMic(MicOwner.rehearsal, take: _take)]);

      expect(recorder.heard, ['start:$_take:rehearsal']);
    },
  );

  test('open, speak, close: one take is handed to the machine', () async {
    var machine = Machine(generation: generation);
    void reduceAndRun(MachineEvent event) {
      final before = machine;
      final (next, effects) = reduce(machine, event);
      machine = next;
      runner.run(effects, micWasOpen: before.channel is Microphone);
    }

    host.onAnswer = reduceAndRun;

    reduceAndRun(const MicOpened(MicOwner.conversation, take: _take));
    recorder.answerTheStart(MicAnswer.started);
    await pumpEventQueue();
    reduceAndRun(const MicClosing());
    recorder.answerTheStop(_file);
    await pumpEventQueue();

    expect(answered().where((answer) => answer.take != null), hasLength(1));
    expect(machine.lastMic?.take, _file);
    expect(machine.channel, const Silence());
  });

  test(
    'a close the recorder answers with no file comes back as a microphone closed with no take',
    () async {
      runner.run(const [CloseTheMic()]);
      recorder.answerTheStop(null);
      await pumpEventQueue();

      expect(
        answered().single,
        isA<MicAnswered>()
            .having((answer) => answer.answer, 'answer', MicAnswer.closed)
            .having((answer) => answer.take, 'take', isNull),
      );
    },
  );

  test(
    'a recorder that refuses the microphone comes back to the machine as a refused opening, stamped with the generation it was opened under',
    () async {
      runner.run(const [OpenTheMic(MicOwner.conversation, take: _take)]);
      generation = 4;
      recorder.answerTheStart(MicAnswer.refused);
      await pumpEventQueue();

      expect(
        answered().single,
        isA<MicAnswered>()
            .having((answer) => answer.answer, 'answer', MicAnswer.refused)
            .having((answer) => answer.generation, 'generation', 3),
      );
    },
  );

  test(
    'a recorder that fails to start comes back to the machine as a failed opening',
    () async {
      runner.run(const [OpenTheMic(MicOwner.capture, take: _take)]);
      recorder.answerTheStart(MicAnswer.failed);
      await pumpEventQueue();

      expect(
        answered().single,
        isA<MicAnswered>()
            .having((answer) => answer.answer, 'answer', MicAnswer.failed)
            .having((answer) => answer.generation, 'generation', 3),
      );
      expect(recorder.heard, isNot(contains('discard')));
    },
  );

  test(
    'a start that answers after the generation moved leaves no recorder running',
    () async {
      runner.run(const [OpenTheMic(MicOwner.conversation, take: _take)]);
      generation = 4;
      recorder.answerTheStart(MicAnswer.started);
      await pumpEventQueue();

      expect(recorder.heard.last, 'discard');
    },
  );

  test(
    'a start that answers after the room closed its microphone leaves no recorder running',
    () async {
      runner.run(const [OpenTheMic(MicOwner.capture, take: _take)]);
      host.keepsALateStart = false;
      recorder.answerTheStart(MicAnswer.started);
      await pumpEventQueue();

      expect(recorder.heard.last, 'discard');
    },
  );

  test(
    'a take closed after the generation moved is still handed to the machine',
    () async {
      runner.run(const [CloseTheMic()]);
      generation = 4;
      recorder.answerTheStop(_file);
      await pumpEventQueue();

      final (machine, _) = reduce(
        Machine(
          generation: generation,
          channel: const Microphone(MicOwner.conversation),
        ),
        answered().single,
      );
      expect(machine.lastMic?.take, _file);
      expect(machine.channel, const Silence());
    },
  );

  test(
    'a close the recorder fails comes back to the gesture as the failure, with the microphone still open',
    () async {
      final because = Exception('the platform refused to stop');
      runner.run(const [CloseTheMic()]);
      recorder.failTheStop(because);
      await pumpEventQueue();

      final (machine, _) = reduce(
        Machine(
          generation: generation,
          channel: const Microphone(MicOwner.rehearsal),
        ),
        answered().single,
      );
      expect(machine.lastMic?.because, because);
      expect(machine.channel, const Microphone(MicOwner.rehearsal));
    },
  );

  test(
    'the room closes and discards the microphone only when it was open or still opening',
    () {
      runner.run(const [CloseAndDiscardTheMic()]);
      expect(recorder.heard, isEmpty);
      expect(answered(), isEmpty);

      runner.run(const [CloseAndDiscardTheMic()], micWasOpen: true);
      expect(recorder.heard, ['discard']);

      host.recordingStarts = true;
      runner.run(const [CloseAndDiscardTheMic()]);
      expect(recorder.heard, ['discard', 'discard']);
      expect(answered().map((answer) => answer.answer), [
        MicAnswer.discarded,
        MicAnswer.discarded,
      ]);
    },
  );

  test(
    'a call that takes the microphone reaches the room through the recorder port',
    () {
      runner.run(const [OpenTheMic(MicOwner.rehearsal, take: _take)]);
      recorder.takeTheMicrophone();

      expect(host.asked, contains('hearTheMicrophoneTaken:true'));
    },
  );

  test(
    'a close asked for leaves the microphone open until the recorder answers',
    () {
      const machine = Machine(
        channel: Microphone(MicOwner.conversation),
        queue: [_line],
      );

      final (next, effects) = reduce(machine, const MicClosing());

      expect(next.channel, const Microphone(MicOwner.conversation));
      expect(effects, [const CloseTheMic()]);
    },
  );

  test(
    'a microphone closed with a take gives the Channel back to what it held, and keeps the take for the gesture waiting on it',
    () {
      const held = Paused(_part);
      const machine = Machine(
        channel: Microphone(MicOwner.rehearsal, held: held),
      );

      final (next, _) = reduce(
        machine,
        const MicAnswered(MicAnswer.closed, take: _file),
      );

      expect(next.channel, held);
      expect(next.lastMic?.take, _file);
    },
  );

  test(
    'a failed or refused opening gives the Channel back as a closed microphone does',
    () {
      const held = Paused(_part);
      const machine = Machine(
        channel: Microphone(MicOwner.capture, held: held),
        queue: [_line],
      );
      for (final answer in [MicAnswer.failed, MicAnswer.refused]) {
        final (next, effects) = reduce(machine, MicAnswered(answer));

        expect(next.channel, const GuideSpeaking(_line, held: held));
        expect(effects, [const PlayLine(_line)]);
        expect(next.lastMic?.answer, answer);
      }
    },
  );

  test(
    'a take the recorder fails to hand over ends its own gesture, and the next close gets its own take',
    () async {
      final harness = _AHarnessWhoseRecorderFailsToStop();
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);
      await notifier.goConversa();
      await settle();
      notifier.goEnsaio();
      notifier.ensaioTap();
      await settle();

      harness.recorder.failsTheNextStop = StateError('the platform broke');
      notifier.ensaioTap();
      await settle();

      expect(read().needsPerson, isFalse);
      expect(read().ensaio, EnsaioStatus.recording);

      notifier.ensaioTap();
      await settle();

      expect(read().ensaio, EnsaioStatus.recorded);
      expect(read().machine.onTheirWay, isEmpty);
    },
  );
}

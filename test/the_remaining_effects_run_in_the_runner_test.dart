import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/effect_runner.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/room_reach.dart';
import 'package:internalization_room/features/sala/domain/turn_result.dart';

import 'a_station_host_double.dart';
import 'fake_ports.dart';

const _turn = Turn('sessao-1', 'turno-1');

const _reply = TurnResult(
  sessionId: 'sessao-1',
  audioUrl: 'https://sala/turno-1.mp3',
  fixedLine: '',
  transcript: 'a equipe falou',
  peerCue: false,
  usedFailSafe: false,
  degraded: false,
  coverage: null,
  done: false,
  turnId: 'turno-1',
);

void main() {
  late AStorePort store;
  late AStationHost host;
  late EffectRunner runner;

  setUp(() {
    store = AStorePort();
    host = AStationHost()..session = 'sessao-1';
    runner = runnerOver(
      fakePorts(ASoundPort(), room: ARoomPort(), store: store),
      host,
    );
  });

  List<int> gesturesEnded() => [
    for (final answer in host.answers)
      if (answer is GestureEnded) answer.gesture,
  ];

  test(
    'a silenced room is handed to the Station before the machine hears the silence',
    () {
      final handedWhenAnswered = <List<LifecycleHandOff>>[];
      host.onAnswer = (_) => handedWhenAnswered.add([...host.handedOver]);

      runner.run(const [SilenceTheRoom()]);

      expect(host.handedOver, [const SilenceTheRoom()]);
      expect(host.answers, hasLength(1));
      expect(
        host.answers.single,
        isA<GestureSilenced>().having(
          (silenced) => silenced.keepingTheHold,
          'keepingTheHold',
          false,
        ),
      );
      expect(handedWhenAnswered, [
        [const SilenceTheRoom()],
      ]);
    },
  );

  test(
    'a drained Outbox is flushed through the store, then the Station adopts the names and counts what is unsent',
    () {
      fakeAsync((time) {
        runner.run(const [DrainTheOutbox()]);
        time.flushMicrotasks();

        expect(store.heard, ['flush']);
        expect(host.asked, isEmpty);

        store.answerTheFlush();
        time.flushMicrotasks();

        expect(host.asked, ['hearTheOutboxFlushed', 'hearTheOutboxCounted']);
      });
    },
  );

  test(
    'a flush that fails still has the Station count what is unsent, and adopts no names',
    () {
      fakeAsync((time) {
        final surfaced = <Object>[];
        runZonedGuarded(
          () => runner.run(const [DrainTheOutbox()]),
          (error, _) => surfaced.add(error),
        );

        store.failTheFlush(Exception('the outbox could not be sent'));
        time.flushMicrotasks();

        expect(host.asked, ['hearTheOutboxCounted']);
        expect(surfaced, hasLength(1));
      });
    },
  );

  test(
    'a turn let go ends every gesture that waited on it, then the Station watches for a stuck wait',
    () {
      host.awaiting[_turn] = [3, 7];
      final heardWhenEnded = <List<String>>[];
      host.onAnswer = (_) => heardWhenEnded.add([...host.asked]);

      runner.run(const [LetTheTurnGo(_turn)]);

      expect(gesturesEnded(), [3, 7]);
      expect(heardWhenEnded, [<String>[], <String>[]]);
      expect(host.asked, ['hearTheTurnLetGo']);
    },
  );

  test(
    'a turn let go with no gesture waiting on it only has the Station watch for a stuck wait',
    () {
      runner.run(const [LetTheTurnGo(_turn)]);

      expect(host.answers, isEmpty);
      expect(host.asked, ['hearTheTurnLetGo']);
    },
  );

  test('a fall is heard by the Station with its door and its reason', () {
    runner.run(const [FellAt(Door.step, why: RoomReach.roomSilent)]);

    expect(host.asked, ['hearTheFall:step:roomSilent']);
    expect(host.answers, isEmpty);
  });

  test('a counted refusal is heard by the Station', () {
    runner.run(const [CountTheRefusal()]);

    expect(host.asked, ['hearTheRefusalCounted']);
    expect(host.answers, isEmpty);
  });

  test('a passage that cannot open is heard by the Station', () {
    runner.run(const [RefuseThePassage()]);

    expect(host.asked, ['hearThePassageRefused']);
    expect(host.answers, isEmpty);
  });

  test('a reply the look found is heard by the Station with its turn', () {
    runner.run(const [PlayTheReply(_turn, _reply)]);

    expect(host.asked, ['hearTheReplyFound:turno-1']);
    expect(host.answers, isEmpty);
  });

  test('a kept sound is heard by the Station', () {
    runner.run(const [ReplayTheSound(ThePart())]);

    expect(host.asked, ['hearTheSoundKept:ThePart']);
    expect(host.answers, isEmpty);
  });

  test('an opening let go is heard by the Station', () {
    runner.run(const [LetTheOpeningGo()]);

    expect(host.asked, ['hearTheOpeningLetGo']);
    expect(host.answers, isEmpty);
  });

  test(
    'opening the Choice is handed to the Station, and the machine hears nothing',
    () {
      runner.run(const [OpenTheChoice()]);

      expect(host.handedOver, [const OpenTheChoice()]);
      expect(host.answers, isEmpty);
    },
  );

  test(
    'discarding the session is handed to the Station, and the machine hears nothing',
    () {
      runner.run(const [DiscardTheSession()]);

      expect(host.handedOver, [const DiscardTheSession()]);
      expect(host.answers, isEmpty);
    },
  );

  test(
    'resending the Pending request is handed to the Station, and the machine hears nothing',
    () {
      runner.run(const [ResendPending()]);

      expect(host.handedOver, [const ResendPending()]);
      expect(host.answers, isEmpty);
    },
  );

  test('a flush that answers after the runner is disposed is not heard', () {
    fakeAsync((time) {
      runner.run(const [DrainTheOutbox()]);
      runner.dispose();

      store.answerTheFlush();
      time.flushMicrotasks();

      expect(host.asked, isEmpty);
    });
  });

  test('a turn let go after the runner is disposed ends no gesture', () {
    host.awaiting[_turn] = [3, 7];
    runner.dispose();

    runner.run(const [LetTheTurnGo(_turn)]);

    expect(gesturesEnded(), isEmpty);
  });
}

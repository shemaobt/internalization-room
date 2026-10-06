import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/effect_runner.dart';
import 'package:internalization_room/features/sala/domain/failure_policy.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/ports.dart';
import 'package:internalization_room/features/sala/domain/room_reach.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';

import 'a_room_host_double.dart';
import 'fake_ports.dart';

const _snapshot = SessionSnapshot(
  sessionId: 'sessao-1',
  pericope: 'rute-1',
  status: 'in_progress',
  coverage: null,
  done: false,
);

void main() {
  late ARoomPort room;
  late ARoomHost host;
  late EffectRunner runner;

  setUp(() {
    room = ARoomPort();
    host = ARoomHost()..session = 'sessao-1';
    runner = runnerOver(fakePorts(ASoundPort(), room: room), host);
  });

  test('a state read reaches the room port with the room\'s session', () {
    runner.run(const [ReadTheState()]);

    expect(room.heard, ['read:sessao-1']);
  });

  test('a state read with no session asks the room nothing', () {
    host.session = null;

    runner.run(const [ReadTheState()]);

    expect(room.heard, isEmpty);
  });

  test(
    'a state read the room answers is heard by the Station with its snapshot',
    () async {
      runner.run(const [ReadTheState()]);
      room.answerTheRead(const SessionReadAnswered(_snapshot));
      await pumpEventQueue();

      expect(host.readsHeard, [same(_snapshot)]);
      expect(host.answers, isEmpty);
    },
  );

  test(
    'a state read that fails on the network takes the room out of reach at the Watch\'s door',
    () async {
      runner.run(const [ReadTheState()]);
      room.answerTheRead(const SessionReadFailed(RoomNetworkFailed()));
      await pumpEventQueue();

      expect(
        host.answers.single,
        isA<NetworkFailedAt>()
            .having((fell) => fell.door, 'door', Door.watch)
            .having((fell) => fell.why, 'why', RoomReach.noNetwork),
      );
      expect(host.readsHeard, isEmpty);
    },
  );

  test('a state read the room refuses passes', () async {
    runner.run(const [ReadTheState()]);
    room.answerTheRead(const SessionReadFailed(RoomRefused('some_code')));
    await pumpEventQueue();

    expect(host.answers.single, isA<TheRefusalPassed>());
    expect(host.readsHeard, isEmpty);
  });

  test(
    'a state read whose session is gone tells the machine the session is gone',
    () async {
      runner.run(const [ReadTheState()]);
      room.answerTheRead(const SessionReadFailed(RoomSessionGone()));
      await pumpEventQueue();

      expect(host.answers.single, isA<TheSessionIsGone>());
      expect(host.readsHeard, isEmpty);
    },
  );

  test(
    'a state read answered after the room left its session changes nothing',
    () async {
      runner.run(const [ReadTheState()]);
      host.session = null;
      room.answerTheRead(const SessionReadAnswered(_snapshot));
      await pumpEventQueue();

      expect(host.readsHeard, isEmpty);
      expect(host.answers, isEmpty);
    },
  );
}

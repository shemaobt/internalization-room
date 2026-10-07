import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/effect_runner.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/room_reach.dart';

import 'a_room_host_double.dart';
import 'fake_ports.dart';

void main() {
  late ARoomPort room;
  late ARoomHost host;
  late EffectRunner runner;

  setUp(() {
    room = ARoomPort();
    host = ARoomHost()..roomIsReachable = false;
    runner = runnerOver(fakePorts(ASoundPort(), room: room), host);
  });

  test(
    'a probe that finds the room back tells the machine the network returned',
    () async {
      runner.run(const [ProbeTheRoom()]);
      room.answerTheReach(RoomReach.fine);
      await pumpEventQueue();

      expect(room.heard, ['reach']);
      expect(host.answers.single, isA<NetworkReturned>());
    },
  );

  test(
    'a probe that finds the room silent falls at the probe\'s door with why',
    () async {
      runner.run(const [ProbeTheRoom()]);
      room.answerTheReach(RoomReach.roomSilent);
      await pumpEventQueue();

      expect(
        host.answers.single,
        isA<NetworkFailedAt>()
            .having((fell) => fell.door, 'door', Door.probe)
            .having((fell) => fell.why, 'why', RoomReach.roomSilent),
      );
    },
  );

  test(
    'a probe answered after the room came back on its own does not take it out of reach again',
    () async {
      runner.run(const [ProbeTheRoom()]);
      host.roomIsReachable = true;
      room.answerTheReach(RoomReach.noNetwork);
      await pumpEventQueue();

      expect(host.answers, isEmpty);
    },
  );

  test(
    'a Step\'s ask and a probe in the air together ask the room once and fall once',
    () async {
      host.roomIsReachable = true;
      final asked = runner.askTheRoom(forAStep: true);
      runner.run(const [ProbeTheRoom()]);
      room.answerTheReach(RoomReach.noNetwork);
      await pumpEventQueue();

      expect(await asked, RoomReach.noNetwork);
      expect(room.heard, ['reach']);
      expect(host.answers.whereType<NetworkFailedAt>(), hasLength(1));
    },
  );
}

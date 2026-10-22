import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/effect_runner.dart';
import 'package:internalization_room/features/sala/domain/failure_policy.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/refusal_code.dart';

import 'a_station_host_double.dart';
import 'fake_ports.dart';

Halt _theSignAfter(List<MachineEvent> answers) => answers
    .fold(
      const Machine(halt: Blocking()),
      (machine, event) => reduce(machine, event).$1,
    )
    .halt;

void main() {
  late ARoomPort room;
  late AStationHost host;
  late EffectRunner runner;

  setUp(() {
    room = ARoomPort();
    host = AStationHost()..session = 'sessao-1';
    runner = runnerOver(fakePorts(ASoundPort(), room: room), host);
  });

  test(
    'a call for a person reaches the room port with the room\'s session',
    () {
      runner.run(const [CallForAPerson()]);

      expect(room.heard, ['call:sessao-1']);
    },
  );

  test('a call for a person the room answers lands the call', () async {
    runner.run(const [CallForAPerson()]);
    room.answerTheCall(const RoomAnswered());
    await pumpEventQueue();

    expect(host.answers, isEmpty);
    expect(host.callsLanded, 1);
  });

  test(
    'a call for a person the room refuses asks again on the ladder',
    () async {
      runner.run(const [CallForAPerson()]);
      room.answerTheCall(const RoomRefused('some_code'));
      await pumpEventQueue();

      expect(host.answers.single, isA<TheCallWasRefused>());
      expect(host.callsLanded, 0);
      expect(_theSignAfter(host.answers), isA<Blocking>());
    },
  );

  test(
    'a call for a person refused because nobody can be reached passes',
    () async {
      runner.run(const [CallForAPerson()]);
      room.answerTheCall(const RoomRefused(RefusalCode.nobodyToReach));
      await pumpEventQueue();

      expect(host.answers.single, isA<TheRefusalPassed>());
    },
  );

  test(
    'a call for a person that meets a closed passage closes the passage',
    () async {
      runner.run(const [CallForAPerson()]);
      room.answerTheCall(const RoomRefused(RefusalCode.passageClosed));
      await pumpEventQueue();

      expect(host.answers.single, isA<TheCallMetAClosedPassage>());
    },
  );

  test(
    'a call for a person that fails on the network asks again on the ladder',
    () async {
      runner.run(const [CallForAPerson()]);
      room.answerTheCall(const RoomNetworkFailed());
      await pumpEventQueue();

      expect(host.answers.single, isA<TheCallWasRefused>());
      expect(_theSignAfter(host.answers), isA<Blocking>());
    },
  );

  test(
    'a call for a person whose session is gone tells the machine the session is gone',
    () async {
      runner.run(const [CallForAPerson()]);
      room.answerTheCall(const RoomSessionGone());
      await pumpEventQueue();

      expect(host.answers.single, isA<TheSessionIsGone>());
    },
  );

  test('one call for a person is in the air at a time', () async {
    runner.run(const [CallForAPerson()]);
    runner.run(const [CallForAPerson()]);

    expect(room.heard, ['call:sessao-1']);
  });

  test(
    'one call for a person is in the air at a time, not one call ever: once it is answered, the next halt calls again',
    () async {
      runner.run(const [CallForAPerson()]);
      room.answerTheCall(const RoomAnswered());
      await pumpEventQueue();

      runner.run(const [CallForAPerson()]);

      expect(room.heard, ['call:sessao-1', 'call:sessao-1']);
    },
  );

  test('a call for a person nobody wants asks the room nothing', () {
    host.callIsWanted = false;

    runner.run(const [CallForAPerson()]);

    expect(room.heard, isEmpty);
  });

  test(
    'a call answered for an earlier session is heard by the Station with that session',
    () async {
      runner.run(const [CallForAPerson()]);
      host
        ..session = 'sessao-2'
        ..callIsWanted = false;
      room.answerTheCall(const RoomRefused(RefusalCode.passageClosed));
      await pumpEventQueue();

      expect(host.earlierCallsHeard.single.$1, 'sessao-1');
      expect(
        host.earlierCallsHeard.single.$2,
        isA<RoomRefused>().having(
          (refused) => refused.code,
          'code',
          RefusalCode.passageClosed,
        ),
      );
      expect(host.answers, isEmpty);
    },
  );

  test(
    'a call for an earlier session that fails on the network still asks for the room\'s session, and the machine is told nothing',
    () async {
      runner.run(const [CallForAPerson()]);
      host.session = 'sessao-2';
      room.answerTheCall(const RoomNetworkFailed());
      await pumpEventQueue();

      expect(room.heard, ['call:sessao-1', 'call:sessao-2']);
      expect(host.answers, isEmpty);
      expect(host.earlierCallsHeard, isEmpty);
    },
  );

  test(
    'after an earlier session\'s answer, a call still wanted is asked again for the room\'s session',
    () async {
      runner.run(const [CallForAPerson()]);
      host.session = 'sessao-2';
      room.answerTheCall(const RoomAnswered());
      await pumpEventQueue();

      expect(room.heard, ['call:sessao-1', 'call:sessao-2']);
      expect(host.answers, isEmpty);
    },
  );

  test('a call for a person with no session asks the room nothing', () async {
    host.session = null;

    runner.run(const [CallForAPerson()]);
    await pumpEventQueue();

    expect(room.heard, isEmpty);
    expect(host.answers, isEmpty);
  });

  test('nothing comes back after the runner is disposed', () async {
    runner.run(const [CallForAPerson()]);
    runner.dispose();
    room.answerTheCall(const RoomAnswered());
    final earlier = runnerOver(fakePorts(ASoundPort(), room: room), host);
    earlier.run(const [CallForAPerson()]);
    earlier.dispose();
    host.session = 'sessao-2';
    room.answerTheCall(const RoomRefused(RefusalCode.passageClosed));
    await pumpEventQueue();

    expect(host.answers, isEmpty);
    expect(host.callsLanded, 0);
    expect(host.earlierCallsHeard, isEmpty);
    expect(host.asked, isEmpty);
    expect(room.heard, ['call:sessao-1', 'call:sessao-1']);
  });
}

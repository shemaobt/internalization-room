import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/effect_runner.dart';
import 'package:internalization_room/features/sala/domain/failure_policy.dart';
import 'package:internalization_room/features/sala/domain/halt.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/ports.dart';
import 'package:internalization_room/features/sala/domain/refusal_code.dart';
import 'package:internalization_room/features/sala/domain/room_reach.dart';

import 'a_room_host_double.dart';
import 'fake_ports.dart';

Halt _theSignAfter(List<MachineEvent> answers) => answers
    .fold(
      const Machine(halt: Blocking(NothingKept())),
      (machine, event) => reduce(machine, event).$1,
    )
    .halt;

void main() {
  late ARoomPort room;
  late ARoomHost host;
  late EffectRunner runner;

  setUp(() {
    room = ARoomPort();
    host = ARoomHost()
      ..session = 'sessao-1'
      ..passageInCourse = 'rute-1';
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

    expect(host.answers.single, isA<TheCallLanded>());
    expect(host.callsLanded, 1);
    expect(host.callsLandedWithoutASession, 0);
    expect(
      _theSignAfter(host.answers),
      isA<Blocking>().having((sign) => sign.serverKnows, 'serverKnows', true),
    );
  });

  test(
    'a call for a person the room refuses asks again on the ladder',
    () async {
      runner.run(const [CallForAPerson()]);
      room.answerTheCall(const RoomRefused('some_code'));
      await pumpEventQueue();

      expect(host.answers.single, isA<TheCallWasRefused>());
      expect(host.callsLanded + host.callsLandedWithoutASession, 0);
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
    'a call for a person that meets a closed passage marks it closed',
    () async {
      runner.run(const [CallForAPerson()]);
      room.answerTheCall(const RoomRefused(RefusalCode.passageClosed));
      await pumpEventQueue();

      expect(host.answers.single, isA<TheCallMetAClosedPassage>());
    },
  );

  test(
    'a call for a person that fails on the network takes the room out of reach at the person\'s door',
    () async {
      runner.run(const [CallForAPerson()]);
      room.answerTheCall(const RoomNetworkFailed());
      await pumpEventQueue();

      expect(
        host.answers.single,
        isA<NetworkFailedAt>()
            .having((fell) => fell.door, 'door', Door.person)
            .having((fell) => fell.why, 'why', RoomReach.noNetwork),
      );
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
    'a call answered for an earlier session is heard by the Station with that session and its passage',
    () async {
      runner.run(const [CallForAPerson()]);
      host
        ..session = 'sessao-2'
        ..passageInCourse = 'rute-2'
        ..callIsWanted = false;
      room.answerTheCall(const RoomRefused(RefusalCode.passageClosed));
      await pumpEventQueue();

      expect(host.earlierCallsHeard.single.$1, 'sessao-1');
      expect(host.earlierCallsHeard.single.$2, 'rute-1');
      expect(
        host.earlierCallsHeard.single.$3,
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
    'a call for an earlier session that fails on the network falls at the person\'s door and does not ask again',
    () async {
      runner.run(const [CallForAPerson()]);
      host.session = 'sessao-2';
      room.answerTheCall(const RoomNetworkFailed());
      await pumpEventQueue();

      expect(
        host.answers.single,
        isA<NetworkFailedAt>().having((fell) => fell.door, 'door', Door.person),
      );
      expect(host.earlierCallsHeard, isEmpty);
      expect(room.heard, ['call:sessao-1']);
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

  test(
    'a call with no session asks the room by the tablet; the Station hears it landed, and the machine is told nothing',
    () async {
      host.session = null;

      runner.run(const [CallForAPerson()]);
      room.answerTheTabletCall(const TabletCallAnswered(RoomAnswered()));
      await pumpEventQueue();

      expect(room.heard, ['call by the tablet']);
      expect(host.callsLandedWithoutASession, 1);
      expect(host.callsLanded, 0);
      expect(host.answers, isEmpty);
    },
  );

  test(
    'a call with no session for an unknown tablet changes nothing',
    () async {
      host.session = null;

      runner.run(const [CallForAPerson()]);
      room.answerTheTabletCall(const TheTabletIsUnknown());
      await pumpEventQueue();

      expect(host.callsLanded + host.callsLandedWithoutASession, 0);
      expect(host.answers, isEmpty);
      expect(host.asked, isEmpty);
    },
  );

  test(
    'a call with no session whose device link cannot be read is asked again on the ladder',
    () async {
      host.session = null;

      runner.run(const [CallForAPerson()]);
      room.answerTheTabletCall(const TheDeviceLinkUnread());
      await pumpEventQueue();

      expect(host.asked, ['askForAPersonAgain']);
      expect(host.answers, isEmpty);
    },
  );

  test(
    'a person-arrived mark reaches the room port with the room\'s session; with none, it asks nothing',
    () {
      runner.run(const [TellAPersonArrived()]);
      host.session = null;
      runner.run(const [TellAPersonArrived()]);

      expect(room.heard, ['arrived:sessao-1']);
    },
  );

  test(
    'a person-arrived mark that fails on the network takes the room out of reach at the person\'s door',
    () async {
      runner.run(const [TellAPersonArrived()]);
      room.answerTheArrival(const RoomNetworkFailed());
      await pumpEventQueue();

      expect(
        host.answers.single,
        isA<NetworkFailedAt>().having((fell) => fell.door, 'door', Door.person),
      );
    },
  );

  test(
    'a person-arrived mark whose session is gone tells the machine so; for a session no longer the room\'s, the Station hears it',
    () async {
      runner.run(const [TellAPersonArrived()]);
      room.answerTheArrival(const RoomSessionGone());
      await pumpEventQueue();

      expect(host.answers.single, isA<TheSessionIsGone>());
      expect(host.earlierSessionsGone, isEmpty);

      runner.run(const [TellAPersonArrived()]);
      host.session = 'sessao-2';
      room.answerTheArrival(const RoomSessionGone());
      await pumpEventQueue();

      expect(host.answers, hasLength(1));
      expect(host.earlierSessionsGone, ['sessao-1']);
    },
  );

  test(
    'a person-arrived mark the room answers or refuses changes nothing',
    () async {
      runner.run(const [TellAPersonArrived(), TellAPersonArrived()]);
      room
        ..answerTheArrival(const RoomAnswered())
        ..answerTheArrival(const RoomRefused('some_code'));
      await pumpEventQueue();

      expect(host.answers, isEmpty);
      expect(host.earlierSessionsGone, isEmpty);
    },
  );

  test('nothing comes back after the runner is disposed', () async {
    runner.run(const [CallForAPerson(), TellAPersonArrived()]);
    runner.dispose();
    room
      ..answerTheCall(const RoomAnswered())
      ..answerTheArrival(const RoomNetworkFailed());
    final earlier = runnerOver(fakePorts(ASoundPort(), room: room), host);
    earlier.run(const [CallForAPerson()]);
    earlier.dispose();
    host.session = 'sessao-2';
    room.answerTheCall(const RoomRefused(RefusalCode.passageClosed));
    host.session = null;
    final withoutASession = runnerOver(
      fakePorts(ASoundPort(), room: room),
      host,
    );
    withoutASession.run(const [CallForAPerson()]);
    withoutASession.dispose();
    room.answerTheTabletCall(const TheDeviceLinkUnread());
    await pumpEventQueue();

    expect(host.answers, isEmpty);
    expect(host.callsLanded + host.callsLandedWithoutASession, 0);
    expect(host.earlierCallsHeard, isEmpty);
    expect(host.asked, isEmpty);
    expect(room.heard, [
      'call:sessao-1',
      'arrived:sessao-1',
      'call:sessao-1',
      'call by the tablet',
    ]);
  });
}

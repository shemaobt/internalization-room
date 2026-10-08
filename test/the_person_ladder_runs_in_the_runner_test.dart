import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/effect_runner.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/failure_policy.dart';
import 'package:internalization_room/features/sala/domain/refusal_code.dart';

import 'a_station_host_double.dart';
import 'fake_ports.dart';

const _first = Duration(seconds: 2);
const _last = Duration(seconds: 7);
const _ms = Duration(milliseconds: 1);

void main() {
  late ARoomPort room;
  late AStorePort store;
  late AStationHost host;
  late EffectRunner runner;
  var machine = const Machine();

  setUp(() {
    room = ARoomPort();
    store = AStorePort();
    host = AStationHost()
      ..session = 'sessao-1'
      ..passageInCourse = 'rute-1'
      ..passageToMark = (book: 'rute', passage: 'rute-1');
    machine = const Machine();
    runner = EffectRunner(
      room: room,
      sound: ASoundPort(),
      recorder: ARecorderPort(),
      store: store,
      host: host,
      watchPeriod: () => const Duration(seconds: 30),
      retryDelay: (step) => step == 0 ? _first : _last,
      partCeiling: () => null,
      clipGrace: () => Duration.zero,
      offlineNotice: () =>
          const Line(LineKind.offlineNotice, 0, asset: 'offline.mp3'),
      generation: () => machine.generation,
    );
  });

  void askAgain() => runner.run(const [AskForAPersonAgain()]);

  void theCallIsRefused(FakeAsync time) {
    room.answerTheCall(const RoomRefused(RefusalCode.nobodyToReach));
    time.flushMicrotasks();
  }

  test(
    'a person still needed is asked for again after the ladder\'s delay',
    () {
      fakeAsync((time) {
        askAgain();

        time.elapse(_first - _ms);
        expect(room.heard, isEmpty);

        time.elapse(_ms);
        expect(room.heard, ['call:sessao-1']);
      });
    },
  );

  test(
    'a ladder armed before the generation moves asks nothing when it fires',
    () {
      fakeAsync((time) {
        askAgain();
        machine = moveTheGeneration(machine);

        time.elapse(_last);

        expect(room.heard, isEmpty);
      });
    },
  );

  test(
    'each ask again waits the next step of the ladder, and stays on the last',
    () {
      fakeAsync((time) {
        askAgain();
        time.elapse(_first - _ms);
        expect(room.heard, hasLength(0));
        time.elapse(_ms);
        expect(room.heard, hasLength(1));
        theCallIsRefused(time);

        askAgain();
        time.elapse(_last - _ms);
        expect(room.heard, hasLength(1));
        time.elapse(_ms);
        expect(room.heard, hasLength(2));
        theCallIsRefused(time);

        askAgain();
        time.elapse(_last - _ms);
        expect(room.heard, hasLength(2));
        time.elapse(_ms);
        expect(room.heard, hasLength(3));
      });
    },
  );

  test('a second ask again before the fire replaces the first', () {
    fakeAsync((time) {
      askAgain();
      time.elapse(_ms);
      askAgain();

      time.elapse(_first);
      expect(room.heard, isEmpty);

      time.elapse(_last - _first);
      expect(room.heard, ['call:sessao-1']);
    });
  });

  test('no person needed, no ask again', () {
    fakeAsync((time) {
      host.aPersonIsNeeded = false;
      askAgain();
      time.elapse(_last * 2);
      expect(room.heard, isEmpty);

      host.aPersonIsNeeded = true;
      askAgain();
      time.elapse(_first - _ms);
      expect(room.heard, isEmpty);
      time.elapse(_ms);
      expect(room.heard, ['call:sessao-1']);
    });
  });

  test(
    'the stop cancels the ladder and starts it again from the first step',
    () {
      fakeAsync((time) {
        askAgain();
        time.elapse(_first);
        theCallIsRefused(time);
        askAgain();

        runner.run(const [StopCallingForAPerson()]);
        time.elapse(_last * 2);
        expect(room.heard, hasLength(1));
        expect(host.callsStopped, 1);

        askAgain();
        time.elapse(_first - _ms);
        expect(room.heard, hasLength(1));
        time.elapse(_ms);
        expect(room.heard, hasLength(2));
      });
    },
  );

  test(
    'a forgotten passage cancels the ladder and starts it again from the first step',
    () {
      fakeAsync((time) {
        askAgain();
        time.elapse(_first);
        theCallIsRefused(time);
        askAgain();

        runner.forgetTheLadder();
        time.elapse(_last * 2);
        expect(room.heard, hasLength(1));

        askAgain();
        time.elapse(_first - _ms);
        expect(room.heard, hasLength(1));
        time.elapse(_ms);
        expect(room.heard, hasLength(2));
      });
    },
  );

  test(
    'the closed-passage mark writes the passage through the store, and the Station hears it closed for the session',
    () async {
      runner.run(const [MarkThePassageClosed()]);
      await pumpEventQueue();

      expect(store.heard, ['mark:rute:rute-1']);
      expect(host.marksHeard, ['begin']);

      store.answerTheMark();
      await pumpEventQueue();

      expect(host.marksHeard, ['begin', 'end:sessao-1:rute-1']);
    },
  );

  test('a closed-passage mark with no session writes nothing', () async {
    host.session = null;

    runner.run(const [MarkThePassageClosed()]);
    await pumpEventQueue();

    expect(store.heard, isEmpty);
    expect(host.marksHeard, isEmpty);
  });

  test(
    'a closed-passage mark with no passage in course writes nothing, and the Station still hears it end',
    () async {
      host.passageToMark = null;

      runner.run(const [MarkThePassageClosed()]);
      await pumpEventQueue();

      expect(store.heard, isEmpty);
      expect(host.marksHeard, ['begin', 'end:sessao-1:null']);
    },
  );

  test('a ladder armed then disposed asks nothing at its delay', () {
    fakeAsync((time) {
      askAgain();
      runner.dispose();

      time.elapse(_last);

      expect(room.heard, isEmpty);
    });
  });

  test(
    'a closed-passage mark whose store answers after dispose is not heard to end',
    () async {
      runner.run(const [MarkThePassageClosed()]);
      await pumpEventQueue();
      runner.dispose();
      store.answerTheMark();
      await pumpEventQueue();

      expect(host.marksHeard, ['begin']);
    },
  );
}

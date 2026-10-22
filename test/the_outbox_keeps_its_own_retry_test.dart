import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/take_upload_queue.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

import 'fakes.dart';

const _onTheCanvas = Machine(station: Canvas());
const _onePartPending = {'linha-1': PartFact.pending};

(Machine, List<Effect>) _run(Machine from, List<MachineEvent> events) {
  var machine = from;
  final effects = <Effect>[];
  for (final event in events) {
    final (next, said) = reduce(machine, event);
    machine = next;
    effects.addAll(said);
  }
  return (machine, effects);
}

void main() {
  group('2 (b): with a part pending, the retry is armed by the Outbox\'s own '
      'backoff', () {
    test('a tally with a part pending arms the retry when it is due', () {
      final (_, effects) = reduce(
        _onTheCanvas,
        const OutboxChanged(_onePartPending, due: Duration(seconds: 30)),
      );

      expect(effects, contains(const ArmTheRetry(due: Duration(seconds: 30))));
    });

    test('the retry firing drains the Outbox', () {
      final (machine, effects) = _run(_onTheCanvas, const [
        OutboxChanged(_onePartPending, due: Duration(seconds: 30)),
        RetryFired(),
      ]);

      expect(effects.last, const DrainTheOutbox());
      expect(machine.draining, isTrue);
    });

    test('a tally with nothing pending cancels the retry', () {
      final (_, effects) = _run(_onTheCanvas, const [
        OutboxChanged(_onePartPending, due: Duration(seconds: 30)),
        OutboxChanged({'linha-1': PartFact.sent}),
      ]);

      expect(effects.last, const CancelTheRetry());
    });
  });

  late Directory home;
  late DateTime now;

  setUp(() {
    home = Directory.systemTemp.createTempSync('fila-alcance');
    now = DateTime.utc(2026, 10, 1, 9);
  });
  tearDown(() => home.deleteSync(recursive: true));

  TakeUploadQueue queueOn(FakeRoom room, {List<Duration> backoff = const []}) =>
      TakeUploadQueue(
        room: room,
        home: () async => home,
        recordings: FakeRecorder.new,
        backoff: backoff,
        now: () => now,
      );

  Future<void> enqueue(TakeUploadQueue queue, String scope) async {
    final file = File('${home.path}/$scope.m4a')..writeAsStringSync('parte');
    await queue.enqueue(
      file,
      sessionId: 'sessao-1',
      kind: 'ensaio',
      scope: scope,
    );
  }

  test('1 (a): a flush that falls on the network says so', () async {
    final room = FakeRoom()..reachable = false;
    final queue = queueOn(room);
    await enqueue(queue, 'parte-1');
    final falls = <void>[];
    final listening = queue.fallsOnTheNetwork.listen(falls.add);
    addTearDown(listening.cancel);

    await queue.flush();
    await Future<void>.delayed(Duration.zero);

    expect(falls, hasLength(1));
  });

  test('2 (b): the tally says each part\'s fact and when the next try is '
      'due', () async {
    final room = FakeRoom()..unreachableTake = 'ensaio/parte-1';
    final queue = queueOn(room, backoff: const [Duration(seconds: 30)]);
    await enqueue(queue, 'parte-1');
    await enqueue(queue, 'parte-2');
    await queue.flush();
    now = now.add(const Duration(seconds: 10));

    final tally = await queue.tally(sessionId: 'sessao-1');

    expect(tally.parts.values, containsAll([PartFact.pending, PartFact.sent]));
    expect(tally.due, const Duration(seconds: 20));
  });

  test('11: a refusal field that is not a code loads as no code, and the '
      'whole manifest loads', () async {
    final guardadas = Directory('${home.path}/guardadas')..createSync();
    File('${guardadas.path}/a.m4a').writeAsStringSync('parte');
    File('${guardadas.path}/b.m4a').writeAsStringSync('parte');
    File('${guardadas.path}/fila.json').writeAsStringSync(
      jsonEncode([
        {
          'id': 'linha-1',
          'name': 'a.m4a',
          'session_id': 'sessao-1',
          'kind': 'ensaio',
          'scope': 'parte-1',
          'attempts': takeUploadAttempts,
          'refusal': 42,
        },
        {
          'id': 'linha-2',
          'name': 'b.m4a',
          'session_id': 'sessao-1',
          'kind': 'ensaio',
          'scope': 'parte-2',
        },
      ]),
    );

    final rows = await queueOn(FakeRoom()).entries();

    expect(rows.map((row) => row.id), ['linha-1', 'linha-2']);
    expect(rows.first.refusal, isNull);
  });

  group('11: a row stranded on a refusal with no code', () {
    Future<TakeUploadQueue> refusedWith(String code) async {
      final room = FakeRoom()
        ..refuseTake = 'ensaio/parte-1'
        ..refuseTakeCode = code;
      final queue = queueOn(room);
      await enqueue(queue, 'parte-1');
      await queue.flush();
      room.refuseTake = null;
      return queue;
    }

    test('keeps the code it was refused with across a restart', () async {
      await refusedWith('HTTP_400');

      final rows = await queueOn(FakeRoom()).entries();

      expect(rows.single.refusal, 'HTTP_400');
    });

    test('gets one more try on a drain that asks for it, and lands', () async {
      final queue = await refusedWith('HTTP_400');

      await queue.flush();
      expect(await queue.giveUps(), hasLength(1), reason: 'only when asked');
      await queue.flush(withTheCodeless: true);

      expect(await queue.pending(), isEmpty);
    });

    test('with a known code stays stranded on that drain', () async {
      final queue = await refusedWith('UNKNOWN_REFERENCE');

      await queue.flush(withTheCodeless: true);

      expect(await queue.giveUps(), hasLength(1));
    });
  });
}

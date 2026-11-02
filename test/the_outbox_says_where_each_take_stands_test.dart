import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/take_upload_queue.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';

import 'fakes.dart';
import 'support/temp.dart';

void main() {
  late Directory home;
  late DateTime now;

  setUp(() {
    home = aTempDir('fila-alcance');
    now = DateTime.utc(2026, 10, 1, 9);
  });

  TakeUploadQueue queueOn(FakeRoom room) => TakeUploadQueue(
    room: room,
    home: () async => home,
    recordings: FakeRecorder.new,
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

  test('2 (b): the tally says each part\'s fact', () async {
    final room = FakeRoom()
      ..refuseTake = 'ensaio/parte-1'
      ..refuseTakeCode = RefusalCode.deviceRevoked;
    final queue = queueOn(room);
    await enqueue(queue, 'parte-2');
    await enqueue(queue, 'parte-1');
    await queue.flush();

    final tally = await queue.tally(sessionId: 'sessao-1');

    expect(tally.parts.values, containsAll([PartFact.pending, PartFact.sent]));
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
  });
}

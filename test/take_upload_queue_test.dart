import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/take_upload_queue.dart';

import 'fakes.dart';

void main() {
  late Directory home;

  setUp(() => home = Directory.systemTemp.createTempSync('fila-tomadas'));
  tearDown(() => home.deleteSync(recursive: true));

  var clock = DateTime(2026, 8, 12, 9);

  TakeUploadQueue queueOn(
    FakeRoom room, {
    List<Duration> backoff = const [],
  }) =>
      TakeUploadQueue(
        room: room,
        home: () async => home,
        backoff: backoff,
        now: () => clock,
      );

  File aTake(String name) {
    final file = File('${home.path}/$name.m4a');
    file.writeAsStringSync('a equipe contou a passagem');
    return file;
  }

  test('a take waits on disk until the room takes it', () async {
    final room = FakeRoom()..reachable = false;
    final queue = queueOn(room);

    await queue.enqueue(aTake('tomada'), sessionId: 'sessao-1', kind: 'ensaio', scope: 'inteira');
    final sent = await queue.flush();

    expect(sent, 0);
    expect(await queue.pending(), hasLength(1),
        reason: 'sem rede a tomada não some — ela espera');
  });

  test('the queue survives the app being closed', () async {
    final room = FakeRoom()..reachable = false;
    await queueOn(room).enqueue(
      aTake('tomada'),
      sessionId: 'sessao-1',
      kind: 'ensaio',
      scope: 'inteira',
    );

    final afterRestart = queueOn(FakeRoom());
    expect(await afterRestart.pending(), hasLength(1),
        reason: 'a fila é um arquivo em disco, não uma lista na memória');

    expect(await afterRestart.flush(), 1);
    expect(await afterRestart.pending(), isEmpty);
  });

  test('the audio file is never deleted, even after the room has it', () async {
    final room = FakeRoom();
    final queue = queueOn(room);
    final entry = await queue.enqueue(
      aTake('tomada'),
      sessionId: 'sessao-1',
      kind: 'ensaio',
      scope: 'inteira',
    );

    await queue.flush();

    expect(File(entry.path).existsSync(), isTrue,
        reason: 'o ensaio e a retro são o produto — a cópia local fica');
  });

  test('a take already taken is not sent again', () async {
    final room = FakeRoom();
    final queue = queueOn(room);
    await queue.enqueue(aTake('tomada'), sessionId: 'sessao-1', kind: 'ensaio', scope: 'inteira');

    await queue.flush();
    await queue.flush();

    expect(room.takesKept, hasLength(1));
  });

  test('one take that will not go does not block the rest forever', () async {
    final room = FakeRoom()..reachable = false;
    final queue = queueOn(room);
    await queue.enqueue(aTake('primeira'), sessionId: 'sessao-1', kind: 'ensaio', scope: 'inteira');
    await queue.enqueue(aTake('segunda'), sessionId: 'sessao-1', kind: 'retro', scope: 'P03');

    expect(await queue.flush(), 0);
    room.reachable = true;

    expect(await queue.flush(), 2);
    expect(room.takesKept, ['ensaio/inteira', 'retro/P03']);
  });

  test('a take whose file vanished stops being retried', () async {
    final room = FakeRoom()..reachable = false;
    final queue = queueOn(room);
    final entry = await queue.enqueue(
      aTake('tomada'),
      sessionId: 'sessao-1',
      kind: 'ensaio',
      scope: 'inteira',
    );
    File(entry.path).deleteSync();

    room.reachable = true;
    await queue.flush();

    expect(await queue.pending(), isEmpty,
        reason: 'insistir para sempre num arquivo que não existe é uma fila que nunca esvazia');
    expect(room.takesKept, isEmpty);
  });

  test('one take that will not go never blocks the ones behind it', () async {
    final room = FakeRoom();
    final queue = queueOn(room);
    await queue.enqueue(aTake('presa'), sessionId: 'sessao-1', kind: 'ensaio', scope: 'inteira');
    await queue.enqueue(aTake('livre'), sessionId: 'sessao-1', kind: 'retro', scope: 'P03');
    room.refuseTake = 'ensaio/inteira';

    final sent = await queue.flush();

    expect(sent, 1);
    expect(room.takesKept, ['retro/P03'],
        reason: 'uma tomada que o servidor recusa não pode prender a fila inteira atrás dela');
  });

  test('the backoff keeps a failed take from being retried at once', () async {
    final room = FakeRoom()..reachable = false;
    final queue = queueOn(room, backoff: const [Duration(minutes: 5)]);
    await queue.enqueue(aTake('tomada'), sessionId: 'sessao-1', kind: 'ensaio', scope: 'inteira');

    await queue.flush();
    room.reachable = true;
    expect(await queue.flush(), 0, reason: 'ainda dentro da espera');

    clock = clock.add(const Duration(minutes: 6));
    expect(await queue.flush(), 1);
  });

  test('after the ceiling it stops trying but nothing is thrown away', () async {
    final room = FakeRoom()..reachable = false;
    final queue = queueOn(room);
    final entry = await queue.enqueue(
      aTake('tomada'),
      sessionId: 'sessao-1',
      kind: 'ensaio',
      scope: 'inteira',
    );

    for (var attempt = 0; attempt < takeUploadAttempts + 2; attempt++) {
      await queue.flush();
    }

    expect(await queue.waiting(), isEmpty);
    expect(await queue.giveUps(), hasLength(1),
        reason: 'passado o teto ela para de ser tentada sozinha');
    expect(File(entry.path).existsSync(), isTrue,
        reason: 'mas o áudio continua em disco — desistir em silêncio é uma forma de perder');
    expect(await queue.pending(), hasLength(1),
        reason: 'e a entrada continua no manifesto, não é apagada');
  });

  test('a manifest written before attempts existed is still read', () async {
    final dir = Directory('${home.path}/guardadas')..createSync(recursive: true);
    File('${dir.path}/fila.json').writeAsStringSync(
      '[{"id":"antiga","path":"${dir.path}/antiga.m4a","session_id":"sessao-1",'
      '"kind":"ensaio","scope":"inteira","pass_number":null,"chunk_index":null,'
      '"stored":false}]',
    );
    File('${dir.path}/antiga.m4a').writeAsStringSync('a equipe contou');

    final queue = queueOn(FakeRoom());
    final waiting = await queue.waiting();

    expect(waiting, hasLength(1));
    expect(waiting.single.attempts, 0);
    expect(await queue.flush(), 1);
  });
}

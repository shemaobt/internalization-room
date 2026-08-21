import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/take_upload_queue.dart';

import 'fakes.dart';

void main() {
  late Directory home;

  setUp(() => home = Directory.systemTemp.createTempSync('fila-tomadas'));
  tearDown(() => home.deleteSync(recursive: true));

  TakeUploadQueue queueOn(FakeRoom room) =>
      TakeUploadQueue(room: room, home: () async => home);

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

  test('a second take recorded under the same name does not eat the first', () async {
    final room = FakeRoom()..reachable = false;
    final queue = queueOn(room);
    final source = aTake('retro_passada1_pedaco1');

    final first = await queue.enqueue(
      source,
      sessionId: 'sessao-1',
      kind: 'retro',
      scope: 'inteira',
    );
    source.writeAsStringSync('a equipe contou de novo');
    final second = await queue.enqueue(
      source,
      sessionId: 'sessao-1',
      kind: 'retro',
      scope: 'inteira',
    );

    expect(second.id, isNot(first.id));
    expect(File(first.path).readAsStringSync(), 'a equipe contou a passagem',
        reason: 'a segunda tentativa não escreve por cima do áudio da primeira');
    expect(File(second.path).readAsStringSync(), 'a equipe contou de novo');

    room.reachable = true;
    expect(await queue.flush(), 2);
    expect(room.takesKept, ['retro/inteira', 'retro/inteira']);
    expect(await queue.pending(), isEmpty);
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
}

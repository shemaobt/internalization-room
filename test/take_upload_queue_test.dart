import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
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

  File manifest() => File('${home.path}/guardadas/fila.json');

  test('a manifest it cannot read is never rewritten from scratch', () async {
    final room = FakeRoom()..reachable = false;
    final queue = queueOn(room);
    await queue.enqueue(aTake('velha-1'),
        sessionId: 'sessao-1', kind: 'ensaio', scope: 'inteira');
    await queue.enqueue(aTake('velha-2'),
        sessionId: 'sessao-1', kind: 'ensaio', scope: 'inteira');

    manifest().writeAsStringSync('[{"id": "velha-1", tru');

    await queue.enqueue(aTake('nova'),
        sessionId: 'sessao-2', kind: 'ensaio', scope: 'inteira');

    expect(await queue.lostHistory(), isTrue,
        reason: 'as linhas ilegíveis nomeavam áudio e a sessão dele — não podem sumir sem deixar marca');
    expect(File('${home.path}/guardadas/fila.json.ilegivel').existsSync(), isTrue);
    expect(
        Directory('${home.path}/guardadas')
            .listSync()
            .whereType<File>()
            .any((file) => p.basename(file.path).startsWith('ensaio-velha-1-')),
        isTrue,
        reason: 'o áudio continua no aparelho mesmo quando o registro dele se perdeu');
  });

  test('a keep racing a flush does not drop the take it just enqueued', () async {
    final room = FakeRoom()..reachable = false;
    final queue = queueOn(room);
    await queue.enqueue(aTake('primeira'),
        sessionId: 'sessao-1', kind: 'ensaio', scope: 'inteira');

    room.reachable = true;
    await Future.wait([
      queue.flush(),
      queue.enqueue(aTake('segunda'),
          sessionId: 'sessao-1', kind: 'ensaio', scope: 'inteira'),
    ]);

    expect(await queue.entries(), hasLength(2),
        reason: 'as duas escritas liam a fila antes de escrever, e a última apagava a outra');
  });

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

    expect(await queue.waiting(), isEmpty,
        reason: 'insistir para sempre num arquivo que não existe é uma fila que nunca esvazia');
    expect(await queue.giveUps(), hasLength(1),
        reason: 'um áudio que sumiu não é um áudio entregue, e a sala precisa dizer isso');
    expect(await queue.unsentOf('ensaio', sessionId: 'sessao-1'), 1);
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

  test('a room that refuses spends the tries, and keeps the audio', () async {
    final room = FakeRoom()..refuseTake = 'ensaio/inteira';
    final queue = queueOn(room);
    final entry = await queue.enqueue(
      aTake('tomada'),
      sessionId: 'sessao-1',
      kind: 'ensaio',
      scope: 'inteira',
    );

    for (var attempt = 0; attempt < takeUploadAttempts + 2; attempt++) {
      clock = clock.add(const Duration(minutes: 20));
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

  test('a room it never reached is paced, never abandoned', () async {
    final room = FakeRoom()..reachable = false;
    final queue = queueOn(room);
    await queue.enqueue(
      aTake('tomada'),
      sessionId: 'sessao-1',
      kind: 'ensaio',
      scope: 'inteira',
    );

    for (var attempt = 0; attempt < takeUploadAttempts + 4; attempt++) {
      clock = clock.add(const Duration(minutes: 20));
      await queue.flush();
    }

    expect(await queue.waiting(), hasLength(1),
        reason: 'um timeout não é uma recusa: num link ruim as cinco tentativas eram '
            'gastas em cinco esperas e a gravação era abandonada de vez');
    expect((await queue.pending()).single.attempts, 0,
        reason: 'nenhuma espera pode gastar o orçamento de recusas');
    expect(await queue.giveUps(), hasLength(1),
        reason: 'continua sendo tentada, mas parar de avisar durante horas é a metade '
            'da decisão que nunca foi construída');

    room.reachable = true;
    clock = clock.add(const Duration(minutes: 20));

    expect(await queue.flush(), 1, reason: 'e ela sobe assim que a sala volta');
  });

  test('a manifest it cannot read never claims the audio is safe', () async {
    final dir = Directory('${home.path}/guardadas')..createSync(recursive: true);
    File('${dir.path}/fila.json').writeAsStringSync('{ isto nao e json');

    final queue = queueOn(FakeRoom());

    expect(await queue.unsentOf('ensaio', sessionId: 'sessao-1'), greaterThan(0),
        reason: 'devolver 0 pintava as contas cheias e dizia à equipe que as '
            'gravações chegaram ao servidor, na palavra de um arquivo que a fila '
            'acabara de não conseguir ler');
  });

  test('a manifest with a broken entry is not read as an empty queue', () async {
    final dir = Directory('${home.path}/guardadas')..createSync(recursive: true);
    File('${dir.path}/fila.json').writeAsStringSync('[{"id":"sem-o-resto"}]');

    final queue = queueOn(FakeRoom());

    expect(await queue.unsentOf('ensaio', sessionId: 'sessao-1'), greaterThan(0),
        reason: 'o TypeError do fromJson nem era capturado');
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

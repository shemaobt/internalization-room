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

  /// The tablet comes back from a backup under a container prefix it has never had.
  void theContainerIsRenamed() {
    final restored = Directory.systemTemp.createTempSync('fila-tomadas-restaurada');
    Directory('${home.path}/guardadas')
        .renameSync('${restored.path}/guardadas');
    home.deleteSync(recursive: true);
    home = restored;
  }

  void aQueueWrittenByTheOlderApp(String name) {
    final dir = Directory('${home.path}/guardadas')..createSync(recursive: true);
    File('${dir.path}/$name').writeAsStringSync('a equipe contou a passagem');
    File('${dir.path}/fila.json').writeAsStringSync(
      '[{"id":"antiga","path":"${dir.path}/$name","session_id":"sessao-1",'
      '"kind":"ensaio","scope":"inteira","pass_number":null,"chunk_index":null,'
      '"stored":false,"lost":false,"attempts":0,"waits":0,"last_try":null}]',
    );
  }

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

  test('a take whose audio is gone stops being retried', () async {
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

  test('audio that is back on the tablet is sent, even after being written off', () async {
    final room = FakeRoom()..reachable = false;
    final queue = queueOn(room);
    final entry = await queue.enqueue(
      aTake('tomada'),
      sessionId: 'sessao-1',
      kind: 'ensaio',
      scope: 'inteira',
    );

    // O flush não acha o arquivo — que é o que acontecia quando o prefixo do contêiner
    // mudava e o áudio seguia inteiro no aparelho.
    final audio = File(entry.path);
    final gravado = audio.readAsBytesSync();
    audio.deleteSync();
    room.reachable = true;
    await queue.flush();

    // E o áudio está de volta no caminho em que a fila procura.
    audio.writeAsBytesSync(gravado);

    expect(await queue.flush(), 1,
        reason: 'há tablets no campo agora segurando áudio que o app já deu por perdido: '
            'dar por perdido foi um palpite sobre o disco, e o disco desmentiu');
    expect(room.takesKept, ['ensaio/inteira']);
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

  test('a take kept before a restore is sent after the container is renamed', () async {
    final room = FakeRoom()..reachable = false;
    await queueOn(room).enqueue(
      aTake('tomada'),
      sessionId: 'sessao-1',
      kind: 'ensaio',
      scope: 'inteira',
    );

    theContainerIsRenamed();
    room.reachable = true;
    final afterRestore = queueOn(room);

    expect(await afterRestore.flush(), 1,
        reason: 'o ensaio está em guardadas/, intacto: a restauração só trocou o prefixo '
            'do contêiner, e a fila o dava por perdido para sempre');
    expect(room.takesKept, ['ensaio/inteira']);
  });

  test('a take whose audio really vanished stays lost across a restore', () async {
    final room = FakeRoom()..reachable = false;
    final entry = await queueOn(room).enqueue(
      aTake('tomada'),
      sessionId: 'sessao-1',
      kind: 'ensaio',
      scope: 'inteira',
    );
    File(entry.path).deleteSync();

    theContainerIsRenamed();
    room.reachable = true;
    final afterRestore = queueOn(room);
    await afterRestore.flush();

    expect(await afterRestore.waiting(), isEmpty,
        reason: 'reconstruir o caminho não pode virar tentar para sempre um áudio que '
            'não está mais no aparelho');
    expect(await afterRestore.giveUps(), hasLength(1),
        reason: 'um áudio que sumiu continua contando como pendente, e a sala diz isso');
    expect(room.takesKept, isEmpty);
  });

  test('a queue written by the older app, with absolute paths, is still sent', () async {
    aQueueWrittenByTheOlderApp('ensaio-antiga-1.m4a');

    final queue = queueOn(FakeRoom());

    expect(await queue.flush(), 1,
        reason: 'os tablets do piloto já têm fila.json gravado no formato de hoje — '
            'deixar de ler o formato antigo perde gravação em toda atualização');
  });

  test('a row the older app condemned is sent when its audio is still there', () async {
    final dir = Directory('${home.path}/guardadas')..createSync(recursive: true);
    File('${dir.path}/ensaio-antiga-1.m4a')
        .writeAsStringSync('a equipe contou a passagem');
    // O manifesto do campo: caminho absoluto de um contêiner que já não existe, e a
    // linha condenada justamente por isso — com o áudio ali do lado o tempo todo.
    File('${dir.path}/fila.json').writeAsStringSync(
      '[{"id":"antiga","path":"/var/mobile/Containers/Data/antigo/ensaio-antiga-1.m4a",'
      '"session_id":"sessao-1","kind":"ensaio","scope":"inteira","pass_number":null,'
      '"chunk_index":null,"stored":false,"lost":true,"attempts":0,"waits":0,'
      '"last_try":null}]',
    );

    final room = FakeRoom();

    expect(await queueOn(room).flush(), 1,
        reason: 'é o tablet de piloto real: a resolução de caminho que condenou essa '
            'linha já foi consertada, mas nada nunca voltou para olhar a linha');
    expect(room.takesKept, ['ensaio/inteira']);
  });

  test('a take recovered from the write-off is no longer called given up', () async {
    final dir = Directory('${home.path}/guardadas')..createSync(recursive: true);
    File('${dir.path}/ensaio-antiga-1.m4a')
        .writeAsStringSync('a equipe contou a passagem');
    File('${dir.path}/fila.json').writeAsStringSync(
      '[{"id":"antiga","path":"/var/mobile/Containers/Data/antigo/ensaio-antiga-1.m4a",'
      '"session_id":"sessao-1","kind":"ensaio","scope":"inteira","pass_number":null,'
      '"chunk_index":null,"stored":false,"lost":true,"attempts":0,"waits":0,'
      '"last_try":null}]',
    );
    final room = FakeRoom()..reachable = false;
    final queue = queueOn(room);

    // O áudio está lá, então a linha é tentada — e a sala é que não responde.
    await queue.flush();

    expect(await queue.giveUps(), isEmpty,
        reason: 'a sala fala a partir dessa conta: uma gravação que está sendo enviada '
            'agora não pode seguir contada como abandonada');
    expect(await queue.waiting(), hasLength(1),
        reason: 'e ela continua na fila, sendo tentada');
  });

  test('a queue written by the older app survives the container being renamed', () async {
    aQueueWrittenByTheOlderApp('ensaio-antiga-1.m4a');
    final room = FakeRoom();

    theContainerIsRenamed();

    expect(await queueOn(room).flush(), 1,
        reason: 'é o tablet de piloto real: manifesto no formato antigo e restauração de '
            'backup no mesmo aparelho');
  });

  test('a take still uploads after the tablet clock jumps backwards', () async {
    final room = FakeRoom()..reachable = false;
    final queue = queueOn(room, backoff: const [Duration(minutes: 5)]);
    clock = DateTime(2026, 8, 12, 9);
    await queue.enqueue(aTake('tomada'),
        sessionId: 'sessao-1', kind: 'ensaio', scope: 'inteira');
    await queue.flush();

    // A correção automática de horário chega justamente quando a rede volta.
    clock = clock.subtract(const Duration(hours: 1));
    room.reachable = true;

    expect(await queue.flush(), 1,
        reason: 'com o relógio atrás do instante gravado a espera nunca vencia, e a '
            'linha nunca voltava a ser tentada: cinquenta minutos de rede boa sem um '
            'envio, e a sala não diz nada, porque só fala de tomada esgotada, perdida '
            'ou emperrada');
    expect(room.takesKept, ['ensaio/inteira']);
  });

  test('the queue survives a timezone change across a restart', () async {
    final room = FakeRoom()..reachable = false;
    clock = DateTime(2026, 8, 12, 9);
    final queue = queueOn(room, backoff: const [Duration(minutes: 5)]);
    await queue.enqueue(aTake('tomada'),
        sessionId: 'sessao-1', kind: 'ensaio', scope: 'inteira');
    await queue.flush();

    // O aparelho reabre num fuso atrás do primeiro, e o instante volta do disco
    // adiante do relógio de agora.
    clock = clock.subtract(const Duration(hours: 3));
    room.reachable = true;
    final afterRestart = queueOn(room, backoff: const [Duration(minutes: 5)]);

    expect(await afterRestart.flush(), 1,
        reason: 'o instante atravessa o disco: gravado num fuso e lido noutro, ele '
            'volta como um horário à frente e prendia a fila para sempre');
    expect(room.takesKept, ['ensaio/inteira']);
  });

  test('a row written before this change, its stamp now ahead of the clock, is sent',
      () async {
    final dir = Directory('${home.path}/guardadas')..createSync(recursive: true);
    File('${dir.path}/ensaio-antiga-1.m4a')
        .writeAsStringSync('a equipe contou a passagem');
    File('${dir.path}/fila.json').writeAsStringSync(
      '[{"id":"antiga","name":"ensaio-antiga-1.m4a","session_id":"sessao-1",'
      '"kind":"ensaio","scope":"inteira","pass_number":null,"chunk_index":null,'
      '"stored":false,"lost":false,"attempts":0,"waits":1,'
      '"last_try":"2026-08-12T12:00:00.000"}]',
    );
    clock = DateTime(2026, 8, 12, 9);
    final room = FakeRoom();
    final queue = queueOn(room, backoff: const [Duration(minutes: 5)]);

    expect(await queue.flush(), 1,
        reason: 'os tablets do piloto já têm fila.json gravado sem fuso nenhum — a '
            'atualização não pode deixar essas linhas presas');
  });

  test('a take freed by a backwards jump goes back to waiting its backoff', () async {
    final room = FakeRoom()..reachable = false;
    final queue = queueOn(room, backoff: const [Duration(minutes: 5)]);
    clock = DateTime(2026, 8, 12, 9);
    await queue.enqueue(aTake('tomada'),
        sessionId: 'sessao-1', kind: 'ensaio', scope: 'inteira');
    await queue.flush();

    clock = clock.subtract(const Duration(hours: 1));
    await queue.flush();

    room.reachable = true;
    expect(await queue.flush(), 0,
        reason: 'soltar a linha de um carimbo do futuro vale uma tentativa, não todas: '
            'essa tentativa grava um carimbo são, e a espera volta a valer — senão a '
            'fila martela a sala a cada flush enquanto o relógio estiver atrás');

    clock = clock.add(const Duration(minutes: 6));
    expect(await queue.flush(), 1,
        reason: 'e ela sobe quando a espera vence, contada do relógio de agora');
  });
}

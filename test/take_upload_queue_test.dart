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

  TakeUploadQueue queueOn(FakeRoom room, {List<Duration> backoff = const []}) =>
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
    final restored = Directory.systemTemp.createTempSync(
      'fila-tomadas-restaurada',
    );
    Directory(
      '${home.path}/guardadas',
    ).renameSync('${restored.path}/guardadas');
    home.deleteSync(recursive: true);
    home = restored;
  }

  void aQueueWrittenByTheOlderApp(String name) {
    final dir = Directory('${home.path}/guardadas')
      ..createSync(recursive: true);
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
    await queue.enqueue(
      aTake('velha-1'),
      sessionId: 'sessao-1',
      kind: 'ensaio',
      scope: 'inteira',
    );
    await queue.enqueue(
      aTake('velha-2'),
      sessionId: 'sessao-1',
      kind: 'ensaio',
      scope: 'inteira',
    );

    manifest().writeAsStringSync('[{"id": "velha-1", tru');

    await queue.enqueue(
      aTake('nova'),
      sessionId: 'sessao-2',
      kind: 'ensaio',
      scope: 'inteira',
    );

    expect(
      await queue.lostHistory(),
      isTrue,
      reason:
          'as linhas ilegíveis nomeavam áudio e a sessão dele — não podem sumir sem deixar marca',
    );
    expect(
      File('${home.path}/guardadas/fila.json.ilegivel').existsSync(),
      isTrue,
    );
    expect(
      Directory('${home.path}/guardadas').listSync().whereType<File>().any(
        (file) => p.basename(file.path).startsWith('ensaio-velha-1-'),
      ),
      isTrue,
      reason:
          'o áudio continua no aparelho mesmo quando o registro dele se perdeu',
    );
  });

  test('a keep racing a flush does not drop the take it just enqueued', () async {
    final room = FakeRoom()..reachable = false;
    final queue = queueOn(room);
    await queue.enqueue(
      aTake('primeira'),
      sessionId: 'sessao-1',
      kind: 'ensaio',
      scope: 'inteira',
    );

    room.reachable = true;
    await Future.wait([
      queue.flush(),
      queue.enqueue(
        aTake('segunda'),
        sessionId: 'sessao-1',
        kind: 'ensaio',
        scope: 'inteira',
      ),
    ]);

    expect(
      await queue.entries(),
      hasLength(2),
      reason:
          'as duas escritas liam a fila antes de escrever, e a última apagava a outra',
    );
  });

  test('a take waits on disk until the room takes it', () async {
    final room = FakeRoom()..reachable = false;
    final queue = queueOn(room);

    await queue.enqueue(
      aTake('tomada'),
      sessionId: 'sessao-1',
      kind: 'ensaio',
      scope: 'inteira',
    );
    final sent = await queue.flush();

    expect(sent, 0);
    expect(
      await queue.pending(),
      hasLength(1),
      reason: 'sem rede a tomada não some — ela espera',
    );
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
    expect(
      await afterRestart.pending(),
      hasLength(1),
      reason: 'a fila é um arquivo em disco, não uma lista na memória',
    );

    expect(await afterRestart.flush(), 1);
    expect(await afterRestart.pending(), isEmpty);
  });

  test(
    'a manifest whose stat has not changed is not read from disk again',
    () async {
      final room = FakeRoom()..reachable = false;
      final queue = queueOn(room);
      await queue.enqueue(
        aTake('tomada'),
        sessionId: 'sessao-1',
        kind: 'ensaio',
        scope: 'inteira',
      );

      final file = manifest();
      final stamp = DateTime(2026, 1, 1);
      final size = await file.length();
      await file.setLastModified(stamp);
      expect(await queue.entries(), hasLength(1));

      file.writeAsBytesSync(List.filled(size, 'x'.codeUnitAt(0)));
      await file.setLastModified(stamp);
      final after = await file.stat();
      expect(
        after.modified,
        stamp,
        reason:
            'o teste só prova algo se o stat continuar igual ao de antes — um '
            'timestamp com fração de segundo não sobrevive ao round-trip de '
            'setLastModified neste sistema de arquivos, daí o carimbo redondo',
      );
      expect(after.size, size);

      expect(
        await queue.entries(),
        hasLength(1),
        reason:
            'o stat não mudou, então a leitura de antes ainda vale — reparsear '
            'os bytes de agora devolveria uma lista vazia, não a de uma linha',
      );
    },
  );

  test(
    'a manifest rewritten by something other than this queue is read again',
    () async {
      final room = FakeRoom()..reachable = false;
      final queue = queueOn(room);
      await queue.enqueue(
        aTake('primeira'),
        sessionId: 'sessao-1',
        kind: 'ensaio',
        scope: 'inteira',
      );
      expect(await queue.entries(), hasLength(1));

      manifest().writeAsStringSync(
        '[{"id":"externa-1","path":"${home.path}/guardadas/externa1.m4a",'
        '"session_id":"sessao-2","kind":"ensaio","scope":"inteira",'
        '"pass_number":null,"chunk_index":null,"stored":false,"lost":false,'
        '"attempts":0,"waits":0,"last_try":null},'
        '{"id":"externa-2","path":"${home.path}/guardadas/externa2.m4a",'
        '"session_id":"sessao-2","kind":"ensaio","scope":"inteira",'
        '"pass_number":null,"chunk_index":null,"stored":false,"lost":false,'
        '"attempts":0,"waits":0,"last_try":null}]',
      );

      expect(
        await queue.entries(),
        hasLength(2),
        reason:
            'o arquivo mudou de verdade por fora — o cache tem que perceber '
            'e reler, não continuar servindo a leitura de uma linha só',
      );
    },
  );

  test(
    'clearing a list entries() handed back does not empty the next one',
    () async {
      final room = FakeRoom()..reachable = false;
      final queue = queueOn(room);
      await queue.enqueue(
        aTake('tomada'),
        sessionId: 'sessao-1',
        kind: 'ensaio',
        scope: 'inteira',
      );

      final first = await queue.entries();
      first.clear();

      expect(
        await queue.entries(),
        hasLength(1),
        reason:
            'a lista devolvida é uma cópia da leitura guardada — mexer nela '
            'por fora não pode apagar o que o cache guarda',
      );
    },
  );

  test(
    'tally counts what unsentOf and unsentScopesOf count, from one read',
    () async {
      final room = FakeRoom()..reachable = false;
      final queue = queueOn(room);
      await queue.enqueue(
        aTake('um'),
        sessionId: 'sessao-1',
        kind: 'ensaio',
        scope: 'inteira',
      );
      await queue.enqueue(
        aTake('dois'),
        sessionId: 'sessao-1',
        kind: 'retro',
        scope: 'inteira',
      );
      await queue.enqueue(
        aTake('tres'),
        sessionId: 'sessao-2',
        kind: 'ensaio',
        scope: 'inteira',
      );

      final tally = await queue.tally(sessionId: 'sessao-1');

      expect(tally.stranded, isFalse);
      expect(tally.unsentTakes, 1, reason: 'só a linha ensaio da sessao-1');
      expect(tally.unsentChunks, 1, reason: 'só a linha retro da sessao-1');
      expect(tally.unsentTakeScopes, {'inteira'});
    },
  );

  test(
    'a manifest tally cannot read never claims the audio is safe either',
    () async {
      final room = FakeRoom()..reachable = false;
      final queue = queueOn(room);
      await queue.enqueue(
        aTake('velha'),
        sessionId: 'sessao-1',
        kind: 'ensaio',
        scope: 'inteira',
      );
      manifest().writeAsStringSync('[{"id": "velha-1", tru');

      final tally = await queue.tally(sessionId: 'sessao-1');

      expect(
        tally.unsentTakes,
        1,
        reason:
            'um manifesto ilegível nunca pode dizer que não há nada pendente',
      );
      expect(tally.unsentChunks, 1);
      expect(tally.unsentTakeScopes, {unknownScope});
    },
  );

  test(
    'tally is stranded once quarantine has happened, from the same read',
    () async {
      final room = FakeRoom()..reachable = false;
      final queue = queueOn(room);
      await queue.enqueue(
        aTake('velha-1'),
        sessionId: 'sessao-1',
        kind: 'ensaio',
        scope: 'inteira',
      );

      manifest().writeAsStringSync('[{"id": "velha-1", tru');
      await queue.enqueue(
        aTake('nova'),
        sessionId: 'sessao-1',
        kind: 'ensaio',
        scope: 'inteira',
      );

      final tally = await queue.tally(sessionId: 'sessao-1');

      expect(
        tally.stranded,
        isTrue,
        reason:
            'a quarentena aconteceu — a mesma leitura que conta precisa saber disso',
      );
    },
  );

  test(
    'a manifest of three thousand rows is parsed once and reused, not on every read',
    () async {
      final room = FakeRoom()..reachable = false;
      final queue = queueOn(room);

      final buffer = StringBuffer('[');
      for (var n = 0; n < 3000; n++) {
        if (n > 0) buffer.write(',');
        buffer.write(
          '{"id":"linha-$n","path":"${home.path}/guardadas/tomada-$n.m4a",'
          '"session_id":"sessao-1","kind":"ensaio","scope":"parte-${n % 12}",'
          '"pass_number":null,"chunk_index":null,"stored":false,"lost":false,'
          '"attempts":0,"waits":0,"last_try":null}',
        );
      }
      buffer.write(']');
      Directory('${home.path}/guardadas').createSync(recursive: true);
      final file = manifest();
      file.writeAsStringSync(buffer.toString());

      final stamp = DateTime(2026, 1, 1);
      await file.setLastModified(stamp);
      expect(
        await queue.entries(),
        hasLength(3000),
        reason: 'a primeira leitura precisa mesmo parsear as 3.000 linhas',
      );

      final size = await file.length();
      final stopwatch = Stopwatch()..start();
      for (var round = 0; round < 20; round++) {
        file.writeAsBytesSync(List.filled(size, 'x'.codeUnitAt(0)));
        await file.setLastModified(stamp);
        expect(
          await queue.entries(),
          hasLength(3000),
          reason:
              'o stat não mudou — a leitura das 3.000 linhas de antes ainda '
              'vale; reparsear os bytes corrompidos de agora devolveria uma '
              'lista vazia, não 3.000',
        );
      }
      stopwatch.stop();

      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(2000),
        reason:
            'vinte leituras repetidas de um manifesto de 3.000 linhas sem '
            'mudar não podem custar perto do que vinte reparses custariam',
      );
    },
  );

  test(
    'a manifest moved to a new home, its stat preserved, resolves audio '
    'against the new folder, not the one that is gone',
    () async {
      final room = FakeRoom()..reachable = false;
      final queue = queueOn(room);
      await queue.enqueue(
        aTake('tomada'),
        sessionId: 'sessao-1',
        kind: 'ensaio',
        scope: 'inteira',
      );

      final stamp = DateTime(2026, 1, 1);
      await manifest().setLastModified(stamp);
      final before = await queue.entries();
      final oldPath = before.single.path;

      theContainerIsRenamed();
      await manifest().setLastModified(stamp);

      final after = await queue.entries();
      expect(
        after.single.path,
        isNot(equals(oldPath)),
        reason:
            'a pasta mudou de verdade — servir o caminho antigo aponta para '
            'um áudio que não está mais lá, mesmo com o manifesto intacto',
      );
      expect(
        File(after.single.path).existsSync(),
        isTrue,
        reason: 'o caminho devolvido precisa apontar para onde o áudio está agora',
      );
    },
  );

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

    expect(
      File(entry.path).existsSync(),
      isTrue,
      reason: 'o ensaio e a retro são o produto — a cópia local fica',
    );
  });

  test('a take already taken is not sent again', () async {
    final room = FakeRoom();
    final queue = queueOn(room);
    await queue.enqueue(
      aTake('tomada'),
      sessionId: 'sessao-1',
      kind: 'ensaio',
      scope: 'inteira',
    );

    await queue.flush();
    await queue.flush();

    expect(room.takesKept, hasLength(1));
  });

  test('one take that will not go does not block the rest forever', () async {
    final room = FakeRoom()..reachable = false;
    final queue = queueOn(room);
    await queue.enqueue(
      aTake('primeira'),
      sessionId: 'sessao-1',
      kind: 'ensaio',
      scope: 'inteira',
    );
    await queue.enqueue(
      aTake('segunda'),
      sessionId: 'sessao-1',
      kind: 'retro',
      scope: 'P03',
    );

    expect(await queue.flush(), 0);
    room.reachable = true;

    expect(await queue.flush(), 2);
    expect(room.takesKept, ['ensaio/inteira', 'retro/P03']);
  });

  test(
    'a second take recorded under the same name does not eat the first',
    () async {
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
      expect(
        File(first.path).readAsStringSync(),
        'a equipe contou a passagem',
        reason: 'a segunda tentativa não escreve por cima do áudio da primeira',
      );
      expect(File(second.path).readAsStringSync(), 'a equipe contou de novo');

      room.reachable = true;
      expect(await queue.flush(), 2);
      expect(room.takesKept, ['retro/inteira', 'retro/inteira']);
      expect(await queue.pending(), isEmpty);
    },
  );

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

    expect(
      await queue.waiting(),
      isEmpty,
      reason:
          'insistir para sempre num arquivo que não existe é uma fila que nunca esvazia',
    );
    expect(
      await queue.giveUps(),
      hasLength(1),
      reason:
          'um áudio que sumiu não é um áudio entregue, e a sala precisa dizer isso',
    );
    expect(await queue.unsentOf('ensaio', sessionId: 'sessao-1'), 1);
    expect(room.takesKept, isEmpty);
  });

  test(
    'audio that is back on the tablet is sent, even after being written off',
    () async {
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

      expect(
        await queue.flush(),
        1,
        reason:
            'há tablets no campo agora segurando áudio que o app já deu por perdido: '
            'dar por perdido foi um palpite sobre o disco, e o disco desmentiu',
      );
      expect(room.takesKept, ['ensaio/inteira']);
    },
  );

  test('one take that will not go never blocks the ones behind it', () async {
    final room = FakeRoom();
    final queue = queueOn(room);
    await queue.enqueue(
      aTake('presa'),
      sessionId: 'sessao-1',
      kind: 'ensaio',
      scope: 'inteira',
    );
    await queue.enqueue(
      aTake('livre'),
      sessionId: 'sessao-1',
      kind: 'retro',
      scope: 'P03',
    );
    room.refuseTake = 'ensaio/inteira';

    final sent = await queue.flush();

    expect(sent, 1);
    expect(
      room.takesKept,
      ['retro/P03'],
      reason:
          'uma tomada que o servidor recusa não pode prender a fila inteira atrás dela',
    );
  });

  test('a row behind a refused row of its part does not leave', () async {
    final room = FakeRoom()..refuseTake = 'ensaio/parte-2';
    final queue = queueOn(room);
    await queue.enqueue(
      aTake('primeira'),
      sessionId: 'sessao-1',
      kind: 'ensaio',
      scope: 'parte-2',
    );
    final segunda = await queue.enqueue(
      aTake('segunda'),
      sessionId: 'sessao-1',
      kind: 'ensaio',
      scope: 'parte-2',
    );

    expect(await queue.flush(), 0);

    expect(room.takesKept, isEmpty);
    expect(
      room.calls.where((call) => call == 'sendTake'),
      hasLength(1),
      reason: 'a sala só pode ter visto a primeira gravação da parte 2',
    );
    final atras = (await queue.pending()).firstWhere(
      (entry) => entry.id == segunda.id,
    );
    expect(
      [atras.attempts, atras.lastTry],
      [0, null],
      reason:
          'a linha de trás não foi tentada: não gasta tentativa nem marca hora',
    );
  });

  test(
    'inside the window nothing of that part leaves, and past it both land in order',
    () async {
      final room = FakeRoom()..refuseTake = 'ensaio/parte-2';
      final queue = queueOn(room, backoff: const [Duration(seconds: 5)]);
      final primeira = await queue.enqueue(
        aTake('primeira'),
        sessionId: 'sessao-1',
        kind: 'ensaio',
        scope: 'parte-2',
      );
      await queue.flush();
      room.refuseTake = null;
      final segunda = await queue.enqueue(
        aTake('segunda'),
        sessionId: 'sessao-1',
        kind: 'ensaio',
        scope: 'parte-2',
      );

      expect(
        await queue.flush(),
        0,
        reason:
            'a primeira ainda espera a sua vez, e a segunda não passa na frente dela',
      );
      expect(room.takesKept, isEmpty);

      clock = clock.add(const Duration(seconds: 6));

      expect(await queue.flush(), 2);
      expect(room.takesKept, ['ensaio/parte-2', 'ensaio/parte-2']);
      expect(
        [await queue.takeIdOf(primeira.id), await queue.takeIdOf(segunda.id)],
        [room.takeIds.first, room.takeIds.last],
        reason:
            'a gravação que a equipe fez primeiro é a primeira que a sala recebe',
      );
    },
  );

  test('a row of another part is not held by one that is waiting', () async {
    final room = FakeRoom()..refuseTake = 'ensaio/parte-2';
    final queue = queueOn(room, backoff: const [Duration(seconds: 5)]);
    await queue.enqueue(
      aTake('parte-dois'),
      sessionId: 'sessao-1',
      kind: 'ensaio',
      scope: 'parte-2',
    );
    await queue.enqueue(
      aTake('parte-tres'),
      sessionId: 'sessao-1',
      kind: 'ensaio',
      scope: 'parte-3',
    );

    expect(await queue.flush(), 1);
    expect(
      room.takesKept,
      ['ensaio/parte-3'],
      reason: 'a ordem é a de cada parte: a parte 3 não espera a parte 2',
    );
  });

  test(
    'the same part of another session is not held by one that is waiting',
    () async {
      final room = FakeRoom();
      final queue = queueOn(room);
      final sumida = await queue.enqueue(
        aTake('de-uma-sessao'),
        sessionId: 'sessao-1',
        kind: 'ensaio',
        scope: 'parte-2',
      );
      final outra = await queue.enqueue(
        aTake('de-outra-sessao'),
        sessionId: 'sessao-2',
        kind: 'ensaio',
        scope: 'parte-2',
      );
      File(sumida.path).deleteSync();

      expect(await queue.flush(), 1);

      expect(
        await queue.takeIdOf(outra.id),
        isNotNull,
        reason:
            'a parte 2 de outra sessão é outra parte: duas equipes em dois '
            'ensaios não têm ordem nenhuma entre si',
      );
      expect(await queue.takeIdOf(sumida.id), isNull);
    },
  );

  test('a stretch is not held by a part that is waiting', () async {
    final room = FakeRoom()..refuseTake = 'ensaio/parte-2';
    final queue = queueOn(room);
    await queue.enqueue(
      aTake('parte-dois'),
      sessionId: 'sessao-1',
      kind: 'ensaio',
      scope: 'parte-2',
    );
    await queue.enqueue(
      aTake('trecho'),
      sessionId: 'sessao-1',
      kind: 'retro',
      scope: 'parte-2',
    );

    expect(await queue.flush(), 1);
    expect(
      room.takesKept,
      ['retro/parte-2'],
      reason: 'a regra é da parte gravada, e um trecho contado não é uma delas',
    );
  });

  test('a row that gave up holds nothing behind it', () async {
    final room = FakeRoom()..refuseTake = 'ensaio/parte-2';
    final queue = queueOn(room);
    await queue.enqueue(
      aTake('primeira'),
      sessionId: 'sessao-1',
      kind: 'ensaio',
      scope: 'parte-2',
    );
    final segunda = await queue.enqueue(
      aTake('segunda'),
      sessionId: 'sessao-1',
      kind: 'ensaio',
      scope: 'parte-2',
    );

    for (var attempt = 0; attempt < takeUploadAttempts; attempt++) {
      clock = clock.add(const Duration(minutes: 20));
      await queue.flush();
    }
    room.refuseTake = null;

    expect(await queue.flush(), 1);
    expect(room.takesKept, ['ensaio/parte-2']);
    expect(
      await queue.takeIdOf(segunda.id),
      isNotNull,
      reason:
          'quem desistiu não está à espera, e quem não espera não segura ninguém',
    );
  });

  test(
    'the flush after the write-off sends the row behind the audio that is gone',
    () async {
      final room = FakeRoom();
      final queue = queueOn(room);
      final primeira = await queue.enqueue(
        aTake('primeira'),
        sessionId: 'sessao-1',
        kind: 'ensaio',
        scope: 'parte-2',
      );
      await queue.enqueue(
        aTake('segunda'),
        sessionId: 'sessao-1',
        kind: 'ensaio',
        scope: 'parte-2',
      );
      File(primeira.path).deleteSync();

      expect(
        await queue.flush(),
        0,
        reason:
            'neste flush a primeira só é dada por perdida, e até aí ela é uma '
            'gravação da parte 2 que ainda não subiu',
      );

      expect(await queue.flush(), 1);
      expect(
        room.takesKept,
        ['ensaio/parte-2'],
        reason: 'dada por perdida, ela sai da espera e não segura mais nada',
      );
    },
  );

  test('the backoff keeps a failed take from being retried at once', () async {
    final room = FakeRoom()..reachable = false;
    final queue = queueOn(room, backoff: const [Duration(minutes: 5)]);
    await queue.enqueue(
      aTake('tomada'),
      sessionId: 'sessao-1',
      kind: 'ensaio',
      scope: 'inteira',
    );

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
    expect(
      await queue.giveUps(),
      hasLength(1),
      reason: 'passado o teto ela para de ser tentada sozinha',
    );
    expect(
      File(entry.path).existsSync(),
      isTrue,
      reason:
          'mas o áudio continua em disco — desistir em silêncio é uma forma de perder',
    );
    expect(
      await queue.pending(),
      hasLength(1),
      reason: 'e a entrada continua no manifesto, não é apagada',
    );
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

    expect(
      await queue.waiting(),
      hasLength(1),
      reason:
          'um timeout não é uma recusa: num link ruim as cinco tentativas eram '
          'gastas em cinco esperas e a gravação era abandonada de vez',
    );
    expect(
      (await queue.pending()).single.attempts,
      0,
      reason: 'nenhuma espera pode gastar o orçamento de recusas',
    );
    expect(
      await queue.giveUps(),
      hasLength(1),
      reason:
          'continua sendo tentada, mas parar de avisar durante horas é a metade '
          'da decisão que nunca foi construída',
    );

    room.reachable = true;
    clock = clock.add(const Duration(minutes: 20));

    expect(await queue.flush(), 1, reason: 'e ela sobe assim que a sala volta');
  });

  test('a manifest it cannot read never claims the audio is safe', () async {
    final dir = Directory('${home.path}/guardadas')
      ..createSync(recursive: true);
    File('${dir.path}/fila.json').writeAsStringSync('{ isto nao e json');

    final queue = queueOn(FakeRoom());

    expect(
      await queue.unsentOf('ensaio', sessionId: 'sessao-1'),
      greaterThan(0),
      reason:
          'devolver 0 pintava as contas cheias e dizia à equipe que as '
          'gravações chegaram ao servidor, na palavra de um arquivo que a fila '
          'acabara de não conseguir ler',
    );
  });

  test(
    'a manifest with a broken entry is not read as an empty queue',
    () async {
      final dir = Directory('${home.path}/guardadas')
        ..createSync(recursive: true);
      File('${dir.path}/fila.json').writeAsStringSync('[{"id":"sem-o-resto"}]');

      final queue = queueOn(FakeRoom());

      expect(
        await queue.unsentOf('ensaio', sessionId: 'sessao-1'),
        greaterThan(0),
        reason: 'o TypeError do fromJson nem era capturado',
      );
    },
  );

  test('a stamp that is not a string costs neither its row nor the queue', () async {
    final dir = Directory('${home.path}/guardadas')
      ..createSync(recursive: true);
    for (final scope in ['primeira', 'segunda', 'terceira']) {
      File(
        '${dir.path}/ensaio-$scope.m4a',
      ).writeAsStringSync('a equipe contou a passagem');
    }
    String row(String scope, String lastTry) =>
        '{"id":"$scope","name":"ensaio-$scope.m4a","session_id":"sessao-1",'
        '"kind":"ensaio","scope":"$scope","pass_number":null,"chunk_index":null,'
        '"stored":false,"lost":false,"attempts":0,"waits":0,"last_try":$lastTry}';
    File('${dir.path}/fila.json').writeAsStringSync(
      '[${row('primeira', 'null')},'
      '${row('segunda', '1755000000000')},'
      '${row('terceira', 'null')}]',
    );
    final room = FakeRoom();
    final queue = queueOn(room);

    await queue.flush();

    expect(
      room.takesKept,
      unorderedEquals(['ensaio/primeira', 'ensaio/segunda', 'ensaio/terceira']),
      reason:
          'um carimbo que não é texto numa linha punha a fila inteira em '
          'quarentena — as outras duas gravações não iam a lugar nenhum por '
          'causa de um byte. E a própria linha também sobe: o áudio e a sessão '
          'dela estão intactos, só o ritmo é que ninguém sabe, e ritmo '
          'desconhecido vence agora',
    );
  });

  test('a manifest written before attempts existed is still read', () async {
    final dir = Directory('${home.path}/guardadas')
      ..createSync(recursive: true);
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

  test(
    'a take kept before a restore is sent after the container is renamed',
    () async {
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

      expect(
        await afterRestore.flush(),
        1,
        reason:
            'o ensaio está em guardadas/, intacto: a restauração só trocou o prefixo '
            'do contêiner, e a fila o dava por perdido para sempre',
      );
      expect(room.takesKept, ['ensaio/inteira']);
    },
  );

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

    expect(
      await afterRestore.waiting(),
      isEmpty,
      reason:
          'reconstruir o caminho não pode virar tentar para sempre um áudio que '
          'não está mais no aparelho',
    );
    expect(
      await afterRestore.giveUps(),
      hasLength(1),
      reason:
          'um áudio que sumiu continua contando como pendente, e a sala diz isso',
    );
    expect(room.takesKept, isEmpty);
  });

  test(
    'a queue written by the older app, with absolute paths, is still sent',
    () async {
      aQueueWrittenByTheOlderApp('ensaio-antiga-1.m4a');

      final queue = queueOn(FakeRoom());

      expect(
        await queue.flush(),
        1,
        reason:
            'os tablets do piloto já têm fila.json gravado no formato de hoje — '
            'deixar de ler o formato antigo perde gravação em toda atualização',
      );
    },
  );

  test('a row the older app condemned is sent when its audio is still there', () async {
    final dir = Directory('${home.path}/guardadas')
      ..createSync(recursive: true);
    File(
      '${dir.path}/ensaio-antiga-1.m4a',
    ).writeAsStringSync('a equipe contou a passagem');
    // O manifesto do campo: caminho absoluto de um contêiner que já não existe, e a
    // linha condenada justamente por isso — com o áudio ali do lado o tempo todo.
    File('${dir.path}/fila.json').writeAsStringSync(
      '[{"id":"antiga","path":"/var/mobile/Containers/Data/antigo/ensaio-antiga-1.m4a",'
      '"session_id":"sessao-1","kind":"ensaio","scope":"inteira","pass_number":null,'
      '"chunk_index":null,"stored":false,"lost":true,"attempts":0,"waits":0,'
      '"last_try":null}]',
    );

    final room = FakeRoom();

    expect(
      await queueOn(room).flush(),
      1,
      reason:
          'é o tablet de piloto real: a resolução de caminho que condenou essa '
          'linha já foi consertada, mas nada nunca voltou para olhar a linha',
    );
    expect(room.takesKept, ['ensaio/inteira']);
  });

  test('a take recovered from the write-off is no longer called given up', () async {
    final dir = Directory('${home.path}/guardadas')
      ..createSync(recursive: true);
    File(
      '${dir.path}/ensaio-antiga-1.m4a',
    ).writeAsStringSync('a equipe contou a passagem');
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

    expect(
      await queue.giveUps(),
      isEmpty,
      reason:
          'a sala fala a partir dessa conta: uma gravação que está sendo enviada '
          'agora não pode seguir contada como abandonada',
    );
    expect(
      await queue.waiting(),
      hasLength(1),
      reason: 'e ela continua na fila, sendo tentada',
    );
  });

  test(
    'a queue written by the older app survives the container being renamed',
    () async {
      aQueueWrittenByTheOlderApp('ensaio-antiga-1.m4a');
      final room = FakeRoom();

      theContainerIsRenamed();

      expect(
        await queueOn(room).flush(),
        1,
        reason:
            'é o tablet de piloto real: manifesto no formato antigo e restauração de '
            'backup no mesmo aparelho',
      );
    },
  );

  test('a take still uploads after the tablet clock jumps backwards', () async {
    final room = FakeRoom()..reachable = false;
    final queue = queueOn(room, backoff: const [Duration(minutes: 5)]);
    clock = DateTime(2026, 8, 12, 9);
    await queue.enqueue(
      aTake('tomada'),
      sessionId: 'sessao-1',
      kind: 'ensaio',
      scope: 'inteira',
    );
    await queue.flush();

    // A correção automática de horário chega justamente quando a rede volta.
    clock = clock.subtract(const Duration(hours: 1));
    room.reachable = true;

    expect(
      await queue.flush(),
      1,
      reason:
          'com o relógio atrás do instante gravado a espera nunca vencia, e a '
          'linha nunca voltava a ser tentada: cinquenta minutos de rede boa sem um '
          'envio, e a sala não diz nada, porque só fala de tomada esgotada, perdida '
          'ou emperrada',
    );
    expect(room.takesKept, ['ensaio/inteira']);
  });

  test('the queue survives a timezone change across a restart', () async {
    final room = FakeRoom()..reachable = false;
    clock = DateTime(2026, 8, 12, 9);
    final queue = queueOn(room, backoff: const [Duration(minutes: 5)]);
    await queue.enqueue(
      aTake('tomada'),
      sessionId: 'sessao-1',
      kind: 'ensaio',
      scope: 'inteira',
    );
    await queue.flush();

    // O aparelho reabre num fuso atrás do primeiro, e o instante volta do disco
    // adiante do relógio de agora.
    clock = clock.subtract(const Duration(hours: 3));
    room.reachable = true;
    final afterRestart = queueOn(room, backoff: const [Duration(minutes: 5)]);

    expect(
      await afterRestart.flush(),
      1,
      reason:
          'o instante atravessa o disco: gravado num fuso e lido noutro, ele '
          'volta como um horário à frente e prendia a fila para sempre',
    );
    expect(room.takesKept, ['ensaio/inteira']);
  });

  test(
    'a row written before this change, its stamp now ahead of the clock, is sent',
    () async {
      final dir = Directory('${home.path}/guardadas')
        ..createSync(recursive: true);
      File(
        '${dir.path}/ensaio-antiga-1.m4a',
      ).writeAsStringSync('a equipe contou a passagem');
      File('${dir.path}/fila.json').writeAsStringSync(
        '[{"id":"antiga","name":"ensaio-antiga-1.m4a","session_id":"sessao-1",'
        '"kind":"ensaio","scope":"inteira","pass_number":null,"chunk_index":null,'
        '"stored":false,"lost":false,"attempts":0,"waits":1,'
        '"last_try":"2026-08-12T12:00:00.000"}]',
      );
      clock = DateTime(2026, 8, 12, 9);
      final room = FakeRoom();
      final queue = queueOn(room, backoff: const [Duration(minutes: 5)]);

      expect(
        await queue.flush(),
        1,
        reason:
            'os tablets do piloto já têm fila.json gravado sem fuso nenhum — a '
            'atualização não pode deixar essas linhas presas',
      );
    },
  );

  test(
    'a take freed by a backwards jump goes back to waiting its backoff',
    () async {
      final room = FakeRoom()..reachable = false;
      final queue = queueOn(room, backoff: const [Duration(minutes: 5)]);
      clock = DateTime(2026, 8, 12, 9);
      await queue.enqueue(
        aTake('tomada'),
        sessionId: 'sessao-1',
        kind: 'ensaio',
        scope: 'inteira',
      );
      await queue.flush();

      clock = clock.subtract(const Duration(hours: 1));
      await queue.flush();

      room.reachable = true;
      expect(
        await queue.flush(),
        0,
        reason:
            'soltar a linha de um carimbo do futuro vale uma tentativa, não todas: '
            'essa tentativa grava um carimbo são, e a espera volta a valer — senão a '
            'fila martela a sala a cada flush enquanto o relógio estiver atrás',
      );

      clock = clock.add(const Duration(minutes: 6));
      expect(
        await queue.flush(),
        1,
        reason: 'e ela sobe quando a espera vence, contada do relógio de agora',
      );
    },
  );
}

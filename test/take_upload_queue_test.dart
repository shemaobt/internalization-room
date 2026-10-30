import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/take_upload_queue.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';

import 'a_wav_take.dart';
import 'fakes.dart';

void main() {
  late Directory home;
  late FakeRecorder recorder;

  setUp(() {
    home = Directory.systemTemp.createTempSync('fila-tomadas');
    recorder = FakeRecorder();
  });
  tearDown(() => home.deleteSync(recursive: true));

  var clock = DateTime(2026, 8, 12, 9);

  TakeUploadQueue queueOn(FakeRoom room) => TakeUploadQueue(
    room: room,
    home: () async => home,
    recordings: () => recorder,
    now: () => clock,
  );

  File aTake(String name) {
    final file = File('${home.path}/$name.m4a');
    file.writeAsStringSync('a equipe contou a passagem');
    return file;
  }

  Future<PendingTake> keep(
    TakeUploadQueue queue,
    String name,
    String session,
  ) => queue.enqueue(
    aTake(name),
    sessionId: session,
    kind: 'ensaio',
    scope: 'inteira',
  );

  /// The team taps every row still waiting, the only way a row goes up again.
  Future<int> aTapOnEveryRow(TakeUploadQueue queue) async {
    for (final row in await queue.pending()) {
      queue.tapped(row.id);
    }
    return queue.flush();
  }

  List<String> inTheFolder() => [
    for (final e in Directory('${home.path}/guardadas').listSync())
      p.basename(e.path),
  ];

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

  test('the end of a life empties the Outbox with its copies and refuses a '
      'take until the next life begins', () async {
    final queue = queueOn(FakeRoom()..reachable = false);
    await keep(queue, 'velha-1', 'sessao-1');
    await keep(queue, 'velha-2', 'sessao-2');

    await queue.endTheLife();

    expect(await queue.entries(), isEmpty);
    expect(inTheFolder(), ['fila.json']);
    await expectLater(
      keep(queue, 'tardia', 'sessao-1'),
      throwsA(isA<TheLifeEnded>()),
    );
    queue.beginALife();
    await keep(queue, 'nova', 'sessao-3');
    expect(await queue.entries(), hasLength(1));
  });

  test('a life that ends with a copy it cannot delete leaves no row behind, '
      'and after a relaunch no row is without its copy', () async {
    final queue = queueOn(FakeRoom()..reachable = false);
    final kept = await keep(queue, 'velha', 'sessao-1');
    await keep(queue, 'outra', 'sessao-1');
    File(kept.path).deleteSync();
    Directory(kept.path).createSync();

    expect(await queue.endTheLife(), isFalse);
    expect(await queue.entries(), isEmpty);

    final relaunched = queueOn(FakeRoom()..reachable = false);
    expect([
      for (final row in await relaunched.entries())
        if (!File(row.path).existsSync()) row.id,
    ], isEmpty);
  });

  test('the end of a life deletes every recording on the tablet', () async {
    final queue = queueOn(FakeRoom()..reachable = false);
    final recording = File('${recorder.home.path}/ensaio_parte1.wav')
      ..writeAsBytesSync([1]);

    expect(await queue.endTheLife(), isTrue);

    expect(recording.existsSync(), isFalse);
  });

  test('a recordings folder that cannot be swept fails the sweep', () async {
    final queue = queueOn(FakeRoom()..reachable = false);
    for (final error in [
      const FileSystemException('o disco falhou'),
      MissingPlatformDirectoryException('sem pasta'),
    ]) {
      recorder.deleteEveryThrows = error;

      expect(await queue.endTheLife(), isFalse);
    }
  });

  test('a sweep goes on past a copy already gone', () async {
    final queue = queueOn(FakeRoom()..reachable = false);
    final first = await keep(queue, 'velha-1', 'sessao-1');
    await keep(queue, 'velha-2', 'sessao-1');
    File(first.path).deleteSync();

    expect(await queue.endTheLife(), isTrue);
    expect(await queue.entries(), isEmpty);
    expect(inTheFolder(), ['fila.json']);
  });

  test(
    'a take being copied when the life ends leaves no row and no copy',
    () async {
      final queue = queueOn(FakeRoom()..reachable = false);

      final enqueuing = keep(queue, 'no-ar', 'sessao-1');
      final ending = queue.endTheLife();

      await expectLater(enqueuing, throwsA(isA<TheLifeEnded>()));
      await ending;
      expect(File('${home.path}/no-ar.m4a').existsSync(), isFalse);
      expect(await queue.entries(), isEmpty);
      expect(inTheFolder(), ['fila.json']);
    },
  );

  group('a copy no row names', () {
    Future<PendingTake> aJoinRowInTheAir(
      TakeUploadQueue queue,
      FakeRoom room,
    ) async {
      final row = (await queue.enqueueTheJoin(
        File('${home.path}/parte-2-junta-ensaio-2.wav')
          ..writeAsBytesSync(aWavTake()),
        sessionId: 'sessao-1',
        number: 2,
        passNumber: 1,
        origin: 'ensaio-2',
      ))!;
      queue.tapped(row.id);
      unawaited(queue.flush());
      await room.untilTakeHeld();
      return row;
    }

    test('a copy whose row was withdrawn while in the air is swept at the next '
        'open', () async {
      final room = FakeRoom()..holdNextTake('parte-2');
      final queue = queueOn(room);
      final row = await aJoinRowInTheAir(queue, room);
      expect(await queue.withdrawEvenInTheAir(row), isTrue);

      final relaunched = queueOn(room);
      await relaunched.sweepTheCopiesLeftBehind();

      expect(await relaunched.entries(), isEmpty);
      expect(inTheFolder(), ['fila.json']);
    });

    test('a withdrawn copy the disk will not delete does not stop the rows '
        'behind it', () async {
      final room = FakeRoom()..holdNextTake('parte-2');
      final queue = queueOn(room);
      final row = (await queue.enqueueTheJoin(
        File('${home.path}/parte-2-junta-ensaio-2.wav')
          ..writeAsBytesSync(aWavTake()),
        sessionId: 'sessao-1',
        number: 2,
        passNumber: 1,
        origin: 'ensaio-2',
      ))!;
      final behind = await keep(queue, 'inteira', 'sessao-1');
      queue.tapped(row.id);
      queue.tapped(behind.id);
      final outside = Zone.current;
      final flushed = IOOverrides.runZoned(
        queue.flush,
        createFile: (path) {
          final real = outside.run(() => File(path));
          return path == row.path ? _ACopyTheDiskWillNotDelete(real) : real;
        },
      );
      await room.untilTakeHeld();
      expect(await queue.withdrawEvenInTheAir(row), isTrue);
      room.finishHeldTake();
      await flushed;

      expect(
        room.takesKept,
        ['ensaio/parte-2', 'ensaio/inteira'],
        reason:
            'a cópia que o disco recusava apagar saía do catch do envio, e a '
            'fila parava antes da linha seguinte',
      );
    });

    test('the open sweep leaves the link, the resume point and the current '
        'session in their folder', () async {
      final folder = Directory('${home.path}/guardadas')..createSync();
      for (final ledger in [
        'vinculo.json',
        'em_curso.json',
        'sessao_atual.json',
      ]) {
        File('${folder.path}/$ledger').writeAsStringSync('{}');
      }
      File(
        '${folder.path}/ensaio-parte-2-1761730000000000-0.m4a',
      ).writeAsStringSync('a equipe contou a passagem');

      await queueOn(FakeRoom()).sweepTheCopiesLeftBehind();

      expect(inTheFolder()..sort(), [
        'em_curso.json',
        'sessao_atual.json',
        'vinculo.json',
      ]);
    });

    test(
      'the open sweep goes on past a copy the disk will not delete',
      () async {
        final folder = Directory('${home.path}/guardadas')..createSync();
        final orphans = [
          for (final n in [1, 2, 3])
            '${folder.path}/ensaio-parte-$n-176173000000000$n-0.m4a',
        ];
        for (final orphan in orphans) {
          File(orphan).writeAsStringSync('a equipe contou a passagem');
        }
        var refusals = 0;
        final outside = Zone.current;
        await IOOverrides.runZoned(
          queueOn(FakeRoom()).sweepTheCopiesLeftBehind,
          createFile: (path) {
            final real = outside.run(() => File(path));
            if (!orphans.contains(path)) return real;
            return _ACopyTheDiskWillNotDelete(
              real,
              whenRefused: () => refusals++,
            );
          },
        );

        expect(
          refusals,
          3,
          reason:
              'a primeira cópia que o disco recusava apagar parava a varredura, '
              'e as órfãs atrás dela ficavam na pasta',
        );
      },
    );

    test(
      'a take being kept while the Outbox opens keeps its copy and its row',
      () async {
        final queue = queueOn(FakeRoom()..reachable = false);
        final take = _ATakeWhoseCopyIsHeld(aTake('nova'));

        final keeping = queue.enqueue(
          take,
          sessionId: 'sessao-1',
          kind: 'ensaio',
          scope: 'inteira',
        );
        await take.copied.future;
        await queue.sweepTheCopiesLeftBehind();
        take.release.complete();
        final row = await keeping;

        expect([for (final entry in await queue.entries()) entry.id], [row.id]);
        expect(File(row.path).existsSync(), isTrue);
      },
    );

    test('the next try at the end of a life deletes the copies the first one '
        'left', () async {
      final room = FakeRoom()..holdNextTake('parte-2');
      final queue = queueOn(room);
      final row = await aJoinRowInTheAir(queue, room);
      await queue.withdrawEvenInTheAir(row);

      expect(await queue.endTheLife(), isTrue);
      expect(inTheFolder(), ['fila.json']);

      room.finishHeldTake();
      await queue.flush();

      expect(inTheFolder(), ['fila.json']);
      expect(await queue.entries(), isEmpty);
    });

    test('the end of a life leaves the link and the resume point in their '
        'folder', () async {
      final queue = queueOn(FakeRoom()..reachable = false);
      await keep(queue, 'velha', 'sessao-1');
      for (final ledger in ['vinculo.json', 'em_curso.json']) {
        File('${home.path}/guardadas/$ledger').writeAsStringSync('{}');
      }

      expect(await queue.endTheLife(), isTrue);

      expect(inTheFolder()..sort(), [
        'em_curso.json',
        'fila.json',
        'vinculo.json',
      ]);
    });
  });

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
      File('${home.path}/guardadas/fila.json.ilegivel').existsSync(),
      isTrue,
      reason:
          'as linhas ilegíveis nomeavam áudio e a sessão dele — não podem sumir sem deixar marca',
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

  test(
    'a keep racing a flush does not drop the take it just enqueued',
    () async {
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
        (await queue.entries()).length + room.takesKept.length,
        2,
        reason:
            'as duas escritas liam a fila antes de escrever, e a última apagava '
            'a outra; ENG-1347: a confirmada sai da fila, a outra fica ou sobe',
      );
    },
  );

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

  test('a sentence kept for its row is never sent by a flush, before or '
      'after a restart', () async {
    final room = FakeRoom();
    await queueOn(room).enqueue(
      aTake('frase'),
      sessionId: 'sessao-1',
      kind: sentenceKind,
      scope: '3',
    );

    final afterRestart = queueOn(room);
    expect(await afterRestart.flush(), 0);
    expect(
      room.takesKept,
      isEmpty,
      reason:
          'a frase guardada subia sozinha como tomada, sem a equipe tocar '
          'na linha',
    );
    expect(await afterRestart.pending(), hasLength(1));
    expect((await afterRestart.sentenceHeldIn('sessao-1'))?.scope, '3');
    expect(await afterRestart.sentenceHeldIn('sessao-2'), isNull);
  });

  test('a sentence withdrawn is no longer held, even when asked before the '
      'withdrawal is written', () async {
    final queue = queueOn(FakeRoom());
    final row = await queue.enqueue(
      aTake('frase'),
      sessionId: 'sessao-1',
      kind: sentenceKind,
      scope: '3',
    );

    unawaited(queue.withdraw(row));

    expect(
      await queue.sentenceHeldIn('sessao-1'),
      isNull,
      reason:
          'a leitura passava à frente da retirada ainda por escrever, e a '
          'frase deixada voltava',
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

    expect(await aTapOnEveryRow(afterRestart), 1);
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
    'tally counts what unsentOf counts and holds the unsent rehearsal takes by '
    'part, from one read',
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
        kind: sentenceKind,
        scope: '2',
      );
      await queue.enqueue(
        aTake('tres'),
        sessionId: 'sessao-2',
        kind: 'ensaio',
        scope: 'inteira',
      );

      final tally = await queue.tally(sessionId: 'sessao-1');

      expect(tally.unsentTakes, 1, reason: 'só a linha ensaio da sessao-1');
      expect(tally.unsentChunks, 1, reason: 'só a linha frase da sessao-1');
      expect(tally.unsentParts.keys, ['inteira']);
      expect(tally.unsentParts['inteira'], hasLength(1));
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
      expect(tally.unsentParts, isEmpty);
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
    },
  );

  test('a manifest moved to a new home, its stat preserved, resolves audio '
      'against the new folder, not the one that is gone', () async {
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
      reason:
          'o caminho devolvido precisa apontar para onde o áudio está agora',
    );
  });

  test(
    'the audio file is never deleted while the room has not confirmed it',
    () async {
      final room = FakeRoom()..refuseTake = 'ensaio/inteira';
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
        reason:
            'o ensaio e a retro são o produto; ENG-1347: só a cópia de uma '
            'gravação que a sala confirmou sai',
      );
    },
  );

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
    final primeira = await queue.enqueue(
      aTake('primeira'),
      sessionId: 'sessao-1',
      kind: 'ensaio',
      scope: 'inteira',
    );
    final segunda = await queue.enqueue(
      aTake('segunda'),
      sessionId: 'sessao-1',
      kind: 'ensaio',
      scope: 'P03',
    );

    expect(await queue.flush(), 0);
    room.reachable = true;
    await queue.dueAgain(primeira.id);
    await queue.dueAgain(segunda.id);

    expect(await queue.flush(), 2);
    expect(room.takesKept, ['ensaio/inteira', 'ensaio/P03']);
  });

  test(
    'a second take recorded under the same name does not eat the first',
    () async {
      final room = FakeRoom()..reachable = false;
      final queue = queueOn(room);
      final source = aTake('ensaio_passada1');

      final first = await queue.enqueue(
        source,
        sessionId: 'sessao-1',
        kind: 'ensaio',
        scope: 'inteira',
      );
      source.writeAsStringSync('a equipe contou de novo');
      final second = await queue.enqueue(
        source,
        sessionId: 'sessao-1',
        kind: 'ensaio',
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
      expect(room.takesKept, ['ensaio/inteira', 'ensaio/inteira']);
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
      await queue.pending(),
      hasLength(1),
      reason: 'um áudio que sumiu não é um áudio entregue',
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
      await aTapOnEveryRow(queue);

      // E o áudio está de volta no caminho em que a fila procura.
      audio.writeAsBytesSync(gravado);

      expect(
        await aTapOnEveryRow(queue),
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
      kind: 'ensaio',
      scope: 'P03',
    );
    room.refuseTake = 'ensaio/inteira';

    final sent = await queue.flush();

    expect(sent, 1);
    expect(
      room.takesKept,
      ['ensaio/P03'],
      reason:
          'uma tomada que o servidor recusa não pode prender a fila inteira atrás dela',
    );
  });

  test('a row behind a row of its part refused for good is still tried in '
      'that pass', () async {
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
      hasLength(2),
      reason:
          'ENG-1347: uma recusa de vez nunca chegou à sala, então não segura '
          'a gravação de trás nem nesta passada',
    );
    final atras = (await queue.pending()).firstWhere(
      (entry) => entry.id == segunda.id,
    );
    expect(atras.exhausted, isTrue);
  });

  test('a take kept behind a waiting take of its part goes up after it, on its '
      'own keep', () async {
    final room = FakeRoom()
      ..failWith = const Refused(RefusalCode.deviceRevoked);
    final queue = queueOn(room);
    final primeira = await queue.enqueue(
      aTake('primeira'),
      sessionId: 'sessao-1',
      kind: 'ensaio',
      scope: 'parte-2',
    );
    await queue.flush();
    room.failWith = null;
    final segunda = await queue.enqueue(
      aTake('segunda'),
      sessionId: 'sessao-1',
      kind: 'ensaio',
      scope: 'parte-2',
    );

    expect(await queue.flush(), 2);
    expect(room.takesKept, ['ensaio/parte-2', 'ensaio/parte-2']);
    expect(
      [await queue.takeIdOf(primeira.id), await queue.takeIdOf(segunda.id)],
      [room.takeIds.first, room.takeIds.last],
      reason:
          'a gravação que a equipe fez primeiro é a primeira que a sala recebe',
    );
  });

  test('a row of another part is not held by one that is waiting', () async {
    final room = FakeRoom()..refuseTake = 'ensaio/parte-2';
    final queue = queueOn(room);
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

  test('a row that gave up holds nothing behind it', () async {
    final room = FakeRoom()..takeAnswersFirst.add(const Refused('BAD_REQUEST'));
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
        await aTapOnEveryRow(queue),
        0,
        reason:
            'neste flush a primeira só é dada por perdida, e até aí ela é uma '
            'gravação da parte 2 que ainda não subiu',
      );

      expect(await aTapOnEveryRow(queue), 1);
      expect(
        room.takesKept,
        ['ensaio/parte-2'],
        reason: 'dada por perdida, ela sai da espera e não segura mais nada',
      );
    },
  );
  test('a revocation mid-flush leaves the rest of the queue waiting', () async {
    final room = FakeRoom()
      ..failWith = const Refused(RefusalCode.deviceRevoked);
    final queue = queueOn(room);
    for (final session in ['sessao-1', 'sessao-2']) {
      await queue.enqueue(
        aTake(session),
        sessionId: session,
        kind: 'ensaio',
        scope: 'inteira',
      );
    }

    await aTapOnEveryRow(queue);

    expect(
      room.calls.where((call) => call == 'sendTake'),
      hasLength(1),
      reason:
          'depois da revogação o tablet não apresenta nada, e cada parte que '
          'saísse ainda seria recusada por isso',
    );
    expect(
      await queue.waiting(),
      hasLength(2),
      reason:
          'a recusa é do tablet, não da parte: revinculado, ela ainda tem para '
          'onde ir',
    );

    room.failWith = null;
    await aTapOnEveryRow(queue);

    expect(await queue.waiting(), isEmpty);
  });

  test('a take refused unauthorized waits for the link too', () async {
    final room = FakeRoom()..failWith = const Refused(RefusalCode.unauthorized);
    final queue = queueOn(room);
    await queue.enqueue(
      aTake('tomada'),
      sessionId: 'sessao-1',
      kind: 'ensaio',
      scope: 'inteira',
    );

    await queue.flush();

    expect(await queue.waiting(), hasLength(1));
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
      await queue.pending(),
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

  test('a room it never reached spends three attempts in one pass and keeps '
      'the take for a tap', () async {
    final room = FakeRoom()..reachable = false;
    final queue = queueOn(room);
    final entry = await queue.enqueue(
      aTake('tomada'),
      sessionId: 'sessao-1',
      kind: 'ensaio',
      scope: 'inteira',
    );

    for (var pass = 0; pass < 4; pass++) {
      clock = clock.add(const Duration(minutes: 20));
      await queue.flush();
    }

    expect(
      room.calls.where((call) => call == 'sendTake'),
      hasLength(3),
      reason: 'uma falha de rede gasta uma tentativa, e nada sobe sem um toque',
    );
    expect(await queue.waiting(), isEmpty);
    expect(await queue.pending(), hasLength(1));
    expect(File(entry.path).existsSync(), isTrue);

    room.reachable = true;
    await queue.dueAgain(entry.id);

    expect(await queue.flush(), 1, reason: 'o toque devolve as tentativas');
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

    await aTapOnEveryRow(queue);

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
    expect(await aTapOnEveryRow(queue), 1);
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
        await aTapOnEveryRow(afterRestore),
        1,
        reason:
            'o ensaio está em guardadas/, intacto: a restauração só trocou o prefixo '
            'do contêiner, e a fila o dava por perdido para sempre',
      );
      expect(room.takesKept, ['ensaio/inteira']);
    },
  );

  test(
    'a take whose audio really vanished stays lost across a restore',
    () async {
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
      await aTapOnEveryRow(afterRestore);

      expect(
        await afterRestore.waiting(),
        isEmpty,
        reason:
            'reconstruir o caminho não pode virar tentar para sempre um áudio que '
            'não está mais no aparelho',
      );
      expect(
        await afterRestore.pending(),
        hasLength(1),
        reason: 'um áudio que sumiu continua contando como pendente',
      );
      expect(room.takesKept, isEmpty);
    },
  );

  test(
    'a queue written by the older app, with absolute paths, is still sent',
    () async {
      aQueueWrittenByTheOlderApp('ensaio-antiga-1.m4a');

      final queue = queueOn(FakeRoom());

      expect(
        await aTapOnEveryRow(queue),
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
      await aTapOnEveryRow(queueOn(room)),
      1,
      reason:
          'é o tablet de piloto real: a resolução de caminho que condenou essa '
          'linha já foi consertada, mas nada nunca voltou para olhar a linha',
    );
    expect(room.takesKept, ['ensaio/inteira']);
  });

  test('a take recovered from the write-off is tried again', () async {
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
    await aTapOnEveryRow(queue);

    expect(
      room.calls.where((call) => call == 'sendTake'),
      hasLength(3),
      reason: 'ela é tentada',
    );
    expect(
      await queue.pending(),
      hasLength(1),
      reason: 'e ela continua na fila, à espera de um toque',
    );
  });

  test(
    'a queue written by the older app survives the container being renamed',
    () async {
      aQueueWrittenByTheOlderApp('ensaio-antiga-1.m4a');
      final room = FakeRoom();

      theContainerIsRenamed();

      expect(
        await aTapOnEveryRow(queueOn(room)),
        1,
        reason:
            'é o tablet de piloto real: manifesto no formato antigo e restauração de '
            'backup no mesmo aparelho',
      );
    },
  );
  test(
    'a spent take holding a newer take of its part leaves nothing pending '
    'and sends nothing until the team taps; the tap sends both in order',
    () async {
      final room = FakeRoom()..reachable = false;
      final queue = queueOn(room);
      final primeira = await queue.enqueue(
        aTake('primeira'),
        sessionId: 'sessao-1',
        kind: 'ensaio',
        scope: 'parte-3',
        passNumber: 1,
      );
      await queue.flush();
      room.reachable = true;
      final segunda = await queue.enqueue(
        aTake('segunda'),
        sessionId: 'sessao-1',
        kind: 'ensaio',
        scope: 'parte-3',
        passNumber: 2,
      );

      await queue.flush();

      final tally = await queue.tally(sessionId: 'sessao-1');
      expect(tally.parts.values, isNot(contains(PartFact.pending)));
      expect(room.takesKept, isEmpty);

      await queue.dueAgain(primeira.id);
      await queue.dueAgain(segunda.id);
      await queue.flush();

      expect(room.takePasses, [1, 2]);
    },
  );

  test('withdraw removes a pending row and deletes its queued copy', () async {
    final room = FakeRoom();
    final queue = queueOn(room);
    final pendente = await queue.enqueue(
      aTake('pendente'),
      sessionId: 'sessao-1',
      kind: 'ensaio',
      scope: 'inteira',
    );
    final copia = File(pendente.path);
    expect(copia.existsSync(), isTrue);

    await queue.withdraw(pendente);

    expect(await queue.entries(), isEmpty);
    expect(copia.existsSync(), isFalse);
  });

  test('withdraw of a delivered take is a no-op', () async {
    final room = FakeRoom();
    final queue = queueOn(room);
    final entregue = await queue.enqueue(
      aTake('entregue'),
      sessionId: 'sessao-1',
      kind: 'ensaio',
      scope: 'inteira',
    );
    await queue.flush();
    final nome = await queue.takeIdOf(entregue.id);

    await queue.withdraw(entregue);

    expect(
      await queue.entries(),
      isEmpty,
      reason: 'ENG-1347: a tomada confirmada já saiu da fila e não volta',
    );
    expect(
      await queue.takeIdOf(entregue.id),
      nome,
      reason: 'retirar não apaga o nome que a sala deu',
    );
  });

  test('withdraw of a row the queue no longer holds is a no-op', () async {
    final room = FakeRoom();
    final queue = queueOn(room);
    await queue.enqueue(
      aTake('outra'),
      sessionId: 'sessao-1',
      kind: 'ensaio',
      scope: 'inteira',
    );
    const desconhecida = PendingTake(
      id: 'nunca-existiu',
      path: '/nao/existe.m4a',
      sessionId: 'sessao-1',
      kind: 'ensaio',
      scope: 'inteira',
    );

    await queue.withdraw(desconhecida);

    expect(
      await queue.entries(),
      hasLength(1),
      reason:
          'uma linha que a fila nunca guardou não dá erro nem mexe nas outras linhas',
    );
  });

  test(
    'a manifest written by the older app still loads after a withdraw',
    () async {
      aQueueWrittenByTheOlderApp('ensaio-antiga-1.m4a');
      final room = FakeRoom();
      final queue = queueOn(room);

      final nova = await queue.enqueue(
        aTake('nova'),
        sessionId: 'sessao-2',
        kind: 'ensaio',
        scope: 'inteira',
      );
      await queue.withdraw(nova);

      expect(
        await aTapOnEveryRow(queue),
        1,
        reason:
            'a linha do app mais velho ainda é lida e entregue depois de um '
            'withdraw mexer no manifesto',
      );
      expect(room.takesKept, ['ensaio/inteira']);
      expect(
        (await queue.entries()).any((e) => e.id == nova.id),
        isFalse,
        reason: 'a linha retirada não volta a aparecer',
      );
    },
  );

  group('a take the room answers over the wire', () {
    setUpAll(() {
      dotenv.testLoad(fileInput: 'BACKEND_URL=http://sala.local');
    });

    var asked = 0;

    TakeUploadQueue queueAnswering(int status, Map<String, String> body) {
      asked = 0;
      final room = RoomRepository(
        client: MockClient((_) async {
          asked++;
          return http.Response(jsonEncode(body), status);
        }),
        deviceId: () async => 'aparelho-1',
      );
      addTearDown(room.dispose);
      return TakeUploadQueue(
        room: room,
        home: () async => home,
        recordings: FakeRecorder.new,
        now: () => clock,
      );
    }

    Future<void> flushTwelveTimes(TakeUploadQueue queue) async {
      for (var round = 0; round < 12; round++) {
        clock = clock.add(const Duration(minutes: 20));
        await queue.flush();
      }
    }

    test(
      'a take the room refuses leaves the queue at once, its audio kept',
      () async {
        final queue = queueAnswering(422, {
          'detail': 'Internalization room session sessao-1 has no part parte-9',
          'code': 'UNKNOWN_REFERENCE',
        });
        final entry = await queue.enqueue(
          aTake('recusada'),
          sessionId: 'sessao-1',
          kind: 'ensaio',
          scope: 'parte-9',
        );

        await flushTwelveTimes(queue);

        expect(asked, 1, reason: 'uma recusa não tem segunda tentativa');
        expect(await queue.waiting(), isEmpty);
        expect(await queue.pending(), hasLength(1));
        expect(File(entry.path).existsSync(), isTrue);
      },
    );

    test(
      'a take the room fails on with a 500 spends three attempts and stays on '
      'the tablet',
      () async {
        final queue = queueAnswering(500, {
          'detail': 'boom',
          'code': 'INTERNAL_ERROR',
        });
        await queue.enqueue(
          aTake('esperando'),
          sessionId: 'sessao-1',
          kind: 'ensaio',
          scope: 'inteira',
        );

        await flushTwelveTimes(queue);

        expect(asked, 3);
        expect(await queue.waiting(), isEmpty);
        expect(await queue.pending(), hasLength(1));
      },
    );

    test('a take whose request the tablet cannot build spends one try, and '
        'is never taken for the network', () async {
      final room = RoomRepository(
        client: MockClient((_) async {
          asked++;
          return http.Response(jsonEncode({'take_id': 'gravacao-1'}), 200);
        }),
        deviceId: () async => throw const FileSystemException('disco'),
      );
      addTearDown(room.dispose);
      asked = 0;
      final queue = TakeUploadQueue(
        room: room,
        home: () async => home,
        recordings: FakeRecorder.new,
        now: () => clock,
      );
      await queue.enqueue(
        aTake('sem-aparelho'),
        sessionId: 'sessao-1',
        kind: 'ensaio',
        scope: 'inteira',
      );

      await queue.flush();

      expect(asked, 0);
      final row = (await queue.pending()).single;
      expect(row.attempts, 1);
      expect(row.waits, 0);
    });

    test('a take in the air when its session goes keeps its row and its '
        'copy', () async {
      final answer = Completer<void>();
      final reached = Completer<void>();
      final room = RoomRepository(
        client: MockClient((_) async {
          reached.complete();
          await answer.future;
          return http.Response(jsonEncode({'code': 'NOT_FOUND'}), 404);
        }),
        deviceId: () async => 'aparelho-1',
      );
      addTearDown(room.dispose);
      final queue = TakeUploadQueue(
        room: room,
        home: () async => home,
        recordings: FakeRecorder.new,
      );
      final row = await queue.enqueue(
        aTake('no-ar'),
        sessionId: 'sessao-1',
        kind: 'ensaio',
        scope: 'inteira',
      );
      final flushing = queue.flush();
      await reached.future;

      await queue.letGoOfTheSession('sessao-1');
      answer.complete();
      await flushing;

      expect(await queue.entries(), hasLength(1));
      expect(File(row.path).existsSync(), isTrue);
    });

    test('a take whose session is gone stays on the tablet with its copy, and '
        'the Outbox says which session went', () async {
      final queue = queueAnswering(404, {
        'detail': 'Internalization room session not found',
        'code': 'NOT_FOUND',
      });
      final gone = <String>[];
      queue.sessionsGone.listen(gone.add);
      final row = await queue.enqueue(
        aTake('sem-sessao'),
        sessionId: 'sessao-1',
        kind: 'ensaio',
        scope: 'inteira',
      );

      await queue.flush();

      expect(await queue.entries(), hasLength(1));
      expect(File(row.path).existsSync(), isTrue);
      expect(gone, ['sessao-1']);
    });
  });
  group('the scene take in the Outbox', () {
    test('an Outbox row of kind cena goes up through the scene rehearsal keep '
        'door with its label', () async {
      final room = FakeRoom();
      final queue = queueOn(room);
      final take = aTake('cena-1');
      await queue.enqueue(
        take,
        sessionId: 'sessao-1',
        kind: 'cena',
        scope: 'cena',
        scene: 'S2',
      );

      await queue.flush();

      expect(room.scenesKept, ['sessao-1']);
      expect(room.sceneLabels, ['S2']);
      expect(room.sceneTakesSent.single, take.readAsBytesSync());
      expect(room.takesKept, isEmpty, reason: 'não é uma parte do ensaio');
      expect(
        await queue.entries(),
        isEmpty,
        reason: 'a sala confirmou; a linha sai de fila.json',
      );
    });

    group('a scene take waits behind an earlier scene take of its session '
        'that did not land, and not behind one the room refused for good', () {
      test('behind one that did not land', () async {
        final room = FakeRoom()
          ..failSceneWith = const NetworkFailed('sem rede');
        final queue = queueOn(room);
        for (final name in ['cena-1', 'cena-2']) {
          await queue.enqueue(
            aTake(name),
            sessionId: 'sessao-1',
            kind: 'cena',
            scope: 'cena',
          );
        }

        await queue.flush();

        expect(
          room.calls.where((call) => call == 'keepSceneRehearsal'),
          hasLength(3),
          reason:
              'só as tentativas do primeiro: o ensaio de depois chegaria antes e '
              'levaria o número do de antes',
        );
      });

      test(
        'behind one whose attempts are spent, until the team keeps it',
        () async {
          final room = FakeRoom()
            ..failSceneWith = const NetworkFailed('sem rede');
          final queue = queueOn(room);
          await queue.enqueue(
            aTake('cena-1'),
            sessionId: 'sessao-1',
            kind: 'cena',
            scope: 'cena',
          );
          await queue.flush();
          room.failSceneWith = null;
          final segunda = await queue.enqueue(
            aTake('cena-2'),
            sessionId: 'sessao-1',
            kind: 'cena',
            scope: 'cena',
          );

          await queue.flush();

          expect(
            room.sceneTakesSent,
            isEmpty,
            reason: 'a de trás não passa na frente da que espera um toque',
          );

          await queue.keepTheScene(segunda.id);

          expect(room.sceneTakesSent, [
            File('${home.path}/cena-1.m4a').readAsBytesSync(),
            File('${home.path}/cena-2.m4a').readAsBytesSync(),
          ]);
        },
      );

      test('not behind one refused for good', () async {
        final room = FakeRoom()
          ..sceneAnswersFirst.add(const Refused('BAD_REQUEST'));
        final queue = queueOn(room);
        for (final name in ['cena-1', 'cena-2']) {
          await queue.enqueue(
            aTake(name),
            sessionId: 'sessao-1',
            kind: 'cena',
            scope: 'cena',
          );
        }

        await queue.flush();

        expect(
          room.sceneTakesSent.single,
          File('${home.path}/cena-2.m4a').readAsBytesSync(),
          reason: 'nem na mesma passada a recusada segura a de trás',
        );
      });
    });

    test(
      'a take over 25 MiB is refused for good without a byte sent',
      () async {
        final room = FakeRoom();
        final queue = queueOn(room);
        final grande = File('${home.path}/grande.wav')
          ..createSync()
          ..openSync(mode: FileMode.write).truncateSync(25 * 1024 * 1024 + 1);
        final row = await queue.enqueue(
          grande,
          sessionId: 'sessao-1',
          kind: 'cena',
          scope: 'cena',
        );

        await queue.flush();
        await queue.dueAgain(row.id);
        await queue.flush();

        expect(room.calls, isNot(contains('keepSceneRehearsal')));
        final kept = (await queue.entries()).single;
        expect(kept.id, row.id, reason: 'fica em fila.json, nunca apagada');
        expect(kept.refusal, RefusalCode.tooLarge);
      },
    );
  });

  group('every recording the room confirmed leaves fila.json, and its name '
      'still reaches the take', () {
    test('a Part kept and landed', () async {
      final room = FakeRoom();
      final queue = queueOn(room);
      final row = await queue.enqueue(
        aTake('parte-1'),
        sessionId: 'sessao-1',
        kind: 'ensaio',
        scope: 'parte-1',
      );

      await queue.flush();

      expect(await queue.entries(), isEmpty);
      expect(
        Directory('${home.path}/guardadas').listSync().where(
          (file) => !p.basename(file.path).startsWith('fila.json'),
        ),
        isEmpty,
        reason: 'a cópia em guardadas/ sai junto, a sala tem a gravação',
      );
      expect(await queue.takeIdOf(row.id), room.takeIds.single);
      final tally = await queue.tally(sessionId: 'sessao-1');
      expect(tally.parts[row.id], PartFact.sent);
    });

    test('an older manifest sheds its stored rows on the next write', () async {
      final dir = Directory('${home.path}/guardadas')
        ..createSync(recursive: true);
      final copia = File('${dir.path}/ensaio-antiga.m4a')
        ..writeAsStringSync('a equipe contou a passagem');
      File('${dir.path}/fila.json').writeAsStringSync(
        '[{"id":"antiga","name":"ensaio-antiga.m4a","session_id":"sessao-1",'
        '"kind":"ensaio","scope":"parte-1","take_id":"gravacao-1",'
        '"stored":true,"lost":false,"attempts":0,"waits":0,"last_try":null}]',
      );
      final queue = queueOn(FakeRoom()..reachable = false);

      await queue.enqueue(
        aTake('nova'),
        sessionId: 'sessao-1',
        kind: 'ensaio',
        scope: 'parte-2',
      );

      expect([
        for (final row in await queue.entries()) row.id,
      ], isNot(contains('antiga')));
      expect(copia.existsSync(), isFalse);
      expect(
        await queue.takeIdOf('antiga'),
        'gravacao-1',
        reason: 'a parte ainda aprende o nome que a sala deu',
      );
    });
  });

  group('the scene take in the Outbox, against the room', () {
    Future<PendingTake> aScene(TakeUploadQueue queue, String name) =>
        queue.enqueue(
          aTake(name),
          sessionId: 'sessao-1',
          kind: 'cena',
          scope: 'cena',
        );

    test(
      'a scene take never waits behind an older one in backoff when the team '
      'keeps it',
      () async {
        final room = FakeRoom()
          ..failSceneWith = const NetworkFailed('sem rede');
        final queue = queueOn(room);
        await aScene(queue, 'cena-1');
        await queue.flush();
        clock = clock.add(const Duration(seconds: 1));
        room.failSceneWith = null;
        final second = await aScene(queue, 'cena-2');

        final kept = await queue.keepTheScene(second.id);

        expect(kept, isNotNull, reason: 'a equipe pediu; a de trás não segura');
        expect(room.sceneTakesSent, [
          File('${home.path}/cena-1.m4a').readAsBytesSync(),
          File('${home.path}/cena-2.m4a').readAsBytesSync(),
        ]);
      },
    );

    test(
      'a take over 25 MiB holds no one behind it, even within one pass',
      () async {
        final room = FakeRoom();
        final queue = queueOn(room);
        final grande = File('${home.path}/grande.m4a')
          ..createSync()
          ..openSync(
            mode: FileMode.write,
          ).truncateSync(largestTakeTheRoomKeeps + 1);
        await queue.enqueue(
          grande,
          sessionId: 'sessao-1',
          kind: 'cena',
          scope: 'cena',
        );
        await aScene(queue, 'pequena');

        await queue.flush();

        expect(room.sceneTakesSent, hasLength(1));
      },
    );

    test('a retry tapped while the same row is in the air gives it its three '
        'attempts back', () async {
      final room = FakeRoom();
      int keeps() => room.calls.where((c) => c == 'keepSceneRehearsal').length;
      final queue = queueOn(room);
      final row = await aScene(queue, 'cena-1');
      room.holdNextKeepBeforeTheRoomActs();
      final inTheAir = queue.flush();
      await waitFor('a primeira tentativa estar no ar', () => keeps() == 1);
      room.sceneAnswersFirst.add(const NetworkFailed('sem rede'));
      room
        ..finishHeldKeep()
        ..holdNextKeepBeforeTheRoomActs();
      await waitFor('a segunda tentativa estar no ar', () => keeps() == 2);

      await queue.dueAgain(row.id);
      room.sceneAnswersFirst.addAll(const [
        NetworkFailed('sem rede'),
        NetworkFailed('sem rede'),
        NetworkFailed('sem rede'),
      ]);
      room.finishHeldKeep();
      await inTheAir;

      expect(
        room.scenesKept,
        hasLength(1),
        reason:
            'o toque da equipe devolveu as três tentativas; a falha em voo não '
            'as gasta',
      );
    });

    test('a copy gone mid-keep answers not kept, never an error', () async {
      final room = FakeRoom();
      final queue = queueOn(room);
      final row = await aScene(queue, 'cena-1');

      final kept = await IOOverrides.runZoned(
        () => queue.keepTheScene(row.id),
        createFile: (path) =>
            path.contains('${p.separator}guardadas${p.separator}cena-')
            ? _GoneAfterItWasFound(path)
            : _realFile(path),
      );

      expect(kept, isNull);
      expect(room.calls, isNot(contains('keepSceneRehearsal')));
    });
  });

  group('the scene take in the Outbox, after review', () {
    Future<PendingTake> aScene(
      TakeUploadQueue queue,
      String name, {
      String sessionId = 'sessao-1',
    }) => queue.enqueue(
      aTake(name),
      sessionId: sessionId,
      kind: 'cena',
      scope: 'cena',
    );

    test(
      'a take confirmed by another run of the Outbox is still named after its '
      'rehearsal',
      () async {
        final room = FakeRoom()..reachable = false;
        final recorder = FakeRecorder();
        final take = File('${recorder.home.path}/cena_1.wav')
          ..writeAsBytesSync(aWavTake());
        await queueOn(
          room,
        ).enqueue(take, sessionId: 'sessao-1', kind: 'cena', scope: 'cena');
        room.reachable = true;
        final again = TakeUploadQueue(
          room: room,
          home: () async => home,
          recordings: () => recorder,
        );

        await aTapOnEveryRow(again);

        expect(
          await recorder.heldAs(
            'cena-${room.sceneRehearsals.single.rehearsalId}',
          ),
          isNotNull,
          reason: 'o take da equipe leva o nome do ensaio em qualquer execução',
        );
      },
    );

    Future<(TakeUploadQueue, PendingTake)> aSceneOf(
      FakeRoom room,
      FakeRecorder recorder,
    ) async {
      final queue = TakeUploadQueue(
        room: room,
        home: () async => home,
        recordings: () => recorder,
      );
      final take = File('${recorder.home.path}/cena_1.wav')
        ..writeAsBytesSync(aWavTake());
      final row = await queue.enqueue(
        take,
        sessionId: 'sessao-1',
        kind: 'cena',
        scope: 'cena',
      );
      return (queue, row);
    }

    test('the take is named before its row leaves the manifest', () async {
      final room = FakeRoom();
      final (queue, row) = await aSceneOf(room, _ARenameThatNeverEnds());

      unawaited(queue.flush());
      await waitFor('a sala confirmar', () => room.scenesKept.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final afterAKill = TakeUploadQueue(
        room: room,
        home: () async => home,
        recordings: FakeRecorder.new,
      );
      expect(
        [for (final entry in await afterAKill.entries()) entry.id],
        [row.id],
        reason:
            'morto antes de renomear, o tablet ainda tem a linha, e o take é '
            'renomeado quando ela sobe de novo',
      );
    });

    test('a rename that fails in any way never sends the take again', () async {
      final room = FakeRoom();
      final (queue, _) = await aSceneOf(room, _ADiskThatThrowsOnTheRename());

      await queue.flush();
      await queue.flush();

      expect(room.scenesKept, hasLength(1));
      expect(await queue.entries(), isEmpty);
    });

    test(
      'a take refused for good is never made due by the team\'s keep',
      () async {
        final room = FakeRoom()
          ..sceneAnswersFirst.add(const Refused('BAD_REQUEST'));
        final queue = queueOn(room);
        await aScene(queue, 'cena-1');
        await queue.flush();
        final second = await aScene(queue, 'cena-2');

        await queue.keepTheScene(second.id);

        expect(room.sceneTakesSent, [
          File('${home.path}/cena-2.m4a').readAsBytesSync(),
        ]);
      },
    );

    test(
      'another session\'s scene takes are untouched by the team\'s keep',
      () async {
        final room = FakeRoom()
          ..failSceneWith = const NetworkFailed('sem rede');
        final queue = queueOn(room);
        await aScene(queue, 'outra', sessionId: 'sessao-2');
        await queue.flush();
        clock = clock.add(const Duration(seconds: 1));
        room.failSceneWith = null;
        final mine = await aScene(queue, 'minha');

        await queue.keepTheScene(mine.id);

        expect(room.sceneTakesSent, [
          File('${home.path}/minha.m4a').readAsBytesSync(),
        ]);
      },
    );
  });

  test('a take a row can show goes up before every take no row can show, '
      'each part still in its order', () async {
    final room = FakeRoom();
    final queue = queueOn(room)
      ..offerTheTapThrough((row) => row.scope != 'parte-2');
    for (final (name, scope, pass) in [
      ('parte-2-a', 'parte-2', 1),
      ('parte-2-b', 'parte-2', 2),
      ('inteira', 'passagem-inteira', 3),
    ]) {
      await queue.enqueue(
        aTake(name),
        sessionId: 'sessao-1',
        kind: 'ensaio',
        scope: scope,
        passNumber: pass,
      );
    }

    await queue.flush();

    expect(room.takesAsked, [
      'ensaio/passagem-inteira',
      'ensaio/parte-2',
      'ensaio/parte-2',
    ]);
    expect(room.takePasses, [3, 1, 2]);
  });

  group('a session\'s scene takes go up before its parts', () {
    Future<PendingTake> aSceneTake(TakeUploadQueue queue, String scene) =>
        queue.enqueue(
          File('${home.path}/$scene.m4a')..writeAsStringSync(scene),
          sessionId: 'sessao-1',
          kind: 'cena',
          scope: 'cena',
          scene: scene,
        );

    Future<PendingTake> aPartTake(
      TakeUploadQueue queue,
      String name,
      String scope, {
      int? pass,
    }) => queue.enqueue(
      aTake(name),
      sessionId: 'sessao-1',
      kind: 'ensaio',
      scope: scope,
      passNumber: pass,
    );

    List<String> uploads(FakeRoom room) => [
      for (final call in room.calls)
        if (call == 'keepSceneRehearsal' || call == 'sendTake') call,
    ];

    Future<void> spentWhileTheRoomIsOut(
      FakeRoom room,
      TakeUploadQueue queue,
    ) async {
      room.reachable = false;
      for (var pass = 0; pass < 4; pass++) {
        clock = clock.add(const Duration(minutes: 20));
        await queue.flush();
      }
      room
        ..reachable = true
        ..calls.clear();
    }

    test('a scene take recorded after a part goes up before it in the same '
        'pass', () async {
      final room = FakeRoom();
      final queue = queueOn(room);
      await aPartTake(queue, 'parte-1', 'parte-1');
      await aSceneTake(queue, 'cena-1');

      await queue.flush();

      expect(uploads(room), ['keepSceneRehearsal', 'sendTake']);
    });

    test('a session\'s scene takes go up in the order recorded, all before '
        'its parts, and each part keeps its own order', () async {
      final room = FakeRoom();
      final queue = queueOn(room);
      await aPartTake(queue, 'parte-1-a', 'parte-1', pass: 1);
      await aSceneTake(queue, 'cena-1');
      await aPartTake(queue, 'parte-2', 'parte-2', pass: 1);
      await aPartTake(queue, 'parte-1-b', 'parte-1', pass: 2);
      await aSceneTake(queue, 'cena-2');

      await queue.flush();

      expect(uploads(room), [
        'keepSceneRehearsal',
        'keepSceneRehearsal',
        'sendTake',
        'sendTake',
        'sendTake',
      ]);
      expect(room.sceneLabels, ['cena-1', 'cena-2']);
      expect(room.takesAsked, [
        'ensaio/parte-1',
        'ensaio/parte-2',
        'ensaio/parte-1',
      ]);
      expect(room.takePasses, [1, 1, 2]);
    });

    test('a part no row can show still goes up after the scene takes and '
        'after the parts a row can show', () async {
      final room = FakeRoom();
      final queue = queueOn(room)
        ..offerTheTapThrough((row) => row.scope != 'parte-2');
      await aPartTake(queue, 'parte-2', 'parte-2');
      await aPartTake(queue, 'parte-1', 'parte-1');
      await aSceneTake(queue, 'cena-1');

      await queue.flush();

      expect(uploads(room), ['keepSceneRehearsal', 'sendTake', 'sendTake']);
      expect(room.takesAsked, ['ensaio/parte-1', 'ensaio/parte-2']);
    });

    test('a scene take never waits behind a part held for a tap, and the '
        'held part does not go up', () async {
      final room = FakeRoom();
      final queue = queueOn(room);
      await aPartTake(queue, 'parte-1-a', 'parte-1');
      await spentWhileTheRoomIsOut(room, queue);
      await aPartTake(queue, 'parte-1-b', 'parte-1');
      await aSceneTake(queue, 'cena-1');

      await queue.flush();

      expect(uploads(room), ['keepSceneRehearsal']);
    });

    test('a part never waits behind a scene take held for a tap', () async {
      final room = FakeRoom();
      final queue = queueOn(room);
      await aSceneTake(queue, 'cena-1');
      await spentWhileTheRoomIsOut(room, queue);
      await aSceneTake(queue, 'cena-2');
      await aPartTake(queue, 'parte-1', 'parte-1');

      await queue.flush();

      expect(uploads(room), ['sendTake']);
    });

    test('a join row goes up after the session\'s scene takes', () async {
      final room = FakeRoom();
      final queue = queueOn(room);
      final bytes = aWavTake();
      await queue.enqueueTheJoin(
        File('${home.path}/parte-2-junta-ensaio-2.wav')
          ..writeAsBytesSync(bytes),
        sessionId: 'sessao-1',
        number: 2,
        passNumber: 1,
        origin: 'ensaio-2',
        fingerprint: crypto.sha256.convert(bytes).toString(),
      );
      await aSceneTake(queue, 'cena-1');

      await queue.flush();

      expect(uploads(room), ['keepSceneRehearsal', 'sendTake']);
    });
  });

  test('a spent take no row can show goes up once its lost audio is found '
      'again', () async {
    final room = FakeRoom()..unreachableTake = 'ensaio/parte-2';
    final queue = queueOn(room)
      ..offerTheTapThrough((row) => row.scope != 'parte-2');
    final entry = await queue.enqueue(
      aTake('parte-2'),
      sessionId: 'sessao-1',
      kind: 'ensaio',
      scope: 'parte-2',
    );
    await aTapOnEveryRow(queue);
    final bytes = File(entry.path).readAsBytesSync();
    File(entry.path).deleteSync();
    await aTapOnEveryRow(queue);
    expect((await queue.pending()).single.lost, isTrue);
    File(entry.path).writeAsBytesSync(bytes);
    room.unreachableTake = null;

    await aTapOnEveryRow(queue);

    expect(room.takesKept, ['ensaio/parte-2']);
  });

  group('a join row', () {
    File aRehearsal(List<int> bytes) =>
        File('${home.path}/parte-2-junta-ensaio-2.wav')
          ..writeAsBytesSync(bytes);

    String fingerprintOf(List<int> bytes) =>
        crypto.sha256.convert(bytes).toString();

    test('whose copy is not the rehearsal\'s bytes writes nothing and leaves '
        'no copy', () async {
      final queue = queueOn(FakeRoom());

      final row = await queue.enqueueTheJoin(
        aRehearsal(aWavTake()),
        sessionId: 'sessao-1',
        number: 2,
        passNumber: 1,
        origin: 'ensaio-2',
        fingerprint: fingerprintOf([1, 2, 3]),
      );

      expect(row, isNull);
      expect(await queue.entries(), isEmpty);
      expect(
        Directory(
          '${home.path}/guardadas',
        ).listSync().where((file) => !file.path.endsWith('fila.json')),
        isEmpty,
      );
    });

    test('keeps its origin and reopening across a manifest read', () async {
      final room = FakeRoom()..reachable = false;
      aQueueWrittenByTheOlderApp('velha.m4a');
      final older = (await queueOn(room).entries()).single;
      expect(older.origin, isNull);
      expect(older.reopensTheApprovedDraft, isFalse);

      final row = await queueOn(room).enqueueTheJoin(
        aRehearsal(aWavTake()),
        sessionId: 'sessao-1',
        number: 2,
        passNumber: 1,
        origin: 'ensaio-2',
        reopensTheApprovedDraft: true,
      );
      await queueOn(room).flush();
      await queueOn(room).dueAgain(row!.id);

      final read = (await queueOn(room).entries()).last;
      expect(read.tries, 0, reason: 'a linha não passou pelo dueNow');
      expect(read.origin, 'ensaio-2');
      expect(read.reopensTheApprovedDraft, isTrue);
    });

    test('goes up with its origin, the reopening and the rehearsal\'s '
        'fingerprint', () async {
      final room = FakeRoom();
      final queue = queueOn(room);
      final bytes = aWavTake();
      await queue.enqueueTheJoin(
        aRehearsal(bytes),
        sessionId: 'sessao-1',
        number: 2,
        passNumber: 3,
        origin: 'ensaio-2',
        fingerprint: fingerprintOf(bytes),
        reopensTheApprovedDraft: true,
      );

      await queue.flush();

      final sent = room.takesReceivedWhole.single;
      expect(sent.kind, 'ensaio');
      expect(sent.scope, 'parte-2');
      expect(sent.chunkIndex, 2);
      expect(room.takePasses.single, 3);
      expect(sent.origin, 'ensaio-2');
      expect(sent.reopens, isTrue);
      expect(sent.sha256, fingerprintOf(bytes));
      expect(sent.bytes, bytes);
    });

    test('is never spent by network failures: it goes up on the next pass '
        'once the network returns', () async {
      final room = FakeRoom()..unreachableTake = 'ensaio/parte-2';
      final queue = queueOn(room);
      await queue.enqueueTheJoin(
        aRehearsal(aWavTake()),
        sessionId: 'sessao-1',
        number: 2,
        passNumber: 1,
        origin: 'ensaio-2',
      );
      for (var pass = 0; pass < takeUploadAttempts + 1; pass++) {
        await aTapOnEveryRow(queue);
      }
      room.unreachableTake = null;

      await aTapOnEveryRow(queue);

      expect(room.takesKept, ['ensaio/parte-2']);
    });

    test('withdrawn after its pass found it and before it is sent stays '
        'unsent, and the room never receives it', () async {
      final room = FakeRoom();
      final queue = queueOn(room);
      final row = (await queue.enqueueTheJoin(
        aRehearsal(aWavTake()),
        sessionId: 'sessao-1',
        number: 2,
        passNumber: 1,
        origin: 'ensaio-2',
      ))!;
      final copy = (await queue.pending()).single.path;
      final outside = Zone.current;

      await IOOverrides.runZoned(
        queue.flush,
        createFile: (path) {
          final real = outside.run(() => File(path));
          if (path != copy) return real;
          return _AWatchedCopyThatIgnoresDelete(
            real,
            whenChecked: () {
              if (!queue.inTheAir(row.id)) unawaited(queue.withdraw(row));
            },
          );
        },
      );

      expect(room.takesReceivedWhole, isEmpty);
      expect(await queue.pending(), isEmpty);
    });

    test('withdrawn even in the air before its pass claims it is taken off '
        'and never sent', () async {
      final room = FakeRoom();
      final queue = queueOn(room);
      final row = (await queue.enqueueTheJoin(
        aRehearsal(aWavTake()),
        sessionId: 'sessao-1',
        number: 2,
        passNumber: 1,
        origin: 'ensaio-2',
      ))!;
      final copy = (await queue.pending()).single.path;
      final outside = Zone.current;
      late Future<bool> withdrawn;

      await IOOverrides.runZoned(
        queue.flush,
        createFile: (path) {
          final real = outside.run(() => File(path));
          if (path != copy) return real;
          return _AWatchedCopyThatIgnoresDelete(
            real,
            whenChecked: () => withdrawn = queue.withdrawEvenInTheAir(row),
          );
        },
      );

      expect(await withdrawn, isFalse);
      expect(room.takesReceivedWhole, isEmpty);
      expect(await queue.pending(), isEmpty);
    });

    test('withdrawn even in the air once its pass claimed it leaves the Outbox '
        'at once, keeps its copy until its send lands, and that send still '
        'lands', () async {
      final room = FakeRoom()..holdNextTake('parte-2');
      final queue = queueOn(room);
      final row = (await queue.enqueueTheJoin(
        aRehearsal(aWavTake()),
        sessionId: 'sessao-1',
        number: 2,
        passNumber: 1,
        origin: 'ensaio-2',
      ))!;
      final copy = (await queue.pending()).single.path;
      final outside = Zone.current;
      late Future<bool> withdrawn;
      var watched = false;

      final flushed = IOOverrides.runZoned(
        queue.flush,
        createFile: (path) {
          final real = outside.run(() => File(path));
          if (path != copy || watched) return real;
          watched = true;
          return _AWatchedCopyThatIgnoresDelete(
            real,
            whenMeasured: () => Future.microtask(
              () => Future.microtask(
                () => withdrawn = queue.withdrawEvenInTheAir(row),
              ),
            ),
          );
        },
      );
      await room.untilTakeHeld();

      expect(await withdrawn, isTrue);
      expect(await queue.pending(), isEmpty);
      expect(File(copy).existsSync(), isTrue);

      room.finishHeldTake();
      await flushed;

      expect(room.takesKept, ['ensaio/parte-2']);
      expect(File(copy).existsSync(), isFalse);
    });

    test('given way to a hand take while its failing request is in the air, '
        'it never goes up again', () async {
      final room = FakeRoom()
        ..holdNextTake('parte-2')
        ..unreachableTake = 'ensaio/parte-2';
      final queue = queueOn(room);
      final row = (await queue.enqueueTheJoin(
        aRehearsal(aWavTake()),
        sessionId: 'sessao-1',
        number: 2,
        passNumber: 1,
        origin: 'ensaio-2',
      ))!;
      final flushed = queue.flush();
      await room.untilTakeHeld();

      await queue.withdrawTheJoinsOf('sessao-1', 'parte-2');
      room.finishHeldTake();
      await flushed;
      room.unreachableTake = null;
      await queue.flush();

      expect(
        room.takesReceivedWhole,
        isEmpty,
        reason:
            'a junta no ar escapava da retirada e subia depois por cima da '
            'gravação à mão',
      );
      expect(await queue.pending(), isEmpty);
      expect(File(row.path).existsSync(), isFalse);
    });

    test('given way to a hand take while in the air, a room that finds the '
        'part moved still takes its copy away', () async {
      final room = FakeRoom()
        ..holdNextTake('parte-2')
        ..refuseTake = 'ensaio/parte-2'
        ..refuseTakeCode = RefusalCode.takeMoved;
      final queue = queueOn(room);
      final row = (await queue.enqueueTheJoin(
        aRehearsal(aWavTake()),
        sessionId: 'sessao-1',
        number: 2,
        passNumber: 1,
        origin: 'ensaio-2',
      ))!;
      final flushed = queue.flush();
      await room.untilTakeHeld();

      await queue.withdrawTheJoinsOf('sessao-1', 'parte-2');
      room.finishHeldTake();
      await flushed;

      expect(await queue.pending(), isEmpty);
      expect(
        File(row.path).existsSync(),
        isFalse,
        reason: 'a cópia da junta retirada no ar ficava na pasta sem linha',
      );
    });

    test('given way to a hand take while in the air, a refusal leaves no row '
        'behind to stand for the part', () async {
      final room = FakeRoom()
        ..holdNextTake('parte-2')
        ..refuseTake = 'ensaio/parte-2'
        ..refuseTakeCode = 'HTTP_500';
      final queue = queueOn(room);
      final row = (await queue.enqueueTheJoin(
        aRehearsal(aWavTake()),
        sessionId: 'sessao-1',
        number: 2,
        passNumber: 1,
        origin: 'ensaio-2',
      ))!;
      final flushed = queue.flush();
      await room.untilTakeHeld();

      await queue.withdrawTheJoinsOf('sessao-1', 'parte-2');
      room.finishHeldTake();
      await flushed;

      expect(
        await queue.pending(),
        isEmpty,
        reason:
            'a junta recusada ficava na Outbox e a sua recusa aparecia na '
            'cena gravada à mão',
      );
      expect(File(row.path).existsSync(), isFalse);
    });

    test('withdrawn while its pass is under way is given up, and the newer '
        'take of its part goes up in the same pass', () async {
      final room = FakeRoom();
      final queue = queueOn(room);
      final join = (await queue.enqueueTheJoin(
        aRehearsal(aWavTake()),
        sessionId: 'sessao-1',
        number: 2,
        passNumber: 1,
        origin: 'ensaio-2',
      ))!;
      await queue.enqueue(
        aTake('a-mao'),
        sessionId: 'sessao-1',
        kind: 'ensaio',
        scope: 'parte-2',
        passNumber: 2,
      );
      final copy = (await queue.pending()).first.path;
      final outside = Zone.current;

      await IOOverrides.runZoned(
        queue.flush,
        createFile: (path) {
          final real = outside.run(() => File(path));
          if (path != copy) return real;
          return _AWatchedCopyThatIgnoresDelete(
            real,
            whenChecked: () {
              real.deleteSync();
              unawaited(queue.withdraw(join));
            },
          );
        },
      );

      expect(room.takePasses, [2]);
      expect(await queue.pending(), isEmpty);
    });

    test('sends the moment of each try as its Recording time', () async {
      final room = FakeRoom()..unreachableTake = 'ensaio/parte-2';
      final queue = queueOn(room);
      final rehearsal = aRehearsal(aWavTake())
        ..setLastModifiedSync(DateTime(2026, 8, 12, 6));
      clock = DateTime(2026, 8, 12, 9);
      await queue.enqueueTheJoin(
        rehearsal,
        sessionId: 'sessao-1',
        number: 2,
        passNumber: 1,
        origin: 'ensaio-2',
      );
      await aTapOnEveryRow(queue);
      room.unreachableTake = null;
      clock = DateTime(2026, 8, 12, 9, 4);

      await aTapOnEveryRow(queue);

      expect(room.takesReceivedWhole.single.recordedAt, clock);
    });

    test('names the part\'s take it replaces on every try, across a manifest '
        'read', () async {
      final room = FakeRoom()
        ..takes.add(
          const TakeView(
            takeId: 'gravacao-a-mao',
            kind: 'ensaio',
            scope: 'parte-2',
            ordinal: 2,
          ),
        )
        ..unreachableTake = 'ensaio/parte-2';
      await queueOn(room).enqueueTheJoin(
        aRehearsal(aWavTake()),
        sessionId: 'sessao-1',
        number: 2,
        passNumber: 2,
        origin: 'ensaio-2',
        overTake: 'gravacao-a-mao',
      );
      await aTapOnEveryRow(queueOn(room));
      room.unreachableTake = null;

      await aTapOnEveryRow(queueOn(room));

      expect(room.takesReceivedWhole.single.overTake, 'gravacao-a-mao');
    });

    test('the room finds moved leaves the Outbox with its copy, is never '
        'counted unsent and never sent again', () async {
      final room = FakeRoom()
        ..takes.add(
          const TakeView(
            takeId: 'gravacao-a-mao',
            kind: 'ensaio',
            scope: 'parte-2',
            ordinal: 2,
          ),
        );
      final queue = queueOn(room);
      final row = await queue.enqueueTheJoin(
        aRehearsal(aWavTake()),
        sessionId: 'sessao-1',
        number: 2,
        passNumber: 2,
        origin: 'ensaio-2',
        overTake: 'gravacao-de-antes',
      );

      await queue.flush();
      await queue.dueAgain(row!.id);
      await queue.flush();

      expect(await queue.pending(), isEmpty);
      expect(await queue.unsentOf('ensaio', sessionId: 'sessao-1'), 0);
      expect(File(row.path).existsSync(), isFalse);
      expect(room.calls.where((call) => call == 'sendTake'), hasLength(1));
    });
  });

  group('a take stays on the tablet until the room confirms it, and only its '
      'tap sends it', () {
    int sends(FakeRoom room) =>
        room.calls.where((call) => call == 'sendTake').length;

    Future<PendingTake> keepAPart(
      TakeUploadQueue queue,
      int part, {
      String? session = 'sessao-1',
      String? passage = 'Ruth/P01/pt',
    }) => queue.enqueue(
      aTake('parte-$part'),
      sessionId: session,
      passage: passage,
      kind: 'ensaio',
      scope: 'parte-$part',
      passNumber: 1,
      chunkIndex: part,
    );

    test('a take kept in an earlier life is sent by no flush until its own '
        'tap', () async {
      final room = FakeRoom();
      final row = await keepAPart(queueOn(room), 2);
      final relaunched = queueOn(room);

      await relaunched.flush();

      expect(sends(room), 0);
      expect(File(row.path).existsSync(), isTrue);

      await relaunched.dueAgain(row.id);
      await relaunched.flush();

      expect(room.takesKept, ['ensaio/parte-2']);
      expect(await relaunched.entries(), isEmpty);
    });

    test('a tap on one part sends nothing of another part waiting', () async {
      final room = FakeRoom();
      final before = queueOn(room);
      final two = await keepAPart(before, 2);
      final three = await keepAPart(before, 3);
      final relaunched = queueOn(room);

      await relaunched.dueAgain(two.id);
      await relaunched.flush();

      expect(room.takesKept, ['ensaio/parte-2']);
      expect(
        [for (final row in await relaunched.entries()) row.id],
        [three.id],
      );
    });

    test('a take the room turned away is sent by no later flush until its own '
        'tap', () async {
      final room = FakeRoom()
        ..takeAnswersFirst.add(const Refused(RefusalCode.unauthorized));
      final queue = queueOn(room);
      final row = await keepAPart(queue, 2);
      await queue.flush();

      await queue.flush();

      expect(sends(room), 1);
      expect(File(row.path).existsSync(), isTrue);
    });

    test('a take the server already holds leaves the tablet and its row reads '
        'saved', () async {
      final room = FakeRoom();
      room.heldByFingerprint[crypto.sha256
              .convert(utf8.encode('a equipe contou a passagem'))
              .toString()] =
          'ja-guardada';
      room.takes.add(
        const TakeView(takeId: 'ja-guardada', kind: 'ensaio', scope: 'parte-2'),
      );
      final queue = queueOn(room);
      final row = await keepAPart(queue, 2);

      await queue.flush();

      expect(await queue.entries(), isEmpty);
      expect(File(row.path).existsSync(), isFalse);
      final tally = await queue.tally(
        sessionId: 'sessao-1',
        passage: 'Ruth/P01/pt',
      );
      expect(tally.parts[row.id], PartFact.sent);
      expect(await queue.takeIdOf(row.id), 'ja-guardada');
    });

    test('a take the server refuses as stale leaves the tablet', () async {
      final room = FakeRoom()
        ..refuseTake = 'ensaio/parte-2'
        ..refuseTakeCode = RefusalCode.takeMoved;
      final queue = queueOn(room);
      final row = await keepAPart(queue, 2);

      await queue.flush();

      expect(await queue.entries(), isEmpty);
      expect(File(row.path).existsSync(), isFalse);
    });

    test('a take recorded with no open session is on disk and listed in the '
        'Outbox', () async {
      final room = FakeRoom();
      final queue = queueOn(room);
      final row = await keepAPart(queue, 2, session: null);

      await queue.flush();

      expect(sends(room), 0);
      expect(File(row.path).existsSync(), isTrue);
      final tally = await queue.tally(
        sessionId: 'sessao-2',
        passage: 'Ruth/P01/pt',
      );
      expect(
        [for (final listed in tally.unsentParts['parte-2']!) listed.id],
        [row.id],
      );
    });

    test('a take with no session is listed by no other passage', () async {
      final queue = queueOn(FakeRoom());
      await keepAPart(queue, 2, session: null);

      final elsewhere = await queue.tally(
        sessionId: 'sessao-3',
        passage: 'Ruth/P02/pt',
      );

      expect(elsewhere.unsentParts, isEmpty);
    });

    test('a take whose session is gone is sent by its tap into the session '
        'the tap names', () async {
      final room = FakeRoom()..forgetTheSession('sessao-1');
      final queue = queueOn(room);
      final row = await keepAPart(queue, 2);
      await queue.flush();

      await queue.dueAgain(row.id, intoTheSession: 'sessao-2');
      await queue.flush();

      expect(room.takeSessions, ['sessao-1', 'sessao-2']);
      expect(room.takesKept, ['ensaio/parte-2']);
      expect(await queue.entries(), isEmpty);
      expect(File(row.path).existsSync(), isFalse);
    });

    test('an enqueue sends nothing by itself', () async {
      final room = FakeRoom();
      final queue = queueOn(room);

      final row = await keepAPart(queue, 2);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(sends(room), 0);
      expect(File(row.path).existsSync(), isTrue);
    });

    test('a scene take whose session is gone is offered to the passage\'s next '
        'session, and its keep sends it into that session', () async {
      final room = FakeRoom()..forgetTheSession('sessao-1');
      final queue = queueOn(room);
      final row = await queue.enqueue(
        aTake('cena'),
        sessionId: 'sessao-1',
        passage: 'Ruth/P01/pt',
        kind: 'cena',
        scope: 'cena',
      );
      await queue.flush();

      final offered = await queue.sceneWaitingIn(
        'sessao-2',
        passage: 'Ruth/P01/pt',
      );
      final kept = await queue.keepTheScene(row.id, intoTheSession: 'sessao-2');

      expect(offered?.id, row.id);
      expect(kept, isNotNull);
      expect(room.scenesKept, ['sessao-2']);
      expect(await queue.entries(), isEmpty);
    });

    test('a frase whose session is gone is held for the passage\'s next '
        'session', () async {
      final queue = queueOn(FakeRoom());
      final row = await queue.enqueue(
        aTake('frase'),
        sessionId: 'sessao-1',
        passage: 'Ruth/P01/pt',
        kind: 'frase',
        scope: '3',
      );

      await queue.letGoOfTheSession('sessao-1');

      final held = await queue.sentenceHeldIn(
        'sessao-2',
        passage: 'Ruth/P01/pt',
      );
      expect(held?.id, row.id);
      expect(File(row.path).existsSync(), isTrue);
    });
  });

  group('a flush over an Outbox folder that is gone', () {
    test('sends nothing and throws nothing', () async {
      final room = FakeRoom();
      final queue = queueOn(room);

      final sent = await IOOverrides.runZoned(
        queue.flush,
        createDirectory: (path) => path.endsWith('${p.separator}guardadas')
            ? _GoneUnderneath(path)
            : _realDirectory(path),
      );

      expect(sent, 0);
    });
  });
}

final class _Plain extends IOOverrides {}

File _realFile(String path) =>
    IOOverrides.runWithIOOverrides(() => File(path), _Plain());

Directory _realDirectory(String path) =>
    IOOverrides.runWithIOOverrides(() => Directory(path), _Plain());

class _GoneUnderneath implements Directory {
  final Directory _real;

  _GoneUnderneath(String path) : _real = _realDirectory(path);

  @override
  String get path => _real.path;

  @override
  Future<Directory> create({bool recursive = false}) async =>
      throw PathNotFoundException(
        _real.path,
        const OSError('No such file or directory', 2),
        'Creation failed',
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _GoneAfterItWasFound implements File {
  final File _real;

  _GoneAfterItWasFound(String path) : _real = _realFile(path);

  @override
  String get path => _real.path;

  @override
  Future<bool> exists() async => true;

  @override
  bool existsSync() => _real.existsSync();

  @override
  Future<int> length() async =>
      throw FileSystemException('a cópia sumiu', _real.path);

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      _real.delete(recursive: recursive);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ARenameThatNeverEnds extends FakeRecorder {
  @override
  Future<String> keepAs(String path, String fileName) =>
      Completer<String>().future;
}

class _ADiskThatThrowsOnTheRename extends FakeRecorder {
  @override
  Future<String?> heldAs(String fileName) async =>
      throw StateError('o contêiner já foi descartado');
}

class _AWatchedCopyThatIgnoresDelete implements File {
  final File _real;
  final void Function() whenChecked;
  final void Function() whenMeasured;

  _AWatchedCopyThatIgnoresDelete(
    this._real, {
    this.whenChecked = _nothing,
    this.whenMeasured = _nothing,
  });

  static void _nothing() {}

  @override
  String get path => _real.path;

  @override
  Future<bool> exists() {
    whenChecked();
    return _real.exists();
  }

  @override
  bool existsSync() => _real.existsSync();

  @override
  Future<int> length() async {
    final length = await _real.length();
    whenMeasured();
    return length;
  }

  @override
  int lengthSync() => _real.lengthSync();

  @override
  Uint8List readAsBytesSync() => _real.readAsBytesSync();

  @override
  Future<Uint8List> readAsBytes() => _real.readAsBytes();

  @override
  Stream<List<int>> openRead([int? start, int? end]) =>
      _real.openRead(start, end);

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) async => this;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ATakeWhoseCopyIsHeld implements File {
  final File _real;
  final copied = Completer<void>();
  final release = Completer<void>();

  _ATakeWhoseCopyIsHeld(this._real);

  @override
  String get path => _real.path;

  @override
  Future<DateTime> lastModified() => _real.lastModified();

  @override
  Future<bool> exists() => _real.exists();

  @override
  Future<File> copy(String newPath) async {
    final made = await _real.copy(newPath);
    copied.complete();
    await release.future;
    return made;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ACopyTheDiskWillNotDelete implements File {
  final File _real;
  final void Function() whenRefused;

  _ACopyTheDiskWillNotDelete(this._real, {this.whenRefused = _nothing});

  static void _nothing() {}

  @override
  String get path => _real.path;

  @override
  Future<bool> exists() => _real.exists();

  @override
  bool existsSync() => _real.existsSync();

  @override
  Future<int> length() => _real.length();

  @override
  int lengthSync() => _real.lengthSync();

  @override
  Uint8List readAsBytesSync() => _real.readAsBytesSync();

  @override
  Future<Uint8List> readAsBytes() => _real.readAsBytes();

  @override
  Stream<List<int>> openRead([int? start, int? end]) =>
      _real.openRead(start, end);

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) {
    whenRefused();
    return Future.error(const FileSystemException('o disco recusou'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

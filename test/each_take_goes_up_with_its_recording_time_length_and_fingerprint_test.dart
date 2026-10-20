import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/take_upload_queue.dart';

import 'a_wav_take.dart';
import 'fakes.dart';

void main() {
  late Directory home;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) answer;
  var clock = DateTime(2026, 10, 20, 13, 40);
  final stopped = DateTime(2026, 10, 20, 10, 2);

  setUpAll(() {
    dotenv.testLoad(fileInput: 'BACKEND_URL=http://sala.local');
  });

  setUp(() {
    home = Directory.systemTemp.createTempSync('fila-tempo-tamanho-impressao');
    requests = [];
    clock = DateTime(2026, 10, 20, 13, 40);
    answer = (request) async => request.url.path.endsWith('/takes')
        ? http.Response(jsonEncode({'take_id': 'gravacao-1'}), 200)
        : http.Response(jsonEncode(_sceneRehearsal), 200);
  });
  tearDown(() => home.deleteSync(recursive: true));

  RoomRepository roomOnTheWire() {
    final room = RoomRepository(
      client: MockClient((request) async {
        requests.add(request);
        return answer(request);
      }),
      deviceId: () async => 'aparelho-1',
    );
    addTearDown(room.dispose);
    return room;
  }

  TakeUploadQueue queueAt(DateTime Function() now) => TakeUploadQueue(
    room: roomOnTheWire(),
    home: () async => home,
    recordings: FakeRecorder.new,
    backoff: const [Duration(seconds: 5)],
    now: now,
  );

  File recorded(
    String name,
    List<int> bytes, {
    required String extension,
    DateTime? at,
  }) {
    final file = File('${home.path}/$name.$extension')..writeAsBytesSync(bytes);
    file.setLastModifiedSync(at ?? stopped);
    return file;
  }

  Future<PendingTake> keep(
    TakeUploadQueue queue,
    File file, {
    String kind = 'ensaio',
    String scope = 'inteira',
  }) => queue.enqueue(file, sessionId: 'sessao-1', kind: kind, scope: scope);

  String sha256Of(List<int> bytes) => sha256.convert(bytes).toString();

  Uint8List wavOf(Duration length) => aSpokenWav(length: length);

  Uint8List wavWhoseDataNeverGotItsLength() {
    final wav = aWavTake();
    ByteData.sublistView(wav).setUint32(40, 0xFFFFFFFF, Endian.little);
    return wav;
  }

  group('a take goes up with when it was recorded, how long it is and its '
      'fingerprint', () {
    test('a part recorded at 10:02 and sent when the Outbox drains at 13:40 '
        'goes up with 10:02, its length and its fingerprint', () async {
      final bytes = wavOf(const Duration(seconds: 3));
      answer = (_) async => throw const SocketException('sem rede');
      clock = DateTime(2026, 10, 20, 10, 4);
      final first = queueAt(() => clock);
      await keep(first, recorded('parte', bytes, extension: 'wav'));
      answer = (request) async =>
          http.Response(jsonEncode({'take_id': 'gravacao-1'}), 200);
      clock = DateTime(2026, 10, 20, 13, 40);

      await queueAt(() => clock).flush();

      final sent = requests.last;
      expect(sent.url.path, endsWith('/sessions/sessao-1/takes'));
      expect(
        _fields(sent),
        containsPair('recorded_at', stopped.toUtc().toIso8601String()),
      );
      expect(_fields(sent), containsPair('duration_ms', '3000'));
      expect(_fields(sent), containsPair('sha256', sha256Of(bytes)));
      expect(sha256Of(_fileOf(sent)), sha256Of(bytes));
    });

    group('a failed send retried goes up with the same three values', () {
      for (final (name, failure)
          in <(String, Future<http.Response> Function())>[
            ('the room answers 500', () async => http.Response('{}', 500)),
            (
              'the network fails',
              () async => throw const SocketException('sem rede'),
            ),
          ]) {
        test(name, () async {
          final bytes = wavOf(const Duration(seconds: 3));
          final queue = queueAt(() => clock);
          await keep(queue, recorded('parte', bytes, extension: 'wav'));
          answer = (_) => failure();
          await queue.flush();
          answer = (_) async =>
              http.Response(jsonEncode({'take_id': 'gravacao-1'}), 200);
          clock = clock.add(const Duration(minutes: 30));

          await queue.flush();

          expect(requests, hasLength(2));
          expect(_fields(requests.last), _fields(requests.first));
          expect(
            _fields(requests.last),
            containsPair('recorded_at', stopped.toUtc().toIso8601String()),
          );
          expect(_fields(requests.last), containsPair('duration_ms', '3000'));
          expect(
            _fields(requests.last),
            containsPair('sha256', sha256Of(bytes)),
          );
        });
      }
    });

    test('a scene take made due again by a later keep still carries its own '
        'three values', () async {
      final a = wavOf(const Duration(seconds: 2));
      final b = wavOf(const Duration(seconds: 4));
      final stoppedB = DateTime(2026, 10, 20, 10, 6);
      final queue = queueAt(() => clock);
      answer = (_) async => throw const SocketException('sem rede');
      await keep(
        queue,
        recorded('cena-a', a, extension: 'wav'),
        kind: sceneTakeKind,
        scope: sceneTakeKind,
      );
      await queue.flush();
      requests.clear();
      answer = (_) async => http.Response(jsonEncode(_sceneRehearsal), 200);
      final rowB = await keep(
        queue,
        recorded('cena-b', b, extension: 'wav', at: stoppedB),
        kind: sceneTakeKind,
        scope: sceneTakeKind,
      );

      await queue.keepTheScene(rowB.id);

      expect(requests, hasLength(2));
      expect(_fields(requests.first), {
        'recorded_at': stopped.toUtc().toIso8601String(),
        'duration_ms': '2000',
        'sha256': sha256Of(a),
      });
      expect(_fields(requests.last), {
        'recorded_at': stoppedB.toUtc().toIso8601String(),
        'duration_ms': '4000',
        'sha256': sha256Of(b),
      });
    });

    test('a row an older app wrote goes up with none of the three and the '
        "room's answer is accepted", () async {
      final dir = Directory('${home.path}/guardadas')
        ..createSync(recursive: true);
      File('${dir.path}/antiga.m4a').writeAsStringSync('a equipe contou');
      File('${dir.path}/fila.json').writeAsStringSync(
        '[{"id":"antiga","path":"${dir.path}/antiga.m4a",'
        '"session_id":"sessao-1","kind":"ensaio","scope":"inteira",'
        '"pass_number":null,"chunk_index":null,"stored":false,"lost":false,'
        '"attempts":0,"waits":0,"last_try":null}]',
      );
      answer = (_) async => http.Response(
        jsonEncode({
          'take_id': 'gravacao-1',
          'recorded_at': '2026-10-20T13:40:00+00:00',
          'duration_ms': 2500,
        }),
        200,
      );
      final queue = queueAt(() => clock);

      await queue.flush();

      expect(_fields(requests.single), isEmpty);
      expect(await queue.pending(), isEmpty);
      expect(await queue.takeIdOf('antiga'), 'gravacao-1');
    });

    test('a WAV scene take goes up to the scene door with its time, its '
        'length and its fingerprint', () async {
      final bytes = wavOf(const Duration(seconds: 2));
      final queue = queueAt(() => clock);
      final row = await keep(
        queue,
        recorded('cena', bytes, extension: 'wav'),
        kind: sceneTakeKind,
        scope: sceneTakeKind,
      );

      await queue.keepTheScene(row.id);

      expect(requests.single.url.path, endsWith('/scene-rehearsals'));
      expect(_fields(requests.single), {
        'recorded_at': stopped.toUtc().toIso8601String(),
        'duration_ms': '2000',
        'sha256': sha256Of(bytes),
      });
    });

    test('an m4a take goes up with its time and its fingerprint and no '
        'length', () async {
      final scene = utf8.encode('cena em m4a');
      final retro = utf8.encode('traducao em m4a');
      final queue = queueAt(() => clock);
      await keep(
        queue,
        recorded('cena', scene, extension: 'm4a'),
        kind: sceneTakeKind,
        scope: sceneTakeKind,
      );
      await keep(
        queue,
        recorded('retro', retro, extension: 'm4a'),
        kind: 'retro',
        scope: 'parte-1',
      );

      await queue.flush();

      expect(requests, hasLength(2));
      expect(_fields(requests.first), {
        'recorded_at': stopped.toUtc().toIso8601String(),
        'sha256': sha256Of(scene),
      });
      expect(_fields(requests.last), {
        'recorded_at': stopped.toUtc().toIso8601String(),
        'sha256': sha256Of(retro),
      });
    });

    test('a conversation take goes up with none of the three', () async {
      answer = (_) async => http.Response('{}', 200);
      final file = recorded('turno', utf8.encode('fala'), extension: 'm4a');

      await roomOnTheWire().sendTurn('sessao-1', file, turnId: 'turno-1');

      expect(requests.single.url.path, endsWith('/turns'));
      expect(_fields(requests.single), isEmpty);
    });

    test(
      "a part's length is the length of its sound, not of its file",
      () async {
        final bytes = aSpokenWav(
          length: const Duration(milliseconds: 2500),
          chunkBeforeData: true,
        );
        final queue = queueAt(() => clock);
        await keep(queue, recorded('parte', bytes, extension: 'wav'));

        await queue.flush();

        expect(_fields(requests.single), containsPair('duration_ms', '2500'));
      },
    );

    test(
      'a WAV whose header never got its length goes up with no length',
      () async {
        final bytes = wavWhoseDataNeverGotItsLength();
        final queue = queueAt(() => clock);
        await keep(queue, recorded('parte', bytes, extension: 'wav'));

        await queue.flush();

        expect(_fields(requests.single), {
          'recorded_at': stopped.toUtc().toIso8601String(),
          'sha256': sha256Of(bytes),
        });
      },
    );

    test(
      'a WAV whose header says it holds no sound goes up with no length',
      () async {
        final bytes = aWavTake();
        ByteData.sublistView(bytes).setUint32(40, 0, Endian.little);
        final queue = queueAt(() => clock);
        await keep(queue, recorded('parte', bytes, extension: 'wav'));

        await queue.flush();

        expect(_fields(requests.single), {
          'recorded_at': stopped.toUtc().toIso8601String(),
          'sha256': sha256Of(bytes),
        });
      },
    );

    test('a WAV with 12 bits a sample goes up with no length', () async {
      final bytes = aWavTake();
      ByteData.sublistView(bytes).setUint16(34, 12, Endian.little);
      final queue = queueAt(() => clock);
      await keep(queue, recorded('parte', bytes, extension: 'wav'));

      await queue.flush();

      expect(_fields(requests.single), {
        'recorded_at': stopped.toUtc().toIso8601String(),
        'sha256': sha256Of(bytes),
      });
    });

    test('a cut WAV goes up with the length of what exists', () async {
      const padding = 3200;
      final bytes = aWavTake(
        samples: List.filled(16000, 8000),
        chunkBeforeData: true,
        paddingBeforeData: padding,
      );
      ByteData.sublistView(
        bytes,
      ).setUint32(36 + 12 + padding + 4, 2 * 32000, Endian.little);
      final queue = queueAt(() => clock);
      await keep(queue, recorded('parte', bytes, extension: 'wav'));

      await queue.flush();

      expect(_fields(requests.single), containsPair('duration_ms', '1000'));
    });

    test('a row whose recording time is not a time sets the manifest aside, '
        'its history marked lost', () async {
      final dir = Directory('${home.path}/guardadas')
        ..createSync(recursive: true);
      File('${dir.path}/estranha.m4a').writeAsStringSync('a equipe contou');
      File('${dir.path}/fila.json').writeAsStringSync(
        '[{"id":"estranha","path":"${dir.path}/estranha.m4a",'
        '"session_id":"sessao-1","kind":"ensaio","scope":"inteira",'
        '"recorded_at":1760954520}]',
      );
      final queue = queueAt(() => clock);

      await keep(
        queue,
        recorded('nova', utf8.encode('outra'), extension: 'm4a'),
      );

      expect(await queue.lostHistory(), isTrue);
    });

    test('the device clock is not corrected', () async {
      clock = DateTime(2026, 10, 20, 9, 50);
      final queue = queueAt(() => clock);
      await keep(
        queue,
        recorded('parte', wavOf(const Duration(seconds: 1)), extension: 'wav'),
      );

      await queue.flush();

      expect(
        _fields(requests.single),
        containsPair('recorded_at', stopped.toUtc().toIso8601String()),
      );
    });
  });
}

const _sceneRehearsal = {
  'rehearsal_id': 'ensaio-da-cena-1',
  'session_id': 'sessao-1',
  'pericope': 'P01',
  'n': 1,
  'scene': null,
  'scene_said': null,
  'duration_ms': 20000,
  'content_type': 'audio/wav',
  'verified': true,
  'recorded_at': '2026-10-14T09:00:00+00:00',
  'sent_at': null,
  'after_restart': null,
  'frases': <Object?>[],
};

Map<String, String> _fields(http.Request request) {
  final boundary = request.headers['content-type']!.split('boundary=').last;
  final fields = <String, String>{};
  for (final part in latin1.decode(request.bodyBytes).split('--$boundary')) {
    final name = RegExp(r'name="([^"]+)"').firstMatch(part)?.group(1);
    if (name == null || part.contains('filename=')) continue;
    final headEnd = part.indexOf('\r\n\r\n');
    fields[name] = part.substring(headEnd + 4, part.length - 2);
  }
  return {
    for (final name in const ['recorded_at', 'duration_ms', 'sha256'])
      if (fields.containsKey(name)) name: fields[name]!,
  };
}

List<int> _fileOf(http.Request request) {
  final boundary = request.headers['content-type']!.split('boundary=').last;
  final part = latin1
      .decode(request.bodyBytes)
      .split('--$boundary')
      .firstWhere((part) => part.contains('filename='));
  final headEnd = part.indexOf('\r\n\r\n');
  return latin1.encode(part.substring(headEnd + 4, part.length - 2));
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';

void main() {
  setUpAll(() {
    dotenv.testLoad(
      fileInput: 'BACKEND_URL=http://sala.local\nINTERNALIZATION_ROOM_KEY=k',
    );
  });

  RoomRepository answering(int status, [Object? body]) {
    final repository = RoomRepository(
      client: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(body is String ? body : jsonEncode(body ?? const {})),
          status,
        ),
      ),
      deviceId: () async => 'aparelho-1',
    );
    addTearDown(repository.dispose);
    return repository;
  }

  Matcher refusedWith(String code) =>
      isA<Refused>().having((refusal) => refusal.code, 'code', code);

  Future<RoomAnswer<Object?>> replace(RoomRepository room) async =>
      room.replaceSegment(
        'sessao-1',
        'trecho-1',
        await _tempRecording(),
        takeId: 'gravacao-1',
        from: Duration.zero,
        to: const Duration(seconds: 4),
        idempotencyKey: 'chave-1',
      );

  test('a refusal comes back with the code the server named', () async {
    final answer = await answering(422, {
      'detail': 'Internalization room rehearsal take gravacao-1 not found',
      'code': 'UNKNOWN_REFERENCE',
    }).fetchState('sessao-1');

    expect(answer, refusedWith('UNKNOWN_REFERENCE'));
  });

  test(
    'a 404 at a door that asks for the session is the session gone',
    () async {
      expect(await answering(404).fetchState('sessao-1'), isA<SessionGone>());
    },
  );

  test('a 404 on a replace names a stretch, not the session', () async {
    final answer = await replace(answering(404, {'code': 'NOT_FOUND'}));

    expect(answer, isA<Refused>());
  });

  test('a room that answers nothing in time is the network', () {
    fakeAsync((async) {
      var asked = 0;
      final repository = RoomRepository(
        client: MockClient((_) {
          asked++;
          return Completer<http.Response>().future;
        }),
        deviceId: () async => 'aparelho-1',
      );
      RoomAnswer<Object?>? answer;
      repository.fetchState('sessao-1').then((one) => answer = one);

      async.elapse(const Duration(minutes: 1));

      expect(asked, 1);
      expect(answer, isA<NetworkFailed>());
      repository.dispose();
    });
  });

  test('a request that never reaches the room is the network', () async {
    var asked = 0;
    final repository = RoomRepository(
      client: MockClient((_) async {
        asked++;
        throw const SocketException('sem rota');
      }),
      deviceId: () async => 'aparelho-1',
    );
    addTearDown(repository.dispose);

    expect(await repository.fetchState('sessao-1'), isA<NetworkFailed>());
    expect(asked, 1);
  });

  test('a 401 is refused as unauthorized', () async {
    expect(
      await answering(401, {
        'detail': 'Invalid device credential',
        'code': 'UNAUTHORIZED',
      }).fetchState('sessao-1'),
      refusedWith('UNAUTHORIZED'),
    );
    expect(
      await answering(401, {
        'detail': 'no',
        'code': 'BAD_REQUEST',
      }).fetchState('sessao-1'),
      refusedWith('UNAUTHORIZED'),
    );
  });

  test('a 403 is refused as forbidden unless the device was revoked', () async {
    expect(
      await answering(403, {
        'detail': 'no',
        'code': 'ROOM_KEY_INVALID',
      }).fetchState('sessao-1'),
      refusedWith('FORBIDDEN'),
    );
    expect(
      await answering(403, {
        'detail': 'revoked',
        'code': 'DEVICE_REVOKED',
      }).fetchState('sessao-1'),
      refusedWith('DEVICE_REVOKED'),
    );
  });

  test('a 500 or a 429 is the network, not a refusal', () async {
    expect(
      await answering(500, {
        'detail': 'boom',
        'code': 'INTERNAL_ERROR',
      }).fetchState('sessao-1'),
      isA<NetworkFailed>(),
    );
    expect(await answering(429).fetchState('sessao-1'), isA<NetworkFailed>());
  });

  test('a 400 that names no code is still a refusal', () async {
    expect(
      await answering(400, {'detail': 'bad'}).fetchState('sessao-1'),
      isA<Refused>(),
    );
  });

  test('a 200 whose body cannot be read is refused as unreadable', () async {
    expect(
      await answering(200, '<html>').fetchState('sessao-1'),
      refusedWith('UNREADABLE'),
    );
    expect(
      await answering(200, {'nada': 1}).fetchState('sessao-1'),
      refusedWith('UNREADABLE'),
    );
  });

  test(
    'a stretch that no longer counts is told by its code, whatever the words',
    () async {
      final answer = await replace(
        answering(400, {
          'detail': 'Esse trecho já foi trocado por outro',
          'code': 'STRETCH_NO_LONGER_COUNTS',
        }),
      );

      expect(answer, refusedWith('STRETCH_NO_LONGER_COUNTS'));
    },
  );
}

Future<File> _tempRecording() async {
  final file = File(
    '${Directory.systemTemp.path}/sala-cliente-${DateTime.now().microsecondsSinceEpoch}.m4a',
  );
  await file.writeAsBytes([0, 1, 2, 3]);
  addTearDown(() async {
    if (file.existsSync()) await file.delete();
  });
  return file;
}

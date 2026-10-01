import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:internalization_room/features/sala/data/room_client.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';

void main() {
  setUpAll(() {
    dotenv.testLoad(
      fileInput: 'BACKEND_URL=http://sala.local\nINTERNALIZATION_ROOM_KEY=k',
    );
  });

  Future<File> aRecording() async {
    final dir = Directory.systemTemp.createTempSync('sala-chave');
    addTearDown(() => dir.deleteSync(recursive: true));
    return File('${dir.path}/trecho.m4a')..writeAsBytesSync([1, 2, 3]);
  }

  RoomRepository listening(List<http.BaseRequest> heard) {
    final room = RoomRepository(
      client: MockClient((request) async {
        heard.add(request);
        return http.Response('{}', 500);
      }),
      deviceId: () async => 'aparelho-1',
    );
    addTearDown(room.dispose);
    return room;
  }

  test('3 (c): every key the room client mints is its own and fits the '
      'server\'s column', () {
    final keys = [for (var i = 0; i < 50; i++) RoomClient.mintAKey()];

    expect(keys.toSet(), hasLength(50));
    expect(keys.every((key) => key.isNotEmpty && key.length <= 255), isTrue);
  });

  test('3 (c): a stretch told back carries its Idempotency-Key', () async {
    final heard = <http.BaseRequest>[];

    await listening(heard).sendChunk(
      'sessao-1',
      await aRecording(),
      takeId: 'gravacao-1',
      from: Duration.zero,
      to: const Duration(seconds: 4),
      idempotencyKey: 'chave-do-trecho',
    );

    expect(heard.single.headers['Idempotency-Key'], 'chave-do-trecho');
  });

  test('3 (c): a stretch told again carries its Idempotency-Key', () async {
    final heard = <http.BaseRequest>[];

    await listening(heard).replaceSegment(
      'sessao-1',
      'trecho-1',
      await aRecording(),
      takeId: 'gravacao-1',
      from: Duration.zero,
      to: const Duration(seconds: 4),
      idempotencyKey: 'chave-da-correcao',
    );

    expect(heard.single.headers['Idempotency-Key'], 'chave-da-correcao');
  });
}

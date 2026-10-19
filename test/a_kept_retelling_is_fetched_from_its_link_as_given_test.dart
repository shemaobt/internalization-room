import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';

void main() {
  setUpAll(() {
    dotenv.testLoad(fileInput: 'BACKEND_URL=http://sala.local');
  });

  test(
    'a kept retelling is fetched from its signed link as given, not from the room',
    () async {
      final seen = <http.BaseRequest>[];
      final repository = RoomRepository(
        client: MockClient((request) async {
          seen.add(request);
          return http.Response.bytes([7, 7, 7], 200);
        }),
      )..presents('credencial-1');
      addTearDown(repository.dispose);

      final answer = await repository.fetchKeptRetelling(
        'https://storage.example/kept/aa/conto.m4a?X-Goog-Signature=abc',
      );

      expect(
        seen.single.url.toString(),
        'https://storage.example/kept/aa/conto.m4a?X-Goog-Signature=abc',
        reason:
            'o endereço do armazenamento ganhava o endereço da sala na frente',
      );
      expect((answer as Answered).value, [7, 7, 7]);
    },
  );
}

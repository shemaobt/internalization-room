import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/domain/minimum_build.dart';

const _answer =
    '{"build":"x","store":"gcs:y","model":[],"classifier_model":[],'
    '"minimum_app":{"ios":12,"android":14}}';
const _answerOfAnOlderServer =
    '{"build":"x","store":"gcs:y","model":[],"classifier_model":[]}';

RoomRepository _askingServerThatSays(String body, List<http.BaseRequest> seen) {
  final repository = RoomRepository(
    client: MockClient((request) async {
      seen.add(request);
      return http.Response(body, 200);
    }),
  );
  addTearDown(repository.dispose);
  return repository;
}

void main() {
  setUpAll(() {
    dotenv.testLoad(fileInput: 'BACKEND_URL=http://sala.local');
  });

  test("the tablet asks the server's version address and reads each "
      "platform's minimum", () async {
    final seen = <http.BaseRequest>[];
    final repository = _askingServerThatSays(_answer, seen);

    final answer = await repository.minimumBuilds();

    expect(seen.single.method, 'GET');
    expect(seen.single.url.toString(), 'http://sala.local/api/version');
    final minimum = (answer as Answered<dynamic>).value;
    expect(minimum.ios, 12);
    expect(minimum.android, 14);
  });

  test('a version answer from a server with no minimum is no answer', () async {
    final repository = _askingServerThatSays(_answerOfAnOlderServer, []);

    final answer = await repository.minimumBuilds();

    expect(answer, isA<RoomFailure>());
  });

  test('a build that carries no number is never below any minimum', () {
    const minimum = MinimumBuilds(ios: 9, android: 9);

    expect(minimum.keepsOut(0, TargetPlatform.iOS), isFalse);
    expect(minimum.keepsOut(0, TargetPlatform.android), isFalse);
  });
}

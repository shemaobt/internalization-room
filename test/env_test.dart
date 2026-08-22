import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/config/env.dart';

void main() {
  test('a trailing slash does not turn every route into a lost session', () {
    dotenv.testLoad(
      fileInput: 'BACKEND_URL=http://10.0.0.2:8000///\nINTERNALIZATION_ROOM_KEY=k',
    );

    expect(Env.backendUrl, 'http://10.0.0.2:8000',
        reason: 'uma barra a mais produzia //api/... e //health, que não redirecionam; '
            'o 404 resultante é lido como sessão que o servidor esqueceu');
  });

  test('a build without a key knows it, instead of throwing at the first request', () {
    dotenv.testLoad(fileInput: 'BACKEND_URL=http://10.0.0.2:8000\n');

    expect(Env.complete, isFalse,
        reason: 'o throw é um Error, e toda a camada de rede pega Exception — a sala '
            'ficava em laço entre offline e toque-me contra um servidor saudável');
  });

  test('a complete build says so', () {
    dotenv.testLoad(
      fileInput: 'BACKEND_URL=http://10.0.0.2:8000\nINTERNALIZATION_ROOM_KEY=k',
    );

    expect(Env.complete, isTrue);
  });
}

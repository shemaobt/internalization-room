import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/config/env.dart';

void main() {
  test('a trailing slash does not turn every route into a lost session', () {
    dotenv.testLoad(fileInput: 'BACKEND_URL=http://10.0.0.2:8000///');

    expect(
      Env.backendUrl,
      'http://10.0.0.2:8000',
      reason:
          'uma barra a mais produzia //api/... e //health, que não redirecionam; '
          'o 404 resultante é lido como sessão que o servidor esqueceu',
    );
  });

  test('an env with BACKEND_URL alone is complete', () {
    dotenv.testLoad(fileInput: 'BACKEND_URL=http://10.0.0.2:8000\n');
    expect(
      Env.complete,
      isTrue,
      reason:
          'a credencial do aparelho é a única coisa que o tablet manda; uma '
          'chave a mais no .env seria um segredo que o app não usa',
    );

    dotenv.testLoad(fileInput: '');
    expect(
      Env.complete,
      isFalse,
      reason:
          'o throw é um Error, e toda a camada de rede pega Exception — a sala '
          'ficava em laço entre offline e toque-me contra um servidor saudável',
    );
  });

  test('the claim latch is off in any build nobody handed the flag to', () {
    expect(
      Env.devAtalhos,
      isFalse,
      reason:
          'ele abre a sala e a barra de fases num build de release, então a única '
          'coisa que pode ligá-lo é alguém digitando --dart-define naquele build',
    );
  });

  test('the phase-skip latch is off unless a dev build asks for it', () {
    dotenv.testLoad(fileInput: 'BACKEND_URL=http://10.0.0.2:8000');
    expect(
      Env.devPularFases,
      isFalse,
      reason:
          'o portão que ele pula é a metodologia: sem a linha no .env, nada muda',
    );

    dotenv.testLoad(
      fileInput: 'BACKEND_URL=http://10.0.0.2:8000\nDEV_PULAR_FASES=1',
    );
    expect(Env.devPularFases, isTrue);
  });
}

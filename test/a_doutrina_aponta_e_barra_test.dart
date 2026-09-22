import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final check = File('.github/workflows/check.yml').readAsStringSync();

  test('the drift check runs on every pull request', () {
    expect(
      check,
      contains('dart run tool/sync_doctrine.dart --check'),
      reason:
          'um documento vendorizado que nada confere é o espelho da falha que o ENG-829 '
          'corrigiu: a frase da doutrina apontando para o que ninguém lê',
    );
    expect(
      check,
      contains('dart run tool/check_doctrine.dart'),
      reason:
          'o guarda dos seis mecanismos foi deslocado em vez de acompanhado',
    );
    expect(
      check,
      isNot(contains('sync_doctrine.dart --sync')),
      reason:
          'a CI re-pinaria sozinha para a ponta da branch dela, que é a única decisão para '
          'a qual uma ruling existe',
    );
  });

  test(
    'the pull request template asks for her sentence and where it is written',
    () {
      final template = File('.github/pull_request_template.md');

      expect(
        template.existsSync(),
        isTrue,
        reason: 'sem template nada faz a pergunta que o guarda não sabe fazer',
      );
      final asked = template.readAsStringSync();
      expect(asked, contains("Marcia's artifacts"));
      expect(
        asked,
        contains('never an engineering default'),
        reason:
            'a frase do §5.1 não está citada, e é ela que o revisor precisa ler',
      );
      expect(asked, contains('Her words:'));
      expect(asked, contains('Where it is written:'));
    },
  );

  test('the way in says where the doctrine is', () {
    for (final name in ['AGENTS.md', 'README.md']) {
      final text = File(name).readAsStringSync();
      expect(
        text,
        contains('docs/doctrine/'),
        reason:
            '$name não diz onde a doutrina está, e um documento que obriga toda mudança e '
            'que nada aponta é lido só por quem já sabia dele',
      );
      expect(text, contains('DOCTRINE.md'), reason: '$name não a nomeia');
    }
  });
}

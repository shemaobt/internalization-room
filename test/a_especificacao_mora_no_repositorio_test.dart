import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the interaction flows document is vendored in the repo', () {
    final file = File('docs/spec/interaction-flows.html');

    expect(
      file.existsSync(),
      isTrue,
      reason:
          'a especificação com que a sala é medida precisa estar no repositório, '
          'não só citada por ele',
    );
    expect(
      file.lengthSync(),
      greaterThan(10 * 1024),
      reason:
          'um arquivo desse tamanho não é o documento real de fluxos de interação',
    );
  });

  test('the design prototype is vendored in the repo', () {
    final file = File('docs/spec/prototype/Sala de Internalização.dc.html');

    expect(
      file.existsSync(),
      isTrue,
      reason:
          'o protótipo do Claude Design precisa estar no repositório, não só citado '
          'por ele',
    );
    expect(
      file.lengthSync(),
      greaterThan(10 * 1024),
      reason: 'um arquivo desse tamanho não é o protótipo real',
    );
  });

  test(
    'docs/spec/README.md names the origin of each externally-sourced artefact',
    () {
      final readme = File('docs/spec/README.md').readAsStringSync();
      final bullets = readme.split(RegExp(r'\n(?=- `)'));

      for (final artefact in [
        'interaction-flows.html',
        'prototype/Sala de Internalização.dc.html',
      ]) {
        final bullet = bullets.firstWhere(
          (b) => b.contains(artefact),
          orElse: () => '',
        );
        expect(
          bullet,
          isNot(isEmpty),
          reason: 'docs/spec/README.md precisa nomear $artefact',
        );
        expect(
          bullet,
          contains('Origin:'),
          reason:
              'a entrada de $artefact em docs/spec/README.md precisa dizer de onde veio',
        );
      }
    },
  );
}

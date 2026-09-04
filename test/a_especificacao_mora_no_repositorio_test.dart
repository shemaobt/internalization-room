import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The README used to concede that neither reference artefact was in the
/// workspace. This guard exists so the vendored spec cannot be silently
/// deleted, or the concession quietly reintroduced.
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

  test('the README no longer concedes the artefacts are missing', () {
    final readme = File('README.md').readAsStringSync();

    expect(
      readme,
      isNot(contains('Neither reference artifact is in this workspace')),
      reason:
          'a concessão precisa ser substituída pelos caminhos em docs/spec/, agora '
          'que a especificação está vendorizada',
    );
  });
}

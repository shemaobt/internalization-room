import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  test('a wait that runs out fails at the wait, naming what it waited for', () async {
    await expectLater(
      waitFor('a sala responder', () => false,
          limit: const Duration(milliseconds: 100)),
      throwsA(isA<TimeoutException>().having(
        (timeout) => timeout.message,
        'message',
        allOf(contains('100ms'), contains('a sala responder')),
      )),
      reason: 'a espera que desistia em silêncio deixava o teste seguir com a '
          'pré-condição não atendida e estourar longe dali, num List.last — o erro '
          'nunca apontava para a espera que desistiu',
    );
  });
}

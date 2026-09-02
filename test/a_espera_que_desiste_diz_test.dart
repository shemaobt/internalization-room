import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'session_notifier_test.dart';

void main() {
  test('a wait that runs out fails at the wait, saying how long it waited', () async {
    await expectLater(
      until(() => false, limit: const Duration(milliseconds: 100)),
      throwsA(isA<TimeoutException>().having(
        (timeout) => timeout.message,
        'message',
        contains('100ms'),
      )),
      reason: 'a espera que desistia em silêncio deixava o teste seguir com a '
          'pré-condição não atendida e estourar longe dali, num List.last — o erro '
          'nunca apontava para a espera que desistiu',
    );
  });

  test('a wait whose condition arrives says nothing', () async {
    var polls = 0;
    await until(() => ++polls >= 3);

    expect(polls, 3);
  });
}

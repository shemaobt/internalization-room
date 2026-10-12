import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart';

void main() {
  test(
    'a wait that runs out fails at the wait, naming what it waited for',
    () async {
      await expectLater(
        waitFor(
          'a sala responder',
          () => false,
          limit: const Duration(milliseconds: 100),
        ),
        throwsA(
          isA<TimeoutException>().having(
            (timeout) => timeout.message,
            'message',
            allOf(contains('100ms'), contains('a sala responder')),
          ),
        ),
        reason:
            'a espera que desistia em silêncio deixava o teste seguir com a '
            'pré-condição não atendida e estourar longe dali, num List.last — o erro '
            'nunca apontava para a espera que desistiu',
      );
    },
  );

  test(
    'a wait that steps the room is counted in room time, not on the clock',
    () async {
      var steps = 0;

      await waitFor(
        'a sala responder',
        () => steps >= 3,
        limit: const Duration(milliseconds: 300),
        step: () async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          steps++;
        },
      );

      expect(
        steps,
        3,
        reason:
            'o passo lento gastava o relógio da espera antes de a sala ter '
            'andado o que o teste pediu, e a carga da máquina virava timeout',
      );
    },
  );

  test(
    'a wait that steps the room gives up after the room time it was given',
    () async {
      var steps = 0;

      await expectLater(
        waitFor(
          'a sala responder',
          () => false,
          limit: const Duration(milliseconds: 300),
          step: () async => steps++,
        ),
        throwsA(
          isA<TimeoutException>().having(
            (timeout) => timeout.message,
            'message',
            allOf(contains('300ms'), contains('a sala responder')),
          ),
        ),
      );

      expect(
        steps,
        3,
        reason:
            'três passos de cem milissegundos são os trezentos que ela tinha',
      );
    },
  );

  testWidgets(
    'a wait for two parts is not met by the one part that was kept and named',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true)
        ..room.takeLandsAfter = const Duration(seconds: 1);
      final container = await pumpSala(tester, harness);
      final notifier = container.read(salaSessionProvider.notifier);
      await notifier.goConversa();
      await tester.pump(const Duration(milliseconds: 200));
      notifier.goEnsaio();
      await tester.pump(const Duration(milliseconds: 100));
      await gravarUmaParte(tester, notifier);
      await theRoomNamesTheParts(tester, container, parts: 1);

      await expectLater(
        theRoomNamesTheParts(
          tester,
          container,
          parts: 2,
          limit: const Duration(milliseconds: 100),
        ),
        throwsA(isA<TimeoutException>()),
        reason:
            'a espera perguntava se todas as partes tinham nome, e todas é '
            'verdade de uma lista com uma parte só; o retro entrava com a '
            'segunda ainda por gravar',
      );
      closeTheRoom(container);
    },
  );
}

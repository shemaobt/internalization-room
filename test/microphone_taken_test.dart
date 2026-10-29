import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show settle;

void main() {
  test(
    'a call that takes the microphone is not a room that is still listening',
    () async {
      final harness = SalaHarness();
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      await notifier.goConversa(book: 'Ruth');
      await settle();
      notifier.goEnsaio();
      await settle();
      notifier.gravarACena(1);
      await settle();
      expect(
        container.read(salaSessionProvider).ensaio,
        EnsaioStatus.recording,
      );

      harness.recorder.takeTheMicrophone();
      await settle();

      expect(
        container.read(salaSessionProvider).micTaken,
        isTrue,
        reason:
            'o gravador avisava que tinha parado e ninguém escutava, então '
            'a máquina de estados seguia com a tomada aberta como se a equipe '
            'estivesse sendo gravada',
      );

      harness.recorder.giveTheMicrophoneBack();
      await settle();

      expect(
        container.read(salaSessionProvider).micTaken,
        isFalse,
        reason:
            'a tomada volta sozinha quando a ligação acaba, e uma sala que '
            'ficasse marcada de tomada nunca mais desenharia a captura',
      );
    },
  );
}

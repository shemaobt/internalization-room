import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'session_notifier_test.dart' show inConversa;
import 'scenario_helpers.dart' show settle;

void main() {
  test(
    'the recording screen opens with nothing said, not the retired august line',
    () async {
      final harness = SalaHarness();
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      notifier.goEnsaio();
      await settle();

      expect(
        container.read(salaSessionProvider).stage,
        SalaStage.ensaio,
        reason:
            'o gesto precisa ter de fato levado a equipe para a tela de gravação',
      );
      expect(
        harness.voice.assets,
        isEmpty,
        reason:
            'a tela de gravação abre como a dela, em silêncio; os quatro pontos de '
            'agosto vinham de uma fala fixa que nenhum commit de setembro carrega',
      );
    },
  );
}

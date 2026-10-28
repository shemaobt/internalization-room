import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';

import 'fakes.dart';
import 'the_back_translation_is_told_by_beads_test.dart'
    show contarAteOFimDaParte, tocarNoCirculo;
import 'the_translation_is_recorded_over_until_the_check_test.dart'
    show
        cabeca,
        entrarNaTraducao,
        gravarATraducao,
        ouvir,
        ouvirNaGravacao,
        pausar,
        tocar;

void main() {
  testWidgets(
    'a held second part with nothing heard of it comes back from its own start, not from before it',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true)
        ..room.chunksAnswerWithNoName = true;
      final container = await entrarNaTraducao(tester, harness);
      harness.playback.at = cabeca;
      await tocarNoCirculo(tester);
      await gravarATraducao(tester, harness);
      await contarAteOFimDaParte(tester, harness);
      final segunda = container.read(salaSessionProvider).partes[1].path;
      expect(container.read(salaSessionProvider).btParte, 1);
      harness.playback.at = const Duration(seconds: 3);
      await tocar(tester, pausar);

      final sala = container.read(salaSessionProvider.notifier);
      sala.state = sala.state.copyWith(btOuvidoMs: 0);
      await ouvirNaGravacao(tester, container, 0);
      harness.playback.finishPlayback();
      await tester.pump(const Duration(milliseconds: 300));
      await tocar(tester, ouvir);

      expect(harness.playback.played.last, segunda);
      expect(
        harness.playback.playedFrom.last,
        Duration.zero,
        reason:
            'a parte segurada voltava de antes do próprio começo, '
            '0 menos a primeira parte inteira',
      );
      closeTheRoom(container);
    },
  );
}

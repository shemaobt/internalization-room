import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show settle;
import 'session_notifier_test.dart'
    show inConversaWithoutPausing, tellTwoStretches;

void main() {
  test(
    'a second tap starts the translation over: the frases go, P1 is said, and the next frase is the first of part 1',
    () async {
      final harness = SalaHarness();
      final container = await inConversaWithoutPausing(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      await tellTwoStretches(harness, container);

      notifier.recomecarATraducao();
      await settle(const Duration(milliseconds: 700));
      notifier.recomecarATraducao();
      await waitFor(
        'a tradução recomeçar',
        () =>
            harness.room.restartsAsked.isNotEmpty &&
            container.read(salaSessionProvider).btTrechos.isEmpty,
      );

      expect(harness.room.restartsAsked, hasLength(1));
      expect(
        container.read(salaSessionProvider).btTrechos,
        isEmpty,
        reason: 'as frases de antes continuavam na tela depois do recomeço',
      );
      await waitFor(
        'a voz dizer P1',
        () => harness.voice.fixedLines.any((line) => line.$1 == 'P1'),
      );
      expect(
        [for (final line in harness.voice.fixedLines) line.$1],
        contains('P1'),
        reason: 'o recomeço não dizia a instrução de traduzir',
      );

      await waitFor(
        'o clipe voltar a rodar',
        () => container.read(salaSessionProvider).canCut,
      );
      final enviados = harness.room.chunkSpans.length;
      harness.playback.at = const Duration(seconds: 5);
      notifier.cortarTrecho();
      notifier.retroTap();
      await settle();
      await confirmarATraducao(container);
      await waitFor(
        'a primeira frase do recomeço chegar',
        () => container.read(salaSessionProvider).btTrechos.length == 1,
      );

      expect(
        harness.room.chunkSpans.sublist(enviados).first,
        startsWith('0-'),
        reason: 'a frase nova começava onde a antiga terminava',
      );
      expect(
        container.read(salaSessionProvider).btTrechos.single.frase,
        1,
        reason: 'a numeração continuava de onde parou',
      );
      expect(container.read(salaSessionProvider).btPhase, BtPhase.playing);
    },
  );
}

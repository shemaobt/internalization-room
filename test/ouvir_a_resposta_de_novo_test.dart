import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show settle;
import 'tocar_vira_pausar_test.dart' show pumpAoApontado, harnessApontando;

void main() {
  group('ouvir a resposta de novo', () {
    test('repete a fala do veredito, não o trecho', () async {
      final harness = harnessApontando();
      final container = await pumpAoApontado(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      final linha = container.read(salaSessionProvider).lastSpoken;
      expect(linha, isNotNull, reason: 'o veredito falou e foi lembrado');

      final tocadosAntes = harness.voice.played.length;

      notifier.ouvirARespostaDeNovo();
      await waitFor(
        'a resposta tocar de novo',
        () => harness.voice.played.length > tocadosAntes,
      );
      await settle();

      expect(
        harness.voice.played.last,
        linha!.url,
        reason: 'o mesmo clipe do veredito, tocado de novo',
      );
      expect(
        harness.playback.ranges,
        isEmpty,
        reason: 'o botão toca a resposta, não o trecho',
      );
    });

    test('mostra o narrador falando enquanto repete', () async {
      final harness = harnessApontando();
      final container = await pumpAoApontado(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      harness.voice.holdNextLine();
      notifier.ouvirARespostaDeNovo();
      await waitFor(
        'a sala mostrar o narrador falando',
        () => container.read(salaSessionProvider).voice == VoiceState.speaking,
      );

      harness.voice.finishHeldLine();
      await waitFor(
        'a sala voltar a convidar',
        () => container.read(salaSessionProvider).voice == VoiceState.invite,
      );
    });

    test('sem fala guardada, o botão não toca nada', () async {
      final harness = harnessApontando()
        ..room.turnsAreCanned = true
        ..room.verdictUsedFailSafe = true;
      final container = await pumpAoApontado(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      expect(
        container.read(salaSessionProvider).lastSpoken,
        isNull,
        reason:
            'nem o turno de abertura nem o veredito de fail-safe são lembrados',
      );

      final tocadosAntes = harness.voice.played.length;
      final assetsAntes = harness.voice.assets.length;
      final fixasAntes = harness.voice.fixedLines.length;

      notifier.ouvirARespostaDeNovo();
      await settle();

      expect(harness.voice.played.length, tocadosAntes);
      expect(harness.voice.assets.length, assetsAntes);
      expect(harness.voice.fixedLines.length, fixasAntes);
      expect(harness.playback.ranges, isEmpty);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'session_notifier_test.dart' show settle;
import 'tocar_vira_pausar_test.dart' show pumpAoApontado, harnessApontando;

void main() {
  group('a esfera em findings', () {
    test('repete a fala do veredito, não o trecho', () async {
      final harness = harnessApontando();
      final container = await pumpAoApontado(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      final linha = container.read(salaSessionProvider).lastSpoken;
      expect(linha, isNotNull, reason: 'o veredito falou e foi lembrado');

      final tocadosAntes = harness.voice.played.length;

      notifier.retroTap();
      await waitFor(
        'a esfera tocar a fala de novo',
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
        reason: 'a esfera não toca o trecho — os players da grade fazem isso',
      );
    });

    test('mostra o narrador falando enquanto repete', () async {
      final harness = harnessApontando();
      final container = await pumpAoApontado(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      harness.voice.holdNextLine();
      notifier.retroTap();
      await waitFor(
        'a esfera mostrar o narrador falando',
        () => container.read(salaSessionProvider).voice == VoiceState.speaking,
      );

      harness.voice.finishHeldLine();
      await waitFor(
        'a esfera voltar a convidar',
        () => container.read(salaSessionProvider).voice == VoiceState.invite,
      );
    });

    test('sem fala guardada, a esfera não toca o trecho', () async {
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

      notifier.retroTap();
      await settle();

      expect(harness.voice.played.length, tocadosAntes);
      expect(harness.voice.assets.length, assetsAntes);
      expect(harness.playback.ranges, isEmpty);
    });

    test(
      'os players da grade continuam tocando o trecho diretamente',
      () async {
        final harness = harnessApontando();
        final container = await pumpAoApontado(harness);
        addTearDown(container.dispose);
        final notifier = container.read(salaSessionProvider.notifier);

        notifier.ouvirOTrechoEATraducao();
        await waitFor(
          'o trecho apontado estar tocando',
          () => container.read(salaSessionProvider).btTrechoTocando,
        );

        expect(harness.playback.ranges, isNotEmpty);
      },
    );
  });
}

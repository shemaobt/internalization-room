import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'session_notifier_test.dart' show inConversa;

void main() {
  test(
    'a stretch of the retro that fails to play twice leaves silence and calls '
    'nobody',
    () async {
      final harness = SalaHarness();
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      notifier.goEnsaio();
      notifier.ensaioTap();
      notifier.ensaioTap();
      await settle();
      notifier.takeKeep();
      notifier.startRetro();
      await settle();

      harness.playback.failPlayback();
      await settle();
      notifier.ouvirOTrechoPendente();
      await settle();
      harness.playback.failPlayback();
      await settle();

      expect(
        read().needsPerson,
        isFalse,
        reason:
            'só a voz do Guia falhando duas vezes chama alguém; o som de um '
            'trecho que falha deixa silêncio',
      );
      expect(harness.room.personsAsked, 0);
    },
  );

  test(
    'the recorder that never started twice in the retro still calls',
    () async {
      final harness = SalaHarness();
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);

      notifier.goEnsaio();
      notifier.ensaioTap();
      notifier.ensaioTap();
      await settle();
      notifier.takeKeep();
      await waitFor(
        'a sala nomear a parte',
        () => container.read(salaSessionProvider).partes.last.takeId != null,
      );
      notifier.startRetro();
      await settle();

      harness.recorder.startThrows = true;
      harness.playback.at = const Duration(seconds: 2);
      notifier.retroTap();
      notifier.retroTap();
      await settle();
      notifier.retroTap();
      notifier.retroTap();
      await settle();

      expect(read().needsPerson, isTrue);
      expect(
        harness.room.personsAsked,
        1,
        reason:
            'pin: o microfone que nunca abre duas vezes seguidas é a '
            'sala decidindo, e isso continua chamando alguém como sempre',
      );
    },
  );

  test('a warning read after a turn stops nothing and calls nobody', () async {
    final harness = SalaHarness()
      ..room.serverStatus = 'needs_person'
      ..room.serverHalt = HaltKind.warning;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    SalaSessionState read() => container.read(salaSessionProvider);

    await waitFor('o aviso chegar', () => read().warning);

    expect(read().needsPerson, isFalse);
    expect(harness.room.personsAsked, 0);
  });
}

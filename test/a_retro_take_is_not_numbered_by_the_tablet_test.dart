import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'resto_da_historia_test.dart' show settle, umaParteInteira;

void main() {
  test('a guarded back-translation take carries no number, a rehearsal part '
      'keeps its own', () async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.goConversa();
    await settle();
    notifier.goEnsaio();
    await settle();

    notifier.ensaioTap();
    await waitFor(
      'a gravação da parte começar',
      () =>
          container.read(salaSessionProvider).ensaio == EnsaioStatus.recording,
    );
    notifier.ensaioTap();
    await waitFor(
      'a gravação da parte terminar',
      () => container.read(salaSessionProvider).ensaio == EnsaioStatus.recorded,
    );
    notifier.takeKeep();
    await waitFor('a sala nomear a parte', () {
      final partes = container.read(salaSessionProvider).keptTakes;
      return partes.length == 1 && partes.first.takeId != null;
    });

    notifier.startRetro();
    await waitFor('a retro tocar', () => harness.playback.played.isNotEmpty);

    harness.room.chunkCaptured = false;
    harness.playback.at = umaParteInteira;
    notifier.cortarTrecho();
    await settle();
    notifier.retroTap();
    await waitFor(
      'o trecho chegar à sala',
      () => harness.room.chunksSent == 1,
      limit: const Duration(seconds: 2),
    );
    await settle();

    final guardadas = await harness.takes.entries();
    final retro = guardadas.singleWhere((e) => e.kind == 'retro');
    expect(retro.scope, KeptScope.whole);
    expect(retro.chunkIndex, isNull);

    final ensaio = guardadas.singleWhere((e) => e.scope == KeptScope.parte(1));
    expect(ensaio.chunkIndex, 1);
  });

  test('the app reads a take\'s number as ordinal', () {
    final takes = TakeView.listFrom({
      'takes': [
        {'take_id': 'g-1', 'scope': 'composed', 'ordinal': 2},
        {'take_id': 'g-2', 'scope': 'passagem-inteira'},
      ],
    });

    expect(takes[0].ordinal, 2);
    expect(takes[1].ordinal, isNull);
  });
}

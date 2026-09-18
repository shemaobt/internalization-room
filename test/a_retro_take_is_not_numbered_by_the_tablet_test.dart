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
    final harness = SalaHarness();
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
    await waitFor('o trecho chegar à sala', () => harness.room.chunksSent == 1);
    await settle();

    final guardadas = await harness.takes.entries();
    final retro = guardadas.singleWhere((e) => e.kind == 'retro');
    expect(retro.scope, KeptScope.whole);
    expect(retro.chunkIndex, isNull);

    final ensaio = guardadas.singleWhere((e) => e.kind == 'ensaio');
    expect(ensaio.scope, KeptScope.parte(1));
    expect(ensaio.chunkIndex, 1);
  });

  test('a short-way retelling that the room made nothing out of also '
      'guards its take with no number', () async {
    final harness = SalaHarness()..room.verdictChecked = false;
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.goConversa();
    await settle();
    notifier.goEnsaio();
    notifier.ensaioTap();
    await waitFor(
      'a gravação da parte começar',
      () =>
          container.read(salaSessionProvider).ensaio == EnsaioStatus.recording,
    );
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    await waitFor('a sala nomear a parte', () {
      final partes = container.read(salaSessionProvider).keptTakes;
      return partes.length == 1 && partes.first.takeId != null;
    });
    notifier.startRetro();
    await settle();

    harness.playback.at = const Duration(seconds: 20);
    notifier.cortarTrecho();
    await settle();
    notifier.retroTap();
    await waitFor(
      'o primeiro trecho chegar à sala',
      () => harness.room.chunksSent == 1,
    );
    harness.room.verdictFindingSegmentId = harness.room.segments.last.segmentId;
    harness.playback.finishPlayback();
    await waitFor(
      'o clipe poder ser dado por ouvido',
      () => container.read(salaSessionProvider).canFinishBackTranslation,
    );
    await notifier.finishBackTranslation();
    await waitFor(
      'o veredito chegar',
      () => container.read(salaSessionProvider).btPhase == BtPhase.findings,
    );
    notifier.ouvirVozMaterna();
    await waitFor(
      'o trecho apontado estar tocando',
      () => container.read(salaSessionProvider).btTrechoTocando,
    );
    notifier.retellChunk();
    await waitFor('a tradução de novo levar a equipe ao trecho', () {
      final state = container.read(salaSessionProvider);
      return state.btPhase == BtPhase.playing && state.btTrechoTocando;
    });
    harness.playback.finishPlayback();
    // The verb refuses a stretch still sounding or a phase in transit, silently. Waiting on
    // the sound alone let the call land a beat early on CI, do nothing, and the tap that
    // followed opened a fresh capture instead of ending a retelling — no retro entry.
    await waitFor('o trecho apontado parar de tocar, com a fase assentada', () {
      final state = container.read(salaSessionProvider);
      return !state.btTrechoTocando &&
          (state.btPhase == BtPhase.playing || state.btPhase == BtPhase.findings);
    });

    harness.room.replaceCaptured = false;
    await notifier.traduzirDeNovo(
      container.read(salaSessionProvider).btTrechos.first,
    );
    await waitFor(
      'o microfone abrir no trecho',
      () => container.read(salaSessionProvider).btPhase == BtPhase.capturing,
    );
    notifier.retroTap();
    // Waited on the outbox, not on the phase. What this case reads is the row the guard
    // writes to disk, and that write can land after the phase has settled: on a loaded
    // runner it did, and the case read an empty outbox and called it a missing guard.
    await waitFor('a tradução de novo chegar à caixa de saída', () async {
      final naCaixa = await harness.takes.entries();
      return naCaixa.any((entrada) => entrada.kind == 'retro');
    });

    final guardadas = await harness.takes.entries();
    final retells = guardadas.where((e) => e.kind == 'retro');
    expect(retells, isNotEmpty);
    expect(retells.every((e) => e.chunkIndex == null), isTrue);
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

  test('the app reads which of its part\'s recordings a take is', () {
    final takes = TakeView.listFrom({
      'takes': [
        {'take_id': 'g-1', 'scope': 'parte-2', 'ordinal': 2, 'pass_number': 3},
        {'take_id': 'g-2', 'scope': 'parte-1', 'ordinal': 1},
      ],
    });

    expect(takes[0].pass, 3,
        reason: 'é por esta conta que a sala separa a gravação que a equipe '
            'guardou da que ela abandonou');
    expect(takes[1].pass, isNull);
  });
}

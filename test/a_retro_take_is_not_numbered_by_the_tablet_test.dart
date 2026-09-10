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
    await waitFor('a recontagem levar a equipe ao trecho', () {
      final state = container.read(salaSessionProvider);
      return state.btPhase == BtPhase.playing && state.btTrechoTocando;
    });
    harness.playback.finishPlayback();
    await waitFor(
      'o trecho apontado parar de tocar',
      () => !container.read(salaSessionProvider).btTrechoTocando,
    );

    harness.room.replaceCaptured = false;
    await notifier.traduzirDeNovo(
      container.read(salaSessionProvider).btTrechos.first,
    );
    await settle();
    notifier.retroTap();
    await waitFor(
      'a sala sair do pensando',
      () => container.read(salaSessionProvider).btPhase != BtPhase.thinking,
    );

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
}

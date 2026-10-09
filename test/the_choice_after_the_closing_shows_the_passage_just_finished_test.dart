import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/finished_passages.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

import 'fakes.dart';
import 'um_ensaio_de_tres_partes.dart';

void main() {
  test('the room finishes a passage and the Choice opens at once; after both, '
      'the ledger holds the finished mark', () async {
    final home = Directory.systemTemp.createTempSync('sala-feitas');
    addTearDown(() => home.deleteSync(recursive: true));
    final theWriteLands = Completer<void>();
    var homesAsked = 0;
    final ledger = FinishedPassages(
      home: () async {
        if (homesAsked++ == 0) await theWriteLands.future;
        return home;
      },
    );
    final harness = SalaHarness(
      fimLinger: const Duration(milliseconds: 1),
      finishedOnDisk: ledger,
    )..room.verdictChecked = true;
    final container = harness.container();
    addTearDown(container.dispose);
    final it = Sala(harness, container);
    await it.sala.goConversa(pericope: 'P01');
    await waitFor('the passage to open', () => it.estado.sessionId != null);
    it.sala.goEnsaio();
    await gravarUmaParteDoEnsaio(it);
    harness.playback.lengths[it.estado.keptTakes.single.path] =
        partesDoEnsaio.first;
    it.sala.startRetro();
    await waitFor(
      'the part to play',
      () => it.estado.btPhase == BtPhase.playing,
    );
    await ouvirETraduzirAParteInteira(it, partesDoEnsaio.first);
    await pedirOVeredito(it);
    expect(it.estado.btPhase, BtPhase.conferida);

    final wheelsAsked = harness.room.booksAsked.length;
    await it.sala.aprovarRascunhoFinal();
    await waitFor('the Closing', () => it.estado.station is Fim);
    await waitFor('the Choice to open', () => it.estado.station is Menu);
    await waitFor(
      'the Choice to ask for its Wheel',
      () => harness.room.booksAsked.length > wheelsAsked,
    );
    theWriteLands.complete();
    await waitFor('the Wheel to load', () => it.estado.naRoda != null);

    expect(it.estado.feitas, contains('P01'));
    expect(await ledger.all('Ruth'), contains('P01'));
  }, timeout: const Timeout(Duration(seconds: 40)));
}

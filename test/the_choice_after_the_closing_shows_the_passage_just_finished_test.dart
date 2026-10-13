import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

import 'fakes.dart';
import 'um_ensaio_de_tres_partes.dart';

void main() {
  test('the choice after the closing marks the approved passage from the '
      "room's next answer", () async {
    final harness = SalaHarness(fimLinger: const Duration(milliseconds: 1))
      ..room.verdictChecked = true;
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

    harness.room.passages = const [
      Passagem(pericope: 'P01', audioUrl: '/voice/p01', approved: true),
      Passagem(pericope: 'P02', audioUrl: '/voice/p02'),
      Passagem(pericope: 'P03', audioUrl: '/voice/p03'),
    ];
    final wheelsAsked = harness.room.booksAsked.length;
    await it.sala.aprovarRascunhoFinal();
    await waitFor('the Closing', () => it.estado.station is Fim);
    await waitFor('the Choice to open', () => it.estado.station is Menu);
    await waitFor(
      'the Choice to ask for its Wheel',
      () => harness.room.booksAsked.length > wheelsAsked,
    );
    await waitFor('the Wheel to load', () => it.estado.naRoda != null);

    expect(it.estado.naRoda!.map((p) => (p.pericope, p.approved)), [
      ('P01', true),
      ('P02', false),
      ('P03', false),
    ]);
  }, timeout: const Timeout(Duration(seconds: 40)));
}

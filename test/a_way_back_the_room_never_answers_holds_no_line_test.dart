import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show enterThePanorama, settle;
import 'um_ensaio_de_tres_partes.dart' show Sala;

void main() {
  test('a way back to the Panorama that the room never answers lets its Step '
      'go with no person sign, and holds no line', () async {
    final harness =
        SalaHarness(
            lingua: 'pt',
            busyCeiling: const Duration(milliseconds: 300),
          )
          ..room.passages = const [
            Passagem(
              pericope: 'panorama',
              audioUrl: '/voice/panorama',
              kind: PassagemKind.panorama,
            ),
            Passagem(pericope: 'P01', audioUrl: '/voice/p01'),
          ];
    final container = harness.container();
    addTearDown(container.dispose);
    final it = Sala(harness, container);
    harness.voice.holdNextFetch();
    await enterThePanorama(it.sala, () => it.estado);
    await waitFor(
      'the Panorama session to be asked for',
      () => harness.room.sessionIds.isNotEmpty,
    );
    it.sala.leaveThePassage();
    harness.voice.finishHeldFetch();
    await waitFor('the way back', () => it.estado.theWayBackIsLive);
    await settle();
    final checks = harness.network.checks;
    harness.network.holdNextCheck();
    await it.sala.returnToTheLeftEntry();
    await waitFor(
      'the Panorama to ask whether the room is there',
      () => harness.network.checks > checks,
    );
    await waitFor('the Step to be let go', () => !it.estado.awaitingTheGuide);
    await settle();
    expect(it.estado.needsPerson, isFalse);
    harness.voice.assets.clear();

    it.sala.sayTheMicIsBlocked();
    await settle();

    expect(harness.voice.assets, [micBlockedAsset('pt')]);
    harness.network.finishHeldCheck();
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'um_ensaio_de_tres_partes.dart';

void main() {
  test(
    'a parte gravada de novo toca do seu arquivo, e o círculo grava no fim dela',
    () async {
      final it = await umEnsaioDeTresPartesContadoInteiro();
      it.harness.room
        ..verdictChecked = false
        ..verdictHasFinding = true
        ..verdictFindingPlace = 1;
      await pedirOVeredito(it);
      expect(it.estado.btPhase, BtPhase.playing);
      expect(it.estado.btVeredito, isTrue);

      it.sala.leaveTheBackTranslation();
      await regravarAParte(it, 1);
      final nova = it.partes[1].path;
      await untilTheAdvanceDiscLights(it.sala);

      it.sala.startRetro();
      await waitFor(
        'a parte nova soar',
        () =>
            it.harness.playback.sounding &&
            it.harness.playback.played.last == nova,
      );
      expect(it.estado.btParte, 1);

      await theClipOpens(it.harness);
      it.harness.playback.at = partesDoEnsaio[1];
      it.sala.retroTap();
      it.sala.retroTap();
      await waitFor(
        'o microfone abrir',
        () => it.estado.btPhase == BtPhase.capturing,
      );
      expect(it.estado.needsPerson, isFalse);
    },
  );
}

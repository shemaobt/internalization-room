import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/channel.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'um_ensaio_de_tres_partes.dart';

/// A team standing on a finding the analyst addressed to the stretch of part 2, with the
/// three parts recorded and told back whole.
Future<Sala> _oAchadoNaParteDois() async {
  final it = await umEnsaioDeTresPartesContadoInteiro();
  it.harness.room
    ..verdictChecked = false
    ..verdictHasFinding = true
    ..verdictFindingPlace = 1;
  await pedirOVeredito(it);
  expect(it.estado.btPhase, BtPhase.findings);
  return it;
}

void main() {
  test(
    'a part recorded again on the Long way is a WAV rehearsal part',
    () async {
      final it = await _oAchadoNaParteDois();
      final capturesBefore = it.harness.recorder.captures;

      it.sala.gravarAParteDeNovo();
      it.sala.ensaioTap();
      await waitFor(
        'a gravação da parte começar',
        () => it.estado.ensaio == EnsaioStatus.recording,
      );

      expect(it.harness.recorder.captures, greaterThan(capturesBefore));
      expect(
        it.harness.recorder.lastOwner,
        MicOwner.rehearsal,
        reason:
            'a parte gravada de novo substitui uma parte do ensaio, e vai ao '
            'Refine no mesmo formato que ela',
      );
    },
  );

  test(
    'a stretch told again on the Short way opens the capture microphone, not the rehearsal one',
    () async {
      final it = await _oAchadoNaParteDois();
      final capturesBefore = it.harness.recorder.captures;

      await escolherTraduzirDeNovo(it);

      expect(it.harness.recorder.captures, greaterThan(capturesBefore));
      expect(
        it.harness.recorder.lastOwner,
        MicOwner.capture,
        reason:
            'contar o trecho de novo é contar de volta, que fica comprimido '
            'como no app dela',
      );
    },
  );
}

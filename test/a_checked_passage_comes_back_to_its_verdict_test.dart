import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show settle;
import 'um_ensaio_de_tres_partes.dart';

Future<Sala> _conferidaEDeixadaPelaVolta() async {
  final it = await umEnsaioDeTresPartesContadoInteiro();
  it.harness.room.retroSoFar = BackTranslationProgress(
    segments: [...it.harness.room.segments],
    checked: true,
  );
  await pedirOVeredito(it);
  expect(it.estado.btPhase, BtPhase.conferida);
  it.sala.leaveTheBackTranslation();
  await waitFor(
    'a equipe voltar à casa da gravação',
    () => it.estado.stage == SalaStage.ensaio,
  );
  return it;
}

Future<void> _traduzirAGravacao(Sala it) async {
  it.sala.startRetro();
  await waitFor(
    'a tradução voltar',
    () => it.estado.stage == SalaStage.retro && !it.estado.awaitingTheGuide,
  );
  await settle();
}

void main() {
  test(
    'coming back from the home to a passage checked clean lands on its verdict, '
    'with nothing played and nothing said',
    () async {
      final it = await _conferidaEDeixadaPelaVolta();
      it.harness.room.listeningUnheardTakeIds = const [];
      final tocadas = it.harness.playback.played.length;
      final falas = it.harness.voice.fixedLines.length;

      await _traduzirAGravacao(it);

      expect(
        it.estado.btPhase,
        BtPhase.conferida,
        reason: 'a volta da casa esquecia a conferência e reabria a tradução',
      );
      expect(it.estado.btVeredito, isTrue);
      expect(it.harness.playback.played.skip(tocadas), isEmpty);
      expect(it.harness.voice.fixedLines.skip(falas), isEmpty);
    },
  );

  test(
    'a room that says nothing of what was heard still brings the checked '
    'passage back to its verdict, not to the untold ground playing',
    () async {
      final it = await _conferidaEDeixadaPelaVolta();
      it.harness.room.listeningUnheardTakeIds = null;
      final tocadas = it.harness.playback.played.length;

      await _traduzirAGravacao(it);

      expect(it.estado.btPhase, BtPhase.conferida);
      expect(
        it.harness.playback.played.skip(tocadas),
        isEmpty,
        reason: 'a última parte voltava a tocar sobre a conferência limpa',
      );
    },
  );
}

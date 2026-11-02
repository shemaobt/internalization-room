import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show settle;
import 'um_ensaio_de_tres_partes.dart';

const _umaParte = [Duration(seconds: 10)];

Future<Sala> _umaParteComAFraseNova({
  required int startsMs,
  required int endsMs,
  String? noTake,
}) async {
  final it = await umEnsaioGravado(_umaParte);
  it.harness.room
    ..listeningUnheardTakeIds = const []
    ..rerecordedSentences.add(
      RerecordedSentence(
        takeId: noTake ?? it.partes[0].takeId!,
        startsMs: startsMs,
        endsMs: endsMs,
      ),
    );
  it.sala.startRetro();
  await waitFor(
    'a tradução começar a tocar a parte',
    () =>
        it.estado.stage == SalaStage.retro &&
        it.estado.btPhase == BtPhase.playing,
  );
  return it;
}

Future<void> _pausarEm(Sala it, Duration em) async {
  it.harness.playback.at = em;
  it.sala.ouvirGravacao();
  await waitFor('a parte pausar', () => !it.harness.playback.sounding);
}

Future<void> _seguirDe(Sala it, Duration em) async {
  it.harness.playback.at = em;
  it.sala.ouvirGravacao();
  await waitFor('a parte seguir', () => it.harness.playback.sounding);
}

void main() {
  test('a sentence laid into a part the team played around keeps terminei dark '
      'until the sentence itself plays here', () async {
    final it = await _umaParteComAFraseNova(startsMs: 2000, endsMs: 2500);
    await traduzirUmTrecho(it, const Duration(seconds: 1));
    await waitFor(
      'a equipe voltar ao círculo',
      () => it.estado.btPhase == BtPhase.playing,
    );
    await theClipOpens(it.harness);
    await waitFor('a parte seguir', () => it.harness.playback.sounding);

    await _pausarEm(it, const Duration(seconds: 2));
    await _seguirDe(it, const Duration(milliseconds: 2500));
    await _pausarEm(it, const Duration(milliseconds: 9800));
    await settle();

    expect(it.estado.btOuvidaInteira, isTrue);
    expect(
      it.estado.canAdvanceToTheVerdict,
      isFalse,
      reason:
          'a parte contava como ouvida inteira dentro da folga de 750 ms, com '
          'a frase regravada de meio segundo nunca tocada no seu lugar',
    );

    await _seguirDe(it, const Duration(seconds: 2));
    await _pausarEm(it, const Duration(milliseconds: 2500));
    await settle();
    expect(it.estado.canAdvanceToTheVerdict, isTrue);
  });
}

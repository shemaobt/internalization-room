import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show settle;
import 'um_ensaio_de_tres_partes.dart';

const _ateOndeASegundaFoiContada = Duration(seconds: 4);

Future<Sala> _contadaAteOMeioDaSegunda() async {
  final it = await umEnsaioDeTresPartesGravado();
  it.sala.startRetro();
  await waitFor(
    'a tradução começar a tocar a primeira parte',
    () =>
        it.estado.stage == SalaStage.retro &&
        it.estado.btPhase == BtPhase.playing,
  );
  await ouvirETraduzirAParteInteira(it, partesDoEnsaio[0]);
  await traduzirUmTrecho(it, _ateOndeASegundaFoiContada);
  return it;
}

Future<void> _irAoEnsaioEVoltar(Sala it) async {
  it.sala.goEnsaio();
  await waitFor(
    'a equipe voltar ao ensaio',
    () => it.estado.stage == SalaStage.ensaio,
  );
  it.harness.room.listeningUnheardTakeIds = const [];
  it.sala.startRetro();
  await waitFor(
    'a tradução voltar',
    () =>
        it.estado.stage == SalaStage.retro &&
        it.estado.btPhase == BtPhase.playing &&
        !it.estado.awaitingTheGuide,
  );
  await settle();
}

void main() {
  test(
    'coming back to a telling with every part heard plays nothing and says '
    'nothing, and the play control waits where the telling stopped',
    () async {
      final it = await _contadaAteOMeioDaSegunda();
      final tocadas = it.harness.playback.played.length;
      final falas = it.harness.voice.fixedLines.length;

      await _irAoEnsaioEVoltar(it);

      expect(
        it.harness.playback.played.skip(tocadas),
        isEmpty,
        reason: 'a gravação voltava a tocar debaixo da equipe',
      );
      expect(
        it.harness.voice.fixedLines.skip(falas),
        isEmpty,
        reason: 'a voz falava na volta a uma tradução em curso',
      );
      expect(it.estado.canListenToThePendingStretch, isTrue);
      expect(it.estado.aBackTranslationGestureActs, isTrue);

      it.sala.ouvirGravacao();
      await waitFor(
        'a gravação tocar depois do toque',
        () => it.harness.playback.played.length > tocadas,
      );
      expect(it.harness.playback.played.last, it.partes[1].path);
      expect(
        it.harness.playback.playedFrom.last,
        _ateOndeASegundaFoiContada,
        reason:
            'o toque tocava de outro lugar que não o fim do que foi contado',
      );
    },
  );

  test('coming back to a telling told to its end opens «terminei» with nothing '
      'played, the told frases covering the recording', () async {
    final it = await umEnsaioDeTresPartesContadoInteiro();
    final tocadas = it.harness.playback.played.length;

    await _irAoEnsaioEVoltar(it);

    expect(it.harness.playback.played.skip(tocadas), isEmpty);
    expect(
      it.estado.canFinishBackTranslation,
      isTrue,
      reason: 'o terminei esperava a gravação tocar outra vez até o fim',
    );
  });
}

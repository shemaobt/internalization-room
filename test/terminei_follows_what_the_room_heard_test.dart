import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show settle;
import 'um_ensaio_de_tres_partes.dart';

Future<Sala> _ouvidaInteiraPelaSala() async {
  final it = await umEnsaioDeTresPartesGravado();
  it.harness.room.listeningUnheardTakeIds = [
    for (final parte in it.partes) parte.takeId!,
  ];
  it.sala.startRetro();
  for (var onde = 0; onde < partesDoEnsaio.length; onde++) {
    await waitFor(
      'a parte ${onde + 1} entrar no ar',
      () =>
          it.harness.playback.played.isNotEmpty &&
          it.harness.playback.played.last == it.partes[onde].path &&
          it.harness.playback.sounding,
    );
    if (onde == partesDoEnsaio.length - 1) {
      it.harness.room.listeningUnheardTakeIds = const [];
    }
    await ouvirAteOFim(it, partesDoEnsaio[onde]);
  }
  await waitFor(
    'a primeira escuta acabar e a primeira parte voltar ao ar',
    () =>
        !it.estado.btSoOuvir &&
        it.estado.btPhase == BtPhase.playing &&
        it.harness.playback.sounding,
  );
  return it;
}

void main() {
  test('a frase told with the room counting every part heard lights terminei, '
      'though the telling stopped in the middle of the first part', () async {
    final it = await _ouvidaInteiraPelaSala();

    await traduzirUmTrecho(it, const Duration(seconds: 4));
    await waitFor(
      'a equipe voltar ao círculo',
      () => it.estado.btPhase == BtPhase.playing,
    );

    expect(
      it.estado.canAdvanceToTheVerdict,
      isTrue,
      reason:
          'o terminei esperava a tradução chegar ao fim da parte, com a sala '
          'já contando tudo ouvido',
    );
  });

  test('a room still naming a part unheard keeps terminei dark, though the '
      'last part played to its end here and every part was told', () async {
    final it = await _ouvidaInteiraPelaSala();
    it.harness.room.listeningUnheardTakeIds = [it.partes[2].takeId!];

    for (final quanto in partesDoEnsaio) {
      await ouvirETraduzirAParteInteira(it, quanto);
    }
    await waitFor('a última parte acabar', () => it.estado.btClipEnded);
    await settle();

    expect(
      it.estado.canAdvanceToTheVerdict,
      isFalse,
      reason:
          'o fim da última parte no tablet acendia o terminei com a sala '
          'ainda contando a terceira parte sem ouvir',
    );
  });

  test('a part playing with the room counting every part heard leaves '
      'terminei lit, and a tap silences it and sends the check', () async {
    final it = await _ouvidaInteiraPelaSala();
    await traduzirUmTrecho(it, const Duration(seconds: 4));
    await waitFor(
      'a equipe voltar ao círculo',
      () => it.estado.btPhase == BtPhase.playing,
    );
    if (!it.estado.btClipRodando) it.sala.ouvirGravacao();
    await waitFor('a parte tocar', () => it.estado.btClipRodando);

    expect(
      it.estado.canAdvanceToTheVerdict,
      isTrue,
      reason: 'o terminei apagava enquanto a gravação tocava',
    );

    final enviadas = it.harness.room.playedByTakeSent.length;
    await it.sala.finishBackTranslation();
    expect(it.harness.room.playedByTakeSent.length, enviadas + 1);
    expect(it.harness.playback.sounding, isFalse);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
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
  test('a frase told after the first listen keeps terminei dark with the room '
      'counting every part heard, until the telling plays the recording '
      'through', () async {
    final it = await _ouvidaInteiraPelaSala();

    await traduzirUmTrecho(it, const Duration(seconds: 4));
    await waitFor(
      'a equipe voltar ao círculo',
      () => it.estado.btPhase == BtPhase.playing,
    );
    await settle();

    expect(it.estado.btOuvidaInteira, isTrue);
    expect(
      it.estado.canAdvanceToTheVerdict,
      isFalse,
      reason:
          'a primeira escuta contava como ouvida na tradução, e a dela conta '
          'só o que tocou desde que a tradução começou',
    );

    for (final quanto in partesDoEnsaio) {
      await ouvirAteOFim(it, quanto);
    }
    await settle();
    expect(it.estado.canAdvanceToTheVerdict, isTrue);
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
    await ouvirAteOFim(it, partesDoEnsaio[0]);
    await ouvirAteOFim(it, partesDoEnsaio[1]);
    await theClipOpens(it.harness);
    await waitFor('a terceira parte tocar', () => it.estado.btClipRodando);
    it.harness.playback.at =
        partesDoEnsaio[2] - const Duration(milliseconds: 500);
    it.sala.ouvirGravacao();
    await waitFor('a parte pausar', () => !it.harness.playback.sounding);
    it.sala.ouvirGravacao();
    await waitFor('a parte seguir', () => it.estado.btClipRodando);

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

  test('a check the room refuses as a part unheard darkens terminei until the '
      'room counts that part heard, though it had counted it before', () async {
    final it = await _ouvidaInteiraPelaSala();
    for (final quanto in partesDoEnsaio) {
      await ouvirETraduzirAParteInteira(it, quanto);
    }
    await settle();
    expect(it.estado.canAdvanceToTheVerdict, isTrue);
    it.harness.room
      ..verdictRefusal = CheckRefusal.partUnheard
      ..verdictFixedLine = 'P2'
      ..verdictUnheardTakeIds = [it.partes[2].takeId!]
      ..holdNextListening();

    await pedirOVeredito(it);
    await settle();

    expect(
      it.estado.canAdvanceToTheVerdict,
      isFalse,
      reason:
          'a recusa da sala por uma parte sem ouvir deixava o terminei aceso '
          'pela contagem de antes',
    );

    it.harness.room.finishHeldListening();
    await settle(const Duration(milliseconds: 400));
    expect(it.estado.canAdvanceToTheVerdict, isTrue);
  });

  test('the room\'s count of a passage the team left, answered late, is never '
      'the count of what stands on the tablet next', () async {
    final it = await _ouvidaInteiraPelaSala();
    await traduzirUmTrecho(it, const Duration(seconds: 4));
    expect(it.estado.btOuvidaInteira, isTrue);
    final relatos = it.harness.room.listeningReports.length;
    it.harness.room.holdNextListening();

    it.sala.leaveThePassage();
    await waitFor(
      'o relato da passagem deixada sair',
      () => it.harness.room.listeningReports.length > relatos,
    );
    expect(it.estado.sessionId, isNull);
    it.harness.room.finishHeldListening();
    await settle();

    expect(
      it.estado.btOuvidaInteira,
      isNull,
      reason:
          'a resposta atrasada da passagem deixada valia como a contagem da '
          'que veio depois',
    );
  });
}

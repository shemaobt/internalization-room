import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show settle;
import 'um_ensaio_de_tres_partes.dart';

Future<Sala> _recusadoPelaP2(List<String> Function(Sala it) nomeadas) async {
  final it = await umEnsaioDeTresPartesContadoInteiro();
  it.harness.room
    ..verdictRefusal = CheckRefusal.partUnheard
    ..verdictFixedLine = 'P2'
    ..verdictUnheardTakeIds = nomeadas(it)
    ..listeningUnheardTakeIds = nomeadas(it);
  await pedirOVeredito(it);
  return it;
}

void main() {
  test('a re-read right after her P2 that counts every part heard clears '
      'the line and lights terminei, with nothing played', () async {
    final it = await umEnsaioDeTresPartesContadoInteiro();
    it.harness.room
      ..verdictRefusal = CheckRefusal.partUnheard
      ..verdictFixedLine = 'P2'
      ..verdictUnheardTakeIds = [it.partes[2].takeId!]
      ..listeningUnheardTakeIds = const [];
    final tocadas = it.harness.playback.played.length;

    await pedirOVeredito(it);
    await settle();

    expect(
      it.estado.btRecusa,
      isNull,
      reason:
          'o relato que ainda chegava quando o terminei foi conferido já '
          'contava tudo ouvido, e a linha de que falta ouvir ficava',
    );
    expect(
      it.estado.canFinishBackTranslation,
      isTrue,
      reason: 'a sala já conta tudo ouvido, e o terminei seguia apagado',
    );
    expect(it.harness.playback.played.length, tocadas);
  });

  test('a room that still counts a part unheard keeps her line, and the '
      're-read a moment later that counts it heard clears it', () async {
    final it = await _recusadoPelaP2((it) => [it.partes[2].takeId!]);
    await settle();

    expect(it.estado.btRecusa, CheckRefusal.partUnheard);
    expect(it.estado.canFinishBackTranslation, isFalse);

    it.harness.room.listeningUnheardTakeIds = const [];
    await settle(const Duration(milliseconds: 400));

    expect(
      it.estado.btRecusa,
      isNull,
      reason:
          'a sala só perguntava uma vez, e um relato que chegou logo depois '
          'deixava a linha de que falta ouvir até a gravação tocar de novo',
    );
    expect(it.estado.canFinishBackTranslation, isTrue);
  });

  test(
    'a re-read that lands after the team pressed play leaves the replay '
    'playing and her line standing, with terminei lit by the room\'s count',
    () async {
      final it = await umEnsaioDeTresPartesContadoInteiro();
      it.harness.room
        ..verdictRefusal = CheckRefusal.partUnheard
        ..verdictFixedLine = 'P2'
        ..verdictUnheardTakeIds = [it.partes[2].takeId!]
        ..listeningUnheardTakeIds = const []
        ..holdNextListening();
      await pedirOVeredito(it);

      it.sala.ouvirGravacao();
      await theClipOpens(it.harness);
      it.harness.room.finishHeldListening();
      await settle();

      expect(
        it.estado.btClipRodando,
        isTrue,
        reason:
            'a resposta atrasada não pode parar a gravação que a equipe pôs',
      );
      expect(
        it.estado.btRecusa,
        CheckRefusal.partUnheard,
        reason:
            'a resposta atrasada apagava a linha no meio da escuta, e a escuta '
            'perdia as partes que ainda vinham',
      );
      expect(
        it.estado.canFinishBackTranslation,
        isTrue,
        reason:
            'a sala já contava tudo ouvido e o terminei esperava a escuta acabar',
      );
    },
  );

  test('a P2 naming a part this tablet does not hold leaves terminei dark '
      'and play replays every part, not a terminei lit over her line', () async {
    final it = await _recusadoPelaP2((it) => ['ninguem']);
    final tocadas = it.harness.playback.played.length;

    expect(
      it.estado.canFinishBackTranslation,
      isFalse,
      reason:
          'com a parte nomeada fora do tablet o terminei ficava aceso debaixo '
          'da linha de que falta ouvir',
    );
    expect(it.harness.playback.played.length, tocadas);

    it.sala.ouvirGravacao();
    await theClipOpens(it.harness);
    expect(it.harness.playback.played.skip(tocadas), [it.partes[0].path]);
  });

  test('a replay after her P2 held mid-part goes on with that part at the '
      'next tap, not with the next part', () async {
    final it = await _recusadoPelaP2((it) => [it.partes[2].takeId!]);
    final tocadas = it.harness.playback.played.length;

    it.sala.ouvirGravacao();
    await theClipOpens(it.harness);
    it.harness.playback.at = const Duration(seconds: 4);
    it.sala.ouvirGravacao();
    await waitFor('a gravação parar', () => it.estado.btClipPausada);
    it.sala.ouvirGravacao();
    await waitFor('a gravação voltar', () => it.estado.btClipRodando);

    expect(
      it.harness.playback.played.skip(tocadas),
      [it.partes[0].path],
      reason:
          'o segundo toque pulava para a parte seguinte, e o resto da '
          'primeira se perdia',
    );
    expect(it.estado.btClipPausada, isFalse);
  });

  test('after her P2 a tap on play replays the recording from its first '
      'part, not only the part the room named', () async {
    final it = await _recusadoPelaP2((it) => [it.partes[2].takeId!]);
    final tocadas = it.harness.playback.played.length;

    it.sala.ouvirGravacao();
    await theClipOpens(it.harness);
    expect(
      it.harness.playback.played.skip(tocadas),
      [it.partes[0].path],
      reason: 'o play depois da P2 seguia da parte onde a escuta tinha parado',
    );
    await ouvirAteOFim(it, partesDoEnsaio[0]);
    await waitFor(
      'a segunda parte entrar no ar',
      () => it.harness.playback.played.length == tocadas + 2,
    );
    await ouvirAteOFim(it, partesDoEnsaio[1]);
    await waitFor(
      'a terceira parte entrar no ar',
      () => it.harness.playback.played.length == tocadas + 3,
    );
    expect(
      it.estado.canFinishBackTranslation,
      isFalse,
      reason: 'no meio da escuta de novo o terminei acendia',
    );
    it.harness.room.listeningUnheardTakeIds = const [];
    await ouvirAteOFim(it, partesDoEnsaio[2]);

    expect(
      it.harness.playback.played.skip(tocadas),
      [for (final parte in it.partes) parte.path],
      reason:
          'a sala tocava só a parte nomeada, fora do contexto; a dela toca a '
          'gravação de novo do começo',
    );
    expect(it.harness.playback.playedFrom.skip(tocadas), [
      Duration.zero,
      Duration.zero,
      Duration.zero,
    ]);
    expect(
      it.estado.btRecusa,
      isNull,
      reason: 'ouvida a gravação inteira, a linha de que falta ouvir ficava',
    );
    expect(
      it.estado.canFinishBackTranslation,
      isTrue,
      reason: 'ouvida a gravação inteira, o terminei não voltava',
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';

import 'fakes.dart';
import 'um_ensaio_de_tres_partes.dart';

Future<Sala> _recusadoPelaP2(List<String> Function(Sala it) nomeadas) async {
  final it = await umEnsaioDeTresPartesContadoInteiro();
  it.harness.room
    ..verdictRefusal = CheckRefusal.partUnheard
    ..verdictFixedLine = 'P2'
    ..verdictUnheardTakeIds = nomeadas(it);
  await pedirOVeredito(it);
  return it;
}

void main() {
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

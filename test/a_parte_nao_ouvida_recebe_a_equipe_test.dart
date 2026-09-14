import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';

/// A rehearsal of three parts of three different lengths. Three, because the part the
/// room's refusal names has to be able to have neighbours on both sides of it.
const partesDoEnsaio = [
  Duration(seconds: 10),
  Duration(seconds: 8),
  Duration(seconds: 12),
];

/// The line the room says when it answers a *terminei*, whatever the answer turns out to
/// be. The refusal carries no line of its own: the server composed this one for it.
const falaDoVeredito = '/api/internalization-room/voice/veredito';

class Sala {
  final SalaHarness harness;

  /// Not final: a tablet closed and opened again on the same passage is a new container
  /// over the same doubles, and the ruler after a mend is read across that seam.
  ProviderContainer container;

  Sala(this.harness, this.container);

  SalaSessionNotifier get sala => container.read(salaSessionProvider.notifier);

  SalaSessionState get estado => container.read(salaSessionProvider);

  List<KeptTake> get partes => estado.partes;
}

Future<void> gravarUmaParte(Sala it) async {
  final antes = it.estado.keptTakes.length;
  it.sala.ensaioTap();
  await waitFor(
    'a gravação da parte começar',
    () => it.estado.ensaio == EnsaioStatus.recording,
  );
  it.sala.ensaioTap();
  await waitFor(
    'a gravação da parte terminar',
    () => it.estado.ensaio == EnsaioStatus.recorded,
  );
  it.sala.takeKeep();
  await waitFor('a sala nomear a parte nova', () {
    final takes = it.estado.keptTakes;
    return takes.length == antes + 1 && takes.last.takeId != null;
  });
}

/// Translate the part in the air whole: the cut is made at its end, so what the team told
/// back of it runs from its own nought to its own length.
Future<void> ouvirETraduzirAParteInteira(Sala it, Duration quanto) async {
  final antes = it.estado.btTrechos.length;
  it.harness.playback.length = quanto;
  it.harness.playback.at = quanto;
  it.sala.cortarTrecho();
  await waitFor(
    'o microfone abrir no trecho',
    () => it.estado.btPhase == BtPhase.capturing,
  );
  it.sala.retroTap();
  await waitFor(
    'o trecho traduzido entrar no colar',
    () => it.estado.btTrechos.length == antes + 1,
  );
  it.harness.playback.finishPlayback();
  await waitFor(
    'a parte terminar',
    () => it.estado.btParteFronteira || it.estado.btClipEnded,
  );
}

/// The rehearsal recorded in three parts, every one of them told back whole and played to
/// its end, standing with *terminei* lit and nothing pressed yet.
Future<Sala> umEnsaioDeTresPartesContadoInteiro({
  String? compoeEm,
  Duration? tetoDaEspera,
}) async {
  final harness = SalaHarness(busyCeiling: tetoDaEspera)
    ..room.composesInto = compoeEm;
  final container = harness.container();
  addTearDown(container.dispose);
  final it = Sala(harness, container);

  await it.sala.goConversa(pericope: 'P01');
  await waitFor('a sala abrir', () => it.estado.sessionId != null);
  it.sala.goEnsaio();
  for (var onde = 0; onde < partesDoEnsaio.length; onde++) {
    await gravarUmaParte(it);
  }
  final partes = it.estado.keptTakes;
  for (var onde = 0; onde < partesDoEnsaio.length; onde++) {
    harness.playback.lengths[partes[onde].path] = partesDoEnsaio[onde];
  }

  it.sala.startRetro();
  await waitFor(
    'a tradução começar a tocar a primeira parte',
    () =>
        it.estado.stage == SalaStage.retro &&
        it.estado.btPhase == BtPhase.playing,
  );

  for (var onde = 0; onde < partesDoEnsaio.length; onde++) {
    await ouvirETraduzirAParteInteira(it, partesDoEnsaio[onde]);
    if (onde < partesDoEnsaio.length - 1) {
      it.sala.proximaParte();
      await waitFor(
        'a parte seguinte entrar no ar',
        () => !it.estado.btParteFronteira,
      );
    }
  }
  return it;
}

Future<void> pedirOVeredito(Sala it) async {
  await it.sala.finishBackTranslation();
  await waitFor(
    'a sala voltar do veredito',
    () => it.estado.btPhase != BtPhase.thinking,
  );
}

void main() {
  test('a recusa nomeia a terceira parte e a equipe cai nela do começo',
      () async {
    final it = await umEnsaioDeTresPartesContadoInteiro();
    expect(it.estado.canFinishBackTranslation, isTrue,
        reason: 'o ensaio foi ouvido inteiro: é daqui que a equipe aperta');

    final terceira = it.partes[2];
    it.harness.room
      ..verdictChecked = false
      ..verdictUnheardTakeIds = [terceira.takeId!];
    final falasAntes = it.harness.voice.played.length;

    await pedirOVeredito(it);

    expect(it.harness.voice.played.skip(falasAntes), contains(falaDoVeredito),
        reason: 'a sala diz a linha que o servidor mandou com a recusa; '
            'recusar em silêncio deixa a equipe sem saber o que aconteceu');
    expect(it.estado.btPhase, BtPhase.playing,
        reason: 'sair do pensando é o que devolve o toque à equipe: um giro '
            'parado é um botão morto');
    expect(it.estado.btFindings, isEmpty,
        reason: 'uma parte que falta ouvir não é um achado do analista');
    expect(it.harness.playback.played.last, terceira.path,
        reason: 'a equipe cai na parte que o servidor nomeou');
    expect(it.harness.playback.playedFrom.last, Duration.zero,
        reason: 'a recusa é sobre ouvir, não sobre contar: começar depois do '
            'chão já traduzido tocaria silêncio, o relato diria a parte '
            'inteira ouvida e o mesmo terminei seria recusado de novo');
    expect(it.estado.btClipRodando, isTrue,
        reason: 'a parte entra no ar sozinha, sem mais um toque');
    expect(it.estado.btOuvidoMs, 18000,
        reason: 'a cabeça de leitura do colar senta no começo da terceira '
            'parte, que é onde as duas primeiras acabam');
  });

  test('um id que nenhuma parte tem chama uma pessoa', () async {
    final it = await umEnsaioDeTresPartesContadoInteiro();
    final tocadas = it.harness.playback.played.length;

    it.harness.room
      ..verdictChecked = false
      ..verdictUnheardTakeIds = ['ninguem'];
    await pedirOVeredito(it);

    expect(it.estado.needsPerson, isTrue,
        reason: 'um nome que este tablet não sabe virar parte nenhuma é uma '
            'pessoa, e não uma tela a mais para a equipe adivinhar');
    expect(it.estado.btPhase, isNot(BtPhase.thinking),
        reason: 'a sala parada não pode ficar por baixo de um giro que não '
            'aceita toque');
    expect(it.harness.playback.played.length, tocadas,
        reason: 'não há parte em que cair, então nada entra no ar');
  });

  test('a parte que a equipe ouviu inteira volta ao relato e terminei abre de '
      'novo', () async {
    final it = await umEnsaioDeTresPartesContadoInteiro();
    final terceira = it.partes[2];
    it.harness.room
      ..verdictChecked = false
      ..verdictUnheardTakeIds = [terceira.takeId!];
    await pedirOVeredito(it);

    it.harness.playback.length = partesDoEnsaio[2];
    it.harness.playback.at = partesDoEnsaio[2];
    it.harness.playback.finishPlayback();
    await waitFor('a terceira parte acabar', () => it.estado.btClipEnded);

    expect(it.estado.canFinishBackTranslation, isTrue,
        reason: 'ouvida a parte que faltava, o terminei acende de novo: o '
            'aperto não foi gasto pela recusa');

    it.harness.room.verdictUnheardTakeIds = const [];
    await pedirOVeredito(it);

    expect(it.harness.room.playedByTakeSent.last.last, {
      'take_id': terceira.takeId,
      'played_ranges': [
        [0, 12000]
      ],
      'clip_duration_ms': 12000,
    }, reason: 'a escuta da parte em que a equipe caiu abriu no zero dela, '
        'então o relato seguinte a cobre inteira');
    expect(it.estado.btPhase, BtPhase.findings,
        reason: 'sem recusa, o mesmo aperto chega ao veredito como sempre');
  });

  test('uma recusa atrasada não muda nada', () async {
    final it = await umEnsaioDeTresPartesContadoInteiro(
      tetoDaEspera: const Duration(seconds: 2),
    );
    final terceira = it.partes[2];
    final tocadas = it.harness.playback.played.length;

    it.harness.room
      ..verdictChecked = false
      ..verdictUnheardTakeIds = [terceira.takeId!];
    it.harness.voice.holdNextFetch();

    final aperto = it.sala.finishBackTranslation();
    await waitFor(
      'a sala desistir da espera e chamar uma pessoa',
      () => it.estado.needsPerson,
    );
    it.harness.voice.finishHeldFetch();
    await aperto;

    expect(it.harness.playback.played.length, tocadas,
        reason: 'a sala já desistiu desta espera e parou para uma pessoa: a '
            'resposta que chega depois é de uma pergunta que não está mais '
            'de pé, e pôr uma parte no ar por causa dela tira a equipe de '
            'uma sala parada sem ninguém ter vindo');
    expect(it.estado.needsPerson, isTrue,
        reason: 'e a sala parada continua parada até o balcão atender');
  });
}

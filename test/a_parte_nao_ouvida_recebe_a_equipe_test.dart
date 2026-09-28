import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'um_ensaio_de_tres_partes.dart';

void main() {
  test(
    'a recusa nomeia a terceira parte e a equipe cai nela do começo',
    () async {
      final it = await umEnsaioDeTresPartesContadoInteiro();
      expect(
        it.estado.canFinishBackTranslation,
        isTrue,
        reason: 'o ensaio foi ouvido inteiro: é daqui que a equipe aperta',
      );

      final terceira = it.partes[2];
      it.harness.room
        ..verdictChecked = false
        ..verdictUnheardTakeIds = [terceira.takeId!];
      final falasAntes = it.harness.voice.played.length;

      await pedirOVeredito(it);

      expect(
        it.harness.voice.played.skip(falasAntes),
        contains(falaDaParteNaoOuvida),
        reason:
            'a sala diz a linha que o servidor compôs para esta recusa, e '
            'não a de um veredito qualquer; recusar em silêncio deixa a equipe '
            'sem saber o que aconteceu',
      );
      expect(
        it.estado.btPhase,
        BtPhase.playing,
        reason:
            'sair do pensando é o que devolve o toque à equipe: um giro '
            'parado é um botão morto',
      );
      expect(
        it.harness.playback.played.last,
        terceira.path,
        reason: 'a equipe cai na parte que o servidor nomeou',
      );
      expect(
        it.harness.playback.playedFrom.last,
        Duration.zero,
        reason:
            'a recusa é sobre ouvir, não sobre contar: começar depois do '
            'chão já traduzido tocaria silêncio, o relato diria a parte '
            'inteira ouvida e o mesmo terminei seria recusado de novo',
      );
      expect(
        it.estado.btClipRodando,
        isTrue,
        reason: 'a parte entra no ar sozinha, sem mais um toque',
      );
      expect(
        it.estado.btOuvidoMs,
        18000,
        reason:
            'a cabeça de leitura do colar senta no começo da terceira '
            'parte, que é onde as duas primeiras acabam',
      );
    },
  );

  test(
    'um corte depois do pouso não devolve à sala o chão já traduzido',
    () async {
      final it = await umEnsaioDeTresPartesContadoInteiro();
      final terceira = it.partes[2];
      it.harness.room
        ..verdictChecked = false
        ..verdictUnheardTakeIds = [terceira.takeId!];
      await pedirOVeredito(it);

      final trechos = it.estado.btTrechos.length;
      final pedacos = it.harness.room.chunksSent;
      it.harness.playback.at = const Duration(seconds: 3);
      it.sala.cortarTrecho();
      it.sala.retroTap();

      expect(
        it.estado.btPhase,
        isNot(BtPhase.capturing),
        reason:
            'o som voltou ao começo da parte mas a tradução não: a tesoura '
            'atrás do cursor mandaria à sala, como trecho novo, o chão que a '
            'equipe já traduziu — a fala dela devolvida uma segunda vez',
      );
      expect(it.estado.btTrechos.length, trechos);
      expect(it.harness.room.chunksSent, pedacos);
    },
  );

  test('um id que nenhuma parte tem chama uma pessoa', () async {
    final it = await umEnsaioDeTresPartesContadoInteiro();
    final tocadas = it.harness.playback.played.length;

    it.harness.room
      ..verdictChecked = false
      ..verdictUnheardTakeIds = ['ninguem'];
    await pedirOVeredito(it);

    expect(
      it.estado.needsPerson,
      isTrue,
      reason:
          'um nome que este tablet não sabe virar parte nenhuma é uma '
          'pessoa, e não uma tela a mais para a equipe adivinhar',
    );
    expect(
      it.estado.btPhase,
      isNot(BtPhase.thinking),
      reason:
          'a sala parada não pode ficar por baixo de um giro que não '
          'aceita toque',
    );
    expect(
      it.harness.playback.played.length,
      tocadas,
      reason: 'não há parte em que cair, então nada entra no ar',
    );
  });

  test('a parte que a equipe ouviu inteira volta ao relato e terminei abre de '
      'novo', () async {
    final it = await umEnsaioDeTresPartesContadoInteiro();
    final terceira = it.partes[2];
    it.harness.room
      ..verdictChecked = false
      ..verdictUnheardTakeIds = [terceira.takeId!];
    await pedirOVeredito(it);

    expect(
      it.estado.canFinishBackTranslation,
      isFalse,
      reason:
          'a parte acabou de entrar no ar e ninguém a ouviu ainda: um '
          'terminei que continua aceso é a equipe apertando de novo e '
          'ouvindo a mesma recusa, sem fim',
    );

    it.harness.playback.at = const Duration(seconds: 4);
    it.sala.ouvirGravacao();
    await waitFor('a gravação parar', () => !it.estado.btClipRodando);
    it.sala.ouvirGravacao();
    await waitFor('a gravação voltar', () => it.estado.btClipRodando);

    it.harness.playback.length = partesDoEnsaio[2];
    it.harness.playback.at = partesDoEnsaio[2];
    it.harness.playback.finishPlayback();
    await waitFor('a terceira parte acabar', () => it.estado.btClipEnded);

    expect(
      it.estado.canFinishBackTranslation,
      isTrue,
      reason:
          'ouvida a parte que faltava, o terminei acende de novo: o '
          'aperto não foi gasto pela recusa',
    );

    it.harness.room.verdictUnheardTakeIds = const [];
    await pedirOVeredito(it);

    expect(
      it.harness.room.playedByTakeSent.last.last,
      {
        'take_id': terceira.takeId,
        'played_ranges': [
          [0, 12000],
        ],
        'clip_duration_ms': 12000,
      },
      reason:
          'a escuta da parte em que a equipe caiu abriu no zero dela, '
          'então o relato seguinte a cobre inteira',
    );
    expect(
      it.estado.btPhase,
      BtPhase.findings,
      reason: 'sem recusa, o mesmo aperto chega ao veredito como sempre',
    );
  });

  test(
    'a recusa numa parte do meio também devolve o terminei no fim dela',
    () async {
      final it = await umEnsaioDeTresPartesContadoInteiro();
      final primeira = it.partes[0];
      it.harness.room
        ..verdictChecked = false
        ..verdictUnheardTakeIds = [primeira.takeId!];
      await pedirOVeredito(it);

      expect(it.harness.playback.played.last, primeira.path);
      expect(it.estado.canFinishBackTranslation, isFalse);

      it.harness.playback.length = partesDoEnsaio[0];
      it.harness.playback.at = partesDoEnsaio[0];
      it.harness.playback.finishPlayback();
      await waitFor('a primeira parte acabar', () => !it.estado.btClipRodando);

      expect(
        it.estado.canFinishBackTranslation,
        isTrue,
        reason:
            'a equipe ouviu a parte que o servidor pediu; obrigá-la a '
            'atravessar e ouvir todas as partes depois dela para reaver o '
            'aperto é ouvir a história inteira de novo, que é justamente o que '
            'o salto pelo chão já contado existe para evitar',
      );
      expect(
        it.estado.btParteFronteira,
        isTrue,
        reason:
            'e a travessia continua de pé: quem quiser seguir ouvindo a '
            'parte seguinte não perde o gesto por causa disso',
      );
    },
  );

  test(
    'uma parte que acaba sem o player dizer nada não encolhe o colar',
    () async {
      final it = await umEnsaioDeTresPartesContadoInteiro();
      final terceira = it.partes[2];
      it.harness.room
        ..verdictChecked = false
        ..verdictUnheardTakeIds = [terceira.takeId!];
      await pedirOVeredito(it);

      // The player answering nothing about the clip that just ended: no length, and a
      // position read at that instant that comes back as nought.
      it.harness.playback.length = null;
      it.harness.playback.at = Duration.zero;
      it.harness.playback.finishPlayback();
      await waitFor('a terceira parte acabar', () => it.estado.btClipEnded);

      expect(
        it.estado.btFimDasPartesMs,
        [10000, 18000, 30000],
        reason:
            'uma parte nunca tem zero milissegundo: um zero não é uma '
            'medida, é o player sem resposta, e escrevê-lo por cima do '
            'tamanho que a parte já mostrou encolhe o colar por baixo da '
            'equipe',
      );

      it.harness.room.verdictUnheardTakeIds = const [];
      await pedirOVeredito(it);

      expect(
        it.harness.room.playedByTakeSent.last.last['clip_duration_ms'],
        12000,
        reason:
            'e o mesmo zero não pode entrar no relato: é ele que o '
            'servidor lê para decidir esta recusa, e uma parte ouvida '
            'inteira que se diz de zero milissegundo é o mesmo terminei '
            'recusado outra vez',
      );
    },
  );

  test('a última audição atravessa as partes do começo de cada uma', () async {
    final it = await umEnsaioDeTresPartesContadoInteiro();
    it.harness.room.verdictChecked = true;
    await pedirOVeredito(it);
    expect(
      it.estado.btPhase,
      BtPhase.conferida,
      reason:
          'o cenário é a passagem conferida — se não for, não mede a '
          'última audição',
    );

    final tocadas = it.harness.playback.played.length;
    it.sala.ouvirGravacao();
    await waitFor(
      'a primeira parte entrar no ar',
      () => it.harness.playback.played.length > tocadas,
    );

    expect(it.harness.playback.played.last, it.partes[0].path);
    expect(it.harness.playback.playedFrom.last, Duration.zero);

    it.harness.playback.length = partesDoEnsaio[0];
    it.harness.playback.at = partesDoEnsaio[0];
    it.harness.playback.finishPlayback();
    await waitFor('a travessia abrir', () => it.estado.btParteFronteira);

    it.sala.ouvirGravacao();
    await waitFor(
      'a segunda parte entrar no ar',
      () => it.harness.playback.played.last == it.partes[1].path,
    );

    expect(
      it.harness.playback.playedFrom.last,
      Duration.zero,
      reason:
          'uma parte contada inteira tem o cursor no próprio fim, então '
          'atravessar para ela no cursor abre silêncio: a equipe ouvia a '
          'primeira parte e depois apertava duas vezes para nada. Não há '
          'mais tradução a fazer aqui, e o cursor não quer dizer nada numa '
          'passagem que a sala já conferiu',
    );
  });

  test('um servidor que não manda o campo não recusa nada', () {
    final antigo = BackTranslationVerdict.fromJson(const {
      'audio_url': '/voice/veredito',
      'checked': false,
      'findings_remaining': 0,
    });
    expect(antigo.unheardTakeIds, isEmpty);

    final nulo = BackTranslationVerdict.fromJson(const {
      'audio_url': '/voice/veredito',
      'checked': false,
      'unheard_take_ids': null,
      'findings_remaining': 0,
    });
    expect(
      nulo.unheardTakeIds,
      isEmpty,
      reason:
          'uma recusa só existe quando o servidor a nomeia; lê-la de '
          'uma ausência é a inferência que a sala não faz',
    );

    final nomeadas = BackTranslationVerdict.fromJson(const {
      'audio_url': '/voice/veredito',
      'checked': false,
      'unheard_take_ids': ['t3', 't4'],
      'findings_remaining': 0,
    });
    expect(nomeadas.unheardTakeIds, ['t3', 't4']);
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

    expect(
      it.harness.playback.played.length,
      tocadas,
      reason:
          'a sala já desistiu desta espera e parou para uma pessoa: a '
          'resposta que chega depois é de uma pergunta que não está mais '
          'de pé, e pôr uma parte no ar por causa dela tira a equipe de '
          'uma sala parada sem ninguém ter vindo',
    );
    expect(
      it.estado.needsPerson,
      isTrue,
      reason: 'e a sala parada continua parada até o balcão atender',
    );
  });
}

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'um_ensaio_de_tres_partes.dart';

Map<String, Object?> _ouvida(String takeId, int de, int ate, int quanto) => {
  'take_id': takeId,
  'played_ranges': [
    [de, ate],
  ],
  'clip_duration_ms': quanto,
};

Future<Sala> _naTraducao() async {
  final it = await umEnsaioDeTresPartesGravado();
  it.sala.startRetro();
  await waitFor(
    'a tradução começar a tocar a primeira parte',
    () =>
        it.estado.stage == SalaStage.retro &&
        it.estado.btPhase == BtPhase.playing &&
        it.harness.playback.sounding,
  );
  return it;
}

/// The first part played to its end, then the second crossed into and held four seconds
/// in: what the ledger holds that no part's end has reported yet.
Future<Sala> _umaParteOuvidaEOutraSegurada() async {
  final it = await _naTraducao();
  await ouvirAteOFim(it, partesDoEnsaio[0]);
  await waitFor('a segunda parte entrar no ar', () => it.estado.btClipRodando);
  await theClipOpens(it.harness);
  it.harness.playback.at = const Duration(seconds: 4);
  it.sala.ouvirGravacao();
  await waitFor('a segunda parte parar', () => !it.estado.btClipRodando);
  return it;
}

void main() {
  test('cada parte que acaba chega à sala na hora', () async {
    final it = await _naTraducao();
    final antes = it.harness.room.listeningReports.length;

    await ouvirAteOFim(it, partesDoEnsaio[0]);

    expect(it.harness.room.listeningReports.skip(antes), [
      [_ouvida(it.partes[0].takeId!, 0, 10000, 10000)],
    ]);
    expect(
      it.harness.room.playedByTakeSent,
      isEmpty,
      reason: 'chegou antes de qualquer terminei',
    );
  });

  test('uma parte que acabou antes de o app sair fica relatada', () async {
    final it = await _umaParteOuvidaEOutraSegurada();

    it.sala.theAppWentAway();

    expect(it.harness.room.listeningReports.last, [
      _ouvida(it.partes[0].takeId!, 0, 10000, 10000),
      _ouvida(it.partes[1].takeId!, 0, 4000, 0),
    ]);
  });

  test(
    'sair da passagem relata o que foi ouvido antes de esquecê-lo',
    () async {
      final it = await _umaParteOuvidaEOutraSegurada();
      final primeira = it.partes[0].takeId!;
      final segunda = it.partes[1].takeId!;
      final relatos = it.harness.room.listeningReports.length;

      it.sala.leaveThePassage();
      await waitFor('a escolha abrir', () => it.estado.station is Menu);

      expect(
        it.harness.room.listeningReports.skip(relatos),
        [
          [_ouvida(primeira, 0, 10000, 10000), _ouvida(segunda, 0, 4000, 0)],
        ],
        reason:
            'um relato do que a equipe ouviu, e nenhum depois de a escuta '
            'ser esquecida',
      );
    },
  );

  test('sair da tradução para o ensaio relata o que foi ouvido', () async {
    final it = await _umaParteOuvidaEOutraSegurada();
    final primeira = it.partes[0].takeId!;
    final segunda = it.partes[1].takeId!;
    final relatos = it.harness.room.listeningReports.length;

    it.sala.goEnsaio();

    expect(it.harness.room.listeningReports.skip(relatos).single, [
      _ouvida(primeira, 0, 10000, 10000),
      _ouvida(segunda, 0, 4000, 0),
    ]);
  });

  test('um relato que a sala não recebe não muda nada no tablet', () async {
    final it = await _naTraducao();
    it.harness.room.failListeningWith = const NetworkFailed('sem rede');
    final linhas = it.harness.voice.fixedLines.length;
    final falas = it.harness.voice.played.length;
    final antes = it.harness.room.listeningReports.length;

    for (var onde = 0; onde < partesDoEnsaio.length; onde++) {
      await ouvirAteOFim(it, partesDoEnsaio[onde]);
    }

    expect(
      it.harness.room.listeningReports.skip(antes),
      hasLength(partesDoEnsaio.length),
    );
    expect(it.estado.needsPerson, isFalse);
    expect(it.harness.voice.fixedLines.length, linhas);
    expect(it.harness.voice.played.length, falas);
    expect(it.estado.btClipEnded, isTrue);
    expect(it.estado.canFinishBackTranslation, isTrue);
  });

  test(
    'uma parte ouvida inteira no ensaio, nunca aberta na tradução, conta como ouvida',
    () async {
      final it = await umEnsaioDeTresPartesGravado();

      it.sala.ouvirACena(2);
      await theClipOpens(it.harness);
      it.harness.playback
        ..length = partesDoEnsaio[1]
        ..at = partesDoEnsaio[1]
        ..finishPlayback();
      await waitFor(
        'a parte acabar no ensaio',
        () => it.estado.parteDoEnsaioTocando == null,
      );

      expect(
        it.harness.room.listeningReports.last,
        [_ouvida(it.partes[1].takeId!, 0, 8000, 8000)],
        reason: 'ouvir onde quer que seja, naquela gravação, conta',
      );

      it.sala.startRetro();
      await waitFor(
        'a tradução começar a tocar a primeira parte',
        () =>
            it.estado.stage == SalaStage.retro &&
            it.estado.btPhase == BtPhase.playing,
      );
      await ouvirAteOFim(it, partesDoEnsaio[0]);

      expect(
        it.harness.room.listeningReports.last,
        [
          _ouvida(it.partes[0].takeId!, 0, 10000, 10000),
          _ouvida(it.partes[1].takeId!, 0, 8000, 8000),
        ],
        reason: 'entrar na tradução não esquece o que o ensaio ouviu',
      );
    },
  );

  test(
    'uma parte do ensaio segurada no meio relata o que soou, com o tamanho dela',
    () async {
      final it = await umEnsaioDeTresPartesGravado();
      final segunda = it.partes[1].takeId!;
      it.harness.playback.length = partesDoEnsaio[1];

      it.sala.ouvirACena(2);
      await theClipOpens(it.harness);
      it.harness.playback.at = const Duration(seconds: 3);
      it.sala.ouvirACena(2);
      await waitFor('a parte parar', () => it.estado.takePaused);
      it.sala.theAppWentAway();

      expect(
        it.harness.room.listeningReports.last,
        [_ouvida(segunda, 0, 3000, 8000)],
        reason:
            'o player sabe o tamanho da parte inteira que tocou: escrito na '
            'pausa, a sala julga a parte mesmo sem tamanho medido da gravação',
      );
    },
  );

  test('sair do ensaio com uma parte soando relata o que soou', () async {
    final it = await umEnsaioDeTresPartesGravado();
    final primeira = it.partes[0].takeId!;
    final segunda = it.partes[1].takeId!;

    it.sala.ouvirACena(2);
    await theClipOpens(it.harness);
    it.harness.playback.at = const Duration(seconds: 3);
    it.sala.startRetro();
    await waitFor(
      'a tradução começar a tocar a primeira parte',
      () =>
          it.estado.stage == SalaStage.retro &&
          it.estado.btPhase == BtPhase.playing,
    );
    await ouvirAteOFim(it, partesDoEnsaio[0]);

    expect(it.harness.room.listeningReports.last, [
      _ouvida(primeira, 0, 10000, 10000),
      _ouvida(segunda, 0, 3000, 0),
    ]);
  });

  test(
    'no ensaio, uma parte já contada em trechos relata no tempo do próprio arquivo',
    () async {
      final it = await umEnsaioDeTresPartesGravado();
      it.sala.startRetro();
      await waitFor(
        'a tradução começar a tocar a primeira parte',
        () => it.estado.btPhase == BtPhase.playing,
      );
      await traduzirUmTrecho(it, const Duration(seconds: 4));
      await ouvirETraduzirAParteInteira(it, partesDoEnsaio[0]);
      final primeira = it.partes[0].takeId!;

      it.container.dispose();
      it.container = it.harness.container();
      addTearDown(it.container.dispose);
      await it.sala.abrirEscolha();
      await it.sala.goConversa(book: 'Ruth', pericope: 'P01');
      await waitFor(
        'a retomada cair na tradução',
        () => it.estado.stage == SalaStage.retro,
      );
      it.sala.goEnsaio();
      await waitFor('o ensaio abrir', () => it.estado.station is Ensaio);
      final tocadas = it.harness.playback.played.length;

      it.sala.ouvirACena(1);
      await theClipOpens(it.harness);
      it.harness.playback
        ..length = const Duration(seconds: 4)
        ..at = const Duration(seconds: 4)
        ..finishPlayback();
      await waitFor(
        'o segundo trecho entrar no ar',
        () => it.harness.playback.played.length == tocadas + 2,
      );
      await theClipOpens(it.harness);
      it.harness.playback.at = const Duration(seconds: 2);
      it.sala.ouvirACena(1);
      await waitFor('a parte parar', () => it.estado.takePaused);
      it.sala.theAppWentAway();

      expect(
        it.harness.room.listeningReports.last.where(
          (parte) => parte['take_id'] == primeira,
        ),
        [_ouvida(primeira, 0, 6000, 0)],
        reason:
            'o primeiro trecho soou de 0 a 4 s e o segundo, de 4 s, mais 2 s: '
            'um trecho recortado conta a posição do seu próprio começo, e o '
            'tamanho dele não é o da parte',
      );
    },
  );

  test(
    'o app que sai com uma parte do ensaio soando relata o que ela soou',
    () async {
      final it = await umEnsaioDeTresPartesGravado();
      final segunda = it.partes[1].takeId!;

      it.sala.ouvirACena(2);
      await theClipOpens(it.harness);
      it.harness.playback.at = const Duration(seconds: 6);
      it.sala.theAppWentAway();

      expect(it.harness.room.listeningReports.last, [
        _ouvida(segunda, 0, 6000, 0),
      ]);
    },
  );

  test(
    'o app que sai com uma parte da tradução soando relata o que ela soou',
    () async {
      final it = await _naTraducao();
      final primeira = it.partes[0].takeId!;

      await theClipOpens(it.harness);
      it.harness.playback.at = const Duration(seconds: 6);
      it.sala.theAppWentAway();

      expect(it.harness.room.listeningReports.last, [
        _ouvida(primeira, 0, 6000, 0),
      ]);
    },
  );

  test(
    'o app que sai antes de a parte seguinte abrir não perde a escuta dela',
    () async {
      final it = await _naTraducao();
      final segunda = it.partes[1].takeId!;
      await theClipOpens(it.harness);
      it.harness.playback.holdNextOpening();
      await ouvirAteOFim(it, partesDoEnsaio[0]);
      await waitFor(
        'a segunda parte ir para o ar',
        () => !it.estado.btParteFronteira,
      );
      it.harness.playback.at = partesDoEnsaio[0];

      it.sala.theAppWentAway();
      it.harness.playback.finishHeldOpening();
      await theClipOpens(it.harness);
      it.harness.playback.at = const Duration(seconds: 5);
      it.sala.ouvirGravacao();
      await waitFor('a segunda parte parar', () => !it.estado.btClipRodando);
      it.sala.theAppWentAway();

      expect(
        it.harness.room.listeningReports.last.where(
          (parte) => parte['take_id'] == segunda,
        ),
        [_ouvida(segunda, 0, 5000, 0)],
        reason:
            'enquanto a parte ainda não abriu, nada soou dela, e o player ainda '
            'responde pela parte anterior: sair ali não mexe na escuta',
      );
    },
  );

  test('«Ouvir tudo» até o fim conta todas as partes como ouvidas', () async {
    final it = await umEnsaioDeTresPartesGravado();

    it.sala.ouvirTudo();
    await ouvirAteOFim(it, partesDoEnsaio[0]);
    await ouvirAteOFim(it, partesDoEnsaio[1]);
    await theClipOpens(it.harness);
    it.harness.playback
      ..length = partesDoEnsaio[2]
      ..at = partesDoEnsaio[2]
      ..finishPlayback();
    await waitFor(
      'a gravação acabar',
      () => it.estado.ouvirTudo == OuvirTudo.acabou,
    );

    expect(it.estado.ouvirTudo, OuvirTudo.acabou);
    expect(it.harness.room.listeningReports.last, [
      for (var n = 0; n < partesDoEnsaio.length; n++)
        _ouvida(
          it.partes[n].takeId!,
          0,
          partesDoEnsaio[n].inMilliseconds,
          partesDoEnsaio[n].inMilliseconds,
        ),
    ]);
  });

  test(
    'sair de «Ouvir tudo» depois da parte 2 conta as duas e o que soou da terceira',
    () async {
      final it = await umEnsaioDeTresPartesGravado();

      it.sala.ouvirTudo();
      await ouvirAteOFim(it, partesDoEnsaio[0]);
      await ouvirAteOFim(it, partesDoEnsaio[1]);
      await theClipOpens(it.harness);
      it.harness.playback.at = const Duration(seconds: 4);
      it.sala.sairDoOuvirTudo();

      expect(it.estado.ouvirTudo, OuvirTudo.fora);
      expect(it.harness.playback.sounding, isFalse);
      expect(it.harness.room.listeningReports.last, [
        for (var n = 0; n < 2; n++)
          _ouvida(
            it.partes[n].takeId!,
            0,
            partesDoEnsaio[n].inMilliseconds,
            partesDoEnsaio[n].inMilliseconds,
          ),
        _ouvida(it.partes[2].takeId!, 0, 4000, 8000),
      ]);
    },
  );

  testWidgets('o app que vai para o fundo manda um relato', (tester) async {
    late Sala it;
    await tester.runAsync(() async {
      it = await umEnsaioGravado(
        partesDoEnsaio,
        numaSala: SalaHarness(filaEmMemoria: true),
      );
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: it.container,
        child: const SalaApp(),
      ),
    );
    await tester.runAsync(() async {
      it.sala.startRetro();
      await waitFor(
        'a tradução começar a tocar a primeira parte',
        () => it.estado.btPhase == BtPhase.playing,
      );
      await ouvirAteOFim(it, partesDoEnsaio[0]);
    });
    final relatos = it.harness.room.listeningReports.length;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(it.harness.room.listeningReports, hasLength(relatos + 1));
    closeTheRoom(it.container);
  });
}

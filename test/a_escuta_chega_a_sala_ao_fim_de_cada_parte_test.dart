import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/domain/station.dart';

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
        it.estado.btPhase == BtPhase.playing,
  );
  return it;
}

Future<void> _ateOFim(Sala it, Duration quanto) async {
  await theClipOpens(it.harness);
  it.harness.playback
    ..length = quanto
    ..at = quanto
    ..finishPlayback();
  await waitFor(
    'a parte acabar',
    () => it.estado.btParteFronteira || it.estado.btClipEnded,
  );
}

/// The first part played to its end, then the second crossed into and held four seconds
/// in: what the ledger holds that no part's end has reported yet.
Future<Sala> _umaParteOuvidaEOutraSegurada() async {
  final it = await _naTraducao();
  await _ateOFim(it, partesDoEnsaio[0]);
  it.sala.ouvirGravacao();
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

    await _ateOFim(it, partesDoEnsaio[0]);

    expect(it.harness.room.listeningReports, [
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

    for (var onde = 0; onde < partesDoEnsaio.length; onde++) {
      await _ateOFim(it, partesDoEnsaio[onde]);
      if (onde < partesDoEnsaio.length - 1) {
        expect(it.estado.btParteFronteira, isTrue);
        it.sala.ouvirGravacao();
        await waitFor(
          'a parte seguinte entrar no ar',
          () => !it.estado.btParteFronteira,
        );
      }
    }

    expect(it.harness.room.listeningReports, hasLength(partesDoEnsaio.length));
    expect(it.estado.needsPerson, isFalse);
    expect(it.estado.offline, isFalse);
    expect(it.harness.voice.fixedLines.length, linhas);
    expect(it.harness.voice.played.length, falas);
    expect(it.estado.btClipEnded, isTrue);
    expect(it.estado.canFinishBackTranslation, isTrue);
  });

  test(
    'uma parte ouvida inteira no ensaio, nunca aberta na tradução, conta como ouvida',
    () async {
      final it = await umEnsaioDeTresPartesGravado();

      it.sala.tocarAParte(1);
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
      await _ateOFim(it, partesDoEnsaio[0]);

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
}

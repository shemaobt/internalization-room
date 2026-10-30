import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show intoTheRecordingHome, settle;
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

Future<void> _umaVidaNovaNaCasa(Sala it) async {
  it.container.invalidate(salaSessionProvider);
  it.container.read(salaSessionProvider);
  await it.sala.openTheRoom();
  await intoTheRecordingHome(it.sala, () => it.estado);
  await waitFor(
    'a mesma sessão voltar à casa',
    () => it.estado.stage == SalaStage.ensaio && it.partes.length == 3,
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

  test('on a quiet return the circle cuts nothing before anything is heard, '
      'whatever the player last stood at', () async {
    final it = await _contadaAteOMeioDaSegunda();
    await _irAoEnsaioEVoltar(it);
    it.harness.playback.at = const Duration(seconds: 7);

    it.sala.retroTap();
    await settle();
    it.sala.retroTap();
    await settle();

    expect(
      it.estado.btPhase,
      BtPhase.playing,
      reason: 'o microfone abria sobre um trecho que ninguém ouviu nesta volta',
    );
    expect(it.estado.btCortado, isFalse);
  });

  test(
    'a room out of reach on the way back still answers with what it last said, '
    'so the return stays quiet instead of playing the next part aloud',
    () async {
      final it = await _contadaAteOMeioDaSegunda();
      it.harness.room.listeningUnheardTakeIds = const [];
      it.sala.goEnsaio();
      await waitFor(
        'a equipe voltar ao ensaio',
        () => it.estado.stage == SalaStage.ensaio,
      );
      await settle();
      final tocadas = it.harness.playback.played.length;
      final falas = it.harness.voice.fixedLines.length;

      it.harness.room.reachable = false;
      it.sala.startRetro();
      await waitFor(
        'a tradução voltar',
        () =>
            it.estado.stage == SalaStage.retro &&
            it.estado.btPhase == BtPhase.playing &&
            !it.estado.awaitingTheGuide,
      );
      await settle();

      expect(
        it.harness.playback.played.skip(tocadas),
        isEmpty,
        reason:
            'sem a sala, a volta tocava a segunda parte em voz alta debaixo da '
            'equipe',
      );
      expect(it.harness.voice.fixedLines.skip(falas), isEmpty);
      expect(it.estado.canListenToThePendingStretch, isTrue);

      it.sala.ouvirGravacao();
      await waitFor(
        'a gravação tocar depois do toque',
        () => it.harness.playback.played.length > tocadas,
      );
      expect(it.harness.playback.played.last, it.partes[1].path);
      expect(it.harness.playback.playedFrom.last, _ateOndeASegundaFoiContada);
    },
  );

  test('what the room answered on a quiet return is still its word on the next '
      'return, when it can no longer be reached', () async {
    final it = await _contadaAteOMeioDaSegunda();
    await _irAoEnsaioEVoltar(it);
    it.harness.room.reachable = false;
    it.sala.goEnsaio();
    await waitFor(
      'a equipe voltar ao ensaio',
      () => it.estado.stage == SalaStage.ensaio,
    );
    await settle();
    final tocadas = it.harness.playback.played.length;

    it.sala.startRetro();
    await waitFor(
      'a tradução voltar',
      () =>
          it.estado.stage == SalaStage.retro &&
          it.estado.btPhase == BtPhase.playing &&
          !it.estado.awaitingTheGuide,
    );
    await settle();

    expect(
      it.harness.playback.played.skip(tocadas),
      isEmpty,
      reason:
          'a resposta da volta anterior se perdia, e a segunda volta sem a '
          'sala tocava em voz alta',
    );
  });

  test('a room out of reach that last named a part unheard sends the return to '
      'the listen it would answer with, not to the told end', () async {
    final it = await _contadaAteOMeioDaSegunda();
    it.harness.room.listeningUnheardTakeIds = [it.partes[2].takeId!];
    it.sala.goEnsaio();
    await waitFor(
      'a equipe voltar ao ensaio',
      () => it.estado.stage == SalaStage.ensaio,
    );
    await settle();
    final tocadas = it.harness.playback.played.length;
    final falas = it.harness.voice.fixedLines.length;

    it.harness.room.reachable = false;
    it.sala.startRetro();
    await waitFor(
      'a escuta voltar ao ar',
      () => it.harness.playback.played.length > tocadas,
    );

    expect(it.harness.voice.fixedLines.skip(falas).map((linha) => linha.$1), [
      'P0',
    ]);
    expect(
      it.harness.playback.played.skip(tocadas).first,
      it.partes[0].path,
      reason:
          'sem a sala, a volta tocava a segunda parte do fim contado, e não a '
          'escuta que a sala pediu',
    );
  });

  test(
    'what the room said of one passage is never its word on the next, so a '
    'room out of reach still plays the new rehearsal from the start',
    () async {
      final it = await _contadaAteOMeioDaSegunda();
      final primeira = it.estado.sessionId;
      it.harness.room.listeningUnheardTakeIds = const [];
      it.sala.leaveThePassage();
      await settle();
      await it.sala.goConversa(book: 'Ruth', pericope: 'P02');
      await waitFor(
        'a outra passagem abrir',
        () => it.estado.sessionId != null && it.estado.sessionId != primeira,
      );
      it.sala.goEnsaio();
      for (var onde = 0; onde < partesDoEnsaio.length; onde++) {
        await gravarUmaParteDoEnsaio(it, onde + 1);
      }
      for (final (onde, parte) in it.partes.indexed) {
        it.harness.playback.lengths[parte.path] = partesDoEnsaio[onde];
      }
      final tocadas = it.harness.playback.played.length;
      final falas = it.harness.voice.fixedLines.length;

      it.harness.room.reachable = false;
      it.sala.startRetro();
      await waitFor(
        'a nova gravação entrar no ar',
        () => it.harness.playback.played.length > tocadas,
      );

      expect(
        it.harness.voice.fixedLines.skip(falas).map((linha) => linha.$1),
        ['P0'],
        reason:
            'a passagem nova herdava o que a sala disse da anterior e pulava a '
            'escuta',
      );
      expect(it.harness.playback.played.skip(tocadas).first, it.partes[0].path);
    },
  );

  test('an answer the room gave before a newer one never takes its place when '
      'it arrives late', () async {
    final it = await _contadaAteOMeioDaSegunda();
    it.harness.room
      ..listeningUnheardTakeIds = [it.partes[2].takeId!]
      ..holdNextListening();
    final relatos = it.harness.room.listeningReports.length;
    it.sala.goEnsaio();
    await waitFor(
      'o relato da saída partir',
      () => it.harness.room.listeningReports.length > relatos,
    );
    await waitFor(
      'a equipe voltar ao ensaio',
      () => it.estado.stage == SalaStage.ensaio,
    );
    it.harness.room.listeningUnheardTakeIds = const [];
    it.sala.startRetro();
    await waitFor(
      'a tradução voltar calada',
      () =>
          it.estado.stage == SalaStage.retro &&
          it.estado.btPhase == BtPhase.playing &&
          !it.estado.awaitingTheGuide,
    );
    await settle();
    it.harness.room.finishHeldListening();
    await settle();
    it.harness.room.reachable = false;
    it.sala.goEnsaio();
    await waitFor(
      'a equipe voltar ao ensaio',
      () => it.estado.stage == SalaStage.ensaio,
    );
    await settle();
    final tocadas = it.harness.playback.played.length;
    final falas = it.harness.voice.fixedLines.length;

    it.sala.startRetro();
    await waitFor(
      'a tradução voltar',
      () =>
          it.estado.stage == SalaStage.retro &&
          it.estado.btPhase == BtPhase.playing &&
          !it.estado.awaitingTheGuide,
    );
    await settle();

    expect(
      it.harness.voice.fixedLines.skip(falas),
      isEmpty,
      reason:
          'a resposta velha chegava por último e levava a equipe a uma escuta '
          'que a sala já tinha contado',
    );
    expect(it.harness.playback.played.skip(tocadas), isEmpty);
  });

  test('a report that lands after its life has ended is never the next life\'s '
      'word from the room', () async {
    final it = await _contadaAteOMeioDaSegunda();
    it.harness.room
      ..listeningUnheardTakeIds = const []
      ..holdNextListening();
    final relatos = it.harness.room.listeningReports.length;
    final terceira = it.partes[2].takeId!;
    it.sala.goEnsaio();
    await waitFor(
      'o relato da saída partir',
      () => it.harness.room.listeningReports.length > relatos,
    );
    it.container.invalidate(salaSessionProvider);
    it.container.read(salaSessionProvider);
    it.harness.room.finishHeldListening();
    await settle();
    it.harness.room.listeningUnheardTakeIds = [terceira];
    await it.sala.abrirEscolha();
    await it.sala.goConversa(book: 'Ruth', pericope: 'P01');
    await intoTheRecordingHome(it.sala, () => it.estado);
    await waitFor(
      'a mesma sessão voltar',
      () => it.estado.stage == SalaStage.ensaio && it.partes.length == 3,
    );
    await settle();
    it.harness.room.reachable = false;
    final tocadas = it.harness.playback.played.length;
    final falas = it.harness.voice.fixedLines.length;

    it.sala.startRetro();
    await waitFor(
      'a escuta voltar ao ar',
      () => it.harness.playback.played.length > tocadas,
    );

    expect(
      it.harness.voice.fixedLines.skip(falas).map((linha) => linha.$1),
      ['P0'],
      reason:
          'o relato da vida que acabou enchia a lembrança da seguinte, e a volta '
          'sem a sala ficava calada sobre uma parte que a sala ainda contava',
    );
    expect(it.harness.playback.played.skip(tocadas).first, it.partes[0].path);
  });

  test(
    'a life that resumed on the home and reported nothing still returns quiet '
    'when the room is out of reach, not playing the told end aloud',
    () async {
      final it = await _contadaAteOMeioDaSegunda();
      it.sala.goEnsaio();
      await waitFor(
        'a equipe voltar ao ensaio',
        () => it.estado.stage == SalaStage.ensaio,
      );
      await settle();
      it.harness.room.listeningUnheardTakeIds = const [];
      await _umaVidaNovaNaCasa(it);
      final tocadas = it.harness.playback.played.length;
      final falas = it.harness.voice.fixedLines.length;

      it.harness.room.reachable = false;
      it.sala.startRetro();
      await waitFor(
        'a tradução voltar',
        () =>
            it.estado.stage == SalaStage.retro &&
            it.estado.btPhase == BtPhase.playing &&
            !it.estado.awaitingTheGuide,
      );
      await settle();

      expect(
        it.harness.playback.played.skip(tocadas),
        isEmpty,
        reason:
            'a vida retomada não guardava nada da sala, e a volta sem rede tocava '
            'a segunda parte em voz alta',
      );
      expect(it.harness.voice.fixedLines.skip(falas), isEmpty);
    },
  );

  test(
    'a life that resumed on the home, where the room still counts a part '
    'unheard, returns out of reach to the listen, not to the told end',
    () async {
      final it = await _contadaAteOMeioDaSegunda();
      it.sala.goEnsaio();
      await waitFor(
        'a equipe voltar ao ensaio',
        () => it.estado.stage == SalaStage.ensaio,
      );
      await settle();
      it.harness.room.listeningUnheardTakeIds = [it.partes[2].takeId!];
      await _umaVidaNovaNaCasa(it);
      final tocadas = it.harness.playback.played.length;
      final falas = it.harness.voice.fixedLines.length;

      it.harness.room.reachable = false;
      it.sala.startRetro();
      await waitFor(
        'a escuta voltar ao ar',
        () => it.harness.playback.played.length > tocadas,
      );

      expect(
        it.harness.voice.fixedLines.skip(falas).map((linha) => linha.$1),
        ['P0'],
        reason:
            'a vida retomada não guardava nada da sala, e a volta sem rede tocava '
            'o fim contado sem a escuta que a sala pedia',
      );
      expect(it.harness.playback.played.skip(tocadas).first, it.partes[0].path);
    },
  );

  test('a life that resumed on the home with nothing told returns out of reach '
      'to the telling line, not to a recording playing with no word', () async {
    final it = await umEnsaioDeTresPartesGravado();
    it.sala.startRetro();
    await waitFor(
      'a tradução começar a tocar a primeira parte',
      () =>
          it.estado.stage == SalaStage.retro &&
          it.estado.btPhase == BtPhase.playing,
    );
    it.sala.goEnsaio();
    await waitFor(
      'a equipe voltar ao ensaio',
      () => it.estado.stage == SalaStage.ensaio,
    );
    await settle();
    it.harness.room.listeningUnheardTakeIds = const [];
    await _umaVidaNovaNaCasa(it);
    final tocadas = it.harness.playback.played.length;
    final falas = it.harness.voice.fixedLines.length;

    it.harness.room.reachable = false;
    it.sala.startRetro();
    await waitFor(
      'a gravação voltar ao ar',
      () => it.harness.playback.played.length > tocadas,
    );

    expect(
      it.harness.voice.fixedLines.skip(falas).map((linha) => linha.$1),
      ['P1'],
      reason:
          'a vida retomada não guardava nada da sala, e a volta sem rede tocava '
          'a gravação sem dizer à equipe que traduzisse',
    );
    expect(it.harness.playback.played.skip(tocadas).first, it.partes[0].path);
  });

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

  test('coming back to a telling stopped in the middle keeps terminei dark '
      'with the room counting every part heard, until the untold rest is '
      'heard here', () async {
    final it = await _contadaAteOMeioDaSegunda();
    await _irAoEnsaioEVoltar(it);

    expect(it.estado.btOuvidaInteira, isTrue);
    expect(
      it.estado.canAdvanceToTheVerdict,
      isFalse,
      reason:
          'a contagem da sala acendia o terminei sobre uma tradução parada no '
          'meio, que a dela só abre com o resto ouvido',
    );
    expect(it.estado.btAindaFaltaOuvir, isTrue);

    it.sala.ouvirGravacao();
    await theClipOpens(it.harness);
    await atravessarAFronteira(it);
    await ouvirAteOFim(it, partesDoEnsaio[2]);
    await settle();

    expect(it.estado.canAdvanceToTheVerdict, isTrue);
  });
}

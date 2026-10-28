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
        await gravarUmaParteDoEnsaio(it);
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
        it.harness.voice.fixedLines.skip(falas),
        isEmpty,
        reason:
            'a passagem nova herdava o que a sala disse da anterior e pulava a '
            'escuta',
      );
      expect(it.harness.playback.played.skip(tocadas).first, it.partes[0].path);
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

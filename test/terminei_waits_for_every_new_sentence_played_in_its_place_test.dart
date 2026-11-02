import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart'
    show holdTheSession, intoTheRecordingHome, settle;
import 'um_ensaio_de_tres_partes.dart';

const _umaParte = [Duration(seconds: 10)];

Future<Sala> _umaParteComAFraseNova({
  required int startsMs,
  required int endsMs,
  String? noTake,
}) async {
  final it = await umEnsaioGravado(_umaParte);
  it.harness.room
    ..listeningUnheardTakeIds = const []
    ..rerecordedSentences.add(
      RerecordedSentence(
        takeId: noTake ?? it.partes[0].takeId!,
        startsMs: startsMs,
        endsMs: endsMs,
      ),
    );
  it.sala.startRetro();
  await waitFor(
    'a tradução começar a tocar a parte',
    () =>
        it.estado.stage == SalaStage.retro &&
        it.estado.btPhase == BtPhase.playing,
  );
  return it;
}

Future<void> _pausarEm(Sala it, Duration em) async {
  it.harness.playback.at = em;
  it.sala.ouvirGravacao();
  await waitFor('a parte pausar', () => !it.harness.playback.sounding);
}

Future<void> _seguirDe(Sala it, Duration em) async {
  it.harness.playback.at = em;
  it.sala.ouvirGravacao();
  await waitFor('a parte seguir', () => it.harness.playback.sounding);
}

void main() {
  test('a sentence laid into a part the team played around keeps terminei dark '
      'until the sentence itself plays here', () async {
    final it = await _umaParteComAFraseNova(startsMs: 2000, endsMs: 2500);
    await traduzirUmTrecho(it, const Duration(seconds: 1));
    await waitFor(
      'a equipe voltar ao círculo',
      () => it.estado.btPhase == BtPhase.playing,
    );
    await theClipOpens(it.harness);
    await waitFor('a parte seguir', () => it.harness.playback.sounding);

    await _pausarEm(it, const Duration(seconds: 2));
    await _seguirDe(it, const Duration(milliseconds: 2500));
    await _pausarEm(it, const Duration(milliseconds: 9800));
    await settle();

    expect(it.estado.btOuvidaInteira, isTrue);
    expect(
      it.estado.canAdvanceToTheVerdict,
      isFalse,
      reason:
          'a parte contava como ouvida inteira dentro da folga de 750 ms, com '
          'a frase regravada de meio segundo nunca tocada no seu lugar',
    );

    await _seguirDe(it, const Duration(seconds: 2));
    await _pausarEm(it, const Duration(milliseconds: 2500));
    await settle();
    expect(it.estado.canAdvanceToTheVerdict, isTrue);
  });

  test('a sentence laid in under a told frase lights terminei on the way back '
      'with nothing of it played here', () async {
    final it = await _umaParteComAFraseNova(startsMs: 2000, endsMs: 2500);
    await ouvirETraduzirAParteInteira(it, _umaParte[0]);
    it.sala.goEnsaio();
    await waitFor(
      'a equipe voltar ao ensaio',
      () => it.estado.stage == SalaStage.ensaio,
    );
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

    expect(it.harness.playback.played.skip(tocadas), isEmpty);
    expect(
      it.estado.canAdvanceToTheVerdict,
      isTrue,
      reason:
          'a frase contada por cima da frase regravada não valia por ela, e o '
          'terminei esperava a gravação tocar de novo sobre o que já foi dito',
    );
  });

  test(
    'the frases told on both sides of a sentence awaiting its translation '
    'do not stand for it: the line under terminei still asks for listening',
    () async {
      final harness = SalaHarness();
      final pasta = Directory.systemTemp.createTempSync('sala-2134');
      addTearDown(() => pasta.deleteSync(recursive: true));
      final caminho = (File(
        '${pasta.path}/p1.wav',
      )..writeAsBytesSync([1, 2, 3])).path;
      await holdTheSession(
        harness,
        ResumePoint(
          sessionId: 'sessao-antiga',
          stage: SalaStage.retro,
          takes: [
            KeptTake(
              scopeId: KeptScope.parte(1),
              path: caminho,
              takeId: 'gravacao-1',
              origin: 'ensaio-da-cena-1',
            ),
          ],
        ),
      );
      harness.room.takes.add(
        const TakeView(
          takeId: 'gravacao-1',
          kind: 'ensaio',
          scope: 'S1',
          ordinal: 1,
          pass: 1,
          origin: 'ensaio-da-cena-1',
        ),
      );
      harness.room
        ..listeningUnheardTakeIds = const []
        ..retroSoFar = const BackTranslationProgress(
          segments: [
            SegmentView(
              segmentId: 'trecho-1',
              takeId: 'gravacao-1',
              startsMs: 0,
              endsMs: 2000,
              frase: 1,
            ),
            SegmentView(
              segmentId: 'trecho-3',
              takeId: 'gravacao-1',
              startsMs: 2500,
              endsMs: 10000,
              frase: 3,
            ),
          ],
          stale: [
            SegmentView(
              segmentId: 'trecho-2',
              takeId: 'gravacao-1',
              startsMs: 2000,
              endsMs: 2500,
              frase: 2,
            ),
          ],
          awaitingSegmentId: 'trecho-2',
          rerecordedSentences: [
            RerecordedSentence(
              takeId: 'gravacao-1',
              startsMs: 2000,
              endsMs: 2500,
            ),
          ],
        );
      harness.playback.lengths[caminho] = _umaParte[0];
      final container = harness.container();
      addTearDown(container.dispose);
      final it = Sala(harness, container);
      await it.sala.openTheRoom();
      await intoTheRecordingHome(it.sala, () => it.estado);

      it.sala.startRetro();
      await waitFor(
        'a tradução voltar sobre a frase que aguarda',
        () =>
            it.estado.stage == SalaStage.retro &&
            it.estado.btPhase == BtPhase.playing &&
            !it.estado.awaitingTheGuide &&
            it.estado.btFraseQueAguarda == 'trecho-2',
      );
      await waitFor('a sala calar', () => it.estado.voice == VoiceState.invite);
      await settle();

      expect(it.estado.btOuvidaInteira, isTrue);
      expect(
        it.estado.btAindaFaltaOuvir,
        isTrue,
        reason:
            'o alcance do chão contado chegava ao fim da parte pelas frases de '
            'cada lado, e a linha de baixo deixava de pedir a escuta da frase '
            'regravada que ninguém tocou',
      );
    },
  );
}

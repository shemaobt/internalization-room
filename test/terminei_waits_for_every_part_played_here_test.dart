import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart'
    show holdTheSession, intoTheRecordingHome, settle;
import 'um_ensaio_de_tres_partes.dart';

const _duasPartes = [Duration(seconds: 10), Duration(seconds: 8)];
const _umaParteCurta = [Duration(seconds: 10), Duration(seconds: 1)];

Future<Sala> _ouvidaInteiraNumaVidaAnterior() async {
  final it = await umEnsaioGravado(_duasPartes);
  it.harness.room.listeningUnheardTakeIds = const [];
  it.sala.startRetro();
  await waitFor(
    'a tradução começar a tocar a primeira parte',
    () =>
        it.estado.stage == SalaStage.retro &&
        it.estado.btPhase == BtPhase.playing,
  );
  for (final quanto in _duasPartes) {
    await ouvirAteOFim(it, quanto);
  }
  await settle();

  it.container.invalidate(salaSessionProvider);
  it.container.read(salaSessionProvider);
  await it.sala.openTheRoom();
  await intoTheRecordingHome(it.sala, () => it.estado);
  await waitFor(
    'a mesma sessão voltar à casa',
    () => it.estado.stage == SalaStage.ensaio && it.partes.length == 2,
  );
  it.sala.startRetro();
  await waitFor(
    'a tradução voltar',
    () =>
        it.estado.stage == SalaStage.retro &&
        it.estado.btPhase == BtPhase.playing &&
        !it.estado.awaitingTheGuide,
  );
  await settle();
  return it;
}

void main() {
  test(
    'a passage the room counted heard in an earlier life keeps terminei '
    'dark after a frase told here, until every part has played here',
    () async {
      final it = await _ouvidaInteiraNumaVidaAnterior();

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
            'a contagem da sala, feita numa visita anterior, acendia o terminei '
            'com uma frase contada e o resto da gravação nunca tocado aqui',
      );

      await ouvirAteOFim(it, _duasPartes[0]);
      await settle();
      expect(it.estado.canAdvanceToTheVerdict, isFalse);

      await ouvirAteOFim(it, _duasPartes[1]);
      await settle();
      expect(it.estado.canAdvanceToTheVerdict, isTrue);
    },
  );

  test('a part paused a second short of its end is still to hear here, and '
      'one paused within her 750 ms slack is not', () async {
    final it = await _ouvidaInteiraNumaVidaAnterior();
    await traduzirUmTrecho(it, const Duration(seconds: 4));
    await waitFor(
      'a equipe voltar ao círculo',
      () => it.estado.btPhase == BtPhase.playing,
    );
    await ouvirAteOFim(it, _duasPartes[0]);
    await theClipOpens(it.harness);
    await waitFor('a segunda parte tocar', () => it.harness.playback.sounding);

    it.harness.playback.at = _duasPartes[1] - const Duration(seconds: 1);
    it.sala.ouvirGravacao();
    await waitFor('a parte pausar', () => !it.harness.playback.sounding);
    await settle();
    expect(
      it.estado.canAdvanceToTheVerdict,
      isFalse,
      reason:
          'um segundo da parte por ouvir acendia o terminei, fora da folga '
          'de 750 ms que a dela dá ao tocador',
    );

    it.sala.ouvirGravacao();
    await waitFor('a parte seguir', () => it.harness.playback.sounding);
    it.harness.playback.at = _duasPartes[1] - const Duration(milliseconds: 500);
    it.sala.ouvirGravacao();
    await waitFor(
      'a parte pausar de novo',
      () => !it.harness.playback.sounding,
    );
    await settle();
    expect(
      it.estado.canAdvanceToTheVerdict,
      isTrue,
      reason:
          'meio segundo da parte por ouvir deixava o terminei apagado, dentro '
          'da folga que a dela dá',
    );
  });

  test('a recording heard whole on an earlier visit of this same opening is '
      'still to hear once the telling begins, as her record counts from '
      'there', () async {
    final it = await umEnsaioGravado(_duasPartes);
    it.harness.room.listeningUnheardTakeIds = const [];
    it.sala.startRetro();
    await waitFor(
      'a tradução começar a tocar a primeira parte',
      () =>
          it.estado.stage == SalaStage.retro &&
          it.estado.btPhase == BtPhase.playing,
    );
    for (final quanto in _duasPartes) {
      await ouvirAteOFim(it, quanto);
    }
    it.sala.goEnsaio();
    await waitFor(
      'a equipe voltar ao ensaio',
      () => it.estado.stage == SalaStage.ensaio,
    );
    it.sala.startRetro();
    await waitFor(
      'a tradução voltar',
      () =>
          it.estado.stage == SalaStage.retro &&
          it.estado.btPhase == BtPhase.playing &&
          !it.estado.awaitingTheGuide,
    );
    await settle();

    await traduzirUmTrecho(it, const Duration(seconds: 4));
    await waitFor(
      'a equipe voltar ao círculo',
      () => it.estado.btPhase == BtPhase.playing,
    );
    await settle();

    expect(
      it.estado.canAdvanceToTheVerdict,
      isFalse,
      reason:
          'o que tocou antes de a tradução começar contava como ouvido nela, '
          'e a dela esquece o registro local quando a tradução começa',
    );
  });

  test('a part a second long is heard here only with half of it played, not '
      'with all but 750 ms of it', () async {
    final it = await umEnsaioGravado(_umaParteCurta);
    it.harness.room.listeningUnheardTakeIds = const [];
    it.sala.startRetro();
    await waitFor(
      'a tradução começar a tocar a primeira parte',
      () =>
          it.estado.stage == SalaStage.retro &&
          it.estado.btPhase == BtPhase.playing,
    );
    await traduzirUmTrecho(it, const Duration(seconds: 4));
    await waitFor(
      'a equipe voltar ao círculo',
      () => it.estado.btPhase == BtPhase.playing,
    );
    await ouvirAteOFim(it, _umaParteCurta[0]);
    await theClipOpens(it.harness);
    await waitFor('a parte curta tocar', () => it.harness.playback.sounding);

    it.harness.playback.at = const Duration(milliseconds: 400);
    it.sala.ouvirGravacao();
    await waitFor('a parte pausar', () => !it.harness.playback.sounding);
    await settle();
    expect(
      it.estado.canAdvanceToTheVerdict,
      isFalse,
      reason:
          'uma parte de um segundo contava como ouvida com 400 ms tocados, '
          'pela folga fixa de 750 ms; a dela dá no máximo metade da parte',
    );

    it.sala.ouvirGravacao();
    await waitFor('a parte seguir', () => it.harness.playback.sounding);
    it.harness.playback.at = const Duration(milliseconds: 600);
    it.sala.ouvirGravacao();
    await waitFor(
      'a parte pausar de novo',
      () => !it.harness.playback.sounding,
    );
    await settle();
    expect(it.estado.canAdvanceToTheVerdict, isTrue);
  });

  test(
    'a joined part told halfway, its told ground heard on the recording '
    'home, is still to hear once the first listen of the other part is over',
    () async {
      final harness = SalaHarness();
      final pasta = Directory.systemTemp.createTempSync('sala-2109');
      addTearDown(() => pasta.deleteSync(recursive: true));
      final caminhos = [
        for (final n in [1, 2])
          (File('${pasta.path}/p$n.wav')..writeAsBytesSync([1, 2, 3])).path,
      ];
      await holdTheSession(
        harness,
        ResumePoint(
          sessionId: 'sessao-antiga',
          stage: SalaStage.retro,
          takes: [
            for (final n in [1, 2])
              KeptTake(
                scopeId: KeptScope.parte(n),
                path: caminhos[n - 1],
                takeId: 'gravacao-$n',
                origin: 'ensaio-da-cena-$n',
              ),
          ],
        ),
      );
      harness.room.takes.addAll([
        for (final n in [1, 2])
          TakeView(
            takeId: 'gravacao-$n',
            kind: 'ensaio',
            scope: KeptScope.parte(n),
            ordinal: n,
            pass: 1,
            origin: 'ensaio-da-cena-$n',
          ),
      ]);
      harness.room
        ..listeningUnheardTakeIds = const ['gravacao-2']
        ..retroSoFar = const BackTranslationProgress(
          segments: [
            SegmentView(
              segmentId: 'trecho-1',
              takeId: 'gravacao-1',
              startsMs: 0,
              endsMs: 5000,
              frase: 1,
            ),
            SegmentView(
              segmentId: 'trecho-2',
              takeId: 'gravacao-2',
              startsMs: 0,
              endsMs: 8000,
              frase: 2,
            ),
          ],
        );
      harness.playback.lengths[caminhos[0]] = _duasPartes[0];
      harness.playback.lengths[caminhos[1]] = _duasPartes[1];
      final container = harness.container();
      addTearDown(container.dispose);
      final it = Sala(harness, container);
      await it.sala.openTheRoom();
      await intoTheRecordingHome(it.sala, () => it.estado);

      it.sala.ouvirACena(1);
      await theClipOpens(harness);
      harness.playback
        ..length = _duasPartes[0]
        ..at = _duasPartes[0]
        ..finishPlayback();
      await settle();

      it.sala.startRetro();
      await waitFor(
        'a primeira escuta tocar a segunda parte',
        () =>
            it.estado.btSoOuvir &&
            harness.playback.sounding &&
            harness.playback.played.last == caminhos[1],
      );
      harness.room.listeningUnheardTakeIds = const [];
      await ouvirAteOFim(it, _duasPartes[1]);
      await waitFor(
        'a tradução abrir depois da escuta',
        () =>
            !it.estado.btSoOuvir &&
            it.estado.btPhase == BtPhase.playing &&
            !it.estado.awaitingTheGuide,
      );
      await settle();

      expect(it.estado.btOuvidaInteira, isTrue);
      expect(
        it.estado.canAdvanceToTheVerdict,
        isFalse,
        reason:
            'a contagem da sala acendia o terminei sobre uma parte contada só '
            'até o meio, com a tradução sem ter tocado o resto dela',
      );
    },
  );
}

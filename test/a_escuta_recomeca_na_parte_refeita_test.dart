import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'um_ensaio_de_tres_partes.dart';

/// The rehearsal told back end to end, standing at the finding on the stretch of part two.
Future<Sala> _aSalaNaPergunta() async {
  final it = await umEnsaioDeTresPartesContadoInteiro(compoeEm: composta);
  it.harness.room
    ..verdictChecked = false
    ..verdictFinding = BtFindingKind.addition
    ..verdictFindingPlace = 1;
  return it;
}

/// The long way, both stations: the mother tongue recorded again, then the telling redone
/// over it. The room rebuilds the part around it and the part becomes that recording.
Future<void> _consertarPeloCaminhoLongo(Sala it) async {
  final semArquivo = it.harness.room.replacesSemArquivo.length;
  it.sala.regravarAVozMaterna();
  it.sala.retroTap();
  await waitFor(
    'o microfone abrir na materna',
    () => it.estado.voice == VoiceState.listening,
  );
  it.sala.retroTap();
  await waitFor(
    'a voz materna nova substituir o trecho',
    () => it.harness.room.replacesSemArquivo.length == semArquivo + 1,
  );
  await waitFor(
    'a segunda estação abrir sozinha',
    () => it.estado.btPhase == BtPhase.capturing,
  );
  final pontes = it.harness.room.replacesAsked.length;
  it.sala.retroTap();
  await waitFor(
    'a ponte nova substituir o trecho',
    () => it.harness.room.replacesAsked.length == pontes + 1,
  );
  await waitFor(
    'a sala voltar do veredito',
    () => it.estado.btPhase != BtPhase.thinking,
  );
  it.harness.playback.lengths[parteDois(it).path] = aComposta;
}

/// Carry the rehearsal to its end from wherever it stands, crossing whatever part
/// boundaries are left. Each part answers with its own length, the way the tablet measures
/// one.
///
/// Only the parts the room actually puts in the air are played: entering the telling-back
/// again steps over every part already told back whole, and marks those heard without
/// playing them. That is the only way this test can reach a rebuilt part at all — **no
/// gesture takes the team back to a part the room has not heard**, which is ENG-890's
/// job, and until it lands the rebuilt part is reported by the step-over or not at all.
Future<void> _ouvirOEnsaioInteiro(Sala it) async {
  while (!it.estado.btClipEnded) {
    final noAr = it.harness.playback.played.last;
    final quanto = it.harness.playback.lengths[noAr]!;
    it.harness.playback.length = quanto;
    it.harness.playback.at = quanto;
    it.harness.playback.finishPlayback();
    await waitFor(
      'a parte terminar',
      () => it.estado.btParteFronteira || it.estado.btClipEnded,
    );
    if (it.estado.btClipEnded) break;
    it.sala.proximaParte();
    await waitFor(
      'a parte seguinte entrar no ar',
      () => !it.estado.btParteFronteira,
    );
  }
}

void main() {
  test('segurar a gravação no meio de uma parte não parte a escuta dela',
      () async {
    final harness = SalaHarness()..playback.length = const Duration(seconds: 10);
    final container = harness.container();
    addTearDown(container.dispose);
    final it = Sala(harness, container);

    await it.sala.goConversa(pericope: 'P01');
    await waitFor('a sala abrir', () => it.estado.sessionId != null);
    it.sala.goEnsaio();
    await gravarUmaParte(it);
    it.sala.startRetro();
    await waitFor(
      'a tradução começar a tocar',
      () =>
          it.estado.stage == SalaStage.retro &&
          it.estado.btPhase == BtPhase.playing,
    );

    harness.playback.at = const Duration(seconds: 4);
    it.sala.ouvirGravacao();
    await waitFor('a gravação parar', () => !it.estado.btClipRodando);
    it.sala.ouvirGravacao();
    await waitFor('a gravação voltar', () => it.estado.btClipRodando);
    harness.playback.finishPlayback();
    await waitFor('a gravação acabar', () => it.estado.btClipEnded);
    await it.sala.finishBackTranslation();
    await waitFor(
      'a sala voltar do veredito',
      () => it.estado.btPhase != BtPhase.thinking,
    );

    expect(harness.room.playedByTakeSent.last, [
      {
        'take_id': harness.room.takeIds.single,
        'played_ranges': [
          [0, 10000]
        ],
        'clip_duration_ms': 10000,
      },
    ], reason: 'a equipe segurou o ensaio uma vez e deixou correr até o fim: '
        'esquecer de reabrir a escuta ao soltar relata a parte até a pausa e o '
        'portão nunca mais deixa a passagem sair');
  });

  test(
      'a escuta das vizinhas sobrevive ao conserto, e a parte refeita volta '
      'ao relato com o nome e o tamanho da composta', () async {
    final it = await _aSalaNaPergunta();
    await pedirOVeredito(it);

    final gravacoes = [for (final parte in it.estado.partes) parte.takeId];
    expect(it.harness.room.playedByTakeSent.last, [
      {
        'take_id': gravacoes[0],
        'played_ranges': [
          [0, 10000]
        ],
        'clip_duration_ms': 10000,
      },
      {
        'take_id': gravacoes[1],
        'played_ranges': [
          [0, 8000]
        ],
        'clip_duration_ms': 8000,
      },
      {
        'take_id': gravacoes[2],
        'played_ranges': [
          [0, 12000]
        ],
        'clip_duration_ms': 12000,
      },
    ], reason: 'o ensaio foi ouvido inteiro, parte por parte, cada uma no '
        'relógio do próprio arquivo');

    await _consertarPeloCaminhoLongo(it);
    expect(parteDois(it).takeId, composta,
        reason: 'o conserto pelo caminho longo compõe uma gravação nova para '
            'a parte, e é ela que passa a ser a parte');

    it.harness.room.verdictChecked = true;
    it.harness.room.verdictFinding = null;
    await pedirOVeredito(it);

    expect(it.harness.room.playedByTakeSent.last, [
      {
        'take_id': gravacoes[0],
        'played_ranges': [
          [0, 10000]
        ],
        'clip_duration_ms': 10000,
      },
      {
        'take_id': gravacoes[2],
        'played_ranges': [
          [0, 12000]
        ],
        'clip_duration_ms': 12000,
      },
    ], reason: 'a parte refeita é outro arquivo e a escuta dela recomeça do '
        'zero; a escuta das vizinhas não tem por que ir junto, e era isso que '
        'um relato só sobre a passagem colada jogava fora');

    it.sala.startRetro();
    await waitFor(
      'a tradução voltar ao ar',
      () =>
          it.estado.stage == SalaStage.retro &&
          it.estado.btPhase == BtPhase.playing &&
          it.harness.playback.played.isNotEmpty,
    );
    await _ouvirOEnsaioInteiro(it);
    await pedirOVeredito(it);

    expect(it.harness.room.playedByTakeSent.last, [
      {
        'take_id': gravacoes[0],
        'played_ranges': [
          [0, 10000]
        ],
        'clip_duration_ms': 10000,
      },
      {
        'take_id': composta,
        'played_ranges': [
          [0, 5000]
        ],
        'clip_duration_ms': 5000,
      },
      {
        'take_id': gravacoes[2],
        'played_ranges': [
          [0, 12000]
        ],
        'clip_duration_ms': 12000,
      },
    ], reason: 'entrando de novo na tradução, o salto marca a parte refeita '
        'como ouvida com o nome da composta e o tamanho dela: a escuta é '
        'rechaveada no arquivo que a parte virou, e os oito segundos do '
        'arquivo que ela substituiu não vêm junto');
  });
}

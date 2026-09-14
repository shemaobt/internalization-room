import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';

/// A rehearsal of three parts of three different lengths, each told back whole in one
/// stretch. Three, because the part that is mended has to have a neighbour on each side.
const _partes = [
  Duration(seconds: 10),
  Duration(seconds: 8),
  Duration(seconds: 12),
];

/// The name the room gives the recording it rebuilds around the mend, and how long that
/// recording is: shorter than the part it takes the place of, so a length carried over
/// from the old file would show.
const _composta = 'C';
const _aComposta = Duration(seconds: 5);

class _Sala {
  final SalaHarness harness;
  final ProviderContainer container;

  _Sala(this.harness, this.container);

  SalaSessionNotifier get sala => container.read(salaSessionProvider.notifier);

  SalaSessionState get estado => container.read(salaSessionProvider);

  KeptTake get parteDois => estado.keptTakes.firstWhere(
        (take) => take.scopeId == KeptScope.parte(2),
      );
}

Future<void> _gravarUmaParte(_Sala it) async {
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

/// Translate the part in the air whole: the cut is made at its end, so what the team heard
/// of it runs from its own nought to its own length.
Future<void> _ouvirETraduzirAParteInteira(_Sala it, Duration quanto) async {
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

/// The rehearsal told back end to end, standing at the finding on the stretch of part two.
Future<_Sala> _aSalaNaPergunta() async {
  final harness = SalaHarness()
    ..room.verdictChecked = false
    ..room.verdictFinding = BtFindingKind.addition
    ..room.verdictFindingPlace = 1
    ..room.composesInto = _composta;
  final container = harness.container();
  addTearDown(container.dispose);
  final it = _Sala(harness, container);

  await it.sala.goConversa(pericope: 'P01');
  await waitFor('a sala abrir', () => it.estado.sessionId != null);
  it.sala.goEnsaio();
  for (var onde = 0; onde < _partes.length; onde++) {
    await _gravarUmaParte(it);
  }
  final partes = it.estado.keptTakes;
  for (var onde = 0; onde < _partes.length; onde++) {
    harness.playback.lengths[partes[onde].path] = _partes[onde];
  }

  it.sala.startRetro();
  await waitFor(
    'a tradução começar a tocar a primeira parte',
    () =>
        it.estado.stage == SalaStage.retro &&
        it.estado.btPhase == BtPhase.playing,
  );

  for (var onde = 0; onde < _partes.length; onde++) {
    await _ouvirETraduzirAParteInteira(it, _partes[onde]);
    if (onde < _partes.length - 1) {
      it.sala.proximaParte();
      await waitFor(
        'a parte seguinte entrar no ar',
        () => !it.estado.btParteFronteira,
      );
    }
  }
  return it;
}

Future<void> _pedirOVeredito(_Sala it) async {
  await it.sala.finishBackTranslation();
  await waitFor(
    'a sala voltar do veredito',
    () => it.estado.btPhase != BtPhase.thinking,
  );
}

/// The long way, both stations: the mother tongue recorded again, then the telling redone
/// over it. The room rebuilds the part around it and the part becomes that recording.
Future<void> _consertarPeloCaminhoLongo(_Sala it) async {
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
  it.harness.playback.lengths[it.parteDois.path] = _aComposta;
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
Future<void> _ouvirOEnsaioInteiro(_Sala it) async {
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
    final it = _Sala(harness, container);

    await it.sala.goConversa(pericope: 'P01');
    await waitFor('a sala abrir', () => it.estado.sessionId != null);
    it.sala.goEnsaio();
    await _gravarUmaParte(it);
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
    await _pedirOVeredito(it);

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
    expect(it.parteDois.takeId, _composta,
        reason: 'o conserto pelo caminho longo compõe uma gravação nova para '
            'a parte, e é ela que passa a ser a parte');

    it.harness.room.verdictChecked = true;
    it.harness.room.verdictFinding = null;
    await _pedirOVeredito(it);

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
    await _pedirOVeredito(it);

    expect(it.harness.room.playedByTakeSent.last, [
      {
        'take_id': gravacoes[0],
        'played_ranges': [
          [0, 10000]
        ],
        'clip_duration_ms': 10000,
      },
      {
        'take_id': _composta,
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

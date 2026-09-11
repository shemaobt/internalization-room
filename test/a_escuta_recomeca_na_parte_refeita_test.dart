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

/// Tell the part in the air back whole: the cut is made at its end, so what the team heard
/// of it runs from its own nought to its own length.
Future<void> _ouvirEContarAParteInteira(_Sala it, Duration quanto) async {
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
    await _ouvirEContarAParteInteira(it, _partes[onde]);
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

void main() {
  test('a escuta das partes vizinhas sobrevive ao conserto de uma delas',
      () async {
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
  });
}

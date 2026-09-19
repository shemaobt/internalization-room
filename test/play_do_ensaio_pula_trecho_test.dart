import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';

/// ENG-824: six rehearsal parts, each told back as exactly one stretch, the
/// last one recounted by the short way. Reproduces the play skipping the one
/// stretch nobody touched.
const _parteLen = Duration(seconds: 10);

class _Sala {
  final SalaHarness harness;
  ProviderContainer container;

  _Sala(this.harness, this.container);

  SalaSessionNotifier get sala => container.read(salaSessionProvider.notifier);

  SalaSessionState get estado => container.read(salaSessionProvider);
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

Future<void> _traduzirUmTrecho(_Sala it, Duration em) async {
  final antes = it.estado.btTrechos.length;
  it.harness.playback.at = em;
  it.sala.cortarTrecho();
  await waitFor(
    'o microfone abrir no trecho',
    () => it.estado.btPhase == BtPhase.capturing,
  );
  it.sala.retroTap();
  await waitFor(
    'o trecho contado entrar no colar',
    () => it.estado.btTrechos.length == antes + 1,
  );
}

Future<void> _atravessarAFronteira(_Sala it) async {
  it.harness.playback.finishPlayback();
  await waitFor('a parte terminar', () => it.estado.btParteFronteira);
  it.sala.ouvirGravacao();
  await waitFor(
    'a parte seguinte entrar no ar',
    () => !it.estado.btParteFronteira,
  );
}

Future<void> _pedirOVeredito(_Sala it) async {
  while (!it.estado.btClipEnded) {
    it.harness.playback.finishPlayback();
    await waitFor(
      'a parte terminar',
      () => it.estado.btParteFronteira || it.estado.btClipEnded,
    );
    if (it.estado.btClipEnded) break;
    it.sala.ouvirGravacao();
    await waitFor(
      'a parte seguinte entrar no ar',
      () => !it.estado.btParteFronteira,
    );
  }
  await it.sala.finishBackTranslation();
  await waitFor(
    'o analista apontar um trecho',
    () =>
        it.estado.btPhase == BtPhase.findings &&
        it.estado.btFindingTrecho != null,
  );
}

/// Six parts recorded, one stretch cut per part, spanning it whole.
Future<_Sala> _seisPartesSeisTrechos() async {
  final harness = SalaHarness()
    ..playback.length = _parteLen
    ..playback.measured = _parteLen
    ..room.verdictChecked = false
    ..room.verdictFinding = BtFindingKind.addition
    ..room.verdictFindingPlace = 2;
  final container = harness.container();
  addTearDown(container.dispose);
  final it = _Sala(harness, container);

  await it.sala.goConversa(pericope: 'P01');
  await waitFor('a sala abrir', () => it.estado.sessionId != null);
  it.sala.goEnsaio();
  for (var i = 0; i < 6; i++) {
    await _gravarUmaParte(it);
  }
  for (final parte in it.estado.keptTakes) {
    harness.playback.lengths[parte.path] = _parteLen;
  }

  it.sala.startRetro();
  await waitFor(
    'a tradução começar a tocar a primeira parte',
    () =>
        it.estado.stage == SalaStage.retro &&
        it.estado.btPhase == BtPhase.playing,
  );

  for (var i = 0; i < 6; i++) {
    await _traduzirUmTrecho(it, _parteLen);
    if (i < 5) await _atravessarAFronteira(it);
  }
  await _pedirOVeredito(it);
  return it;
}

/// Drive the fake player's clip to completion for every stretch the ghost play opens,
/// until it stops on its own or gives up waiting.
Future<void> _tocarOFantasmaAteAcabar(_Sala it) async {
  for (var tentativas = 0;
      tentativas < 12 && it.estado.ensaio == EnsaioStatus.ghostPlaying;
      tentativas++) {
    it.harness.playback.finishPlayback();
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// The short way: the telling redone over the same mother tongue, no re-recording.
Future<void> _traduzirDeNovoPeloCaminhoCurto(_Sala it) async {
  final trecho = it.estado.btFindingTrecho!;
  await it.sala.traduzirDeNovo(trecho);
  await waitFor(
    'o microfone abrir para traduzir de novo',
    () => it.estado.btPhase == BtPhase.capturing,
  );
  it.sala.retroTap();
  await waitFor(
    'a sala voltar do veredito',
    () => it.estado.btPhase != BtPhase.thinking,
  );
}

void main() {
  test(
      'o play do ensaio toca as seis partes, na ordem, incluindo a que '
      'ninguém consertou', () async {
    final it = await _seisPartesSeisTrechos();

    // Trecho 6 (índice 5), traduzido de novo pelo caminho curto.
    await _traduzirDeNovoPeloCaminhoCurto(it);

    expect(it.estado.btPhase, BtPhase.findings,
        reason: 'a sala está de volta às perguntas depois da última correção');

    it.sala.continuarOEnsaio();
    await waitFor(
      'a sala voltar ao ensaio',
      () => it.estado.stage == SalaStage.ensaio,
    );
    it.harness.playback.played.clear();
    it.harness.playback.ranges.clear();

    it.sala.ghostPlay();
    await _tocarOFantasmaAteAcabar(it);

    expect(
      it.estado.ensaio,
      EnsaioStatus.idle,
      reason: 'o play do ensaio deve terminar sozinho depois das seis '
          'partes, não ficar preso',
    );
    expect(
      it.harness.playback.played.length,
      6,
      reason: 'seis partes, seis trechos, seis toques — nenhum pulado em '
          'silêncio',
    );
    expect(
      it.harness.playback.played[1],
      it.estado.partes[1].path,
      reason: 'a parte 2 não foi consertada: o play do ensaio tem de tocar '
          'o arquivo da própria parte, como a retro tocaria',
    );
  });

  test(
      'um trecho sem nenhum áudio local (sem parte) continua '
      'sendo pulado — o único caso em que pula', () async {
    final gravada = File(
      '${Directory.systemTemp.createTempSync('sala-824').path}/p1.m4a',
    )..writeAsBytesSync([1, 2, 3]);
    addTearDown(() => gravada.parent.deleteSync(recursive: true));
    final harness = SalaHarness()
      ..emAberto.rows['Ruth/P01'] = ResumePoint(
        sessionId: 'sessao-antiga',
        stage: SalaStage.retro,
        takes: [
          KeptTake(
            scopeId: KeptScope.parte(1),
            path: gravada.path,
            takeId: 'gravacao-1',
          ),
        ],
      )
      ..room.retroSoFar = const BackTranslationProgress(
        checked: true,
        segments: [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: 'gravacao-1',
            startsMs: 0,
            endsMs: 12000,
          ),
          // Um trecho de uma gravação que este aparelho não tem e por qual
          // parte a sala não disse que ela responde — este é quem deve ser
          // pulado.
          SegmentView(
            segmentId: 'trecho-2',
            takeId: 'gravacao-fantasma',
            startsMs: 0,
            endsMs: 9000,
          ),
        ],
      );
    final container = harness.container();
    addTearDown(container.dispose);
    final it = _Sala(harness, container);

    await it.sala.abrirEscolha();
    await waitFor(
      'a roda dizer que esta passagem tem trabalho parado',
      () => it.estado.comecadas.contains('P01'),
    );
    await it.sala.goConversa(pericope: 'P01');
    await waitFor(
      'a tradução ser retomada com os dois trechos',
      () =>
          it.estado.stage == SalaStage.retro &&
          it.estado.btTrechos.length == 2,
    );
    harness.playback.played.clear();

    it.sala.ghostPlay();
    await _tocarOFantasmaAteAcabar(it);

    expect(
      it.estado.ensaio,
      EnsaioStatus.idle,
      reason: 'o play do ensaio termina mesmo com um trecho sem áudio '
          'nenhum — ele é pulado, não trava a sala',
    );
    expect(
      harness.playback.played,
      [gravada.path],
      reason: 'só o trecho que tem parte local toca; o trecho que aponta '
          'uma gravação que este tablet não tem é o único pulado',
    );
  });
}

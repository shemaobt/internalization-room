import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';

const _umaParte = Duration(seconds: 30);

class _Sala {
  final SalaHarness harness;
  final ProviderContainer container;

  _Sala(this.harness, this.container);

  SalaSessionNotifier get sala => container.read(salaSessionProvider.notifier);

  SalaSessionState get estado => container.read(salaSessionProvider);
}

/// The stretch at one place in the row, whatever the room has renamed it to.
Trecho _no(ProviderContainer container, int lugar) =>
    container.read(salaSessionProvider).btTrechos[lugar];

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

/// Cut a stretch where the part is playing and tell it back.
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

/// A rehearsal of two parts told back in three stretches — one out of the first part, two
/// out of the second — standing at the analyst's finding on the stretch at [lugar].
Future<_Sala> _aSalaNaPergunta({int lugar = 1}) async {
  final harness = SalaHarness()
    ..playback.length = _umaParte
    ..room.verdictChecked = false
    ..room.verdictFinding = BtFindingKind.addition
    ..room.verdictFindingPlace = lugar;
  final container = harness.container();
  addTearDown(container.dispose);
  final it = _Sala(harness, container);

  await it.sala.goConversa();
  await waitFor('a sala abrir', () => it.estado.sessionId != null);
  it.sala.goEnsaio();
  await _gravarUmaParte(it);
  await _gravarUmaParte(it);
  it.sala.startRetro();
  await waitFor(
    'a tradução começar a tocar a primeira parte',
    () =>
        it.estado.stage == SalaStage.retro &&
        it.estado.btPhase == BtPhase.playing,
  );

  await _traduzirUmTrecho(it, const Duration(seconds: 10));
  harness.playback.finishPlayback();
  await waitFor('a primeira parte terminar', () => it.estado.btParteFronteira);
  it.sala.proximaParte();
  await waitFor(
    'a segunda parte entrar no ar',
    () => !it.estado.btParteFronteira,
  );
  await _traduzirUmTrecho(it, const Duration(seconds: 5));
  await _traduzirUmTrecho(it, const Duration(seconds: 12));
  harness.playback.finishPlayback();
  await waitFor('o ensaio inteiro terminar', () => it.estado.btClipEnded);

  await it.sala.finishBackTranslation();
  await waitFor(
    'o analista apontar um trecho',
    () =>
        it.estado.btPhase == BtPhase.findings &&
        it.estado.btFindingTrecho != null,
  );
  return it;
}

/// The long way's first station: the mother tongue of the pointed stretch, recorded again.
Future<void> _regravarAMaterna(_Sala it) async {
  it.sala.regravarAVozMaterna();
  it.sala.retroTap();
  await waitFor(
    'o microfone abrir na materna',
    () => it.estado.voice == VoiceState.listening,
  );
  it.sala.retroTap();
  await waitFor(
    'a segunda estação abrir sozinha',
    () => it.estado.btPhase == BtPhase.capturing,
  );
}

/// Hand the telling over and let the room say what it was worth. `finishBackTranslation`
/// runs on its own at the end of a correction, so this also lands back on the same
/// finding whenever the room's verdict still points at the same place.
Future<void> _entregarAPonte(_Sala it) async {
  final antes = it.harness.room.replacesAsked.length;
  it.sala.retroTap();
  await waitFor(
    'a ponte nova substituir o trecho',
    () => it.harness.room.replacesAsked.length == antes + 1,
  );
  await waitFor(
    'a sala voltar do veredito',
    () => it.estado.btPhase != BtPhase.thinking,
  );
}

void main() {
  test('depois do caminho longo, ouvir a voz materna toca o arquivo novo — não '
      'a parte', () async {
    final it = await _aSalaNaPergunta();
    final antes = _no(it.container, 1);
    final parte1Antes = it.estado.partes[antes.parte].path;

    it.harness.playback.measured = const Duration(seconds: 7);
    await _regravarAMaterna(it);
    final materna = it.harness.recorder.lastPath!;
    await _entregarAPonte(it);

    // Guarda: o lugar no colar não se move por causa do conserto — é o #111,
    // que continua valendo depois desta fatia.
    expect(
      _no(it.container, 1).parte,
      antes.parte,
      reason:
          'lugar (colar) e arquivo (áudio) são coisas separadas agora; '
          'só a segunda muda com o conserto',
    );

    it.harness.playback.played.clear();
    it.harness.playback.ranges.clear();
    it.sala.ouvirVozMaterna();
    await waitFor(
      'o trecho apontado estar tocando',
      () => it.estado.btTrechoTocando,
    );

    expect(
      it.harness.playback.played.last,
      materna,
      reason:
          'o arquivo é achado pelo take do trecho, não pelo índice herdado '
          'do lugar — senão o dublê receberia $parte1Antes, a parte '
          'original',
    );
    expect(it.harness.playback.played.last, isNot(parte1Antes));
    expect(
      it.harness.playback.ranges.last,
      '0-7000',
      reason:
          'a materna nova vai de zero à própria duração, não aos '
          'limites antigos do trecho na parte velha',
    );

    expect(
      it.estado.keptTakes.any((k) => k.path == materna && k.takeId != null),
      isTrue,
      reason:
          'o take corrigido tem de estar guardado — é dali que o resume '
          'lê onde encontrar o áudio certo',
    );
  });

  test(
    'os trechos vizinhos, sem conserto, continuam tocando a parte original',
    () async {
      for (final lugar in [0, 2]) {
        final it = await _aSalaNaPergunta(lugar: lugar);
        final trecho = it.estado.btFindingTrecho!;
        final caminhoDaParte = it.estado.partes[trecho.parte].path;

        it.sala.ouvirVozMaterna();
        await waitFor(
          'o trecho apontado estar tocando',
          () => it.estado.btTrechoTocando,
        );

        expect(
          it.harness.playback.played.last,
          caminhoDaParte,
          reason:
              'o trecho no lugar $lugar não foi consertado; o arquivo '
              'continua sendo o da parte que sempre foi',
        );
        expect(
          it.harness.playback.ranges.last,
          '${trecho.from.inMilliseconds}-${trecho.to.inMilliseconds}',
        );
      }
    },
  );

  test('depois de fechar e reabrir, a correção continua sendo o áudio', () async {
    final it = await _aSalaNaPergunta();
    await _regravarAMaterna(it);
    final materna = it.harness.recorder.lastPath!;
    await _entregarAPonte(it);

    final corrigido = it.estado.keptTakes.firstWhere((k) => k.path == materna);
    expect(corrigido.takeId, isNotNull);
    final segmentIdCorrigido = it.estado.btFindingTrecho!.segmentId!;

    final segmentos = [
      for (final trecho in it.estado.btTrechos)
        SegmentView(
          segmentId: trecho.segmentId!,
          takeId: trecho.takeId,
          startsMs: trecho.from.inMilliseconds,
          endsMs: trecho.to.inMilliseconds,
          told: trecho.contado,
        ),
    ];

    // Uma sala nova: o mesmo tablet, a mesma sessão, reaberta — parada no ensaio, o
    // jeito medido de chegar à retro com os trechos já lidos (test/resto_da_historia_test.dart).
    final harness2 = SalaHarness()
      ..playback.length = const Duration(seconds: 30)
      ..playback.measured = const Duration(seconds: 10)
      ..room.verdictChecked = false
      ..room.verdictFinding = BtFindingKind.addition
      ..room.verdictFindingSegmentId = segmentIdCorrigido
      ..room.retroSoFar = BackTranslationProgress(
        segments: segmentos,
        checked: false,
      );
    harness2.emAberto.rows['Ruth/P01'] = ResumePoint(
      sessionId: 'sessao-retomada',
      stage: SalaStage.ensaio,
      takes: it.estado.keptTakes,
    );
    final container2 = harness2.container();
    addTearDown(container2.dispose);
    final it2 = _Sala(harness2, container2);

    await it2.sala.abrirEscolha();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await it2.sala.goConversa(pericope: 'P01');
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(it2.estado.stage, SalaStage.ensaio);
    expect(
      it2.estado.btTrechos.map((t) => t.takeId),
      contains(corrigido.takeId),
      reason:
          'o trecho corrigido volta amarrado ao take que o servidor deu '
          'para a correção, mesmo antes de a retro ser chamada',
    );

    it2.sala.startRetro();
    await waitFor(
      'a retro retomada começar a tocar',
      () => it2.harness.playback.played.isNotEmpty,
    );
    harness2.playback.finishPlayback();
    await waitFor(
      'o ensaio retomado terminar de tocar',
      () => it2.estado.btClipEnded,
    );
    await it2.sala.finishBackTranslation();
    await waitFor(
      'o analista apontar de novo o trecho corrigido',
      () =>
          it2.estado.btPhase == BtPhase.findings &&
          it2.estado.btFindingTrecho != null,
    );

    it2.sala.ouvirVozMaterna();
    await waitFor(
      'o trecho apontado estar tocando',
      () => it2.estado.btTrechoTocando,
    );

    expect(
      it2.harness.playback.played.last,
      materna,
      reason:
          'o lugar do trecho corrigido é -1 depois de um resume (o take '
          'corrigido não é uma parte da retomada), então quem acha o '
          'arquivo tem de ser o take, não o lugar',
    );
  });

  test('o take corrigido é um take guardado', () async {
    final it = await _aSalaNaPergunta();
    final antes = it.estado.keptTakes.length;

    await _regravarAMaterna(it);
    final materna = it.harness.recorder.lastPath!;
    await _entregarAPonte(it);

    expect(
      it.estado.keptTakes.length,
      antes + 1,
      reason:
          'o take corrigido é um take a mais, guardado ao lado das '
          'partes do ensaio',
    );
    final corrigido = it.estado.keptTakes
        .where((k) => k.path == materna)
        .toList();
    expect(corrigido, hasLength(1));
    expect(corrigido.single.takeId, isNotNull);
  });

  test('dois consertos no mesmo trecho: o último é o áudio', () async {
    final it = await _aSalaNaPergunta();

    await _regravarAMaterna(it);
    final materna2 = it.harness.recorder.lastPath!;
    await _entregarAPonte(it);

    await _regravarAMaterna(it);
    final materna3 = it.harness.recorder.lastPath!;
    await _entregarAPonte(it);

    expect(materna3, isNot(materna2));

    it.harness.playback.played.clear();
    it.sala.ouvirVozMaterna();
    await waitFor(
      'o trecho apontado estar tocando',
      () => it.estado.btTrechoTocando,
    );

    expect(
      it.harness.playback.played.last,
      materna3,
      reason:
          'o segundo conserto substitui o primeiro no que toca — o '
          'play é sempre o do take mais novo',
    );

    expect(
      it.estado.keptTakes.where((k) => k.path == materna3),
      hasLength(1),
      reason:
          'o take mais novo está guardado, e é o que sobreviveria a um '
          'resume',
    );
  });

  test(
    'o caminho curto não troca a materna nem os limites do trecho',
    () async {
      final it = await _aSalaNaPergunta();
      final antes = _no(it.container, 1);
      final parteAntes = it.estado.partes[antes.parte].path;

      it.sala.traduzirDeNovoEmPortugues();
      await waitFor(
        'o microfone abrir para traduzir de novo',
        () => it.estado.btPhase == BtPhase.capturing,
      );
      await _entregarAPonte(it);

      final depois = _no(it.container, 1);
      expect(depois.from, antes.from);
      expect(depois.to, antes.to);

      it.harness.playback.played.clear();
      it.sala.ouvirVozMaterna();
      await waitFor(
        'o trecho apontado estar tocando',
        () => it.estado.btTrechoTocando,
      );

      expect(
        it.harness.playback.played.last,
        parteAntes,
        reason:
            'o caminho curto não regrava a materna; o áudio continua '
            'sendo o da parte, do jeito que sempre foi',
      );
    },
  );

  test('"ouvir a passagem" no ensaio retomado toca a passagem atual — a '
      'materna corrigida no lugar do trecho 2', () async {
    final it = await _aSalaNaPergunta();
    final parte0 = it.estado.partes[0];
    final trecho0Antes = it.estado.btTrechos[0];
    final trecho2Antes = it.estado.btTrechos[2];
    final parte1 = it.estado.partes[1];

    it.harness.playback.measured = const Duration(seconds: 7);
    await _regravarAMaterna(it);
    final materna = it.harness.recorder.lastPath!;
    await _entregarAPonte(it);

    it.sala.continuarOEnsaio();
    await waitFor(
      'a sala voltar para o ensaio',
      () => it.estado.stage == SalaStage.ensaio,
    );
    expect(
      it.estado.canGhostPlay,
      isTrue,
      reason: '"ouvir a passagem" existe no ensaio retomado',
    );

    it.harness.playback.played.clear();
    it.harness.playback.ranges.clear();
    it.sala.ghostPlay();
    await waitFor(
      'a passagem fantasma tocar o primeiro trecho',
      () => it.harness.playback.played.isNotEmpty,
    );
    it.harness.playback.finishPlayback();
    await waitFor(
      'a passagem fantasma tocar o segundo trecho',
      () => it.harness.playback.played.length >= 2,
    );
    it.harness.playback.finishPlayback();
    await waitFor(
      'a passagem fantasma tocar o terceiro trecho',
      () => it.harness.playback.played.length >= 3,
    );

    expect(
      it.harness.playback.played,
      [parte0.path, materna, parte1.path],
      reason:
          'a sequência de playRange segue os trechos em ordem, com a '
          'materna corrigida no lugar do trecho 2 — nunca a parte original '
          'ali',
    );
    expect(it.harness.playback.ranges, [
      '${trecho0Antes.from.inMilliseconds}-${trecho0Antes.to.inMilliseconds}',
      '0-7000',
      '${trecho2Antes.from.inMilliseconds}-${trecho2Antes.to.inMilliseconds}',
    ]);
  });

  test('gravar uma parte nova depois de um conserto não pula número nem conta '
      'o conserto como parte', () async {
    final it = await _aSalaNaPergunta();
    await _regravarAMaterna(it);
    await _entregarAPonte(it);

    it.sala.continuarOEnsaio();
    await waitFor(
      'a sala voltar para o ensaio',
      () => it.estado.stage == SalaStage.ensaio,
    );

    await _gravarUmaParte(it);

    expect(
      it.estado.keptTakes.last.scopeId,
      KeptScope.parte(3),
      reason:
          'só duas partes de ensaio existiam antes desta — o conserto '
          'já guardado em keptTakes não é uma delas, e não pode empurrar '
          'a numeração',
    );
    expect(
      it.estado.takes,
      3,
      reason:
          'a contagem de partes mostrada à equipe também não conta o '
          'conserto como se fosse uma parte a mais',
    );
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_row.dart';
import 'package:internalization_room/features/sala/presentation/widgets/ensaio_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_view.dart';

import 'fakes.dart';
import 'resto_da_historia_test.dart' show aHistoriaSemOFim;
import 'the_translation_is_recorded_over_until_the_check_test.dart'
    show aceso, byLabel, olhar, tocar;

const ouvirOAchado = 'Ouvir o achado de novo';
const ouvirOTrechoEATraducao = 'Ouvir o trecho e a tradução';
const microfoneDeMadeira = 'Gravar a parte de novo na língua materna';
const microfoneAzul = 'Traduzir este trecho de novo';
const continuarOEnsaio = 'Continuar o ensaio';

const gravarATraducaoDeNovo = 'Tocar para gravar a tradução de novo';
const terminar = 'Tocar ao terminar';
const ouvirATraducao = 'Ouvir a tradução';
const confirmarATraducao = 'Confirmar a tradução e seguir';
const tesoura = 'Cortar aqui';
const conferir = 'Conferir a tradução';

const gravarAParteDoisDeNovo = 'Gravar a parte 2 de novo';
const confirmarAParte = 'Confirmar esta parte';
const irParaATraducao = 'Ir para a tradução';
const sairDaPassagem = 'Deixar esta passagem e escolher outra';

const rotulosDaGrade = [
  'Ouvir a voz de vocês, na língua materna',
  'Ouvir a tradução em português',
  'Gravar esta parte de novo na língua materna',
  'Traduzir de novo só em português',
  'Cortar este trecho em dois, aqui',
  'Ouvir e traduzir a gravação de novo',
];

List<String> contasEm(WidgetTester tester, Type tela) => [
  for (final conta
      in tester
          .widget<BeadRow>(
            find.descendant(
              of: find.byType(tela),
              matching: find.byType(BeadRow),
            ),
          )
          .entries)
    [
      conta.fill.name,
      if (conta.current) 'com anel',
      if (conta.dimmed) 'apagada',
    ].join(' '),
];

SalaSessionState estadoDe(ProviderContainer container) =>
    container.read(salaSessionProvider);

Future<int> traducoesGuardadas(WidgetTester tester, SalaHarness harness) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );
  await tester.pump();
  final naCaixa = await harness.takes.entries();
  return naCaixa.where((entrada) => entrada.kind == 'retro').length;
}

Future<void> abrirOAchado(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 1400));
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  testWidgets('F1 — o achado mostra a conta apontada em evidência, sem grade', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aHistoriaSemOFim(
      tester,
      harness,
      ondeFalta: 'trecho-2',
    );
    await abrirOAchado(tester);
    final estado = estadoDe(container);
    expect(estado.btPhase, BtPhase.findings);

    expect(contasEm(tester, RetroView), [
      'solid apagada',
      'drained com anel',
      'solid apagada',
    ]);
    for (final rotulo in [...rotulosDaGrade, tesoura, continuarOEnsaio]) {
      expect(byLabel(rotulo), findsNothing, reason: rotulo);
    }
    for (final rotulo in [
      ouvirOTrechoEATraducao,
      microfoneDeMadeira,
      microfoneAzul,
    ]) {
      expect(aceso(tester, rotulo), isTrue, reason: rotulo);
    }

    expect(await olhar(tester), 'telha parado');
    final linha = estado.lastSpoken!.url;
    final faladas = harness.voice.played.length;
    await tocar(tester, ouvirOAchado);
    await tester.pump(const Duration(milliseconds: 300));
    expect(harness.voice.played.length, faladas + 1);
    expect(harness.voice.played.last, linha);
    expect(harness.playback.ranges, isEmpty);

    final trecho = estadoDe(container).btTrechos[1];
    final parteDois = estadoDe(container).partes[1].path;
    await tocar(tester, ouvirOTrechoEATraducao);
    expect(harness.playback.played.last, parteDois);
    expect(
      harness.playback.ranges.last,
      '${trecho.from.inMilliseconds}-${trecho.to.inMilliseconds}',
    );
    expect(await olhar(tester), 'wood soando');

    await tocar(tester, ouvirOTrechoEATraducao);
    expect(harness.playback.paused, isTrue);
    expect(harness.playback.sounding, isFalse);
    await tocar(tester, ouvirOTrechoEATraducao);
    expect(harness.playback.sounding, isTrue);
    expect(harness.playback.played.last, parteDois);

    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    expect(harness.playback.played.last, trecho.retroPath);
    expect(await olhar(tester), 'azul soando');

    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    expect(harness.playback.sounding, isFalse);
    expect(await olhar(tester), 'telha parado');
    closeTheRoom(container);
  });

  testWidgets('F1b — a tela do achado segue o quadro X1', (tester) async {
    tester.view
      ..physicalSize = const Size(820, 1180)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aHistoriaSemOFim(
      tester,
      harness,
      ondeFalta: 'trecho-2',
    );
    await abrirOAchado(tester);

    expect(
      tester
          .getTopLeft(
            find.descendant(
              of: find.byType(RetroView),
              matching: find.byType(BeadRow),
            ),
          )
          .dy,
      86,
    );
    expect(tester.getSize(byLabel(ouvirOAchado)), const Size(160, 160));
    expect(tester.getTopLeft(byLabel(ouvirOAchado)), const Offset(330, 456));
    expect(
      tester.getTopLeft(byLabel(ouvirOTrechoEATraducao)),
      const Offset(296, 680),
    );
    expect(
      tester.getTopLeft(byLabel(microfoneDeMadeira)),
      const Offset(380, 680),
    );
    expect(tester.getTopLeft(byLabel(microfoneAzul)), const Offset(464, 680));
    closeTheRoom(container);
  });

  testWidgets('F2 — o microfone de madeira leva ao ensaio, na parte 2', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aHistoriaSemOFim(
      tester,
      harness,
      ondeFalta: 'trecho-2',
    );
    await abrirOAchado(tester);
    final antes = estadoDe(container).partes;

    await tocar(tester, microfoneDeMadeira);
    await tester.pump(const Duration(milliseconds: 200));

    expect(estadoDe(container).stage, SalaStage.ensaio);
    expect(contasEm(tester, EnsaioView), [
      'solid apagada',
      'drained com anel',
      'solid apagada',
    ]);

    await tocar(tester, gravarAParteDoisDeNovo);
    await tocar(tester, terminar);
    expect(contasEm(tester, EnsaioView), [
      'solid apagada',
      'translucent com anel',
      'solid apagada',
    ]);
    await tocar(tester, confirmarAParte);
    await letTheRehearsalReachTheRoom(tester);

    final depois = estadoDe(container);
    expect(depois.partes, hasLength(3));
    expect(depois.partes[1].path, isNot(antes[1].path));
    expect(depois.partes[1].scopeId, antes[1].scopeId);
    expect(depois.partes[1].pass, antes[1].pass + 1);
    expect([
      for (final trecho in depois.btTrechos) trecho.parte,
    ], isNot(contains(1)));
    expect(contasEm(tester, EnsaioView), ['solid', 'solid', 'solid']);

    final tocadas = harness.playback.played.length;
    await tocar(tester, irParaATraducao);
    await tester.pump(const Duration(milliseconds: 300));
    expect(estadoDe(container).stage, SalaStage.retro);
    expect(harness.playback.played.length, greaterThan(tocadas));
    expect(harness.playback.played.last, depois.partes[1].path);
    expect(harness.playback.playedFrom.last, Duration.zero);
    closeTheRoom(container);
  });

  testWidgets('F3 — o microfone azul leva à tradução, no trecho 1', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aHistoriaSemOFim(
      tester,
      harness,
      ondeFalta: 'trecho-1',
    );
    await abrirOAchado(tester);
    final antiga = estadoDe(container).btTrechos[0].retroPath!;
    final capturas = harness.recorder.captures;
    final trechosNaSala = List.of(harness.room.segmentIds);
    final pedacos = harness.room.chunksSent;
    final vereditos = harness.room.playedByTakeSent.length;

    await tocar(tester, microfoneAzul);
    await tester.pump(const Duration(milliseconds: 200));

    final chegada = estadoDe(container);
    expect(chegada.stage, SalaStage.retro);
    expect(chegada.btPhase, BtPhase.playing);
    expect(harness.recorder.captures, capturas);
    expect(harness.playback.sounding, isFalse);
    expect(contasEm(tester, RetroView), [
      'drained com anel',
      'solid apagada',
      'solid apagada',
    ]);
    expect(aceso(tester, confirmarATraducao), isFalse);
    expect(aceso(tester, tesoura), isFalse);
    expect(aceso(tester, conferir), isFalse);

    await tocar(tester, confirmarATraducao);
    expect(harness.room.replacesAsked, isEmpty);

    await tocar(tester, ouvirATraducao);
    expect(harness.playback.played.last, antiga);
    expect(await olhar(tester), 'azul soando');
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));

    await tocar(tester, gravarATraducaoDeNovo);
    expect(contasEm(tester, RetroView), [
      'translucent com anel',
      'solid apagada',
      'solid apagada',
    ]);
    await tocar(tester, terminar);
    await tester.pump(const Duration(milliseconds: 300));
    final nova = harness.recorder.lastPath!;
    expect(contasEm(tester, RetroView), [
      'translucent com anel',
      'solid apagada',
      'solid apagada',
    ]);
    expect(aceso(tester, confirmarATraducao), isTrue);
    expect(aceso(tester, tesoura), isFalse);

    harness.room.verdictChecked = true;
    await tocar(tester, confirmarATraducao);
    await tester.pump(const Duration(milliseconds: 600));

    expect(harness.room.replacesAsked, hasLength(1));
    expect(harness.room.replacesAsked.single, startsWith('trecho-1@'));
    expect(harness.room.replacesComArquivo.single, nova);
    expect(harness.room.chunksSent, pedacos);
    expect(harness.room.segmentIds.sublist(1), trechosNaSala.sublist(1));
    expect(harness.room.playedByTakeSent.length, vereditos + 1);
    expect(estadoDe(container).btPhase, BtPhase.conferida);
    expect(contasEm(tester, RetroView), ['solid', 'solid', 'solid']);
    closeTheRoom(container);
  });

  testWidgets('F3b — a tradução antiga é emprestada, nunca apagada', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aHistoriaSemOFim(
      tester,
      harness,
      ondeFalta: 'trecho-1',
    );
    await abrirOAchado(tester);
    final antiga = estadoDe(container).btTrechos[0].retroPath!;
    final guardadas = await traducoesGuardadas(tester, harness);

    await tocar(tester, microfoneAzul);
    await tester.pump(const Duration(milliseconds: 200));
    await tocar(tester, gravarATraducaoDeNovo);
    await tocar(tester, terminar);
    await tester.pump(const Duration(milliseconds: 300));
    final nova = harness.recorder.lastPath!;
    expect(harness.recorder.deleted, isNot(contains(antiga)));

    await tocar(tester, sairDaPassagem);
    await tester.pump(const Duration(milliseconds: 300));

    expect(harness.recorder.deleted, isNot(contains(antiga)));
    expect(harness.recorder.deleted, contains(nova));
    expect(await traducoesGuardadas(tester, harness), guardadas);
    closeTheRoom(container);
  });

  testWidgets('F3c — sair logo da aterragem não apaga a tradução antiga', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aHistoriaSemOFim(
      tester,
      harness,
      ondeFalta: 'trecho-1',
    );
    await abrirOAchado(tester);
    final antiga = estadoDe(container).btTrechos[0].retroPath!;
    final guardadas = await traducoesGuardadas(tester, harness);

    await tocar(tester, microfoneAzul);
    await tester.pump(const Duration(milliseconds: 200));
    await tocar(tester, sairDaPassagem);
    await tester.pump(const Duration(milliseconds: 300));

    expect(harness.recorder.deleted, isNot(contains(antiga)));
    expect(await traducoesGuardadas(tester, harness), guardadas);
    closeTheRoom(container);
  });

  testWidgets('F4 — a falta sem endereço leva ao ensaio, numa parte nova', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(820, 1180)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aHistoriaSemOFim(tester, harness);
    await abrirOAchado(tester);
    expect(estadoDe(container).btPhase, BtPhase.findings);

    expect(contasEm(tester, RetroView), ['solid', 'solid', 'solid']);
    expect(await olhar(tester), 'telha parado');
    for (final rotulo in [...rotulosDaGrade, tesoura]) {
      expect(byLabel(rotulo), findsNothing, reason: rotulo);
    }
    for (final rotulo in [
      ouvirOTrechoEATraducao,
      microfoneDeMadeira,
      microfoneAzul,
    ]) {
      expect(aceso(tester, rotulo), isFalse, reason: rotulo);
    }
    expect(
      tester.getTopLeft(byLabel(ouvirOTrechoEATraducao)),
      const Offset(296, 680),
    );
    expect(aceso(tester, continuarOEnsaio), isTrue);
    expect(tester.getSize(byLabel(continuarOEnsaio)), const Size(78, 78));
    expect(
      tester.getTopLeft(byLabel(continuarOEnsaio)),
      const Offset(371, 798),
    );

    final partes = estadoDe(container).partes.length;
    await tocar(tester, continuarOEnsaio);
    await tester.pump(const Duration(milliseconds: 200));

    final depois = estadoDe(container);
    expect(depois.stage, SalaStage.ensaio);
    expect(depois.partes, hasLength(partes));
    expect(byLabel('Tocar para gravar a próxima parte'), findsOneWidget);
    closeTheRoom(container);
  });

  testWidgets('F5 — a conta apontada, drenada no achado, volta sólida depois '
      'do conserto', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aHistoriaSemOFim(
      tester,
      harness,
      ondeFalta: 'trecho-2',
    );
    await abrirOAchado(tester);
    expect(contasEm(tester, RetroView)[1], 'drained com anel');

    await tocar(tester, microfoneAzul);
    await tester.pump(const Duration(milliseconds: 200));
    await tocar(tester, gravarATraducaoDeNovo);
    await tocar(tester, terminar);
    await tester.pump(const Duration(milliseconds: 300));
    harness.room.failFinishWith = const RoomSlow();
    await tocar(tester, confirmarATraducao);
    await tester.pump(const Duration(milliseconds: 600));

    expect(harness.room.replacesAsked, hasLength(1));
    expect(estadoDe(container).btPhase, isNot(BtPhase.findings));
    expect(contasEm(tester, RetroView), ['solid', 'solid', 'solid']);
    closeTheRoom(container);
  });

  testWidgets('F6 — os rótulos do achado falam a língua da sala', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true, lingua: 'en');
    final container = await aHistoriaSemOFim(
      tester,
      harness,
      ondeFalta: 'trecho-2',
    );
    await abrirOAchado(tester);

    for (final rotulo in [
      'Hear the finding again',
      'Hear the stretch and its translation',
      'Record the part again in the mother tongue',
      'Translate this stretch again',
    ]) {
      expect(byLabel(rotulo), findsOneWidget, reason: rotulo);
    }
    closeTheRoom(container);
  });

  testWidgets('F6b — o disco da falta sem endereço fala a língua da sala', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true, lingua: 'en');
    final container = await aHistoriaSemOFim(tester, harness);
    await abrirOAchado(tester);

    expect(byLabel('Continue the rehearsal'), findsOneWidget);
    closeTheRoom(container);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_row.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_view.dart';

import 'fakes.dart';
import 'resto_da_historia_test.dart' show aHistoriaSemOFim;
import 'scenario_helpers.dart';
import 'the_translation_is_recorded_over_until_the_check_test.dart'
    show aceso, olhar, tocar;

const microfoneDeMadeira = 'voltar e regravar uma parte';
const continuarOEnsaio = 'Continuar o ensaio';

const gravarATraducaoDeNovo = 'Tocar para gravar a tradução de novo';
const terminar = 'Tocar ao terminar';
const pararAGravacao = 'Parar';
const ouvirATraducao = 'Ouvir a tradução';
const tesoura = 'Pausar onde a frase acaba';
const conferir = 'terminei';

const gravarEstaParteDeNovo = 'Gravar de novo';
const confirmarAParte = 'Enviar a gravação';
const irParaATraducao = 'Traduzir a gravação';
const sairDaPassagem = 'Escolher outra passagem';

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
    expect(naLinhaDoEnsaio(tester, 'Gravar de novo'), [
      false,
      true,
      false,
      null,
    ]);

    await tocar(tester, gravarEstaParteDeNovo);
    await tocar(tester, pararAGravacao);
    expect(
      naLinhaDoEnsaio(tester, 'Ouvir'),
      [true, true, true, null],
      reason:
          'pendente a confirmação, as outras linhas não ficam mais '
          'esmaecidas (ADR 0040: esmaecido é o que não se aplica agora)',
    );
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
    expect(naLinhaDoEnsaio(tester, 'Gravar de novo'), [true, true, true, null]);

    final tocadas = harness.playback.played.length;
    await tester.ensureVisible(inTheHome(irParaATraducao));
    await tester.tap(inTheHome(irParaATraducao));
    await tester.pump(const Duration(milliseconds: 300));
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

    traduzirOApontadoDeNovo(container);
    await tester.pump(const Duration(milliseconds: 200));
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));

    final chegada = estadoDe(container);
    expect(chegada.stage, SalaStage.retro);
    expect(chegada.btPhase, BtPhase.playing);
    expect(harness.recorder.captures, capturas);
    expect(contasEm(tester, RetroView), [
      'drained com anel',
      'solid apagada',
      'solid apagada',
    ]);
    expect(aceso(tester, conferir), isFalse);
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
    harness.room.verdictChecked = true;
    await tocar(tester, terminar);
    await tester.pump(const Duration(milliseconds: 300));
    final nova = harness.recorder.lastPath!;
    await tester.pump(const Duration(milliseconds: 600));

    expect(harness.room.replacesAsked, hasLength(1));
    expect(harness.room.replacesAsked.single, startsWith('trecho-1@'));
    expect(harness.room.replacesComArquivo.single, nova);
    expect(harness.room.chunksSent, pedacos);
    expect(harness.room.segmentIds.sublist(1), trechosNaSala.sublist(1));
    expect(
      harness.room.playedByTakeSent.length,
      vereditos,
      reason: 'a sala conferia sozinha depois da tradução de novo',
    );

    await tocar(tester, conferir);
    await tester.pump(const Duration(milliseconds: 600));

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

    traduzirOApontadoDeNovo(container);
    await tester.pump(const Duration(milliseconds: 200));
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    await tocar(tester, gravarATraducaoDeNovo);
    await tocar(tester, terminar);
    await tester.pump(const Duration(milliseconds: 300));
    expect(harness.recorder.deleted, isNot(contains(antiga)));

    await tocar(tester, sairDaPassagem);
    await tester.pump(const Duration(milliseconds: 300));

    expect(harness.recorder.deleted, isNot(contains(antiga)));
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

    traduzirOApontadoDeNovo(container);
    await tester.pump(const Duration(milliseconds: 200));
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    await tocar(tester, sairDaPassagem);
    await tester.pump(const Duration(milliseconds: 300));

    expect(harness.recorder.deleted, isNot(contains(antiga)));
    expect(await traducoesGuardadas(tester, harness), guardadas);
    closeTheRoom(container);
  });

  testWidgets('F4 — a falta sem endereço não leva ao ensaio, e nada se grava '
      'depois da última frase', (tester) async {
    tester.view
      ..physicalSize = const Size(820, 1180)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aHistoriaSemOFim(tester, harness);
    await abrirOAchado(tester);
    expect(estadoDe(container).btPhase, BtPhase.playing);
    expect(estadoDe(container).btVeredito, isTrue);

    expect(contasEm(tester, RetroView), ['solid', 'solid', 'solid']);
    expect(await olhar(tester), 'telha parado');
    for (final rotulo in [...rotulosDaGrade, tesoura]) {
      expect(byLabel(rotulo), findsNothing, reason: rotulo);
    }
    expect(
      tester.widget<Semantics>(byLabel(microfoneDeMadeira)).properties.enabled,
      isFalse,
    );
    expect(
      byLabel(continuarOEnsaio),
      findsNothing,
      reason:
          'o disco levava a equipe a gravar mais depois da última frase, o '
          'caminho que a regra de 21 de setembro tirou',
    );
    expect(estadoDe(container).stage, SalaStage.retro);
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
    expect(contasEm(tester, RetroView)[1], 'drained');

    traduzirOApontadoDeNovo(container);
    await tester.pump(const Duration(milliseconds: 200));
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    await tocar(tester, gravarATraducaoDeNovo);
    harness.room.failFinishWith = const NetworkFailed('timeout');
    await tocar(tester, terminar);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 600));

    expect(harness.room.replacesAsked, hasLength(1));
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

    expect(byLabel('go back and re-record a part'), findsOneWidget);
    expect(byLabel('hear the verdict again'), findsOneWidget);
    closeTheRoom(container);
  });

  testWidgets('F6b — a falta sem endereço não tem disco em língua nenhuma', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true, lingua: 'en');
    final container = await aHistoriaSemOFim(tester, harness);
    await abrirOAchado(tester);

    expect(byLabel('Continue the rehearsal'), findsNothing);
    closeTheRoom(container);
  });
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/presentation/widgets/frase_list.dart';
import 'package:internalization_room/main.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel;
import 'the_back_translation_is_told_by_beads_test.dart'
    show
        confirmar,
        contarAteOFimDaParte,
        entrarNaTraducao,
        gravarATraducao,
        tesoura,
        tocar;

Future<void> _passo(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 100));

void _telaAlta(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(820, 3200)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

const _cortes = [
  [Duration(seconds: 3), Duration(seconds: 6)],
  [
    Duration(milliseconds: 2500),
    Duration(seconds: 5),
    Duration(milliseconds: 7500),
  ],
];

Future<ProviderContainer> _seteFrasesContadas(
  WidgetTester tester,
  SalaHarness harness,
) async {
  _telaAlta(tester);
  final container = await entrarNaTraducao(tester, harness);
  var contadas = 0;
  for (final cortes in _cortes) {
    for (final corte in cortes) {
      harness.playback.at = corte;
      await tocar(tester, tesoura);
      await gravarATraducao(tester);
      await tocar(tester, confirmar);
    }
    await contarAteOFimDaParte(tester, harness);
    contadas += cortes.length + 1;
    await waitFor(
      '$contadas frases ficarem contadas',
      () =>
          container
              .read(salaSessionProvider)
              .btTrechos
              .where((trecho) => trecho.contado)
              .length ==
          contadas,
      step: () => _passo(tester),
    );
  }
  return container;
}

Future<void> _terminei(
  WidgetTester tester,
  ProviderContainer container,
  BtPhase chega,
) async {
  unawaited(
    container.read(salaSessionProvider.notifier).finishBackTranslation(),
  );
  await waitFor(
    'o veredito chegar',
    () => container.read(salaSessionProvider).btPhase == chega,
    step: () => _passo(tester),
  );
  await _passo(tester);
}

Future<ProviderContainer> _vereditoNaFraseTres(
  WidgetTester tester,
  SalaHarness harness,
) async {
  final container = await _seteFrasesContadas(tester, harness);
  harness.room
    ..verdictChecked = false
    ..verdictFindingPlace = 2
    ..verdictFindings = const [
      BtFinding(kind: BtFindingKind.addition, frase: 3, segmentId: 'trecho-3'),
    ];
  await _terminei(tester, container, BtPhase.findings);
  return container;
}

Future<ProviderContainer> _seteFrasesConferidas(
  WidgetTester tester,
  SalaHarness harness,
) async {
  final container = await _seteFrasesContadas(tester, harness);
  harness.room
    ..verdictChecked = true
    ..verdictFindings = const [];
  await _terminei(tester, container, BtPhase.conferida);
  return container;
}

Future<ProviderContainer> _voltaAUmaTraducaoConferida(
  WidgetTester tester,
  SalaHarness harness,
) async {
  _telaAlta(tester);
  final pasta = Directory.systemTemp.createTempSync('sala-1220');
  addTearDown(() => pasta.deleteSync(recursive: true));
  final partes = [
    for (final n in [1, 2])
      KeptTake(
        scopeId: KeptScope.parte(n),
        path: (File('${pasta.path}/p$n.m4a')..writeAsBytesSync([1, 2, 3])).path,
        takeId: 'gravacao-$n',
      ),
  ];
  harness.emAberto.rows['Ruth/P01/pt'] = ResumePoint(
    sessionId: 'sessao-antiga',
    stage: SalaStage.retro,
    takes: partes,
  );
  harness.room.retroSoFar = const BackTranslationProgress(
    checked: true,
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
        endsMs: 5000,
        frase: 2,
      ),
    ],
  );
  final container = harness.container();
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await _passo(tester);
  unawaited(
    container
        .read(salaSessionProvider.notifier)
        .goConversa(book: 'Ruth', pericope: 'P01'),
  );
  await waitFor(
    'a tradução conferida voltar',
    () => container.read(salaSessionProvider).btPhase == BtPhase.conferida,
    step: () => letTheRehearsalReachTheRoom(tester),
  );
  await _passo(tester);
  return container;
}

const _conferida = '✓ traduzida e conferida';
const _aprovar = 'Aprovar como rascunho final';

String _barra(int n) => 'Ouvir esta frase de novo e traduzir de novo — $n';

List<String> _naLista(WidgetTester tester) => [
  for (final texto in tester.widgetList<Text>(
    find.descendant(of: find.byType(FraseList), matching: find.byType(Text)),
  ))
    texto.data ?? '',
];

Future<void> _traduzirDeNovo(
  WidgetTester tester,
  ProviderContainer container, {
  String circulo = 'Tocar para gravar a tradução de novo',
}) async {
  await tocar(tester, circulo);
  await tocar(tester, 'Tocar ao terminar');
  await _passo(tester);
  await tocar(tester, confirmar);
  await waitFor(
    'a frase traduzida de novo pousar',
    () => container.read(salaSessionProvider).btTrechoTraduzidoDeNovo == null,
    step: () => _passo(tester),
  );
  await _passo(tester);
}

void main() {
  testWidgets('after a verdict naming frase 3, a tap on frase 7 replays its '
      'piece and asks for the circle', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _vereditoNaFraseTres(tester, harness);
    final parteDois = container.read(salaSessionProvider).partes[1].path;

    expect(
      byLabel(_barra(7)),
      findsOneWidget,
      reason: 'depois do veredito a frase 7 não aceitava toque',
    );
    final tocadas = harness.playback.played.length;
    await tocar(tester, _barra(7));

    expect(
      harness.playback.played.skip(tocadas),
      [parteDois],
      reason: 'o toque na frase não tocava o pedaço dela na gravação',
    );
    expect(harness.playback.ranges, ['7500-10000']);
    expect(
      find.text('traduzindo de novo a frase 7 — toquem no círculo'),
      findsOneWidget,
      reason: 'a tela não dizia qual frase estava sendo traduzida de novo',
    );
    closeTheRoom(container);
  });

  testWidgets('the circle after a tap on frase 7 tells exactly its span '
      'again through the replace door, not as a new frase', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _vereditoNaFraseTres(tester, harness);
    final pedacos = harness.room.chunksSent;

    await tocar(tester, _barra(7));
    await _traduzirDeNovo(tester, container);

    expect(
      harness.room.replacesAsked,
      ['trecho-7@gravacao-2:7500-10000'],
      reason: 'a nova tradução não ia pela porta de substituir a frase 7',
    );
    expect(
      harness.room.chunksSent,
      pedacos,
      reason: 'a frase traduzida de novo subia como uma frase nova',
    );
    closeTheRoom(container);
  });

  testWidgets('frase 7 told again keeps its number and the other marks, and '
      'no check starts until the team says terminei', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _vereditoNaFraseTres(tester, harness);

    await tocar(tester, _barra(7));
    await _traduzirDeNovo(tester, container);
    for (var passo = 0; passo < 10; passo++) {
      await _passo(tester);
    }

    expect(
      harness.room.playedByTakeSent,
      hasLength(1),
      reason:
          'a sala pedia uma conferência sozinha depois da frase traduzida '
          'de novo',
    );
    expect(container.read(salaSessionProvider).btPhase, BtPhase.playing);
    expect(_naLista(tester), [
      'FRASES TRADUZIDAS',
      '1',
      'parte 1',
      '2',
      'parte 1',
      '3',
      'parte 1',
      'acrescentado',
      '4',
      'parte 2',
      '5',
      'parte 2',
      '6',
      'parte 2',
      '7',
      'parte 2',
    ]);
    closeTheRoom(container);
  });

  testWidgets('«manter a tradução de antes» leaves the earlier translation '
      'and the verdict, with nothing recorded', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _vereditoNaFraseTres(tester, harness);
    final antes = container.read(salaSessionProvider).btTrechos[6];
    final pedacos = harness.room.chunksSent;
    final capturas = harness.recorder.captures;

    await tocar(tester, _barra(7));
    expect(
      byLabel('manter a tradução de antes'),
      findsOneWidget,
      reason: 'a frase tocada não tinha como voltar atrás',
    );
    await tocar(tester, 'manter a tradução de antes');
    for (var passo = 0; passo < 10; passo++) {
      await _passo(tester);
    }

    final estado = container.read(salaSessionProvider);
    expect(
      estado.btPhase,
      BtPhase.findings,
      reason: 'manter a tradução de antes não voltava ao veredito',
    );
    expect(estado.btTrechoTraduzidoDeNovo, isNull);
    expect(estado.btTrechos[6].retroPath, antes.retroPath);
    expect(harness.room.replacesAsked, isEmpty);
    expect(harness.room.chunksSent, pedacos);
    expect(harness.recorder.captures, capturas);
    expect(
      find.text('traduzindo de novo a frase 7 — toquem no círculo'),
      findsNothing,
    );
    expect(byLabel('manter a tradução de antes'), findsNothing);
    closeTheRoom(container);
  });

  testWidgets('«manter a tradução de antes» after a recording nobody confirmed '
      'lets that recording go and sends nothing', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _vereditoNaFraseTres(tester, harness);
    final pedacos = harness.room.chunksSent;

    await tocar(tester, _barra(7));
    await tocar(tester, 'Tocar para gravar a tradução de novo');
    await tocar(tester, 'Tocar ao terminar');
    await _passo(tester);
    final gravada = harness.recorder.lastPath!;
    await tocar(tester, 'manter a tradução de antes');
    for (var passo = 0; passo < 10; passo++) {
      await _passo(tester);
    }

    expect(
      harness.recorder.deleted,
      contains(gravada),
      reason: 'a gravação que ninguém confirmou ficava guardada',
    );
    expect(container.read(salaSessionProvider).btTraducaoPendente, isNull);
    expect(harness.room.replacesAsked, isEmpty);
    expect(harness.room.chunksSent, pedacos);
    closeTheRoom(container);
  });

  testWidgets('the findings screen\'s retell names its frase the same way, and '
      'its «manter a tradução de antes» goes back to the finding', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _vereditoNaFraseTres(tester, harness);

    await tocar(tester, 'Traduzir este trecho de novo');

    expect(
      find.text('traduzindo de novo a frase 3 — toquem no círculo'),
      findsOneWidget,
    );
    await tocar(tester, 'manter a tradução de antes');
    await _passo(tester);

    expect(
      container.read(salaSessionProvider).btPhase,
      BtPhase.findings,
      reason: 'voltar atrás no trecho do achado largava a equipe na tradução',
    );
    expect(harness.room.replacesAsked, isEmpty);
    closeTheRoom(container);
  });

  testWidgets('a conferida telling with frase 2 told again is no longer '
      'conferida, until a new clean check', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _seteFrasesConferidas(tester, harness);
    expect(find.text(_conferida), findsOneWidget);

    await tocar(tester, _barra(2));
    expect(
      container.read(salaSessionProvider).btTrechoTraduzidoDeNovo?.frase,
      2,
      reason: 'na tradução conferida a frase 2 não abria para traduzir de novo',
    );
    await _traduzirDeNovo(tester, container);

    expect(
      find.text(_conferida),
      findsNothing,
      reason: 'a tela seguia dizendo conferida com a frase 2 traduzida de novo',
    );
    expect(byLabel(_aprovar), findsNothing);

    await _terminei(tester, container, BtPhase.conferida);

    expect(find.text(_conferida), findsOneWidget);
    expect(byLabel(_aprovar), findsOneWidget);
    closeTheRoom(container);
  });

  testWidgets('«manter a tradução de antes» on a conferida telling leaves it '
      'conferida, with its approval', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _seteFrasesConferidas(tester, harness);

    await tocar(tester, _barra(5));
    expect(find.text(_conferida), findsNothing);
    await tocar(tester, 'manter a tradução de antes');
    await _passo(tester);

    expect(
      find.text(_conferida),
      findsOneWidget,
      reason: 'desistir de traduzir de novo tirava a tradução de conferida',
    );
    expect(byLabel(_aprovar), findsOneWidget);
    expect(harness.room.replacesAsked, isEmpty);
    closeTheRoom(container);
  });

  testWidgets('after a frase is told again the verdict still stands: the '
      'sub-line is the verdict\'s and another frase still opens', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _seteFrasesConferidas(tester, harness);

    await tocar(tester, _barra(2));
    await _traduzirDeNovo(tester, container);

    expect(
      find.text(
        'Toquem numa frase para ouvir e traduzir de novo; voltem para regravar '
        'uma parte; ou toquem em terminei para conferir de novo.',
      ),
      findsOneWidget,
      reason:
          'a tela esquecia o veredito depois da primeira frase traduzida '
          'de novo',
    );
    await tocar(tester, _barra(5));
    expect(
      container.read(salaSessionProvider).btTrechoTraduzidoDeNovo?.frase,
      5,
      reason: 'depois de uma frase traduzida de novo as outras não abriam mais',
    );
    closeTheRoom(container);
  });

  testWidgets('a conferida session picked back up still stands on its '
      'verdict after a frase is told again', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaAUmaTraducaoConferida(tester, harness);

    await tocar(tester, _barra(1));
    await _traduzirDeNovo(
      tester,
      container,
      circulo: 'Tocar para gravar a tradução deste trecho',
    );

    expect(
      find.text(
        'Toquem numa frase para ouvir e traduzir de novo; voltem para regravar '
        'uma parte; ou toquem em terminei para conferir de novo.',
      ),
      findsOneWidget,
      reason: 'a sessão retomada esquecia o veredito que a leitura trazia',
    );
    await tocar(tester, _barra(2));
    expect(
      container.read(salaSessionProvider).btTrechoTraduzidoDeNovo?.frase,
      2,
    );
    closeTheRoom(container);
  });
}

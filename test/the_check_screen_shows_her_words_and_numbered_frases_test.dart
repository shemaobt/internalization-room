import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_row.dart';
import 'package:internalization_room/features/sala/presentation/widgets/frase_list.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'the_back_translation_is_told_by_beads_test.dart'
    show
        cabeca,
        confirmar,
        contarAteOFimDaParte,
        entrarNaTraducao,
        gravarATraducao,
        tesoura,
        tocar;

const _quatroFrases = [
  SegmentView(
    segmentId: 'trecho-1',
    takeId: 'gravacao-1',
    startsMs: 0,
    endsMs: 4000,
    frase: 1,
  ),
  SegmentView(
    segmentId: 'trecho-2',
    takeId: 'gravacao-1',
    startsMs: 4000,
    endsMs: 9000,
    frase: 2,
  ),
  SegmentView(
    segmentId: 'trecho-3',
    takeId: 'gravacao-2',
    startsMs: 0,
    endsMs: 6000,
    frase: 3,
  ),
  SegmentView(
    segmentId: 'trecho-4',
    takeId: 'gravacao-2',
    startsMs: 6000,
    endsMs: 8000,
    frase: 4,
  ),
];

Future<void> _passo(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 100));

void _telaAlta(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(820, 2400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<ProviderContainer> _voltaATraducao(
  WidgetTester tester,
  SalaHarness harness,
  BackTranslationProgress contado,
) async {
  _telaAlta(tester);
  final pasta = Directory.systemTemp.createTempSync('sala-1205');
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
  harness.room.retroSoFar = contado;
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
    'a tradução voltar com as frases que a sala guardou',
    () =>
        container.read(salaSessionProvider).stage == SalaStage.retro &&
        container.read(salaSessionProvider).btTrechos.length ==
            contado.segments.length,
    step: () => letTheRehearsalReachTheRoom(tester),
  );
  await _passo(tester);
  return container;
}

const _subTell =
    'Toquem no círculo para pausar onde a frase acaba; toquem de novo para '
    'traduzir só o que aquela frase diz, e de novo para a gravação seguir.';

const _subVerdict =
    'Toquem numa frase para ouvir e traduzir de novo; voltem para regravar uma '
    'parte; ou toquem em terminei para conferir de novo.';

Finder _cabecalho(String texto) => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      widget.properties.header == true &&
      widget.properties.label == texto,
);

List<String> _naLista(WidgetTester tester) => [
  for (final texto in tester.widgetList<Text>(
    find.descendant(of: find.byType(FraseList), matching: find.byType(Text)),
  ))
    texto.data ?? '',
];

void main() {
  testWidgets('four frases the room numbered are listed one to four, each '
      'under its parte, below her heading', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaATraducao(
      tester,
      harness,
      const BackTranslationProgress(segments: _quatroFrases),
    );

    expect(
      _naLista(tester),
      [
        'FRASES TRADUZIDAS',
        '1',
        'parte 1',
        '2',
        'parte 1',
        '3',
        'parte 2',
        '4',
        'parte 2',
      ],
      reason:
          'a tela não tinha número nenhum: a voz dizia «na frase 3» e não '
          'havia nada para apontar',
    );
    closeTheRoom(container);
  });

  testWidgets('a frase just told shows the number its answer carries, not '
      'a count the tablet keeps, before the session is read again', (
    tester,
  ) async {
    _telaAlta(tester);
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);
    harness.playback.at = cabeca;
    await tocar(tester, tesoura);
    await gravarATraducao(tester);
    harness.room.fraseDaProximaFrase = 7;
    await tocar(tester, confirmar);
    await waitFor(
      'a frase contada pousar',
      () => container
          .read(salaSessionProvider)
          .btTrechos
          .any((trecho) => trecho.contado),
      step: () => _passo(tester),
    );

    expect(
      _naLista(tester),
      ['FRASES TRADUZIDAS', '7', 'parte 1'],
      reason:
          'a frase recém-contada entrava sem número até a próxima leitura da '
          'sessão',
    );
    closeTheRoom(container);
  });

  testWidgets('a told stretch the room gave no number is listed with no '
      'number, never one the tablet counted', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaATraducao(
      tester,
      harness,
      BackTranslationProgress(
        segments: [
          _quatroFrases[0],
          const SegmentView(
            segmentId: 'trecho-2',
            takeId: 'gravacao-1',
            startsMs: 4000,
            endsMs: 9000,
          ),
          _quatroFrases[2],
        ],
      ),
    );

    expect(
      _naLista(tester),
      ['FRASES TRADUZIDAS', '1', 'parte 1', 'parte 1', '3', 'parte 2'],
      reason:
          'um número contado no aparelho não é o da voz, e a «frase 2» da '
          'tela seria outra',
    );
    closeTheRoom(container);
  });

  testWidgets('the loudspeaker of a frase plays the team\'s own translation '
      'of it, named by its number', (tester) async {
    _telaAlta(tester);
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);
    harness.playback.at = cabeca;
    await tocar(tester, tesoura);
    await gravarATraducao(tester);
    harness.room.fraseDaProximaFrase = 3;
    await tocar(tester, confirmar);
    await waitFor(
      'a frase contada pousar',
      () => container
          .read(salaSessionProvider)
          .btTrechos
          .any((trecho) => trecho.contado),
      step: () => _passo(tester),
    );
    final contada = harness.room.chunkFiles.last;
    harness.playback.finishPlayback();
    await _passo(tester);

    await tocar(tester, 'ouvir a minha tradução da frase 3');

    expect(
      harness.playback.played.last,
      contada,
      reason: 'a lista não tinha como ouvir a tradução de uma frase',
    );
    closeTheRoom(container);
  });

  testWidgets('a bead says the frase the room numbered, or the parte it lies '
      'in, never «Trecho»', (tester) async {
    _telaAlta(tester);
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness);
    harness.playback.at = cabeca;
    await tocar(tester, tesoura);
    await gravarATraducao(tester);
    harness.room.fraseDaProximaFrase = 7;
    await tocar(tester, confirmar);
    await waitFor(
      'a frase contada pousar',
      () => container
          .read(salaSessionProvider)
          .btTrechos
          .any((trecho) => trecho.contado),
      step: () => _passo(tester),
    );

    expect(
      [
        for (final conta
            in tester.widget<BeadRow>(find.byType(BeadRow)).entries)
          conta.semanticLabel,
      ],
      ['frase 7', 'parte 1'],
      reason:
          'as contas diziam «Trecho N», uma palavra que não é dela e um '
          'número que não era o da voz',
    );
    closeTheRoom(container);
  });

  testWidgets('the check screen is headed with her words, «Traduzir a '
      'gravação», not left without a title', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _voltaATraducao(
      tester,
      harness,
      const BackTranslationProgress(segments: _quatroFrases),
    );

    expect(
      find.descendant(
        of: _cabecalho('Traduzir a gravação'),
        matching: find.text('Traduzir a gravação'),
      ),
      findsOneWidget,
      reason: 'a tela da tradução não dizia o que era',
    );
    closeTheRoom(container);
  });

  testWidgets('the sub-line tells the team to pause and translate before a '
      'verdict, and to tap a frase or terminei after one', (tester) async {
    _telaAlta(tester);
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await entrarNaTraducao(tester, harness, partes: 1);

    expect(
      find.text(_subTell),
      findsOneWidget,
      reason: 'nada na tela dizia à equipe o que fazer',
    );

    harness.playback.at = cabeca;
    await tocar(tester, tesoura);
    await gravarATraducao(tester);
    await tocar(tester, confirmar);
    await contarAteOFimDaParte(tester, harness);
    harness.room
      ..verdictChecked = false
      ..verdictFindingPlace = 0;
    unawaited(
      container.read(salaSessionProvider.notifier).finishBackTranslation(),
    );
    await waitFor(
      'o veredito chegar com um achado',
      () => container.read(salaSessionProvider).btPhase == BtPhase.findings,
      step: () => _passo(tester),
    );

    expect(
      find.text(_subVerdict),
      findsOneWidget,
      reason: 'depois do veredito a linha seguia dizendo para pausar',
    );
    expect(find.text(_subTell), findsNothing);
    closeTheRoom(container);
  });
}

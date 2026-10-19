import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
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

String _barra(int n) => 'Ouvir esta frase de novo e traduzir de novo — $n';

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
}

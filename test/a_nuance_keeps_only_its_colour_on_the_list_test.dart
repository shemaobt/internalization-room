import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/core/theme/sala_colors.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/frase_list.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel;
import 'the_back_translation_is_told_by_beads_test.dart'
    show
        cabeca,
        confirmar,
        contarAteOFimDaParte,
        entrarNaTraducao,
        gravarATraducao,
        tesoura,
        tocar;

Future<void> _passo(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 100));

Future<ProviderContainer> _quatroFrasesComUmaNuance(
  WidgetTester tester,
  SalaHarness harness, {
  required int naFrase,
}) async {
  tester.view
    ..physicalSize = const Size(820, 2400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = await entrarNaTraducao(tester, harness);
  for (var parte = 1; parte <= 2; parte++) {
    harness.playback.at = cabeca;
    await tocar(tester, tesoura);
    await gravarATraducao(tester);
    await tocar(tester, confirmar);
    await contarAteOFimDaParte(tester, harness);
    await waitFor(
      'a parte $parte ficar contada em duas frases',
      () =>
          container
              .read(salaSessionProvider)
              .btTrechos
              .where((trecho) => trecho.contado)
              .length ==
          parte * 2,
      step: () => _passo(tester),
    );
  }
  harness.room
    ..verdictChecked = true
    ..verdictFindings = const []
    ..verdictCheckAt = '2026-10-19T19:58:13.123456Z'
    ..verdictNamedNuance = BtFinding(
      kind: BtFindingKind.nuance,
      frase: naFrase,
      segmentId: 'trecho-$naFrase',
    );
  unawaited(
    container.read(salaSessionProvider.notifier).finishBackTranslation(),
  );
  await waitFor(
    'a conferência chegar',
    () => container.read(salaSessionProvider).btPhase == BtPhase.conferida,
    step: () => _passo(tester),
  );
  await _passo(tester);
  return container;
}

Finder _aFrase(int n) => find.ancestor(
  of: find.descendant(of: find.byType(FraseList), matching: find.text('$n')),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Container &&
        widget.decoration is BoxDecoration &&
        (widget.decoration as BoxDecoration).border != null &&
        (widget.decoration as BoxDecoration).borderRadius ==
            BorderRadius.circular(16),
  ),
);

Color _borda(WidgetTester tester, int n) =>
    ((tester.widget<Container>(_aFrase(n).first).decoration as BoxDecoration)
                .border!
            as Border)
        .top
        .color;

bool _barraEm(WidgetTester tester, int n, Color cor) => tester
    .widgetList<Container>(
      find.descendant(of: _aFrase(n).first, matching: find.byType(Container)),
    )
    .any(
      (caixa) =>
          caixa.decoration is BoxDecoration &&
          (caixa.decoration as BoxDecoration).color == cor,
    );

List<String> _naLista(WidgetTester tester) => [
  for (final texto in tester.widgetList<Text>(
    find.descendant(of: find.byType(FraseList), matching: find.byType(Text)),
  ))
    texto.data ?? '',
];

void main() {
  testWidgets('the frase whose nuance the last verdict named keeps only the '
      'finding\'s colour, never a word, and no other frase is coloured', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrasesComUmaNuance(
      tester,
      harness,
      naFrase: 3,
    );

    expect(
      _borda(tester, 3),
      ShemaBrand.azul,
      reason: 'a frase da nuance ficava igual às outras, sem a cor do achado',
    );
    expect(_barraEm(tester, 3, ShemaBrand.azul), isTrue);
    for (final outra in [1, 2, 4]) {
      expect(_borda(tester, outra), isNot(ShemaBrand.azul));
      expect(_barraEm(tester, outra, ShemaBrand.azul), isFalse);
    }
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
        'regravar a frase 3',
        '4',
        'parte 2',
      ],
      reason:
          'uma nuance não leva palavra nenhuma na frase, só o pedido do veredito',
    );
    closeTheRoom(container);
  });

  testWidgets('a conferida translation whose verdict named a nuance on frase 4 '
      'offers «regravar a frase 4» on that frase and on no other', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrasesComUmaNuance(
      tester,
      harness,
      naFrase: 4,
    );

    expect(
      find.descendant(
        of: find.byType(FraseList),
        matching: byLabel('regravar a frase 4'),
      ),
      findsOneWidget,
      reason:
          'o veredito pediu para regravar a frase 4 e a tela não dava onde tocar',
    );
    for (final outra in [1, 2, 3]) {
      expect(byLabel('regravar a frase $outra'), findsNothing);
    }
    closeTheRoom(container);
  });

  testWidgets(
    'a refused approval that sends the team back to the telling keeps '
    'the nuance\'s colour and takes «regravar a frase 4» away',
    (tester) async {
      final harness = SalaHarness(filaEmMemoria: true);
      final container = await _quatroFrasesComUmaNuance(
        tester,
        harness,
        naFrase: 4,
      );
      harness.room.releaseBlockers = const ['telling_back_not_checked'];

      await tocar(tester, 'Aprovar como rascunho final');
      await waitFor(
        'a recusa devolver a equipe à tradução',
        () => container.read(salaSessionProvider).btPhase == BtPhase.playing,
        step: () => _passo(tester),
      );
      await _passo(tester);

      expect(_borda(tester, 4), ShemaBrand.azul);
      expect(
        byLabel('regravar a frase 4'),
        findsNothing,
        reason:
            'o botão é da tradução conferida; fora dela regravar a frase segue a '
            'regra de todas as frases',
      );
      closeTheRoom(container);
    },
  );

  testWidgets('a check whose only finding is a nuance reads as conferida, and '
      'the approval goes with nothing forced', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrasesComUmaNuance(
      tester,
      harness,
      naFrase: 2,
    );
    final sessao = container.read(salaSessionProvider).sessionId;

    expect(
      find.text('✓ traduzida e conferida'),
      findsOneWidget,
      reason: 'uma nuance segurava a passagem como se fosse um achado',
    );
    await tocar(tester, 'Aprovar como rascunho final');
    await waitFor(
      'a aprovação chegar à sala',
      () => harness.room.releasesAsked.isNotEmpty,
      step: () => _passo(tester),
    );

    expect(
      harness.room.releasesAsked,
      [sessao],
      reason: 'a nuance nunca impede a aprovação da equipe',
    );
    closeTheRoom(container);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/frase_list.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_view.dart';

import 'a_wav_take.dart';
import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel;
import 'the_back_translation_is_told_by_beads_test.dart'
    show cabeca, confirmar, entrarNaTraducao, parte, tesoura, tocar;

Future<void> _passo(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 100));

Finder _circulo() => find.descendant(
  of: find.byType(RetroView),
  matching: find.byType(FacilitatorCircle),
);

Future<void> _tocarOCirculo(WidgetTester tester) async {
  await tester.tap(_circulo());
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _traduzir(WidgetTester tester) async {
  await _tocarOCirculo(tester);
  await _tocarOCirculo(tester);
  await tocar(tester, confirmar);
}

Future<ProviderContainer> _quatroFrases(
  WidgetTester tester,
  SalaHarness harness, {
  bool emWav = true,
}) async {
  tester.view
    ..physicalSize = const Size(820, 2400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (emWav) {
    harness.recorder.rehearsalSpeaks = aSpokenWav(length: parte);
  }
  final container = await entrarNaTraducao(tester, harness);
  for (var contada = 1; contada <= 2; contada++) {
    harness.playback.at = cabeca;
    await tocar(tester, tesoura);
    await _traduzir(tester);
    harness.playback.at = parte;
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    await _traduzir(tester);
    await waitFor(
      'a parte $contada ficar contada em duas frases',
      () =>
          container
              .read(salaSessionProvider)
              .btTrechos
              .where((trecho) => trecho.contado)
              .length ==
          contada * 2,
      step: () => _passo(tester),
    );
  }
  await _passo(tester);
  return container;
}

Finder _naLista(String label) =>
    find.descendant(of: find.byType(FraseList), matching: byLabel(label));

bool _acesa(WidgetTester tester, String label) =>
    tester.widget<Semantics>(_naLista(label)).properties.enabled ?? false;

void main() {
  testWidgets('every frase of a wav recording offers its whole sentence to '
      'be recorded again, lit', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrases(tester, harness);

    for (var n = 1; n <= 4; n++) {
      expect(_naLista('regravar a frase $n'), findsOneWidget);
      expect(
        _acesa(tester, 'regravar a frase $n'),
        isTrue,
        reason:
            'a frase $n não oferecia regravar, e um detalhe custava a parte',
      );
    }
    closeTheRoom(container);
  });

  testWidgets('a recording not in wav offers no sentence on any row', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrases(tester, harness, emWav: false);

    expect(find.byType(FraseList), findsOneWidget);
    for (var n = 1; n <= 4; n++) {
      expect(
        _naLista('regravar a frase $n'),
        findsNothing,
        reason: 'a sala não pode trocar uma frase de uma parte que não é wav',
      );
    }
    closeTheRoom(container);
  });

  testWidgets('the first re-record of a visit says her two lines with the '
      'sentence as it is between them, then waits for the circle', (
    tester,
  ) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await _quatroFrases(tester, harness);
    harness.voice.fixedLines.clear();

    await tocar(tester, 'regravar a frase 3');

    expect(harness.voice.fixedLines, [('N6', 'pt')]);
    expect(
      harness.playback.ranges.last,
      '0-4000',
      reason: 'a frase como está agora não tocava antes de pedirem a nova',
    );
    expect(find.text('gravem a frase inteira'), findsNothing);

    harness.playback.finishPlayback();
    await _passo(tester);
    await _passo(tester);

    expect(
      harness.voice.fixedLines,
      [('N6', 'pt'), ('N7', 'pt')],
      reason: 'a voz não pedia a frase inteira depois de tocá-la',
    );
    expect(
      find.descendant(
        of: find.byType(RetroView),
        matching: find.text('gravem a frase inteira'),
      ),
      findsOneWidget,
    );
    closeTheRoom(container);
  });
}

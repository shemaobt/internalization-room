import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'fakes.dart';
import 'resto_da_historia_test.dart' show aHistoriaSemOFim;

const ouvirOTrecho = 'Ouvir o trecho e a tradução';

Finder byLabel(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

IconData iconeDoPlay(WidgetTester tester) => tester
    .widget<Icon>(
      find.descendant(of: byLabel(ouvirOTrecho), matching: find.byType(Icon)),
    )
    .icon!;

Future<void> tocar(WidgetTester tester) async {
  await tester.tap(byLabel(ouvirOTrecho));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('o ícone do play segue o estado das duas vozes', (tester) async {
    final harness = SalaHarness(filaEmMemoria: true);
    final container = await aHistoriaSemOFim(
      tester,
      harness,
      ondeFalta: 'trecho-2',
    );

    expect(iconeDoPlay(tester), LucideIcons.play);

    await tocar(tester);
    expect(
      iconeDoPlay(tester),
      LucideIcons.pause,
      reason: 'a materna tocando mostra o ícone de pausar',
    );

    await tocar(tester);
    expect(
      iconeDoPlay(tester),
      LucideIcons.play,
      reason: 'pausado é, para o play, o mesmo repouso que parado',
    );

    await tocar(tester);
    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      iconeDoPlay(tester),
      LucideIcons.pause,
      reason: 'a tradução tocando depois da materna também mostra pausar',
    );

    harness.playback.finishPlayback();
    await tester.pump(const Duration(milliseconds: 300));
    expect(iconeDoPlay(tester), LucideIcons.play);
    closeTheRoom(container);
  });
}

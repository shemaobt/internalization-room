import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/presentation/widgets/colar_overlay.dart';
import 'package:internalization_room/features/sala/presentation/widgets/ensaio_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_view.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show byLabel;
import 'sala_screen_test.dart' show pumpSala;

void _onAPhone(
  WidgetTester tester, {
  required double width,
  required double bar,
}) {
  tester.view
    ..physicalSize = Size(width, 844)
    ..devicePixelRatio = 1
    ..padding = FakeViewPadding(top: bar)
    ..viewPadding = FakeViewPadding(top: bar);
  addTearDown(tester.view.reset);
}

Future<ProviderContainer> _atTheRecordingHome(WidgetTester tester) async {
  final container = await pumpSala(tester, SalaHarness());
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.goConversa(book: 'Ruth');
  await tester.pump(const Duration(milliseconds: 300));
  notifier.goEnsaio();
  await tester.pump(const Duration(milliseconds: 1600));
  return container;
}

Future<ProviderContainer> _inTheConversa(WidgetTester tester) async {
  final container = await pumpSala(tester, SalaHarness());
  await container.read(salaSessionProvider.notifier).goConversa(book: 'Ruth');
  await tester.pump(const Duration(milliseconds: 1600));
  return container;
}

void main() {
  for (final (width, bar) in [(390.0, 59.0), (768.0, 0.0)]) {
    testWidgets(
      'the recording home starts below the status bar and scrolls from '
      'there, not from under it, on a ${width.toInt()} px screen',
      (tester) async {
        _onAPhone(tester, width: width, bar: bar);
        final container = await _atTheRecordingHome(tester);

        final home = find.byType(EnsaioView);
        expect(
          tester
              .getTopLeft(
                find.descendant(of: home, matching: find.byType(Scrollable)),
              )
              .dy,
          greaterThanOrEqualTo(bar),
          reason:
              'a lista rolava por baixo do relógio: o título passava sobre o '
              'sinal e a hora',
        );
        expect(
          tester
              .getTopLeft(
                find.descendant(of: home, matching: find.byType(Text)).first,
              )
              .dy,
          greaterThanOrEqualTo(bar),
          reason: 'o título ficava debaixo da barra de estado',
        );
        closeTheRoom(container);
      },
    );

    testWidgets('the necklace hangs below the status bar, not across it, on a '
        '${width.toInt()} px screen', (tester) async {
      _onAPhone(tester, width: width, bar: bar);
      final container = await _inTheConversa(tester);

      final beads = find.descendant(
        of: find.byType(ColarOverlay),
        matching: find.byType(AnimatedContainer),
      );
      expect(beads, findsWidgets);
      for (var i = 0; i < beads.evaluate().length; i++) {
        expect(
          tester.getTopLeft(beads.at(i)).dy,
          greaterThanOrEqualTo(bar),
          reason: 'a conta $i do colar ficava sobre o relógio',
        );
      }
      closeTheRoom(container);
    });

    testWidgets('the way out counts her 5% from under the status bar, on a '
        '${width.toInt()} px screen', (tester) async {
      _onAPhone(tester, width: width, bar: bar);
      final container = await _inTheConversa(tester);

      final corner = tester.getTopLeft(byLabel('Escolher outra passagem'));
      expect(corner.dx, closeTo(width * 0.06 - 7, 0.01));
      expect(
        corner.dy,
        closeTo(bar + 844 * 0.05 - 11, 0.01),
        reason: 'o canto contava do topo da tela, sob o relógio',
      );
      closeTheRoom(container);
    });
  }

  testWidgets('while the recording home fades into the check screen one corner '
      'button stands, not two', (tester) async {
    _onAPhone(tester, width: 390, bar: 59);
    final container = await _atTheRecordingHome(tester);
    final notifier = container.read(salaSessionProvider.notifier);
    notifier.gravarACena(1);
    notifier.gravarACena(1);
    await tester.pump(const Duration(milliseconds: 100));
    notifier.takeKeep();
    await untilTheAdvanceDiscLights(
      notifier,
      step: () => letTheRehearsalReachTheRoom(tester),
    );
    notifier.startRetro();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.byType(EnsaioView), findsOneWidget);
    expect(find.byType(RetroView), findsOneWidget);
    expect(
      byLabel('Voltar para a gravação'),
      findsOneWidget,
      reason:
          'a cópia da tela que saía e a da que chegava desenhavam um botão '
          'cada, a 16 px uma da outra, e as duas esmaeciam juntas',
    );
    expect(byLabel('Voltar para a passagem atual'), findsNothing);
    closeTheRoom(container);
  });
}

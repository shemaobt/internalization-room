import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/presentation/widgets/ensaio_view.dart';

import 'fakes.dart';
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
  }
}

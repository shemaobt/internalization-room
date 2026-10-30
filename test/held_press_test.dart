import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show onTheRows;

void main() {
  testWidgets('a finger held on a Scene row\'s record opens the microphone', (
    tester,
  ) async {
    final container = await pumpSala(tester, SalaHarness());
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.goConversa(book: 'Ruth');
    await tester.pump(const Duration(milliseconds: 200));
    notifier.goEnsaio();
    await tester.pump(const Duration(milliseconds: 120));

    final finger = await tester.startGesture(
      tester.getCenter(onTheRows('Gravar')),
    );
    await tester.pump(const Duration(milliseconds: 900));
    await finger.up();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      container.read(salaSessionProvider).ensaio,
      EnsaioStatus.recording,
      reason:
          'o toque longo ganha a arena do toque, e numa sala saudável ele '
          'não tem o que fazer — segurar o dedo não abria microfone nenhum',
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show bySemanticsLabelWidget, pumpSala;

Future<void> _holdTheCircle(WidgetTester tester) async {
  final circle = bySemanticsLabelWidget('Tocar para gravar o ensaio');
  final finger = await tester.startGesture(tester.getCenter(circle));
  await tester.pump(const Duration(milliseconds: 900));
  await finger.up();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('a finger held on the record circle opens the microphone', (
    tester,
  ) async {
    final container = await pumpSala(tester, SalaHarness());
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    await tester.pump(const Duration(milliseconds: 120));

    await _holdTheCircle(tester);

    expect(
      container.read(salaSessionProvider).ensaio,
      EnsaioStatus.recording,
      reason:
          'o toque longo ganha a arena do toque, e numa sala saudável ele '
          'não tem o que fazer — segurar o dedo não abria microfone nenhum',
    );
  });

  testWidgets('a held press still unsticks an ensaio the room abandoned', (
    tester,
  ) async {
    final harness = SalaHarness()..recorder.returnsNothing = true;
    final container = await pumpSala(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await tester.pump(const Duration(milliseconds: 200));
    expect(container.read(salaSessionProvider).needsPerson, isTrue);

    harness.recorder.returnsNothing = false;
    await _holdTheCircle(tester);

    expect(
      container.read(salaSessionProvider).voice,
      VoiceState.invite,
      reason: 'um ensaio travado não tem outra saída pela tela',
    );
  });
}

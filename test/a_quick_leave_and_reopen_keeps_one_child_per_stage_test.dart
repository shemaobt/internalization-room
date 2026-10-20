import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/conversa_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/escolha_view.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;

void main() {
  testWidgets('leaving a passage and reopening it at once builds no stage '
      'twice, not a duplicate-key error', (tester) async {
    final container = await pumpSala(tester, SalaHarness());
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.goConversa(book: 'Ruth', pericope: 'P01');
    await tester.pump(const Duration(milliseconds: 200));
    notifier.leaveThePassage();
    await tester.pump(const Duration(milliseconds: 200));
    await notifier.goConversa(book: 'Ruth', pericope: 'P01');
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      tester.takeException(),
      isNull,
      reason: 'a escolha e a conversa disputavam a mesma chave na transição',
    );
    expect(container.read(salaSessionProvider).stage, SalaStage.conversa);
  });

  testWidgets('three quick round trips leave one view of the stage the team '
      'is on, not a stale copy of each', (tester) async {
    final container = await pumpSala(tester, SalaHarness());
    final notifier = container.read(salaSessionProvider.notifier);

    for (var round = 0; round < 3; round++) {
      await notifier.goConversa(book: 'Ruth', pericope: 'P01');
      await tester.pump(const Duration(milliseconds: 150));
      notifier.leaveThePassage();
      await tester.pump(const Duration(milliseconds: 150));
    }
    await notifier.goConversa(book: 'Ruth', pericope: 'P01');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 1500));

    expect(
      tester.takeException(),
      isNull,
      reason: 'duas cópias da mesma etapa em fade disputavam a mesma chave',
    );
    expect(find.byType(ConversaView), findsOneWidget);
    expect(
      find.byType(EscolhaView),
      findsNothing,
      reason: 'uma escolha velha ficava na tela depois da transição',
    );
  });
}

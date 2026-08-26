import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_styles.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/features/sala/presentation/widgets/retro_view.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';

Future<SalaHarness> pumpToRestartInFlight(WidgetTester tester) async {
  final harness = SalaHarness()
    ..room.verdictChecked = false
    ..room.verdictFinding = BtFindingKind.addition;
  final container = harness.container();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));

  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.goConversa();
  await tester.pump(const Duration(milliseconds: 200));
  notifier.goEnsaio();
  await tester.pump(const Duration(milliseconds: 100));
  notifier.ensaioTap();
  notifier.ensaioTap();
  await tester.pump(const Duration(milliseconds: 100));
  notifier.takeKeep();
  notifier.startRetro();
  await tester.pump(const Duration(milliseconds: 200));

  harness.playback.at = const Duration(seconds: 10);
  notifier.cortarTrecho();
  await tester.pump(const Duration(milliseconds: 200));
  notifier.retroTap();
  await tester.pump(const Duration(milliseconds: 600));
  harness.playback.finishPlayback();
  await tester.pump(const Duration(milliseconds: 200));
  await notifier.finishBackTranslation();
  await tester.pump(const Duration(milliseconds: 300));

  expect(container.read(salaSessionProvider).btPhase, BtPhase.findings);

  harness.room.holdNextTurn();
  unawaited(notifier.reRecordClip());
  await tester.pump(const Duration(milliseconds: 200));
  return harness;
}

void main() {
  testWidgets('the findings screen offers nothing to tap while the room is '
      'restarting the clip', (tester) async {
    await pumpToRestartInFlight(tester);

    expect(
      find.descendant(
        of: find.byType(RetroView),
        matching: find.byType(RoundActionButton),
      ),
      findsNothing,
      reason: 'a equipe agia dentro da espera e o app ficava segurando trechos '
          'que a sessão já tinha descartado',
    );
  });

  testWidgets('the circle shows the room is busy while it restarts the clip',
      (tester) async {
    await pumpToRestartInFlight(tester);

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is FacilitatorCircle && widget.voice == VoiceState.thinking,
      ),
      findsOneWidget,
      reason: 'a tela não tem uma palavra legível: sumir com os botões e deixar '
          'a sala parada faria a equipe tocar de novo sem entender',
    );
  });
}

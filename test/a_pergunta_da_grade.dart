import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';

/// A team that told two stretches back over one rehearsal part and got a finding on the
/// first, standing in front of the question of which voice must speak again.
///
/// The harness is handed back beside the container rather than left in a field of its
/// own: a double reached through a global outlives the test that set it.
Future<(ProviderContainer, SalaHarness)> pumpToPergunta(
  WidgetTester tester,
) async {
  final harness = SalaHarness(filaEmMemoria: true)
    ..room.verdictChecked = false
    ..room.verdictHasFinding = true
    ..room.verdictFindingSegmentId = 'trecho-1';
  final container = harness.container();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SalaApp()),
  );
  await tester.pump(const Duration(milliseconds: 100));

  final sala = container.read(salaSessionProvider.notifier);
  await sala.goConversa();
  await tester.pump(const Duration(milliseconds: 200));
  sala.goEnsaio();
  sala.ensaioTap();
  sala.ensaioTap();
  await tester.pump(const Duration(milliseconds: 100));
  sala.takeKeep();
  await letTheRehearsalReachTheRoom(tester);
  sala.startRetro();
  await tester.pump(const Duration(milliseconds: 200));

  for (final at in const [Duration(seconds: 10), Duration(seconds: 20)]) {
    harness.playback.at = at;
    sala.cortarTrecho();
    sala.retroTap();
    await tester.pump(const Duration(milliseconds: 200));
    await confirmarATraducaoNaTela(tester, container);
    await tester.pump(const Duration(milliseconds: 600));
  }
  harness.playback.finishPlayback();
  await tester.pump(const Duration(milliseconds: 200));
  await sala.finishBackTranslation();
  await tester.pump(const Duration(milliseconds: 300));
  return (container, harness);
}

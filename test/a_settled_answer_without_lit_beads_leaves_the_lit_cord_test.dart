import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/coverage.dart';
import 'package:internalization_room/features/sala/domain/coverage_event.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'session_notifier_test.dart' show inConversa;

void main() {
  test('a settled answer without the bead fields leaves the lit beads as they '
      'were', () async {
    final harness = SalaHarness(settleDelay: const Duration(seconds: 60));
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    int lit() => container.read(salaSessionProvider).coverage.beadsFilled;

    final lit4 = Coverage.fromJson(const {
      'engaged': 3,
      'surfaced': 3,
      'total': 9,
      'beads_total': 12,
      'beads_filled': 4,
    });
    harness.room.turnIdInResponse = 'turno-2';
    harness.room.nextCoverage = lit4;
    harness.room.settledCoverage = lit4;
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();
    harness.room.pushCoverage(
      const CoverageEvent(turnId: 'turno-2', status: CoverageStatus.settled),
    );
    await waitFor('o colar acender quatro contas', () => lit() == 4);

    harness.room.turnIdInResponse = 'turno-3';
    harness.room.settledCoverage = Coverage.fromJson(const {
      'engaged': 5,
      'surfaced': 5,
      'total': 9,
    });
    final pulls = harness.room.calls.where((c) => c == 'fetchState').length;
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();
    harness.room.pushCoverage(
      const CoverageEvent(turnId: 'turno-3', status: CoverageStatus.settled),
    );
    await waitFor(
      'a leitura do fim do turno chegar',
      () => harness.room.calls.where((c) => c == 'fetchState').length > pulls,
    );
    await settle();

    expect(lit(), 4);
  });
}

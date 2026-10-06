import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/coverage.dart';
import 'package:internalization_room/features/sala/domain/coverage_event.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'session_notifier_test.dart' show inConversa;

void main() {
  test('a settled answer without the bead fields moves the elements and leaves '
      'the lit beads and the beads clock as they were', () async {
    final harness = SalaHarness(settleDelay: const Duration(seconds: 60));
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    Coverage shown() => container.read(salaSessionProvider).coverage;

    Future<void> aTurn(String id) async {
      harness.room.turnIdInResponse = id;
      notifier.conversaTap();
      await settle();
      notifier.conversaTap();
      await settle();
    }

    final lit4 = Coverage.fromJson(const {
      'engaged': 3,
      'surfaced': 3,
      'total': 9,
      'beads_total': 12,
      'beads_filled': 4,
    });
    harness.room.nextCoverage = lit4;
    harness.room.settledCoverage = lit4;
    await aTurn('turno-2');
    harness.room.pushCoverage(
      const CoverageEvent(turnId: 'turno-2', status: CoverageStatus.settled),
    );
    await waitFor(
      'o colar acender quatro contas',
      () => shown().beadsFilled == 4,
    );

    harness.room.settledCoverage = Coverage.fromJson(const {
      'engaged': 5,
      'surfaced': 6,
      'total': 9,
    });
    await aTurn('turno-3');
    harness.room.pushCoverage(
      const CoverageEvent(turnId: 'turno-3', status: CoverageStatus.settled),
    );
    await waitFor('os elementos andarem', () => shown().engaged == 5);
    expect(shown().surfaced, 6);
    expect(shown().beadsFilled, 4);
    await aTurn('turno-4');

    expect(
      harness.room.clientTimingsSent.last,
      isNot(contains('sound_to_beads=')),
      reason: 'as contas não andaram, então não houve conta a cronometrar',
    );
  });
}

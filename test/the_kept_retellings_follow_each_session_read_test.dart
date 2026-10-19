import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'session_notifier_test.dart' show inConversa;

const _sceneOne = KeptRetelling(
  scope: 'S1',
  turnNumber: 2,
  audioUrl: 'https://storage.example/kept/aa/conto.m4a?sig=1',
);

void main() {
  test(
    'the read after a turn puts the room\'s kept retellings on the screen\'s state',
    () async {
      final harness = SalaHarness();
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);
      expect(read().keptRetellings, isEmpty);

      harness.room.keptRetellings = [_sceneOne];
      notifier.conversaTap();
      await settle();
      notifier.conversaTap();
      await waitFor(
        'a leitura depois do turno trazer o take mantido',
        () => read().keptRetellings.isNotEmpty,
      );

      expect(
        read().keptRetellings.map((take) => take.scope),
        ['S1'],
        reason: 'o take mantido que a sala listou não chegou à tela',
      );
    },
  );

  test(
    'the next read replaces the list whole, a scene told again keeps its newest take and a read with none empties it',
    () async {
      final harness = SalaHarness()..room.keptRetellings = [_sceneOne];
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      SalaSessionState read() => container.read(salaSessionProvider);
      Future<void> aTurn() async {
        notifier.conversaTap();
        await settle();
        notifier.conversaTap();
      }

      await aTurn();
      await waitFor(
        'a leitura trazer o primeiro take',
        () => read().keptRetellings.isNotEmpty,
      );

      harness.room.keptRetellings = [
        const KeptRetelling(
          scope: 'S1',
          turnNumber: 7,
          audioUrl: 'https://storage.example/kept/cc/conto.m4a?sig=3',
        ),
      ];
      await settle();
      await aTurn();
      await waitFor(
        'a leitura trazer o take refeito',
        () => read().keptRetellings.single.turnNumber == 7,
      );
      expect(read().keptRetellings.single.turnNumber, 7);

      harness.room.keptRetellings = const [];
      await settle();
      await aTurn();
      await waitFor(
        'a leitura sem takes esvaziar a lista',
        () => read().keptRetellings.isEmpty,
      );
      expect(
        read().keptRetellings,
        isEmpty,
        reason: 'uma leitura sem takes mantidos deixava os velhos na tela',
      );
    },
  );
}

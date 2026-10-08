import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/moment.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'session_notifier_test.dart' show inConversa;

const _familiarization = Moment(at: MomentAt.familiarization, parts: 4);

void main() {
  test(
    'a later reply that opens scene two moves the moment the team sees',
    () async {
      final harness = SalaHarness()..room.nextMoment = _familiarization;
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      expect(
        container.read(salaSessionProvider).moment?.at,
        MomentAt.familiarization,
      );

      harness.room.nextMoment = const Moment(
        at: MomentAt.internalization,
        part: 2,
        parts: 4,
      );
      notifier.conversaTap();
      await settle();
      notifier.conversaTap();
      await waitFor(
        'o momento seguir a resposta',
        () => container.read(salaSessionProvider).moment?.part == 2,
      );

      final moment = container.read(salaSessionProvider).moment;
      expect(
        moment?.at,
        MomentAt.internalization,
        reason: 'a voz abriu a cena 2 e a tela ficou na Familiarização',
      );
      expect(moment?.part, 2);
    },
  );

  test(
    'a reply that carries no moment takes the label away rather than leave a stale one',
    () async {
      final harness = SalaHarness()..room.nextMoment = _familiarization;
      final container = await inConversa(harness);
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);

      harness.room.nextMoment = null;
      notifier.conversaTap();
      await settle();
      notifier.conversaTap();
      await waitFor(
        'o momento sair da tela',
        () => container.read(salaSessionProvider).moment == null,
      );

      expect(
        container.read(salaSessionProvider).moment,
        isNull,
        reason:
            'a sala parou de mandar o momento e a tela continuou mostrando o antigo',
      );
    },
  );
}

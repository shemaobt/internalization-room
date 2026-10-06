import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_styles.dart';
import 'package:internalization_room/features/sala/presentation/widgets/colar_overlay.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show byLabel;

void main() {
  testWidgets(
    'the panorama played in the invitation draws no necklace, while it plays and after',
    (tester) async {
      final harness = SalaHarness();
      final container = await pumpSala(tester, harness);
      expect(find.byType(ColarOverlay), findsNothing);

      await tester.tap(byLabel('Falar com o facilitador'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(ColarOverlay), findsNothing);

      await tester.pump(const Duration(milliseconds: 200));
      expect(
        container.read(salaSessionProvider).conviteStep,
        ConviteStep.entrada,
        reason: 'a abertura já foi dita',
      );
      expect(find.byType(ColarOverlay), findsNothing);
    },
  );

  testWidgets(
    'a passage just entered draws twelve beads with none lit, whatever its element count',
    (tester) async {
      final harness = SalaHarness()
        ..room.passages = const [
          Passagem(pericope: 'P01', audioUrl: '/voice/p01', beads: 29),
        ];
      final container = await pumpSala(tester, harness);
      final notifier = container.read(salaSessionProvider.notifier);
      await notifier.abrirEscolha();
      await tester.pump(const Duration(milliseconds: 300));

      harness.room.holdNextCreate();
      final entering = notifier.goConversa(pericope: 'P01');
      await tester.pump(const Duration(milliseconds: 100));
      expect(harness.room.createHeld, isTrue);

      expect(find.byType(ColarOverlay), findsOneWidget);
      final beads = find.descendant(
        of: find.byType(ColarOverlay),
        matching: find.byType(AnimatedContainer),
      );
      expect(beads, findsNWidgets(12));
      for (var i = 0; i < 12; i++) {
        final decoration =
            tester.widget<AnimatedContainer>(beads.at(i)).decoration
                as BoxDecoration;
        expect(decoration.gradient, isNot(BeadStyles.wood));
      }

      harness.room.finishHeldCreate();
      await entering;
      closeTheRoom(container);
    },
  );
}

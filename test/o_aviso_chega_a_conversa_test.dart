import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_styles.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;

void main() {
  testWidgets(
    'a warning that lands in the Conversation leaves the team screen as it '
    'was, with no mark beside the circle',
    (tester) async {
      final handle = tester.ensureSemantics();
      final harness = SalaHarness(lingua: 'en')
        ..room.serverStatus = 'needs_person'
        ..room.serverHalt = HaltKind.warning
        ..room.holdNextState();
      Timer(const Duration(seconds: 5), harness.room.finishHeldState);
      final container = await pumpSala(tester, harness);
      final notifier = container.read(salaSessionProvider.notifier);
      await notifier.goConversa(book: 'Ruth');
      await tester.pump(const Duration(milliseconds: 200));

      await waitFor(
        'o aviso chegar',
        () => container.read(salaSessionProvider).warning,
        step: () => tester.pump(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        container.read(salaSessionProvider).warning,
        isTrue,
        reason: 'o aviso chega numa leitura de estado comum, sem parar a sala',
      );
      expect(container.read(salaSessionProvider).stage, SalaStage.conversa);
      expect(
        find.bySemanticsLabel('A warning is asking someone to come watch'),
        findsNothing,
        reason:
            'a marca verde ficava ao lado do círculo até a Mesa atender; a '
            'tela da equipe dela não mostra nada por um aviso (page.tsx:996-1062)',
      );
      expect(
        find.descendant(
          of: find.byType(FacilitatorCircle),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container &&
                (widget.decoration as BoxDecoration?)?.gradient ==
                    BeadStyles.verde,
          ),
        ),
        findsNothing,
        reason: 'nem a bolinha verde sem rótulo',
      );
      handle.dispose();
      closeTheRoom(container);
    },
  );
}

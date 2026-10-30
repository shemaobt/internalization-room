import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/bead_styles.dart';
import 'package:internalization_room/features/sala/presentation/widgets/ensaio_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show holdTheSession, intoTheRecordingHome;

void main() {
  testWidgets(
    'a warning that lands in the Rehearsal draws no mark beside the circle',
    (tester) async {
      final handle = tester.ensureSemantics();
      final gravada = File(
        '${Directory.systemTemp.createTempSync('sala-1141-ensaio').path}/p1.m4a',
      )..writeAsBytesSync([1, 2, 3]);
      addTearDown(() => gravada.parent.deleteSync(recursive: true));
      final harness = SalaHarness(filaEmMemoria: true, lingua: 'en')
        ..room.serverHalt = HaltKind.warning;
      await holdTheSession(
        harness,
        ResumePoint(
          sessionId: 'sessao-antiga',
          stage: SalaStage.ensaio,
          takes: [
            KeptTake(
              scopeId: KeptScope.parte(1),
              path: gravada.path,
              takeId: 'gravacao-1',
            ),
          ],
        ),
        language: 'en',
      );
      final container = harness.container();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const SalaApp()),
      );
      final notifier = container.read(salaSessionProvider.notifier);
      await intoTheRecordingHome(
        notifier,
        () => container.read(salaSessionProvider),
        step: () => letTheRehearsalReachTheRoom(tester),
      );
      await waitFor(
        'a casa ser desenhada com o aviso de pé',
        () =>
            container.read(salaSessionProvider).warning &&
            find.byType(EnsaioView).evaluate().isNotEmpty,
        step: () => letTheRehearsalReachTheRoom(tester),
      );
      await tester.pump();

      expect(
        container.read(salaSessionProvider).stage,
        SalaStage.ensaio,
        reason: 'o caso precisa reabrir dentro do Ensaio',
      );
      expect(find.byType(EnsaioView), findsOneWidget);
      expect(
        container.read(salaSessionProvider).warning,
        isTrue,
        reason: 'e com o aviso já de pé, herdado da retomada',
      );
      expect(
        find.text('A warning is asking someone to come watch'),
        findsNothing,
      );
      expect(
        find.bySemanticsLabel('A warning is asking someone to come watch'),
        findsNothing,
        reason:
            'a marca verde aparecia também no Ensaio; a tela dela não '
            'mostra nada por um aviso, e quem lista o aviso é a Mesa',
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
      );
      closeTheRoom(container);
      handle.dispose();
    },
  );
}

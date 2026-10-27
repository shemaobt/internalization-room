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
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';

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
      harness.emAberto.rows['Ruth/P01/en'] = ResumePoint(
        sessionId: 'sessao-antiga',
        stage: SalaStage.ensaio,
        takes: [
          KeptTake(
            scopeId: KeptScope.parte(1),
            path: gravada.path,
            takeId: 'gravacao-1',
          ),
        ],
      );
      final container = harness.container();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const SalaApp()),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final notifier = container.read(salaSessionProvider.notifier);
      await tester.runAsync(notifier.abrirEscolha);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.runAsync(
        () => notifier.goConversa(book: 'Ruth', pericope: 'P01'),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(seconds: 1));
      }

      expect(
        container.read(salaSessionProvider).stage,
        SalaStage.ensaio,
        reason: 'o caso precisa reabrir dentro do Ensaio',
      );
      expect(
        container.read(salaSessionProvider).warning,
        isTrue,
        reason: 'e com o aviso já de pé, herdado da retomada',
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
      handle.dispose();
    },
  );
}

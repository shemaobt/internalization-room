import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/main.dart';

import 'fakes.dart';

void main() {
  testWidgets(
    'a warning that lands in the Rehearsal shows its mark beside the circle',
    (tester) async {
      final handle = tester.ensureSemantics();
      final gravada = File(
        '${Directory.systemTemp.createTempSync('sala-1141-ensaio').path}/p1.m4a',
      )..writeAsBytesSync([1, 2, 3]);
      addTearDown(() => gravada.parent.deleteSync(recursive: true));
      final harness = SalaHarness(filaEmMemoria: true, lingua: 'en')
        ..room.serverHalt = HaltKind.warning;
      harness.emAberto.rows['Ruth/P01'] = ResumePoint(
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
      await tester.runAsync(() => notifier.goConversa(pericope: 'P01'));
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
        findsOneWidget,
        reason:
            'a Rehearsal é onde a língua materna é gravada (madeira), e um '
            'aviso atravessa as estações — o glossário diz "enquanto um '
            'aviso estiver de pé", não só na Conversa e na Retro',
      );
      handle.dispose();
    },
  );
}

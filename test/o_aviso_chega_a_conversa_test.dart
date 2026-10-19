import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;

void main() {
  testWidgets(
    'a warning that lands in the Conversation shows its mark beside the '
    'circle, in the rooms language',
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
        findsOneWidget,
        reason:
            'a marca existe ao lado do círculo, mas o que ela diz a um '
            'leitor de tela em inglês precisa vir do mapa, não do português '
            'fixo — a Conversa é onde a equipe passa a maior parte do turno',
      );
      handle.dispose();
      closeTheRoom(container);
    },
  );
}

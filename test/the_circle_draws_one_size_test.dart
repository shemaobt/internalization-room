import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/linked_team.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/presentation/widgets/escolha_view.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;

const _unclaimed = RememberedLink();

void main() {
  testWidgets('o convite desenha o círculo em 160 px', (tester) async {
    await pumpSala(tester, SalaHarness());

    expect(
      tester.getSize(find.byType(FacilitatorCircle)),
      const Size(160, 160),
    );
  });

  testWidgets('a escolha desenha o círculo em 160 px', (tester) async {
    final container = await pumpSala(tester, SalaHarness());
    await container.read(salaSessionProvider.notifier).abrirEscolha();
    await tester.pump(const Duration(milliseconds: 1500));

    expect(
      tester.getSize(
        find.descendant(
          of: find.byType(EscolhaView),
          matching: find.byType(FacilitatorCircle),
        ),
      ),
      const Size(160, 160),
    );
  });

  testWidgets('o código desenha o círculo em 160 px', (tester) async {
    final harness = SalaHarness(linkedAs: _unclaimed)..room.holdNextCode();
    await pumpSala(tester, harness);
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      tester.getSize(find.byType(FacilitatorCircle)),
      const Size(160, 160),
    );
  });

  testWidgets('a porta do microfone desenha o círculo em 160 px', (
    tester,
  ) async {
    final harness = SalaHarness()..recorder.permitted = false;
    await pumpSala(tester, harness);
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      tester.getSize(find.byType(FacilitatorCircle)),
      const Size(160, 160),
    );
  });
}

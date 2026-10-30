import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/linked_team.dart';
import 'package:internalization_room/features/sala/presentation/widgets/facilitator_circle.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;

const _unclaimed = RememberedLink();

void main() {
  testWidgets('o código desenha o círculo em 160 px', (tester) async {
    final harness = SalaHarness(linkedAs: _unclaimed)..room.holdNextCode();
    await pumpSala(tester, harness);
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      tester.getSize(find.byType(FacilitatorCircle)),
      const Size(160, 160),
    );
  });
}

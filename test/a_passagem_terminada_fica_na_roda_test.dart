import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/core/theme/sala_colors.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';
import 'package:internalization_room/features/sala/presentation/widgets/passage_ruler.dart';

import 'fakes.dart';
import 'sala_screen_test.dart' show pumpSala;
import 'scenario_helpers.dart' show settle;

void main() {
  testWidgets('a passage with work waiting on this tablet looks like one '
      'never opened', (tester) async {
    final harness = SalaHarness();
    harness.emAberto.rows['Ruth/P02'] = const ResumePoint(
      sessionId: 'sessao-da-p02',
      stage: SalaStage.retro,
    );
    final container = await pumpSala(tester, harness);
    await container.read(salaSessionProvider.notifier).abrirEscolha();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byType(PassageRuler),
      paints
        ..line(color: SalaColors.light.cord, strokeWidth: 1.5)
        ..line(color: SalaColors.light.cord, strokeWidth: 2)
        ..line(color: SalaColors.light.cord, strokeWidth: 2)
        ..line(color: SalaColors.light.cord, strokeWidth: 2),
    );
    expect(find.byType(PassageRuler), isNot(paints..circle(radius: 3)));
  });

  testWidgets('the entry the team left is tinted', (tester) async {
    final harness = SalaHarness();
    final container = await pumpSala(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);
    await tester.runAsync(() async {
      await notifier.goConversa(pericope: 'P03');
      await settle();
      notifier.leaveThePassage();
      await settle();
    });
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byType(PassageRuler),
      paints
        ..line(color: SalaColors.light.cord, strokeWidth: 1.5)
        ..line(color: SalaColors.light.cord, strokeWidth: 2)
        ..line(color: SalaColors.light.cord, strokeWidth: 2)
        ..line(color: ShemaBrand.azul),
    );
  });

  testWidgets('nothing is tinted after the tablet is relaunched', (
    tester,
  ) async {
    final harness = SalaHarness();
    final container = await pumpSala(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);
    await tester.runAsync(() async {
      await notifier.goConversa(pericope: 'P03');
      await settle();
      notifier.leaveThePassage();
      await settle();
    });
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byType(PassageRuler),
      paints
        ..line(color: SalaColors.light.cord, strokeWidth: 1.5)
        ..line(color: SalaColors.light.cord, strokeWidth: 2)
        ..line(color: SalaColors.light.cord, strokeWidth: 2)
        ..line(color: ShemaBrand.azul),
    );

    await tester.pumpWidget(const SizedBox());
    container.dispose();
    final relaunched = await pumpSala(tester, harness);
    await relaunched.read(salaSessionProvider.notifier).abrirEscolha();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byType(PassageRuler),
      paints
        ..line(color: SalaColors.light.cord, strokeWidth: 1.5)
        ..line(color: SalaColors.light.cord, strokeWidth: 2)
        ..line(color: SalaColors.light.cord, strokeWidth: 2)
        ..line(color: SalaColors.light.cord, strokeWidth: 2),
    );
  });

  testWidgets('the Panorama the team left is tinted', (tester) async {
    final harness = SalaHarness()
      ..room.passages = const [
        Passagem(
          pericope: 'OV',
          audioUrl: '/voice/ov',
          kind: PassagemKind.panorama,
        ),
        Passagem(pericope: 'P01', audioUrl: '/voice/p01'),
      ];
    final container = await pumpSala(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);
    await tester.runAsync(() async {
      await notifier.abrirEscolha();
      await settle();
      notifier.entrarNaOferecida();
      await settle();
      notifier.leaveThePassage();
      await settle();
    });
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byType(PassageRuler),
      paints
        ..line(color: SalaColors.light.cord, strokeWidth: 1.5)
        ..line(color: ShemaBrand.azul),
    );
  });

  testWidgets('a zeroed passage loses its mark at the next load', (
    tester,
  ) async {
    final harness = SalaHarness()
      ..room.passages = const [
        Passagem(pericope: 'P01', audioUrl: '/voice/p01', approved: true),
        Passagem(pericope: 'P02', audioUrl: '/voice/p02'),
      ];
    final container = await pumpSala(tester, harness);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byType(PassageRuler),
      paints
        ..line(color: SalaColors.light.cord, strokeWidth: 1.5)
        ..line(color: ShemaBrand.verdeClaro)
        ..circle(x: 30, color: SalaColors.light.telha, radius: 3),
    );

    harness.room.passages = const [
      Passagem(pericope: 'P01', audioUrl: '/voice/p01'),
      Passagem(pericope: 'P02', audioUrl: '/voice/p02'),
    ];
    await notifier.abrirEscolha();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(PassageRuler), isNot(paints..circle(radius: 3)));
    expect(
      find.byType(PassageRuler),
      isNot(paints..line(color: ShemaBrand.verdeClaro)),
    );
  });
}

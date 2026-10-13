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

const _todasFeitas = {'Ruth/P01', 'Ruth/P02', 'Ruth/P03'};

void main() {
  test('a book with every passage finished calls nobody', () async {
    final harness = SalaHarness();
    harness.finished.done.addAll(_todasFeitas);
    final container = harness.container();
    addTearDown(container.dispose);

    await container.read(salaSessionProvider.notifier).abrirEscolha();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(
      state.naRoda,
      hasLength(3),
      reason:
          'a equipe que terminou Rute ficava com uma roda vazia, e a '
          'resposta da sala a terminar o livro era chamar uma pessoa',
    );
    expect(state.needsPerson, isFalse);
    expect(
      harness.voice.fixedLines,
      isNot(contains(('E0', testLanguage))),
      reason:
          'o círculo é alive at done: o registro informa, ele não fecha '
          'a conversa',
    );
  });

  testWidgets('a passage with work waiting or carried to the end on this '
      'tablet looks like one never opened', (tester) async {
    final harness = SalaHarness();
    harness.finished.done.add('Ruth/P01');
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

  test(
    'a passage already carried to the end is entered from the wheel again',
    () async {
      final harness = SalaHarness();
      harness.finished.done.add('Ruth/P01');
      final container = harness.container();
      addTearDown(container.dispose);
      final notifier = container.read(salaSessionProvider.notifier);
      await notifier.abrirEscolha();
      await settle();

      notifier.entrarNaOferecida();
      await settle();

      expect(
        harness.room.pericopesAsked,
        contains('P01'),
        reason:
            'a P01 abre a roda, e a equipe que quer voltar ao que trabalhou '
            'não tinha por onde: a passagem não estava mais lá para ser tocada',
      );
      expect(container.read(salaSessionProvider).stage, SalaStage.conversa);
    },
  );
}

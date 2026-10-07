import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
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

  testWidgets(
    'the row is told which notch the team already carried to the end',
    (tester) async {
      final harness = SalaHarness();
      harness.finished.done.add('Ruth/P01');
      final container = await pumpSala(tester, harness);
      await container.read(salaSessionProvider.notifier).abrirEscolha();
      await tester.pump(const Duration(milliseconds: 300));

      final regua = tester.widget<PassageRuler>(find.byType(PassageRuler));
      expect(
        regua.finished,
        {0},
        reason:
            'a P01 é a primeira da roda, e sem o índice a régua desenha a '
            'passagem terminada igual a uma que ninguém tocou',
      );
      expect(
        regua.started,
        isEmpty,
        reason:
            'terminar apaga o ponto de retomada: trabalho parado e trabalho '
            'terminado são dois atos diferentes e a régua não pode confundi-los',
      );
    },
  );

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

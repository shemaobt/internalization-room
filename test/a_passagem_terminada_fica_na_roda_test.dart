import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';

import 'fakes.dart';
import 'session_notifier_test.dart' show settle;

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
    expect(state.naRoda, hasLength(3),
        reason: 'a equipe que terminou Rute ficava com uma roda vazia, e a '
            'resposta da sala a terminar o livro era chamar uma pessoa');
    expect(state.needsPerson, isFalse);
    expect(harness.voice.assets,
        isNot(contains(fixedLineAsset(needsPersonLine, testLanguage))),
        reason: 'o círculo é alive at done: o registro informa, ele não fecha '
            'a conversa');
  });
}

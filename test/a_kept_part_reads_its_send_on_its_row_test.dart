import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/scene_question.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

const _cenas = [
  Scene(sceneId: 'S1', title: 'A fome em Belém'),
  Scene(sceneId: 'S2', title: 'Noemi decide voltar'),
  Scene(sceneId: 'S3', title: 'Rute fica com Noemi'),
];

SceneRow _partThreeWhenItsNewestTakeIs(PartFact fact) => SalaSessionState(
  machine: Machine(
    session: 's1',
    keptThisVisit: const {'linha-3': (session: 's1', part: 3)},
    parts: {'linha-3': fact},
  ),
  scenes: const ScenesHad(_cenas),
).sceneRows[2];

void main() {
  test('a part whose newest kept take still waits to go reads enviando, never '
      'falhou', () {
    final row = _partThreeWhenItsNewestTakeIs(PartFact.pending);

    expect(row.unsent, isNotNull);
    expect(row.unsent?.failure, isNull);
  });

  test('a part whose newest kept take lost its copy reads falhou', () {
    final row = _partThreeWhenItsNewestTakeIs(PartFact.stranded);

    expect(row.unsent?.failure, SendFailure.failed);
  });
}

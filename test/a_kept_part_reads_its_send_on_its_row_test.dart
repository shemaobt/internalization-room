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

  test('a part whose newest kept take lost its copy reads it gone', () {
    final row = _partThreeWhenItsNewestTakeIs(PartFact.stranded);

    expect(row.unsent?.failure, SendFailure.gone);
  });

  test('a part being kept reads enviando over a failure it showed before', () {
    final row = SalaSessionState(
      machine: const Machine(
        session: 's1',
        keeping: {(session: 's1', part: 3): 1},
      ),
      scenes: const ScenesHad(_cenas),
      unsentParts: const {
        3: UnsentPart(fromAnEarlierVisit: false, failure: SendFailure.failed),
      },
    ).sceneRows[2];

    expect(row.unsent, isNotNull);
    expect(row.unsent?.failure, isNull);
  });
}

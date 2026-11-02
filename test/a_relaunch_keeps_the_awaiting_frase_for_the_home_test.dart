import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/scene_question.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart';
import 'um_ensaio_de_tres_partes.dart' show Sala;
import 'support/temp.dart';

Future<Sala> _relancarEAbrirACasa({required String takeDaFrase}) async {
  final harness = SalaHarness()
    ..playback.measured = const Duration(seconds: 10)
    ..room.passageScenes = const [
      Scene(sceneId: 'S1', title: 'Cena um'),
      Scene(sceneId: 'S2', title: 'Cena dois'),
    ];
  final casa = aTempDir('sala-frase-que-aguarda');
  KeptTake guardada(int n) => KeptTake(
    scopeId: KeptScope.parte(n),
    path: (File(
      '${casa.path}/gravacao-$n.m4a',
    )..writeAsBytesSync([1, 2, 3])).path,
    takeId: 'gravacao-$n',
  );
  harness.room
    ..takes.addAll([
      TakeView(
        takeId: 'gravacao-1',
        kind: 'ensaio',
        scope: KeptScope.parte(1),
        ordinal: 1,
      ),
      const TakeView(
        takeId: 'gravacao-velha-2',
        kind: 'ensaio',
        scope: 'parte-2',
        ordinal: 2,
      ),
      TakeView(
        takeId: 'gravacao-2',
        kind: 'ensaio',
        scope: KeptScope.parte(2),
        ordinal: 2,
      ),
    ])
    ..retroSoFar = BackTranslationProgress(
      segments: [
        SegmentView(
          segmentId: 'trecho-2',
          takeId: takeDaFrase,
          startsMs: 0,
          endsMs: 4000,
        ),
      ],
      awaitingSegmentId: 'trecho-2',
    );
  harness.emAberto.rows['Ruth/P01/pt'] = ResumePoint(
    sessionId: 'sessao-antiga',
    stage: SalaStage.ensaio,
    takes: [guardada(1), guardada(2)],
  );
  final it = Sala(harness, harness.container());
  addTearDown(it.container.dispose);
  await it.sala.abrirEscolha();
  await it.sala.goConversa(book: 'Ruth', pericope: 'P01');
  await throughTheOrangeDot(it.sala, () => it.estado);
  return it;
}

void main() {
  for (final (nome, take) in [
    ('a gravação emendada que o tablet guarda', 'gravacao-2'),
    (
      'a gravação velha que a emendada, listada depois, trocou',
      'gravacao-velha-2',
    ),
  ]) {
    test('a relaunch keeps the frase that awaits on $nome, so the home shows '
        'it on its scene row', () async {
      final it = await _relancarEAbrirACasa(takeDaFrase: take);

      await waitFor(
        'a frase que aguarda achar a sua cena',
        () => it.estado.trechoChamado(it.estado.btFraseQueAguarda)?.parte == 1,
      );
    });
  }
}

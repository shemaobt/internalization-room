import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/scene_question.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show intoTheRecordingHome, settle;

void main() {
  test('a row that still marks a part to record again reopens on the plain '
      'home, with no part marked', () async {
    final casa = Directory.systemTemp.createTempSync('sala-2035-marcada');
    addTearDown(() => casa.deleteSync(recursive: true));
    for (final n in [1, 2]) {
      File('${casa.path}/p$n.m4a').writeAsBytesSync([1, 2, 3]);
    }
    const linhaAntiga =
        '{"session_id":"sessao-antiga","stage":"ensaio",'
        '"part_being_recorded_again":0,"takes":['
        '{"name":"p1.m4a","scope":"parte-1","take":"gravacao-1"},'
        '{"name":"p2.m4a","scope":"parte-2","take":"gravacao-2"}]}';
    final harness = SalaHarness()
      ..room.passageScenes = const [
        Scene(sceneId: 'S1', title: 'A fome em Belém'),
        Scene(sceneId: 'S2', title: 'Noemi decide voltar'),
      ];
    harness.emAberto.rows['Ruth/P01/pt'] = ResumePoint.fromJson(
      jsonDecode(linhaAntiga) as Map<String, Object?>,
      folder: casa.path,
    )!;
    final container = harness.container();
    addTearDown(container.dispose);
    final sala = container.read(salaSessionProvider.notifier);
    await sala.abrirEscolha();
    await settle();
    unawaited(sala.goConversa(book: 'Ruth', pericope: 'P01'));
    await intoTheRecordingHome(sala, () => container.read(salaSessionProvider));

    await waitFor('a equipe voltar à casa do ensaio com as duas cenas', () {
      final estado = container.read(salaSessionProvider);
      return estado.stage == SalaStage.ensaio && estado.sceneRows.length == 2;
    });
    await settle();

    final estado = container.read(salaSessionProvider);
    expect(
      estado.ensaioDone,
      isTrue,
      reason: 'a marca da linha antiga deixava o disco de avançar apagado',
    );
  });
}

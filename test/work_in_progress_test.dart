import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

void main() {
  test('a resume point with several parts survives the disk in order', () async {
    final home = Directory.systemTemp.createTempSync('sala-em-curso');
    addTearDown(() => home.deleteSync(recursive: true));
    final gravacoes = Directory('${home.path}/recordings')
      ..createSync(recursive: true);
    final ledger = WorkInProgress(
      home: () async => home,
      recordings: () async => gravacoes,
    );

    await ledger.remember(
      'Ruth',
      'P03',
      ResumePoint(
        sessionId: 'sessao-1',
        stage: SalaStage.ensaio,
        takes: const [
          KeptTake(scopeId: 'parte-1', path: '/tmp/p1.m4a'),
          KeptTake(scopeId: 'parte-2', path: '/tmp/p2.m4a'),
          KeptTake(scopeId: 'parte-3', path: '/tmp/p3.m4a'),
        ],
      ),
    );

    final back = await ledger.of('Ruth', 'P03');

    expect(back, isNotNull);
    expect(back!.sessionId, 'sessao-1');
    expect([for (final take in back.takes) take.scopeId],
        ['parte-1', 'parte-2', 'parte-3']);
    expect([for (final take in back.takes) take.path], [
      '${gravacoes.path}/p1.m4a',
      '${gravacoes.path}/p2.m4a',
      '${gravacoes.path}/p3.m4a',
    ]);
  });

  test('a legacy row without a scope reads back as the whole passage', () async {
    final home = Directory.systemTemp.createTempSync('sala-em-curso-legado');
    addTearDown(() => home.deleteSync(recursive: true));
    final gravacoes = Directory('${home.path}/recordings')
      ..createSync(recursive: true);
    final ledger = WorkInProgress(
      home: () async => home,
      recordings: () async => gravacoes,
    );
    await ledger.remember(
      'Ruth',
      'P03',
      ResumePoint(
        sessionId: 'sessao-antiga',
        stage: SalaStage.ensaio,
        takes: const [KeptTake(scopeId: KeptScope.whole, path: '/tmp/todo.m4a')],
      ),
    );

    final back = await ledger.of('Ruth', 'P03');

    expect(back!.takes.single.scopeId, KeptScope.whole);
  });

  test('a row written by the shipped app still finds its audio', () async {
    final home = Directory.systemTemp.createTempSync('sala-em-curso-formato-antigo');
    addTearDown(() => home.deleteSync(recursive: true));
    final gravacoes = Directory('${home.path}/recordings')
      ..createSync(recursive: true);
    Directory('${home.path}/guardadas').createSync(recursive: true);
    // The shape the shipped app writes: the whole path, under a prefix this tablet no
    // longer has.
    File('${home.path}/guardadas/em_curso.json').writeAsStringSync(
      '{"Ruth/P03":{"session_id":"sessao-antiga","stage":"ensaio","pass":1,'
      '"takes":[{"path":"/var/mobile/Containers/Data/velho/recordings/p1.m4a",'
      '"scope":"parte-1"}]}}',
    );
    final ledger = WorkInProgress(
      home: () async => home,
      recordings: () async => gravacoes,
    );

    final back = await ledger.of('Ruth', 'P03');

    expect(back!.takes.single.path, '${gravacoes.path}/p1.m4a');
  });
}

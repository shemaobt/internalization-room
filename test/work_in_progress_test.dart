import 'dart:convert';
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

  test('each take carries which of its part\'s recordings it is', () async {
    final home = Directory.systemTemp.createTempSync('sala-em-curso-passada');
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
          KeptTake(scopeId: 'parte-2', path: '/tmp/p2.m4a', pass: 2),
        ],
      ),
    );

    final back = await ledger.of('Ruth', 'P03');

    expect([for (final take in back!.takes) take.pass], [1, 2],
        reason: 'sem isto a parte gravada de novo volta da retomada como a '
            'primeira gravação dela, e sobe outra vez sob a passada que a sala '
            'já tem');
  });

  test('a row written before the pass was kept per take reads every take as the first',
      () async {
    final home = Directory.systemTemp.createTempSync('sala-em-curso-passada-antiga');
    addTearDown(() => home.deleteSync(recursive: true));
    final gravacoes = Directory('${home.path}/recordings')
      ..createSync(recursive: true);
    Directory('${home.path}/guardadas').createSync(recursive: true);
    File('${home.path}/guardadas/em_curso.json').writeAsStringSync(
      '{"Ruth/P03":{"session_id":"sessao-antiga","stage":"ensaio","pass":2,'
      '"takes":[{"name":"p1.m4a","scope":"parte-1"},'
      '{"name":"p2.m4a","scope":"parte-2"}]}}',
    );
    final ledger = WorkInProgress(
      home: () async => home,
      recordings: () async => gravacoes,
    );

    final back = await ledger.of('Ruth', 'P03');

    expect([for (final take in back!.takes) take.pass], [1, 1],
        reason: 'a passada do ensaio inteiro não diz de qual gravação de qual '
            'parte ela era, e contar a partir dela numeraria partes que nunca '
            'foram gravadas de novo');
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

  test('uma linha escrita com lugares abre igual a uma sem', () async {
    const semLugares =
        '{"session_id":"sessao-antiga","stage":"retro","pass":2,'
        '"takes":[{"name":"p1.m4a","scope":"parte-1","take":"antiga-1"}]}';
    const comLugares =
        '{"session_id":"sessao-antiga","stage":"retro","pass":2,'
        '"takes":[{"name":"p1.m4a","scope":"parte-1","take":"antiga-1"}],'
        '"lugares":[{"take":"conserto-1","parte":0,"de":0,"ate":6000,'
        '"segmento":"trecho-1","fallback_arquivo":"materna-1.m4a",'
        '"fallback_de":0,"fallback_ate":27000}]}';

    ResumePoint linha(String bruto) => ResumePoint.fromJson(
          jsonDecode(bruto) as Map<String, Object?>,
          folder: '/gravacoes',
        )!;

    final velha = linha(comLugares);
    final nova = linha(semLugares);

    expect(velha.sessionId, nova.sessionId);
    expect(velha.stage, nova.stage);
    expect(
      [
        for (final take in velha.takes)
          '${take.scopeId}|${take.path}|${take.takeId}|${take.pass}',
      ],
      [
        for (final take in nova.takes)
          '${take.scopeId}|${take.path}|${take.takeId}|${take.pass}',
      ],
      reason: 'uma linha escrita por uma versão que ainda guardava lugares é '
          'aberta pela chave que lhe falta, e não pela que lhe sobra: o '
          'aparelho da equipe volta ao ponto onde parou',
    );
    expect(velha.toJson().containsKey('lugares'), isFalse,
        reason: 'e ao ser reescrita a linha não leva a chave adiante — nada a '
            'lê, e um lugar que ninguém consulta é a única fonte local que '
            'podia discordar do servidor');
  });
}

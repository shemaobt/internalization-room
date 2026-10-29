import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/grain.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

void main() {
  test(
    'a resume point with several parts survives the disk in order',
    () async {
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
        'pt',
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

      final back = await ledger.of('Ruth', 'P03', 'pt');

      expect(back, isNotNull);
      expect(back!.sessionId, 'sessao-1');
      expect(
        [for (final take in back.takes) take.scopeId],
        ['parte-1', 'parte-2', 'parte-3'],
      );
      expect(
        [for (final take in back.takes) take.path],
        [
          '${gravacoes.path}/p1.m4a',
          '${gravacoes.path}/p2.m4a',
          '${gravacoes.path}/p3.m4a',
        ],
      );
    },
  );

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
      'pt',
      ResumePoint(
        sessionId: 'sessao-1',
        stage: SalaStage.ensaio,
        takes: const [
          KeptTake(scopeId: 'parte-1', path: '/tmp/p1.m4a'),
          KeptTake(scopeId: 'parte-2', path: '/tmp/p2.m4a', pass: 2),
        ],
      ),
    );

    final back = await ledger.of('Ruth', 'P03', 'pt');

    expect(
      [for (final take in back!.takes) take.pass],
      [1, 2],
      reason:
          'sem isto a parte gravada de novo volta da retomada como a '
          'primeira gravação dela, e sobe outra vez sob a passada que a sala '
          'já tem',
    );
  });

  test(
    'a row written before the pass was kept per take reads every take as the first',
    () async {
      final home = Directory.systemTemp.createTempSync(
        'sala-em-curso-passada-antiga',
      );
      addTearDown(() => home.deleteSync(recursive: true));
      final gravacoes = Directory('${home.path}/recordings')
        ..createSync(recursive: true);
      Directory('${home.path}/guardadas').createSync(recursive: true);
      File('${home.path}/guardadas/em_curso.json').writeAsStringSync(
        '{"Ruth/P03":{"session_id":"sessao-antiga","language":"pt","stage":"ensaio","pass":2,'
        '"takes":[{"name":"p1.m4a","scope":"parte-1"},'
        '{"name":"p2.m4a","scope":"parte-2"}]}}',
      );
      final ledger = WorkInProgress(
        home: () async => home,
        recordings: () async => gravacoes,
      );

      final back = await ledger.of('Ruth', 'P03', 'pt');

      expect(
        [for (final take in back!.takes) take.pass],
        [1, 1],
        reason:
            'a passada do ensaio inteiro não diz de qual gravação de qual '
            'parte ela era, e contar a partir dela numeraria partes que nunca '
            'foram gravadas de novo',
      );
    },
  );

  test(
    'a legacy row without a scope reads back as the whole passage',
    () async {
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
        'pt',
        ResumePoint(
          sessionId: 'sessao-antiga',
          stage: SalaStage.ensaio,
          takes: const [
            KeptTake(scopeId: KeptScope.whole, path: '/tmp/todo.m4a'),
          ],
        ),
      );

      final back = await ledger.of('Ruth', 'P03', 'pt');

      expect(back!.takes.single.scopeId, KeptScope.whole);
    },
  );

  test('a row written by the shipped app still finds its audio', () async {
    final home = Directory.systemTemp.createTempSync(
      'sala-em-curso-formato-antigo',
    );
    addTearDown(() => home.deleteSync(recursive: true));
    final gravacoes = Directory('${home.path}/recordings')
      ..createSync(recursive: true);
    Directory('${home.path}/guardadas').createSync(recursive: true);
    // The shape the shipped app writes: the whole path, under a prefix this tablet no
    // longer has.
    File('${home.path}/guardadas/em_curso.json').writeAsStringSync(
      '{"Ruth/P03":{"session_id":"sessao-antiga","language":"pt","stage":"ensaio","pass":1,'
      '"takes":[{"path":"/var/mobile/Containers/Data/velho/recordings/p1.m4a",'
      '"scope":"parte-1"}]}}',
    );
    final ledger = WorkInProgress(
      home: () async => home,
      recordings: () async => gravacoes,
    );

    final back = await ledger.of('Ruth', 'P03', 'pt');

    expect(back!.takes.single.path, '${gravacoes.path}/p1.m4a');
  });

  test('a resume point keeps the wholes the room holds set aside through '
      'toJson/fromJson, and a row without them reads none', () {
    const linha = ResumePoint(
      sessionId: 'sessao-1',
      stage: SalaStage.ensaio,
      wholeHeldByTheRoom: ['gravacao-inteira'],
    );
    const semEles = '{"session_id":"sessao-1","stage":"ensaio","takes":[]}';

    final volta = ResumePoint.fromJson(linha.toJson(), folder: '/gravacoes')!;
    final antiga = ResumePoint.fromJson(
      jsonDecode(semEles) as Map<String, Object?>,
      folder: '/gravacoes',
    )!;

    expect(volta.wholeHeldByTheRoom, ['gravacao-inteira']);
    expect(antiga.wholeHeldByTheRoom, isEmpty);
  });

  test('a resume point keeps the grain in force through toJson/fromJson, and a '
      'row without it reads none', () {
    const linha = ResumePoint(
      sessionId: 'sessao-1',
      stage: SalaStage.ensaio,
      grain: Grain.whole,
    );
    const semEle = '{"session_id":"sessao-1","stage":"ensaio","takes":[]}';

    final volta = ResumePoint.fromJson(linha.toJson(), folder: '/gravacoes')!;
    final antiga = ResumePoint.fromJson(
      jsonDecode(semEle) as Map<String, Object?>,
      folder: '/gravacoes',
    )!;

    expect(volta.grain, Grain.whole);
    expect(antiga.grain, isNull);
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
      reason:
          'uma linha escrita por uma versão que ainda guardava lugares é '
          'aberta pela chave que lhe falta, e não pela que lhe sobra: o '
          'aparelho da equipe volta ao ponto onde parou',
    );
    expect(
      velha.toJson().containsKey('lugares'),
      isFalse,
      reason:
          'e ao ser reescrita a linha não leva a chave adiante — nada a '
          'lê, e um lugar que ninguém consulta é a única fonte local que '
          'podia discordar do servidor',
    );
  });

  test('forgetting a session leaves the place of another session in that '
      'passage', () async {
    final home = Directory.systemTemp.createTempSync('sala-em-curso-outra');
    addTearDown(() => home.deleteSync(recursive: true));
    final ledger = WorkInProgress(
      home: () async => home,
      recordings: () async => home,
    );
    await ledger.remember(
      'Ruth',
      'P01',
      'pt',
      const ResumePoint(sessionId: 'sessao-2', stage: SalaStage.conversa),
    );
    await ledger.remember(
      'Ruth',
      'P02',
      'pt',
      const ResumePoint(sessionId: 'sessao-1', stage: SalaStage.conversa),
    );

    final forgotten = await ledger.forgetTheSession('sessao-1');

    expect(forgotten.map((row) => row.sessionId), ['sessao-1']);
    expect((await ledger.of('Ruth', 'P01', 'pt'))?.sessionId, 'sessao-2');
    expect(await ledger.of('Ruth', 'P02', 'pt'), isNull);
  });

  group('a Resume point is kept per passage and language', () {
    late Directory home;
    late WorkInProgress ledger;
    File file() => File('${home.path}/guardadas/em_curso.json');

    setUp(() {
      home = Directory.systemTemp.createTempSync('sala-em-curso-lingua');
      ledger = WorkInProgress(
        home: () async => home,
        recordings: () async => home,
      );
    });
    tearDown(() => home.deleteSync(recursive: true));

    test('one passage keeps a Portuguese and an English place', () async {
      await ledger.remember(
        'Ruth',
        'P01',
        'pt',
        const ResumePoint(sessionId: 'sessao-pt', stage: SalaStage.ensaio),
      );
      await ledger.remember(
        'Ruth',
        'P01',
        'en',
        const ResumePoint(sessionId: 'sessao-en', stage: SalaStage.conversa),
      );

      expect((await ledger.of('Ruth', 'P01', 'pt'))?.sessionId, 'sessao-pt');
      expect((await ledger.of('Ruth', 'P01', 'en'))?.sessionId, 'sessao-en');
    });

    test('forgetting the English place leaves the Portuguese one', () async {
      await ledger.remember(
        'Ruth',
        'P01',
        'pt',
        const ResumePoint(sessionId: 'sessao-pt', stage: SalaStage.ensaio),
      );
      await ledger.remember(
        'Ruth',
        'P01',
        'en',
        const ResumePoint(sessionId: 'sessao-en', stage: SalaStage.conversa),
      );

      await ledger.forget('Ruth', 'P01', 'en');

      expect(await ledger.of('Ruth', 'P01', 'en'), isNull);
      expect((await ledger.of('Ruth', 'P01', 'pt'))?.sessionId, 'sessao-pt');
    });

    test(
      'a row the shipped app wrote is read as its language\'s row and left as it '
      'was until the team moves on',
      () async {
        Directory('${home.path}/guardadas').createSync(recursive: true);
        const shipped =
            '{"Ruth/P01":{"session_id":"sessao-antiga","stage":"ensaio",'
            '"language":"pt","takes":[]}}';
        file().writeAsStringSync(shipped);

        expect(
          (await ledger.of('Ruth', 'P01', 'pt'))?.sessionId,
          'sessao-antiga',
        );
        expect(await ledger.of('Ruth', 'P01', 'en'), isNull);
        expect(await ledger.startedIn('Ruth', 'pt'), {'P01'});
        expect(file().readAsStringSync(), shipped);

        await ledger.remember(
          'Ruth',
          'P01',
          'pt',
          const ResumePoint(sessionId: 'sessao-antiga', stage: SalaStage.retro),
        );

        expect(
          (await ledger.of('Ruth', 'P01', 'pt'))?.stage,
          SalaStage.retro,
          reason:
              'a linha antiga não pode voltar a responder depois de a equipe ter '
              'avançado',
        );
        expect(await ledger.of('Ruth', 'P01', 'en'), isNull);
        expect(await ledger.startedIn('Ruth', 'pt'), {'P01'});
      },
    );

    test('a row with no language answers for no language', () async {
      Directory('${home.path}/guardadas').createSync(recursive: true);
      file().writeAsStringSync(
        '{"Ruth/P01":{"session_id":"sessao-sem-lingua","stage":"ensaio",'
        '"takes":[]}}',
      );

      expect(await ledger.of('Ruth', 'P01', 'pt'), isNull);
      expect(await ledger.of('Ruth', 'P01', 'en'), isNull);
      expect(await ledger.startedIn('Ruth', 'pt'), isEmpty);
      expect(await ledger.startedIn('Ruth', 'en'), isEmpty);
    });

    test(
      'a passage is started only in the languages it has a place in',
      () async {
        Directory('${home.path}/guardadas').createSync(recursive: true);
        file().writeAsStringSync(
          '{"Ruth/P03":{"session_id":"sessao-antiga","stage":"ensaio",'
          '"language":"en","takes":[]}}',
        );
        await ledger.remember(
          'Ruth',
          'P01',
          'pt',
          const ResumePoint(sessionId: 'sessao-pt', stage: SalaStage.ensaio),
        );
        await ledger.remember(
          'Ruth',
          'P02',
          'en',
          const ResumePoint(sessionId: 'sessao-en', stage: SalaStage.ensaio),
        );

        expect(await ledger.startedIn('Ruth', 'pt'), {'P01'});
        expect(await ledger.startedIn('Ruth', 'en'), {'P02', 'P03'});
      },
    );

    test('closing a passage clears its row with no language too', () async {
      Directory('${home.path}/guardadas').createSync(recursive: true);
      file().writeAsStringSync(
        '{"Ruth/P01":{"session_id":"sessao-sem-lingua","stage":"ensaio",'
        '"takes":[]}}',
      );
      await ledger.remember(
        'Ruth',
        'P01',
        'pt',
        const ResumePoint(sessionId: 'sessao-pt', stage: SalaStage.retro),
      );

      await ledger.forget('Ruth', 'P01', 'pt');

      expect(file().readAsStringSync(), '{}');
    });
  });
}

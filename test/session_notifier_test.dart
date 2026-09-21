import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/facilitator_voice_service.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/take_upload_queue.dart';
import 'package:internalization_room/features/sala/domain/bt_finding.dart';
import 'package:internalization_room/features/sala/domain/coverage_event.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/hand_reply.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';

Future<void> settle([Duration delay = const Duration(milliseconds: 120)]) async {
  await Future<void>.delayed(delay);
}

Future<void> _intoFindings(
  SalaHarness harness,
  SalaSessionNotifier notifier,
  ProviderContainer container,
) async {
  notifier.goEnsaio();
  notifier.ensaioTap();
  notifier.ensaioTap();
  await settle();
  notifier.takeKeep();
  // A stretch is a slice of a recording the room can name, and the name is adopted only
  // once the take lands. Entering the retro before that makes every cut arrive with
  // nothing to point at, and the room drops it instead of sending it.
  await waitFor(
    'a sala nomear a parte',
    () => container.read(salaSessionProvider).partes.last.takeId != null,
  );
  notifier.startRetro();
  await settle();
  var contados = 0;
  for (final at in const [Duration(seconds: 12), Duration(seconds: 30)]) {
    harness.playback.at = at;
    notifier.cortarTrecho();
    await settle();
    notifier.retroTap();
    contados++;
    await waitFor('o trecho chegar à sala', () => harness.room.chunksSent == contados);
  }
  harness.playback.finishPlayback();
  // finishBackTranslation is a no-op while the clip has not ended, so the wait here is
  // for the door it opens rather than for a slice of clock.
  await waitFor(
    'o clipe poder ser dado por ouvido',
    () => container.read(salaSessionProvider).canFinishBackTranslation,
  );
  await notifier.finishBackTranslation();
}

Future<void> _intoConferida(
  SalaHarness harness,
  SalaSessionNotifier notifier,
) async {
  notifier.goEnsaio();
  notifier.ensaioTap();
  notifier.ensaioTap();
  await settle();
  notifier.takeKeep();
  notifier.startRetro();
  await settle();
  harness.playback.finishPlayback();
  await settle();
  await notifier.finishBackTranslation();
  await settle();
}

/// The team approves what it made, which is what finishes the passage and closes the
/// necklace. A clean verdict only opens the gesture.
Future<void> _aprovar(SalaSessionNotifier notifier) async {
  await notifier.aprovarRascunhoFinal();
  await settle(const Duration(milliseconds: 900));
}

Future<ProviderContainer> inConversa(SalaHarness harness) async {
  final container = harness.container();
  await container.read(salaSessionProvider.notifier).goConversa();
  await settle();
  return container;
}

void main() {
  test('session starts at convite with an inviting voice', () {
    final container = SalaHarness().container();
    addTearDown(container.dispose);

    final state = container.read(salaSessionProvider);

    expect(state.stage, SalaStage.convite);
    expect(state.voice, VoiceState.invite);
    expect(state.sessionId, isNull);
    expect(state.colarOn, isFalse);
  });

  test('resuming past the conversa does not reopen the conversa', () async {
    final harness = SalaHarness();
    final gravada = File(
      '${Directory.systemTemp.createTempSync('sala-retomada').path}/p1.m4a',
    )..writeAsBytesSync([1, 2, 3]);
    addTearDown(() => gravada.parent.deleteSync(recursive: true));
    harness.emAberto.rows['Ruth/P01'] = ResumePoint(
      sessionId: 'sessao-antiga',
      stage: SalaStage.ensaio,
      takes: [KeptTake(scopeId: KeptScope.parte(1), path: gravada.path)],
    );
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await settle();

    await notifier.goConversa(pericope: 'P01');
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.stage, SalaStage.ensaio);
    expect(state.partes.single.path, gravada.path);
    expect(harness.room.calls, isNot(contains('openSession')),
        reason: 'reabrir a conversa fazia o Guia perguntar como numa '
            'internalização para uma equipe que já estava no ensaio');
    expect(harness.room.calls, contains('fetchState'));
    expect(state.coverage.total, totalBeads);
  });

  test('a rehearsal with one part missing comes back to the conversa', () async {
    final harness = SalaHarness();
    final gravadas = Directory.systemTemp.createTempSync('sala-ensaio-partido');
    addTearDown(() => gravadas.deleteSync(recursive: true));
    final partes = [
      for (var parte = 1; parte <= 3; parte++)
        KeptTake(
          scopeId: KeptScope.parte(parte),
          path: (File('${gravadas.path}/parte-$parte.m4a')
                ..writeAsBytesSync([1, 2, 3]))
              .path,
        ),
    ];
    File(partes[1].path).deleteSync();
    harness.emAberto.rows['Ruth/P01'] = ResumePoint(
      sessionId: 'sessao-antiga',
      stage: SalaStage.ensaio,
      takes: partes,
    );
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await settle();

    await notifier.goConversa(pericope: 'P01');
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.stage, SalaStage.conversa,
        reason: 'duas partes de um ensaio de três voltavam como se fossem o '
            'ensaio inteiro, e a retro era contada por cima do buraco');
    expect(state.partes, isEmpty,
        reason: 'a próxima parte era carimbada com o número da que sumiu, e '
            'duas gravações diferentes chegavam ao servidor com um rótulo só');
    expect(File(partes.first.path).existsSync(), isTrue,
        reason: 'cair na conversa é deixar de oferecer o ensaio, não apagar o '
            'que a equipe gravou e ainda está no aparelho');
  });

  test('a row saved a week ago is resumed, not thrown away', () async {
    final harness = SalaHarness();
    final gravada = File(
      '${Directory.systemTemp.createTempSync('sala-semana-passada').path}/p1.m4a',
    )..writeAsBytesSync([1, 2, 3]);
    addTearDown(() => gravada.parent.deleteSync(recursive: true));
    harness.emAberto.rows['Ruth/P01'] = ResumePoint(
      sessionId: 'sessao-velha',
      stage: SalaStage.ensaio,
      takes: [KeptTake(scopeId: KeptScope.parte(1), path: gravada.path)],
      savedAt: DateTime.now().subtract(const Duration(days: 8)),
    );
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await settle();

    await notifier.goConversa(pericope: 'P01');
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.stage, SalaStage.ensaio,
        reason: 'a equipe que volta na semana seguinte encontra a passagem na '
            'estação em que a deixou, não na conversa');
    expect(state.partes.single.path, gravada.path,
        reason: 'com o ensaio que ela gravou debaixo dela');
    expect(state.sessionId, 'sessao-velha',
        reason: 'e dentro da sessão que o servidor continua a guardar');
    expect(harness.room.pericopesAsked, isEmpty,
        reason: 'pedir uma sessão nova aqui deixa órfã a que guarda tudo o '
            'que a equipe contou');
    expect(harness.emAberto.rows['Ruth/P01']?.sessionId, 'sessao-velha');
  });

  test('a passage entered afresh carries nothing of the session before it',
      () async {
    final harness = SalaHarness();
    final gravada = File(
      '${Directory.systemTemp.createTempSync('sala-recomeco').path}/p1.m4a',
    )..writeAsBytesSync([1, 2, 3]);
    addTearDown(() => gravada.parent.deleteSync(recursive: true));
    harness.emAberto.rows['Ruth/P01'] = ResumePoint(
      sessionId: 'sessao-antiga',
      stage: SalaStage.retro,
      takes: [
        KeptTake(
          scopeId: KeptScope.parte(1),
          path: gravada.path,
          takeId: 'gravacao-1',
        ),
      ],
    );
    harness.room.retroSoFar = const BackTranslationProgress(
      segments: [
        SegmentView(
          segmentId: 'trecho-1',
          takeId: 'gravacao-1',
          startsMs: 0,
          endsMs: 12000,
        ),
      ],
    );
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await settle();
    await notifier.goConversa(pericope: 'P01');
    await waitFor(
      'a sessão anterior estar de pé com o que ela contou',
      () => container.read(salaSessionProvider).btFimDasPartesMs.isNotEmpty,
    );

    await notifier.goConversa(pericope: 'P01', fresh: true);
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.keptTakes, isEmpty,
        reason: 'as contas da sessão recusada reapareciam no ensaio da '
            'sessão nova, como se a equipe já tivesse gravado nela');
    expect(state.takes, 0);
    expect(state.btTrechos, isEmpty,
        reason: 'e os trechos contados na sessão anterior não são desta');
    expect(state.btFimDasPartesMs, isEmpty,
        reason: 'nem a régua medida sobre as partes daquela');
    expect(state.stage, SalaStage.conversa);
    expect(state.sessionId, harness.room.sessionIds.single);
    expect(harness.room.pericopesAsked, hasLength(1),
        reason: 'entrar de novo é pedir uma sessão nova para a passagem');
    final linha = harness.emAberto.written.last;
    expect(linha.sessionId, harness.room.sessionIds.single);
    expect(linha.stage, SalaStage.conversa);
    expect(linha.takes, isEmpty);
  });

  test('the row written at the next station names only what this session recorded',
      () async {
    final harness = SalaHarness();
    harness.room.refuseTake = 'ensaio/${KeptScope.parte(1)}';
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await settle();
    await notifier.goConversa(pericope: 'P01');
    await settle();
    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await waitFor(
      'a tomada ser oferecida',
      () => container.read(salaSessionProvider).ensaio == EnsaioStatus.recorded,
    );
    notifier.takeKeep();
    await waitFor(
      'a gravação entrar na caixa de saída',
      () async => (await harness.takes.pending()).isNotEmpty,
    );
    final naCaixa = [for (final linha in await harness.takes.pending()) linha.id];

    await notifier.goConversa(pericope: 'P01', fresh: true);
    await settle();
    notifier.goEnsaio();
    await settle();

    final linha = harness.emAberto.written.last;
    expect(linha.sessionId, harness.room.sessionIds.last);
    expect(linha.stage, SalaStage.ensaio,
        reason: 'é a linha do ensaio que se mede: a da conversa é vazia por '
            'construção, e as duas escritas correm soltas');
    expect(linha.takes, isEmpty,
        reason: 'a linha era reescrita no ensaio com as gravações da sessão '
            'anterior sob o id da nova, e o servidor guardava a sessão que a '
            'equipe gravou sem linha nenhuma que a nomeasse');
    expect([for (final pendente in await harness.takes.pending()) pendente.id],
        naCaixa,
        reason: 'começar limpo é não herdar o que a sessão anterior gravou, '
            'não jogar fora o que ainda está subindo');
  });

  test('a session held through one 500 is dropped after the second, not kept forever',
      () async {
    final harness = SalaHarness();
    harness.emAberto.rows['Ruth/P01'] = ResumePoint(
      sessionId: 'sessao-velha',
      stage: SalaStage.conversa,
      savedAt: DateTime.now(),
    );
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await settle();

    harness.room.failWith = const RoomBroke('sem resposta');
    await notifier.goConversa(pericope: 'P01');
    await settle();

    expect(harness.emAberto.rows['Ruth/P01']?.sessionId, 'sessao-velha',
        reason: 'um único 500 é passageiro — não é motivo para abandonar o id');

    await notifier.goConversa(pericope: 'P01');
    await settle();

    expect(harness.emAberto.rows.containsKey('Ruth/P01'), isFalse,
        reason: 'dois 500 seguidos numa sessão retomada prendiam o aparelho a '
            'um id que o servidor não consegue servir');
  });

  test('the next passage opens with nothing of the one before it', () async {
    final harness = SalaHarness();
    final gravada = File(
      '${Directory.systemTemp.createTempSync('sala-passagem-anterior').path}/p1.m4a',
    )..writeAsBytesSync([1, 2, 3]);
    addTearDown(() => gravada.parent.deleteSync(recursive: true));
    harness.emAberto.rows['Ruth/P01'] = ResumePoint(
      sessionId: 'sessao-antiga',
      stage: SalaStage.retro,
      takes: [
        KeptTake(
          scopeId: KeptScope.parte(1),
          path: gravada.path,
          takeId: 'gravacao-1',
        ),
      ],
    );
    harness.room.retroSoFar = const BackTranslationProgress(
      segments: [
        SegmentView(
          segmentId: 'trecho-1',
          takeId: 'gravacao-1',
          startsMs: 0,
          endsMs: 12000,
        ),
      ],
    );
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await settle();
    await notifier.goConversa(pericope: 'P01');
    await waitFor(
      'a passagem anterior estar de pé com o que ela contou',
      () => container.read(salaSessionProvider).btFimDasPartesMs.isNotEmpty,
    );

    await notifier.goConversa(pericope: 'P02');
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.keptTakes, isEmpty,
        reason: 'a passagem seguinte abre sem as gravações da anterior: elas '
            'não são desta equipe nesta passagem');
    expect(state.btTrechos, isEmpty);
    expect(state.btFimDasPartesMs, isEmpty,
        reason: 'nem a régua medida sobre as partes da outra');
    expect(state.stage, SalaStage.conversa);
    final linha = harness.emAberto.written.last;
    expect(linha.sessionId, harness.room.sessionIds.single);
    expect(linha.takes, isEmpty,
        reason: 'e a linha da passagem nova não nomeia gravação nenhuma');
  });

  test('a take recorded and never kept does not stay on the tablet when the passage starts over',
      () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await settle();
    await notifier.goConversa(pericope: 'P01');
    await settle();
    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await waitFor(
      'a tomada ser oferecida',
      () => container.read(salaSessionProvider).ensaio == EnsaioStatus.recorded,
    );
    final gravada = harness.recorder.lastPath;

    await notifier.goConversa(pericope: 'P01', fresh: true);
    await settle();

    expect(harness.recorder.deleted, contains(gravada),
        reason: 'a gravação que a equipe não guardou não é nem tomada nem '
            'lixo: deixá-la no aparelho é a órfã que sair da passagem já '
            'sabia apagar');
  });

  test('a stored id created in pt does not post a turn to it from a device now in en',
      () async {
    final harness = SalaHarness(lingua: 'en');
    final gravada = File(
      '${Directory.systemTemp.createTempSync('sala-outra-lingua').path}/p2.m4a',
    )..writeAsBytesSync([1, 2, 3]);
    addTearDown(() => gravada.parent.deleteSync(recursive: true));
    harness.emAberto.rows['Ruth/P02'] = ResumePoint(
      sessionId: 'sessao-p02',
      stage: SalaStage.ensaio,
      savedAt: DateTime.now(),
      takes: [KeptTake(scopeId: KeptScope.parte(1), path: gravada.path)],
    );
    harness.emAberto.rows['Ruth/P01'] = ResumePoint(
      sessionId: 'sessao-pt',
      stage: SalaStage.conversa,
      savedAt: DateTime.now(),
      language: 'pt',
    );
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await settle();
    await notifier.goConversa(pericope: 'P02');
    await waitFor(
      'o ensaio da outra passagem estar de pé',
      () => container.read(salaSessionProvider).keptTakes.isNotEmpty,
    );

    await notifier.goConversa(pericope: 'P01');
    await settle();

    expect(harness.room.sessionsSpokenTo, isNot(contains('sessao-pt')),
        reason: 'a sessão foi aberta em português, e o Guia continuaria '
            'falando português para um aparelho que agora está em inglês');
    expect(harness.room.languagesSent, contains('en'),
        reason: 'a sessão nova é pedida na língua do aparelho de hoje, não na '
            'que a sessão abandonada carregava');
    expect(container.read(salaSessionProvider).keptTakes, isEmpty,
        reason: 'e a sessão nova nasce sem nada da passagem anterior');
  });

  test('advancing past the conversa still remembers when and in what language '
      'the session was born', () async {
    final harness = SalaHarness(lingua: 'en');
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await settle();
    await notifier.goConversa(pericope: 'P01');
    await settle();

    notifier.goEnsaio();

    final row = harness.emAberto.rows['Ruth/P01'];
    expect(row?.language, 'en',
        reason: 'a linha reescrita ao avançar de estágio apagava a língua '
            'gravada na criação, e a checagem de idioma parava de valer a '
            'partir do primeiro avanço');
    expect(row?.savedAt, isNotNull,
        reason: 'a mesma reescrita apagava a data em que a sessão nasceu, que '
            'é o que a linha guarda sobre ela');
  });

  test('the opening is told in two movements, and the necklace waits', () async {
    final harness = SalaHarness()..room.opensInTwoMovements = true;
    final container = await inConversa(harness);
    addTearDown(container.dispose);

    expect(harness.voice.played, [panoramaUrl, sceneUrl],
        reason: 'o todo primeiro, a cena depois — nessa ordem e sem emenda');

    final state = container.read(salaSessionProvider);
    expect(state.contasEnfiadas, isTrue,
        reason: 'as contas entram quando a cena chega e ficam');
    expect(state.lastSpoken!.url, sceneUrl);
    expect(state.lastSpoken!.panoramaUrl, panoramaUrl);
  });

  test('the necklace stays off the cord while the whole is being told', () async {
    final harness = SalaHarness()..room.opensInTwoMovements = true;
    harness.voice.holdNextLine();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    unawaited(notifier.goConversa(pericope: 'P01'));
    await waitFor('a primeira fala tocar', () => harness.voice.played.isNotEmpty);
    await settle();

    expect(harness.voice.played, [panoramaUrl]);
    expect(container.read(salaSessionProvider).contasEnfiadas, isFalse,
        reason: 'um colar cheio sobre uma passagem ainda não aberta diz que o '
            'trabalho já está posto');

    harness.voice.finishHeldLine();
    await waitFor(
      'as contas ficarem enfiadas',
      () => container.read(salaSessionProvider).contasEnfiadas,
    );
  });

  test('replaying takes the circle off team-talk while the room speaks', () async {
    final harness = SalaHarness()..room.peerCue = true;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    expect(container.read(salaSessionProvider).peerCue, isTrue);
    expect(container.read(salaSessionProvider).voice, VoiceState.invite,
        reason: 'é isto que desenha o círculo azul da equipe');

    harness.voice.fetched.clear();
    harness.voice.holdNextLine();
    unawaited(notifier.hearAgain());
    await waitFor('a segunda fala tocar', () => harness.voice.played.length > 1);
    await settle();

    expect(container.read(salaSessionProvider).voice, VoiceState.speaking,
        reason: 'enquanto a sala fala, o círculo é dela — não da equipe');
    expect(harness.voice.fetched, isEmpty,
        reason: 'a fala já está no aparelho: passar pela cara de "pensando" '
            'fazia o círculo mudar de cor duas vezes para repetir o que ela '
            'já tem na mão');

    harness.voice.finishHeldLine();
    await waitFor('o círculo voltar ao convite',
      () => container.read(salaSessionProvider).voice == VoiceState.invite,
    );

    expect(container.read(salaSessionProvider).peerCue, isTrue,
        reason: 'acabou de falar, a bola volta para a equipe');
  });

  test('a line the tablet no longer holds is waited for, not mimed', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    final line = container.read(salaSessionProvider).lastSpoken!.url;
    harness.voice.missing.add(line);
    harness.voice.holdNextFetch();

    unawaited(notifier.hearAgain());
    await settle();

    expect(container.read(salaSessionProvider).voice, VoiceState.thinking,
        reason: 'o círculo falando sem som é o que a espera de download '
            'sempre significou');

    harness.voice.finishHeldFetch();
    await waitFor('o círculo voltar ao convite',
      () => container.read(salaSessionProvider).voice == VoiceState.invite,
    );
  });

  test('a scene that never played is not a turn that finished', () async {
    final harness = SalaHarness()..room.opensInTwoMovements = true;
    harness.room.peerCue = true;
    harness.voice.refuses.add(sceneUrl);
    final container = await inConversa(harness);
    addTearDown(container.dispose);

    final state = container.read(salaSessionProvider);
    expect(harness.voice.played, [panoramaUrl, sceneUrl]);
    expect(state.peerCue, isFalse,
        reason: 'o panorama tocou e o convite não — dizer "conversem entre '
            'vocês" ali é a sala fingir que terminou de falar');
    expect(state.contasEnfiadas, isTrue);
  });

  test('ouvir de novo repeats the scene, never the whole passage', () async {
    final harness = SalaHarness()..room.opensInTwoMovements = true;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    harness.voice.played.clear();

    await notifier.hearAgain();
    await settle();

    expect(harness.voice.played, [sceneUrl]);
  });

  test('a held press gives the whole opening back, necklace and all', () async {
    final harness = SalaHarness()..room.opensInTwoMovements = true;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    harness.voice.played.clear();
    harness.voice.holdNextLine();

    unawaited(notifier.hearTheWholeOpening());
    await waitFor('a primeira fala tocar', () => harness.voice.played.isNotEmpty);
    await settle();

    expect(harness.voice.played, [panoramaUrl]);
    expect(container.read(salaSessionProvider).contasEnfiadas, isFalse,
        reason: 'as contas saem do fio para o panorama e voltam com a cena — é '
            'o que faz o gesto ser percebido sem uma palavra');

    harness.voice.finishHeldLine();
    await waitFor('a segunda fala tocar', () => harness.voice.played.length > 1);
    await settle();

    expect(harness.voice.played, [panoramaUrl, sceneUrl]);
    expect(container.read(salaSessionProvider).contasEnfiadas, isTrue);
  });

  test('an opening told in one breath shows the necklace at once', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);

    final state = container.read(salaSessionProvider);
    expect(state.contasEnfiadas, isTrue);
    expect(state.lastSpoken!.panoramaUrl, isEmpty);
    expect(state.lastSpoken!.toldInTwoMovements, isFalse);
  });

  test('a scene that will not play still hands the necklace over', () async {
    final harness = SalaHarness()..room.opensInTwoMovements = true;
    harness.voice.succeeds = false;
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.goConversa(pericope: 'P01');
    await settle();

    expect(container.read(salaSessionProvider).contasEnfiadas, isTrue,
        reason: 'um colar preso por uma falha nunca mais chegaria');
  });

  test('a canned line never takes the place of what the room told them', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    final told = container.read(salaSessionProvider).lastSpoken!.url;

    harness.room.turnsAreCanned = true;
    harness.room.fixedLine = 'A0';
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await waitFor('a sala dizer uma fala fixa', () => harness.voice.assets.isNotEmpty);
    await settle();

    expect(container.read(salaSessionProvider).lastSpoken!.url, told,
        reason: 'o replay devolvia "vamos parar um instante aqui" no lugar da '
            'cena que a equipe pediu para ouvir de novo');
  });

  test('the necklace is strung before the server answers', () async {
    final harness = SalaHarness();
    harness.room.passages = const [
      Passagem(pericope: 'P01', audioUrl: '/voice/p01', beads: 7, absenceIndex: 3),
    ];
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await settle();

    final entering = notifier.goConversa(pericope: 'P01');
    final seeded = container.read(salaSessionProvider).coverage;
    expect(seeded.total, 7,
        reason: 'esperar o create deixava a equipe diante de um cordão nu');
    expect(seeded.engaged, 0);
    expect(seeded.absenceIndex, 3);

    await entering;
    await settle();
    expect(container.read(salaSessionProvider).coverage.total, totalBeads,
        reason: 'a palavra final sobre o colar continua sendo do servidor');
  });

  test('the necklace is on only for the conversa and the fim', () {
    expect(const SalaSessionState(stage: SalaStage.escolha).colarOn, isFalse);
    expect(const SalaSessionState(stage: SalaStage.conversa).colarOn, isTrue);
    expect(const SalaSessionState(stage: SalaStage.ensaio).colarOn, isFalse,
        reason: 'o progresso do ensaio é a fileira de contas dos pedaços; a '
            'cobertura da conversa não muda ali');
    expect(const SalaSessionState(stage: SalaStage.retro).colarOn, isFalse,
        reason: 'na retro as contas são os trechos contados; o colar da '
            'conversa por cima lia como a mesma fileira de novo');
    expect(const SalaSessionState(stage: SalaStage.fim).colarOn, isTrue);
  });

  test('ping range covers newly engaged beads only', () {
    const ping = PingRange(4, 6);

    expect(ping.contains(3), isFalse);
    expect(ping.contains(4), isTrue);
    expect(ping.contains(5), isTrue);
    expect(ping.contains(6), isFalse);
  });

  test('entering the passage opens a session on the backend', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);

    expect(harness.room.calls, containsAllInOrder(['createSession', 'openSession']));
    expect(container.read(salaSessionProvider).sessionId, 'sessao-1');
    expect(harness.voice.played, hasLength(1));
  });

  test('a turn sends the recording and plays what comes back', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.conversaTap();
    expect(container.read(salaSessionProvider).voice, VoiceState.listening);
    await settle();

    notifier.conversaTap();
    await settle();

    expect(harness.room.turnsSent, 1);
    expect(harness.voice.played, hasLength(2));
    expect(container.read(salaSessionProvider).voice, VoiceState.invite);
  });

  test('the conversation keeps the words and throws the recording away', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();

    expect(harness.room.turnsSent, 1);
    expect(harness.recorder.deleted, [endsWith('captura-1.m4a')],
        reason: 'o registro da conversa é o texto no servidor — o áudio da equipe '
            'não é o produto e não pode ficar enchendo o tablet');
  });

  test('a turn the room refused still throws the recording away', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    harness.room.failWith = const RoomUnavailable('sem rede');

    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();

    expect(harness.recorder.deleted, [endsWith('captura-1.m4a')],
        reason: 'nenhum caminho de erro reenvia o arquivo, então guardá-lo só ocupa espaço');
  });

  test('the app never decides coverage — it mirrors the server', () async {
    final harness = SalaHarness()..room.nextCoverage = coverage(engaged: 5, surfaced: 7);
    final container = await inConversa(harness);
    addTearDown(container.dispose);

    final state = container.read(salaSessionProvider);
    expect(state.coverage.engaged, 5);
    expect(state.coverage.surfaced, 7);
    expect(state.coverage.total, totalBeads);
  });

  test('a peer cue from the server hands the talking to the team', () async {
    final harness = SalaHarness()..room.peerCue = true;
    final container = await inConversa(harness);
    addTearDown(container.dispose);

    expect(container.read(salaSessionProvider).peerCue, isTrue);
  });

  test('the next tap leaves team-talk mode and addresses the app', () async {
    final harness = SalaHarness()..room.peerCue = true;
    final container = await inConversa(harness);
    addTearDown(container.dispose);

    container.read(salaSessionProvider.notifier).conversaTap();

    final state = container.read(salaSessionProvider);
    expect(state.peerCue, isFalse);
    expect(state.voice, VoiceState.listening);
  });

  test('a passage opening retried after the room stalls asks again with the same turn id',
      () async {
    final harness = SalaHarness()..room.failHeldTurnWith = const RoomBroke('HTTP 500');
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.goConversa(pericope: 'P01');
    await settle();
    await waitFor('a sala parar', () => container.read(salaSessionProvider).needsPerson);
    harness.room.theDeskAttended();
    notifier.resolveWithPerson();
    await waitFor('o círculo voltar ao convite',
        () => container.read(salaSessionProvider).voice == VoiceState.invite);
    notifier.conversaTap();
    await settle();

    expect(harness.room.turnIdsAsked, hasLength(2),
        reason: 'a primeira falha ao abrir já é a chamada de turno que para a sala; '
            'o toque que segue o atendimento precisa dos dois pedidos de turno '
            'para haver o que comparar');
    expect(harness.room.turnIdsAsked[0], isNotNull);
    expect(harness.room.turnIdsAsked[1], harness.room.turnIdsAsked[0],
        reason: 'um id novo a cada tentativa e o servidor nunca reconhece '
            'a segunda como a mesma abertura que a primeira já começou a escrever');
  });

  test('a passage opening that outlives the wait is asked for again under the same id',
      () async {
    final harness = SalaHarness()..room.failHeldTurnWith = const RoomSlow();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.goConversa(pericope: 'P01');
    await settle();

    expect(harness.room.turnIdsAsked, hasLength(2),
        reason: 'a abertura estourava a espera do tablet, o círculo voltava ao '
            'aceno em silêncio e ninguém pedia a abertura de novo');
    expect(harness.room.turnIdsAsked[1], harness.room.turnIdsAsked[0],
        reason: 'um id novo faz o servidor rodar a abertura inteira outra vez '
            'em vez de devolver a que a primeira chamada já produziu');
    expect(harness.voice.assets, contains(fixedLineAsset('F0', testLanguage)),
        reason: 'a espera pelo segundo pedido é coberta pelo aceno instantâneo, '
            'não por mais silêncio');
  });

  test('the opening that arrives on the second ask is the one the room speaks',
      () async {
    final harness = SalaHarness()..room.failHeldTurnWith = const RoomSlow();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.goConversa(pericope: 'P01');
    await settle();

    expect(harness.voice.played, [turnoUrl],
        reason: 'a abertura atrasada chegava e ninguém a tocava — a sala já '
            'tinha voltado ao aceno como se a sessão nem tivesse começado');
    expect(container.read(salaSessionProvider).voice, VoiceState.invite,
        reason: 'só depois de o Guia falar o aceno fica vivo');
  });

  test('a passage opening the room never answers is given up on at the third ask',
      () async {
    final harness = SalaHarness()..room.failTurnsWith = const RoomSlow();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.goConversa(pericope: 'P01');
    await settle();

    expect(harness.room.turnIdsAsked, hasLength(3),
        reason: 'a sala pode ficar muda três vezes antes de o aparelho parar '
            'de esperar por ela — a abertura gasta o mesmo orçamento que um turno');
    expect(harness.room.turnIdsAsked.toSet(), hasLength(1));
    expect(harness.voice.assets, contains(offlineNoticeAsset(testLanguage)),
        reason: 'passado o limite a sala diz que não responde, do jeito que um '
            'turno lento diz, em vez de voltar ao aceno em silêncio');
  });

  test('a tap before the Guide has spoken asks for the opening, it never records a turn',
      () async {
    final harness = SalaHarness()..room.failTurnsWith = const RoomSlow();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.goConversa(pericope: 'P01');
    await settle();
    expect(container.read(salaSessionProvider).voice, VoiceState.invite);

    harness.room.failTurnsWith = null;
    notifier.conversaTap();
    await settle();

    expect(harness.recorder.captures, 0,
        reason: 'a equipe tocava e falava numa sessão que nunca tinha sido '
            'aberta — o Guia se apresentava em resposta a ela, ou nunca');
    expect(harness.room.turnsSent, 0);
    expect(harness.room.turnIdsAsked, hasLength(4),
        reason: 'o toque pede a abertura que ainda é devida, com o mesmo id');
    expect(harness.room.turnIdsAsked.toSet(), hasLength(1));
    expect(harness.voice.played, [turnoUrl],
        reason: 'a primeira voz na sala é a do Guia');
  });

  test('an opening that arrived but would not play still keeps the tap off the microphone',
      () async {
    final harness = SalaHarness()..voice.succeeds = false;
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.goConversa(pericope: 'P01');
    await settle();
    expect(container.read(salaSessionProvider).voice, VoiceState.invite);

    harness.voice.succeeds = true;
    notifier.conversaTap();
    await settle();

    expect(harness.recorder.captures, 0,
        reason: 'a abertura chegou e não tocou — o Guia ainda não falou, e o '
            'toque abria um take numa sala onde nada tinha sido dito');
    expect(harness.room.turnIdsAsked, hasLength(2));
    expect(harness.room.turnIdsAsked[1], isNot(harness.room.turnIdsAsked[0]),
        reason: 'o mesmo id devolve o mesmo clipe que acabou de falhar');
    expect(harness.voice.played.last, turnoUrl);
  });

  test('a passage left with its opening unheard does not hand its id to the next one',
      () async {
    final harness = SalaHarness()..room.failHeldTurnWith = const RoomBroke('HTTP 500');
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.goConversa(pericope: 'P01');
    await settle();
    notifier.leaveThePassage();
    await settle();
    await notifier.goConversa(pericope: 'P02');
    await settle();

    expect(harness.room.turnIdsAsked, hasLength(2));
    expect(harness.room.turnIdsAsked[1], isNot(harness.room.turnIdsAsked[0]),
        reason: 'o id nascia com a passagem e sobrevivia a ela: a abertura da '
            'passagem seguinte era pedida com o id de uma sessão que já ficou para trás');
  });

  test('two passages opened one after the other each get their own turn id',
      () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.goConversa(pericope: 'P01');
    await settle();
    await notifier.goConversa(pericope: 'P02');
    await settle();

    expect(harness.room.turnIdsAsked, hasLength(2));
    expect(harness.room.turnIdsAsked[1], isNot(harness.room.turnIdsAsked[0]),
        reason: 'a primeira passagem já foi aberta e falada; reaproveitar o '
            'id dela na segunda faria o servidor devolver aquela abertura '
            'em vez de abrir a passagem de fato pedida agora');
  });

  test('an opening the room could not play does not keep its id for the next attempt',
      () async {
    final harness = SalaHarness()..voice.succeeds = false;
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.goConversa(pericope: 'P01');
    await settle();
    harness.voice.succeeds = true;
    await notifier.goConversa(pericope: 'P01');
    await settle();

    expect(harness.room.turnIdsAsked, hasLength(2),
        reason: 'a primeira chegou e falhou ao tocar, e o segundo pedido '
            'precisa acontecer para haver o que comparar');
    expect(harness.room.turnIdsAsked[1], isNot(harness.room.turnIdsAsked[0]),
        reason: 'a primeira abertura já chegou da sala — reaproveitar o id '
            'dela faz o servidor devolver o mesmo áudio que acabou de '
            'falhar, em vez de abrir de novo');
  });

  test('beads settle from the server, not from the turn that just spoke', () async {
    final harness = SalaHarness(settleDelay: const Duration(milliseconds: 80))
      ..room.settledCoverage = coverage(engaged: 3, surfaced: 4);
    final container = harness.container();
    addTearDown(container.dispose);

    await container.read(salaSessionProvider.notifier).goConversa();
    expect(container.read(salaSessionProvider).coverage.engaged, 0);

    await settle(const Duration(milliseconds: 300));

    expect(harness.room.calls, contains('fetchState'));
    expect(container.read(salaSessionProvider).coverage.engaged, 3);
  });

  test('a settled frame pushed on the coverage channel updates the necklace before any clock would',
      () async {
    final harness = SalaHarness(settleDelay: const Duration(seconds: 60))
      ..room.turnIdInResponse = 'turno-1'
      ..room.settledCoverage = coverage(engaged: 3, surfaced: 4);
    final container = harness.container();
    addTearDown(container.dispose);

    await container.read(salaSessionProvider.notifier).goConversa();
    expect(container.read(salaSessionProvider).coverage.engaged, 0);

    harness.room.pushCoverage(
      const CoverageEvent(turnId: 'turno-1', status: CoverageStatus.settled),
    );
    await waitFor(
      'o colar assentar pelo canal',
      () => container.read(salaSessionProvider).coverage.engaged == 3,
    );

    expect(harness.room.calls.where((call) => call == 'fetchState').length, 1);
  });

  test('a settled frame that reports fewer beads than the necklace already shows changes nothing',
      () async {
    final harness = SalaHarness(settleDelay: const Duration(seconds: 60))
      ..room.turnIdInResponse = 'turno-1'
      ..room.nextCoverage = coverage(engaged: 5, surfaced: 5)
      ..room.settledCoverage = coverage(engaged: 2, surfaced: 2);
    final container = harness.container();
    addTearDown(container.dispose);

    await container.read(salaSessionProvider.notifier).goConversa();
    expect(container.read(salaSessionProvider).coverage.engaged, 5);

    harness.room.pushCoverage(
      const CoverageEvent(turnId: 'turno-1', status: CoverageStatus.settled),
    );
    await waitFor(
      'a leitura do servidor chegar',
      () => harness.room.calls.where((call) => call == 'fetchState').length == 1,
    );

    expect(container.read(salaSessionProvider).coverage.engaged, 5,
        reason: 'uma leitura que chega atrás não pode devolver o colar para trás '
            'do que a equipe já viu encher');
  });

  test('a failed frame ends the wait without asking the room anything', () async {
    final harness = SalaHarness(settleDelay: const Duration(seconds: 60))
      ..room.turnIdInResponse = 'turno-1';
    final container = harness.container();
    addTearDown(container.dispose);

    await container.read(salaSessionProvider.notifier).goConversa();

    harness.room.pushCoverage(
      const CoverageEvent(turnId: 'turno-1', status: CoverageStatus.failed),
    );
    await settle(const Duration(milliseconds: 200));

    expect(harness.room.calls, isNot(contains('fetchState')),
        reason: 'a classificação que falhou não deixa número nenhum para o colar buscar');
  });

  test('a coverage channel that never answers still gets exactly one fetch, and does not ask again',
      () async {
    final harness = SalaHarness(settleDelay: const Duration(milliseconds: 40))
      ..room.turnIdInResponse = 'turno-1';
    final container = harness.container();
    addTearDown(container.dispose);

    await container.read(salaSessionProvider.notifier).goConversa();

    await waitFor(
      'o fallback disparar',
      () => harness.room.calls.where((call) => call == 'fetchState').length == 1,
    );
    await settle(const Duration(milliseconds: 400));

    expect(harness.room.calls.where((call) => call == 'fetchState').length, 1,
        reason: 'a escada de tentativas saiu junto com o timer — uma leitura sem '
            'resposta nova não pede outra depois dela');
  });

  test('a turn already settled while it still spoke is not armed again when it finishes',
      () async {
    final harness = SalaHarness(settleDelay: const Duration(milliseconds: 40))
      ..room.turnIdInResponse = 'turno-1';
    harness.voice.holdNextLine();
    final container = harness.container();
    addTearDown(container.dispose);

    final opening = container.read(salaSessionProvider.notifier).goConversa();

    harness.room.pushCoverage(
      const CoverageEvent(turnId: 'turno-1', status: CoverageStatus.settled),
    );
    await waitFor(
      'o settled resolver antes da fala terminar',
      () => harness.room.calls.where((call) => call == 'fetchState').length == 1,
    );

    harness.voice.finishHeldLine();
    await opening;
    await settle(const Duration(milliseconds: 300));

    expect(harness.room.calls.where((call) => call == 'fetchState').length, 1,
        reason: 'o turno já resolveu pelo canal antes de terminar de falar; rearmar '
            'o mesmo id no fim da fala é o poll cego que este ticket tirou');
  });

  test('the hand inbox is still checked after a turn with nothing to wait on',
      () async {
    final harness = SalaHarness(settleDelay: const Duration(milliseconds: 40));
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.goConversa();
    await settle(const Duration(milliseconds: 200));

    harness.inbox.replies = [const HandReply(id: 'r1', audioUrl: 'a.mp3')];
    harness.room.classificationPending = false;
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();

    await waitFor(
      'a caixa da mesa chegar',
      () => container.read(salaSessionProvider).replies.isNotEmpty,
    );

    expect(container.read(salaSessionProvider).replies.single.id, 'r1',
        reason: 'nada de coverage pendente pra esperar não pode significar nada de '
            'caixa da mesa pra checar — são dois pedidos diferentes que só '
            'compartilhavam um timer');
  });

  test('the server closing the session offers the rehearsal, not a circle at rest',
      () async {
    final harness = SalaHarness()..room.done = true;
    final container = await inConversa(harness);
    addTearDown(container.dispose);

    expect(container.read(salaSessionProvider).voice, VoiceState.done);
    expect(container.read(salaSessionProvider).conversaDone, isTrue);
  });

  test('a tap on the circle at done still records, not a dead touch',
      () async {
    final harness = SalaHarness()..room.done = true;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    expect(container.read(salaSessionProvider).voice, VoiceState.done);

    notifier.conversaTap();
    expect(
      container.read(salaSessionProvider).voice,
      VoiceState.listening,
      reason: 'o done caía no bloco de no-op do switch de conversaTap, junto '
          'de thinking/speaking/needsPerson/offline/blocked, e nunca chamava '
          '_actOnConversaTap — o círculo não abria o microfone de novo',
    );
    await settle();

    notifier.conversaTap();
    await settle();

    expect(
      harness.room.turnsSent,
      1,
      reason: 'sem o primeiro toque abrindo o microfone, a segunda fala nunca '
          'virava um turno enviado ao Guia',
    );
    expect(
      container.read(salaSessionProvider).stage,
      SalaStage.conversa,
      reason: 'done muda o que a tela oferece, nunca fecha ou reinicia a '
          'conversa sozinha',
    );
    expect(
      container.read(salaSessionProvider).conversaDone,
      isTrue,
      reason: 'a sala continua reportando done, então a entrada de gravação '
          'segue oferecida ao mesmo tempo que o círculo volta a ouvir',
    );
  });

  test('a fixed line comes from the bundle, never from the wire', () async {
    final harness = SalaHarness()..room.fixedLine = 'D1';
    final container = await inConversa(harness);
    addTearDown(container.dispose);

    expect(harness.voice.assets, [fixedLineAsset('D1', testLanguage)]);
    expect(harness.voice.played, isEmpty,
        reason: 'a linha de segurança não pede rede — a rede costuma ser o que falhou');
    expect(harness.room.clipsFetched, isEmpty);
  });

  test('no network is caught before the team ever taps', () async {
    final harness = SalaHarness()..network.reachable = false;
    final container = await inConversa(harness);
    addTearDown(container.dispose);

    final state = container.read(salaSessionProvider);
    expect(state.offline, isTrue);
    expect(harness.voice.assets, [offlineNoticeAsset(testLanguage)]);
    expect(harness.room.calls, isEmpty, reason: 'nem tentou falar com o servidor');
  });

  test('a network that cannot reach the backend still counts as offline', () async {
    final harness = SalaHarness()..room.reachable = false;
    final container = await inConversa(harness);
    addTearDown(container.dispose);

    expect(container.read(salaSessionProvider).offline, isTrue);
    expect(harness.voice.assets, [offlineNoticeAsset(testLanguage)]);
  });

  test('the room comes back on its own when the network returns', () async {
    final harness = SalaHarness()..network.reachable = false;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    expect(container.read(salaSessionProvider).offline, isTrue);

    harness.network.reachable = true;
    harness.network.networkComesBack();
    await settle();

    expect(container.read(salaSessionProvider).offline, isFalse);
  });

  test('a network blip that still cannot reach the room keeps it offline', () async {
    final harness = SalaHarness()..network.reachable = false;
    final container = await inConversa(harness);
    addTearDown(container.dispose);

    harness.network.networkComesBack();
    await settle();

    expect(container.read(salaSessionProvider).offline, isTrue);
  });

  test('the offline notice is spoken once, not on every failure', () async {
    final harness = SalaHarness()..network.reachable = false;
    final container = await inConversa(harness);
    addTearDown(container.dispose);

    harness.network.networkComesBack();
    harness.network.networkComesBack();
    await settle();

    expect(harness.voice.assets, hasLength(1));
  });

  test('losing the backend mid-session goes offline, not to an error', () async {
    final harness = SalaHarness(retryBackoff: const [Duration(seconds: 30)]);
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    harness.room.reachable = false;
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();

    expect(container.read(salaSessionProvider).offline, isTrue);
  });

  test('a person resolves the offline halt once the room answers again', () async {
    final harness = SalaHarness()..room.reachable = false;
    final container = await inConversa(harness);
    addTearDown(container.dispose);

    harness.room.reachable = true;
    container.read(salaSessionProvider.notifier).resolveWithPerson();
    await waitFor('o círculo voltar ao convite',
      () => container.read(salaSessionProvider).voice == VoiceState.invite,
    );

    expect(container.read(salaSessionProvider).voice, VoiceState.invite,
        reason: 'a sala nunca chegou a ter sessão; o convite só é honesto '
            'depois que ela vai buscar uma');
  });

  test('the room comes back without the network ever changing', () async {
    final harness = SalaHarness()..network.reachable = false;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    expect(container.read(salaSessionProvider).offline, isTrue);

    harness.network.reachable = true;
    await settle();

    expect(container.read(salaSessionProvider).offline, isFalse,
        reason: 'esperar um evento do sistema que nunca vem prende a sala para sempre');
  });

  test('a tap asks the room again instead of doing nothing', () async {
    final harness = SalaHarness(retryBackoff: const [Duration(seconds: 30)])
      ..network.reachable = false;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final checksWhileOffline = harness.network.checks;

    harness.network.reachable = true;
    container.read(salaSessionProvider.notifier).conversaTap();
    await settle();

    expect(harness.network.checks, greaterThan(checksWhileOffline));
    expect(container.read(salaSessionProvider).offline, isFalse);
  });

  test('the notice is not spoken again each time a retry fails', () async {
    final harness = SalaHarness()..room.reachable = false;
    final container = await inConversa(harness);
    addTearDown(container.dispose);

    await waitFor('a sala dizer uma fala fixa', () => harness.voice.assets.isNotEmpty);
    await settle(const Duration(milliseconds: 200));

    expect(harness.voice.assets, hasLength(1),
        reason: 'a sala repetindo o aviso a cada 20ms é um alarme, não um recado');
  });

  test('a team that stays silent is never asked twice to begin', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);

    await container.read(salaSessionProvider.notifier).openTheRoom();
    await settle(const Duration(milliseconds: 200));

    expect(harness.voice.assets, isEmpty,
        reason: 'um convite repetido vira cobrança; quem abre a sessão agora é a fala '
            'que começa a passagem, não um lembrete sozinho');
    expect(harness.room.calls, isEmpty,
        reason: 'nada que a sala diz sozinha pode abrir sessao — o toque é que começa');
    expect(container.read(salaSessionProvider).awaitingFirstTouch, isTrue);
  });

  test('the convite speaks the panorama before offering the way in', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);

    await container.read(salaSessionProvider.notifier).openConvite();

    expect(harness.room.pericopesAsked, [panoramaPericope]);
    expect(harness.voice.played, hasLength(1));
    final state = container.read(salaSessionProvider);
    expect(state.conviteStep, ConviteStep.entrada);
    expect(state.showEntrada, isTrue);
    expect(state.sessionId, isNull,
        reason: 'o panorama é do livro; a sessão da perícope nasce ao entrar');
  });

  test('a question raised during the panorama posts against the panorama session',
      () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.openConvite();

    notifier.handTap();
    expect(container.read(salaSessionProvider).noteMode, isTrue,
        reason: 'a mão existe durante o panorama, a sessão inteira');

    notifier.conviteTap();
    notifier.conviteTap();
    await settle();

    expect(harness.inbox.questionsSent, ['sessao-1'],
        reason: 'sem sessão de perícope ainda, a pergunta vai para o panorama');
    expect(container.read(salaSessionProvider).stage, SalaStage.convite);
  });

  test('a touch on the hand before the panorama has a session arms nothing', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.handTap();

    expect(container.read(salaSessionProvider).noteMode, isFalse,
        reason: 'antes do primeiro toque não existe sessão de panorama para postar a '
            'pergunta — armar aqui chamaria uma pessoa na primeiríssima interação');
  });

  test('entering after the panorama says the team already met the facilitator',
      () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.openConvite();
    await notifier.goConversa();
    await settle();

    expect(harness.room.metBefore, [false, true],
        reason: 'sem esse aviso o facilitador se apresenta duas vezes na mesma mesa');
  });

  test('the convite without a room halts spoken, not on a dead screen', () async {
    final harness = SalaHarness(retryBackoff: const [Duration(seconds: 30)])
      ..network.reachable = false;
    final container = harness.container();
    addTearDown(container.dispose);

    await container.read(salaSessionProvider.notifier).openConvite();

    expect(container.read(salaSessionProvider).offline, isTrue);
    expect(harness.voice.assets, [offlineNoticeAsset(testLanguage)]);
    expect(container.read(salaSessionProvider).showEntrada, isFalse);
  });

  test('a room that answers badly does not disguise itself as a dead network',
      () async {
    final harness = SalaHarness()..room.failWith = const RoomBroke('HTTP 500');
    final container = harness.container();
    addTearDown(container.dispose);

    await container.read(salaSessionProvider.notifier).openConvite();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.offline, isFalse,
        reason: 'chamar de queda de rede uma sala que respondeu errado devolve '
            'a equipe ao aceno para sempre, sem nunca pedir ajuda');
    expect(state.needsPerson, isTrue,
        reason: 'abrir o convite é uma chamada de turno: o 500 chama alguém na hora, '
            'em vez de devolver a equipe ao aceno para tentar de novo sozinha');
    expect(harness.voice.assets, isNot(contains(offlineNoticeAsset(testLanguage))));
  });

  test('a convite retried after the room stalls asks again with the same turn id',
      () async {
    final harness = SalaHarness()..room.failHeldTurnWith = const RoomBroke('HTTP 500');
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.openConvite();
    await settle();
    await notifier.openConvite();
    await settle();

    expect(harness.room.turnIdsAsked, hasLength(2),
        reason: 'a primeira falha em abrir e o retoque que segue precisam '
            'dos dois pedidos de turno para haver o que comparar');
    expect(harness.room.turnIdsAsked[0], isNotNull);
    expect(harness.room.turnIdsAsked[1], harness.room.turnIdsAsked[0],
        reason: 'um id novo a cada tentativa e o servidor nunca reconhece '
            'a segunda como a mesma abertura que a primeira já começou a escrever');
  });

  test('a single bad answer asks for a person, not for another touch', () async {
    final harness = SalaHarness()..room.failWith = const RoomBroke('HTTP 500');
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.openConvite();
    await settle();

    expect(container.read(salaSessionProvider).needsPerson, isTrue,
        reason: 'não há escada a subir: o servidor já respondeu mal uma vez, e '
            'esperar mais tentativas é o "retried" que o ticket proíbe');

    notifier.resolveWithPerson();

    expect(container.read(salaSessionProvider).voice, VoiceState.invite);
  });

  test('a server error mid-conversation calls a person; a touch returns to the same '
      'session', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    SalaSessionState read() => container.read(salaSessionProvider);
    final sessionId = read().sessionId;
    expect(sessionId, isNotNull);

    harness.room.failWith = const RoomBroke('HTTP 500');
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await waitFor('a sala parar por causa do servidor', () => read().needsPerson);

    expect(read().sessionId, sessionId,
        reason: 'o erro não é motivo para largar a sessão — só a mesa manda embora '
            'uma sessão que o servidor já esqueceu');

    harness.room.theDeskAttended();
    notifier.resolveWithPerson();
    await waitFor('o toque devolver a sala', () => read().voice == VoiceState.invite);

    expect(read().sessionId, sessionId,
        reason: 'o toque devolve a equipe à mesma conversa — nada aqui pede à mesa '
            'para abrir uma sessão nova');
    expect(read().stage, SalaStage.conversa);
  });

  test('a network that fails every other turn still climbs to a person',
      () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    harness.room.failWith = const RoomBroke('HTTP 500');
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();

    harness.room.failWith = null;
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();

    harness.room.failWith = const RoomBroke('HTTP 500');
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();

    harness.room.failWith = null;
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();

    harness.room.failWith = const RoomBroke('HTTP 500');
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();

    expect(container.read(salaSessionProvider).needsPerson, isTrue,
        reason: 'o turno que tocava zerava _roomFailures a cada sucesso, e '
            'uma rede que cai a cada duas trocas nunca somava três seguidas — '
            'doze falhas em vinte e quatro turnos e a sala nunca chamava '
            'ninguém');
  });

  test(
      'two calm turns bring a failure back down before a person is needed',
      () async {
    final harness = SalaHarness();
    harness.emAberto.rows['Ruth/P01'] =
        const ResumePoint(sessionId: 'sessao-velha', stage: SalaStage.retro);
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await settle();

    // A resume with nothing to restore still checks the room for a telling-back before
    // it falls through to the opening turn — that check keeps the three-strike ladder
    // (it asks the room to hand back work it already holds, not to open a fresh turn),
    // unlike the opening turn itself, whose own RoomBroke now calls a person on the spot.
    harness.room.failWith = const RoomBroke('HTTP 500');
    await notifier.goConversa(pericope: 'P01');
    await settle();

    harness.room.failWith = null;
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();

    harness.room.failWith = const RoomBroke('HTTP 500');
    await notifier.goConversa(pericope: 'P01');
    await settle();
    await notifier.goConversa(pericope: 'P01');
    await settle();

    expect(container.read(salaSessionProvider).needsPerson, isFalse,
        reason: 'duas trocas calmas seguidas perdoam um ponto — sem o '
            'decaimento a falha de antes somava com as duas de agora e batia '
            'o limiar antes da terceira falha de verdade acontecer');
  });

  test(
      'a resume with nothing to restore still raises the affordance on the spot '
      'when its own opening turn breaks', () async {
    final harness = SalaHarness();
    harness.emAberto.rows['Ruth/P01'] =
        const ResumePoint(sessionId: 'sessao-velha', stage: SalaStage.conversa);
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await settle();

    harness.room.failWith = const RoomBroke('HTTP 500');
    await notifier.goConversa(pericope: 'P01');
    await settle();

    expect(container.read(salaSessionProvider).needsPerson, isTrue,
        reason: 'nothing to restore falls through to _askForTheOpening — the same '
            'openSession a person would have been shown E0 in — so one RoomBroke '
            'there is a turn call too, not the first rung of a ladder that never '
            'gets a second one: two more taps just sent the team back to the '
            'invite');
  });

  test('a resolve clears the slow-answer count too, not just the room-failure one',
      () async {
    final harness = SalaHarness()..room.failWith = const RoomSlow();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.openConvite();
    await notifier.openConvite();
    await settle();

    harness.room.failWith = const RoomRefused();
    await notifier.openConvite();
    await settle();
    expect(container.read(salaSessionProvider).needsPerson, isTrue);

    notifier.resolveWithPerson();

    harness.room.failWith = const RoomSlow();
    await notifier.openConvite();

    expect(container.read(salaSessionProvider).offline, isFalse,
        reason: 'o resolve zerava _roomFailures e esquecia _slowAnswers — '
            'duas lentidões de antes do halt mais uma depois do resolve já '
            'batiam o limiar, e a sala caía offline de novo assim que a rede '
            'gaguejasse pela primeira vez');
  });

  test('a resolve clears the inbox-silence count too, not just the room-failure one',
      () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    harness.inbox.cannotBeAsked = true;
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();

    harness.room.failWith = const RoomBroke('HTTP 500');
    for (var i = 0; i < 3; i++) {
      notifier.conversaTap();
      await settle();
      notifier.conversaTap();
      await settle();
    }
    expect(container.read(salaSessionProvider).needsPerson, isTrue);

    notifier.resolveWithPerson();

    harness.room.failWith = null;
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();

    expect(container.read(salaSessionProvider).needsPerson, isFalse,
        reason: 'o resolve zerava _roomFailures e esquecia _inboxSilences — '
            'duas consultas silenciosas de antes do halt mais uma depois do '
            'resolve já batiam o limiar, e a sala chamava alguém de novo no '
            'primeiro turno seguinte');
  });

  test('a passage reached straight through the wheel starts clean, not carrying the last one\'s strikes',
      () async {
    final harness = SalaHarness()..room.failWith = const RoomSlow();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.openConvite();
    await settle();
    await notifier.openConvite();
    await settle();

    harness.room.failWith = null;
    await notifier.abrirEscolha();
    await settle();

    harness.room.failWith = const RoomSlow();
    await notifier.goConversa(pericope: 'P01');
    await settle();

    expect(container.read(salaSessionProvider).offline, isFalse,
        reason: 'abrirEscolha não esquecia _slowAnswers — duas lentidões '
            'ainda no convite mais a primeira da passagem seguinte já '
            'batiam o limiar de três, e a sala caía offline no primeiro '
            'turno de uma passagem que ainda não tinha falhado nenhuma vez');
  });

  test('a degraded turn does not count toward the calm streak that forgives a failure',
      () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    harness.room.failWith = const RoomBroke('HTTP 500');
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();

    harness.room.failWith = null;
    harness.room.turnsAreDegraded = true;
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();

    harness.room.turnsAreDegraded = false;
    harness.room.failWith = const RoomBroke('HTTP 500');
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();

    expect(container.read(salaSessionProvider).needsPerson, isTrue,
        reason: 'dois turnos degradados contavam como dois turnos calmos e '
            'perdoavam a falha de antes — a rede continuava ruim, a fala só '
            'chegava pior, e a sala mesmo assim apagava o que já tinha visto');
  });

  test('an unplayable turn does not count toward the calm streak either',
      () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    harness.room.failWith = const RoomBroke('HTTP 500');
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();

    harness.room.failWith = null;
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();

    harness.voice.succeeds = false;
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();
    harness.voice.succeeds = true;

    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();

    harness.room.failWith = const RoomBroke('HTTP 500');
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();

    expect(container.read(salaSessionProvider).needsPerson, isTrue,
        reason: 'um turno que a sala nem conseguiu dizer contava como um '
            'turno calmo e ainda assim perdoava a falha de antes');
  });

  test('a clean turn right before a degraded one still does not forgive a failure',
      () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    harness.room.failWith = const RoomBroke('HTTP 500');
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();

    harness.room.failWith = null;
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();

    harness.room.turnsAreDegraded = true;
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();
    harness.room.turnsAreDegraded = false;

    harness.room.failWith = const RoomBroke('HTTP 500');
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();

    expect(container.read(salaSessionProvider).needsPerson, isTrue,
        reason: 'o turno limpo levava o streak a um, e o degradado logo '
            'depois completava o par e pagava o ponto antes mesmo de a sala '
            'saber que esse turno tinha vindo ruim');
  });

  test('two visible server errors across an offline episode still fall short of a person',
      () async {
    final harness = SalaHarness();
    harness.emAberto.rows['Ruth/P01'] =
        const ResumePoint(sessionId: 'sessao-velha', stage: SalaStage.retro);
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await settle();
    await notifier.goConversa(pericope: 'P01');
    await settle();

    harness.room.reachable = false;
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle(const Duration(milliseconds: 5));
    expect(container.read(salaSessionProvider).offline, isTrue,
        reason: 'servidor totalmente fora vira queda de rede, não erro do servidor');

    harness.room.reachable = true;
    await settle();
    expect(container.read(salaSessionProvider).offline, isFalse,
        reason: 'a sala volta sozinha assim que a rede responde de novo');

    // The resume's own check for a telling-back keeps the three-strike ladder; a turn's
    // RoomBroke — including the opening turn a resume with nothing to restore falls
    // through to — now calls a person on the spot, so the two visible 503s below are
    // read via that check instead.
    harness.room.failWith = const RoomBroke('HTTP 503');
    await notifier.goConversa(pericope: 'P01');
    await settle();

    harness.room.failWith = null;
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();

    harness.room.failWith = const RoomBroke('HTTP 503');
    await notifier.goConversa(pericope: 'P01');
    await settle();

    expect(container.read(salaSessionProvider).needsPerson, isFalse,
        reason: 'a queda de rede não é erro do servidor e não deve contar para '
            'o mesmo contador — dois 503 visíveis, com um turno bom entre eles, '
            'não somam três seguidas');
  });

  test('a panorama that cannot be spoken leaves a way back', () async {
    final harness = SalaHarness()..voice.succeeds = false;
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.openConvite();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.conviteStep, ConviteStep.boasVindas,
        reason: 'o passo só avança depois que o panorama foi realmente falado');
    expect(state.awaitingFirstTouch, isTrue);

    notifier.conviteTap();
    await settle();

    expect(
      harness.room.calls.where((call) => call == 'openSession'),
      hasLength(2),
      reason: 'um novo toque tenta de novo em vez de bater numa tela morta',
    );
    expect(harness.room.pericopesAsked, hasLength(1),
        reason: 'tentar de novo não é abrir outro panorama: cada toque deixava uma sessão abandonada no servidor');
  });

  test('a line longer than the busy ceiling is not a stuck room', () async {
    final harness = SalaHarness(busyCeiling: const Duration(milliseconds: 40));
    final container = harness.container();
    addTearDown(container.dispose);
    harness.voice.holdNextLine();

    unawaited(container.read(salaSessionProvider.notifier).openConvite());
    await settle(const Duration(milliseconds: 20));

    expect(container.read(salaSessionProvider).voice, VoiceState.speaking);

    await settle(const Duration(milliseconds: 80));

    expect(container.read(salaSessionProvider).voice, VoiceState.speaking,
        reason: 'a abertura de Rute 1:6-14 veio num clipe de 122 s e o teto de '
            '120 s chamou uma pessoa com o Guia ainda falando; quem julga uma fala '
            'é a própria voz, pelo tamanho do clipe, não um relógio de espera');
    expect(container.read(salaSessionProvider).needsPerson, isFalse);
    expect(harness.room.calls.where((call) => call == 'askForAPerson'), isEmpty,
        reason: 'e o servidor nunca soube de uma parada que não houve');

    harness.voice.finishHeldLine();
    await settle();

    expect(container.read(salaSessionProvider).voice, isNot(VoiceState.speaking),
        reason: 'terminada a fala, a sala segue como se o teto não existisse');
  });

  test('a wait for an answer still gives up at the busy ceiling', () async {
    final harness = SalaHarness(busyCeiling: const Duration(milliseconds: 40));
    final container = harness.container();
    addTearDown(container.dispose);
    harness.voice.holdNextFetch();

    unawaited(container.read(salaSessionProvider.notifier).openConvite());
    await settle(const Duration(milliseconds: 20));

    expect(container.read(salaSessionProvider).voice, VoiceState.thinking);

    await settle(const Duration(milliseconds: 80));

    expect(container.read(salaSessionProvider).needsPerson, isTrue,
        reason: 'a espera é a única coisa que pode travar: uma linha que nunca chega '
            'ainda chama uma pessoa');
  });

  test('the last line can be heard again without touching the room', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    expect(container.read(salaSessionProvider).canHearAgain, isTrue);
    final callsBefore = harness.room.calls.length;

    await notifier.hearAgain();

    expect(harness.voice.played, hasLength(2));
    expect(harness.voice.played.last, harness.voice.played.first);
    expect(harness.room.calls.length, callsBefore,
        reason: 'o áudio já está no disco — repetir não pode custar rede');
    expect(container.read(salaSessionProvider).voice, VoiceState.invite);
  });

  test('a fixed line is repeated from the bundle', () async {
    final harness = SalaHarness()..room.fixedLine = 'D1';
    final container = await inConversa(harness);
    addTearDown(container.dispose);

    await container.read(salaSessionProvider.notifier).hearAgain();

    expect(harness.voice.assets, [
      fixedLineAsset('D1', testLanguage),
      fixedLineAsset('D1', testLanguage),
    ]);
    expect(harness.room.clipsFetched, isEmpty);
  });

  test('a replay that works clears the strikes the failed ones left behind', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    harness.voice.succeeds = false;
    await notifier.hearAgain();
    await settle();
    await notifier.hearAgain();
    await settle();

    harness.voice.succeeds = true;
    await notifier.hearAgain();
    await settle();

    harness.voice.succeeds = false;
    await notifier.hearAgain();
    await settle();

    expect(container.read(salaSessionProvider).needsPerson, isFalse,
        reason: 'a conta subia e nunca zerava, então duas falhas espalhadas pela sessão '
            'faziam a próxima buscar alguém numa sala que acabara de falar');
  });

  test('a replay that fails leaves the team where the room had put them', () async {
    final harness = SalaHarness()..room.peerCue = true;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    expect(container.read(salaSessionProvider).peerCue, isTrue);

    harness.voice.succeeds = false;
    await notifier.hearAgain();
    await settle();

    expect(container.read(salaSessionProvider).peerCue, isTrue,
        reason: 'a sala mandou conversarem entre si e não conseguiu repetir a linha — '
            'perder a instrução junto com a repetição troca a tela por baixo da equipe');
  });

  test('three replays nobody could hear fetch a person', () async {
    final harness = SalaHarness()..room.peerCue = true;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    harness.voice.succeeds = false;
    for (var attempt = 0; attempt < 3; attempt++) {
      await notifier.hearAgain();
      await settle();
    }

    expect(container.read(salaSessionProvider).needsPerson, isTrue,
        reason: 'toda fala que não sai conta para buscar alguém, menos esta — o ouvir de '
            'novo era o único caminho por onde a sala podia emudecer para sempre');
  });

  test('replaying puts the facilitator back in the speaking state', () async {
    final harness = SalaHarness()..room.peerCue = true;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    expect(container.read(salaSessionProvider).peerCue, isTrue);

    harness.voice.holdNextLine();
    unawaited(notifier.hearAgain());
    await settle(const Duration(milliseconds: 20));

    expect(container.read(salaSessionProvider).voice, VoiceState.speaking,
        reason: 'repetindo, quem fala é o facilitador — a bola tem de ser a dele');

    harness.voice.finishHeldLine();
    await settle();

    final after = container.read(salaSessionProvider);
    expect(after.voice, VoiceState.invite);
    expect(after.peerCue, isTrue,
        reason: 'a fala repetida acaba e a equipe segue exatamente onde estava — '
            'a bola da conversa entre eles precisa voltar');
  });

  test('the window closes the moment the team starts recording', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);

    container.read(salaSessionProvider.notifier).conversaTap();

    expect(container.read(salaSessionProvider).canHearAgain, isFalse,
        reason: 'gravando, não há mais janela — e o botão sairia debaixo do polegar');
  });

  test('a line that never played is not a line to repeat', () async {
    final harness = SalaHarness()..voice.succeeds = false;
    final container = await inConversa(harness);
    addTearDown(container.dispose);

    expect(container.read(salaSessionProvider).lastSpoken, isNull);
    expect(container.read(salaSessionProvider).canHearAgain, isFalse);
  });

  test('leaving the stage takes the window with it', () async {
    final harness = SalaHarness()..room.done = true;
    final container = await inConversa(harness);
    addTearDown(container.dispose);

    container.read(salaSessionProvider.notifier).goEnsaio();

    expect(container.read(salaSessionProvider).canHearAgain, isFalse);
  });

  test('a line finishing after the stage moved on is not offered there', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    harness.voice.holdNextLine();
    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();

    notifier.goEnsaio();
    harness.voice.finishHeldLine();
    await settle();

    expect(container.read(salaSessionProvider).lastSpoken, isNull,
        reason: 'a fala terminou depois da troca de etapa — escrevê-la de volta '
            'ressuscitaria o áudio da etapa anterior');
  });

  test('a touch on the hand only arms the note, never the microphone', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.handTap();
    expect(container.read(salaSessionProvider).noteMode, isTrue);
    expect(harness.recorder.captures, 0,
        reason: 'a mão arma o modo de nota — gravar aqui capturaria a fala do '
            'facilitador por baixo da pergunta');

    notifier.handTap();
    expect(container.read(salaSessionProvider).noteMode, isFalse);
    expect(harness.recorder.captures, 0);
  });

  test('the circle opens the microphone once armed, and closes it on the next touch',
      () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.handTap();
    notifier.conversaTap();
    await settle();

    expect(harness.recorder.captures, 1,
        reason: 'o primeiro toque no círculo depois da mão é o que abre o microfone');
    expect(harness.inbox.questionsSent, isEmpty,
        reason: 'um só toque no círculo abre o microfone; a pergunta ainda não foi dita');

    notifier.conversaTap();
    await settle();

    expect(harness.inbox.questionsSent, ['sessao-1']);
    expect(harness.recorder.deleted, [endsWith('captura-1.m4a')],
        reason: 'a pergunta já está no servidor, esperando uma pessoa — '
            'a cópia no tablet não serve para nada');
  });

  test('a note raised at done still records, not a dead touch', () async {
    final harness = SalaHarness()..room.done = true;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    expect(container.read(salaSessionProvider).voice, VoiceState.done);

    notifier.handTap();
    expect(container.read(salaSessionProvider).noteMode, isTrue);

    notifier.conversaTap();
    await settle();

    expect(
      harness.recorder.captures,
      1,
      reason: 'done caía no bloco de no-op de _noteTap, junto de thinking/speaking/'
          'needsPerson/offline/blocked, e nunca chamava _startListening — a mão '
          'armava a nota e o círculo não abria o microfone',
    );
    expect(harness.inbox.questionsSent, isEmpty,
        reason: 'um só toque no círculo abre o microfone; a pergunta ainda não foi dita');

    notifier.conversaTap();
    await settle();

    expect(harness.inbox.questionsSent, ['sessao-1']);
    expect(
      container.read(salaSessionProvider).stage,
      SalaStage.conversa,
      reason: 'a pergunta silenciosa nunca fecha nem reinicia a conversa sozinha — '
          'a passagem que já tinha chegado a done não é reaberta nem trocada de etapa',
    );
    expect(
      harness.room.turnsSent,
      0,
      reason: 'a pergunta silenciosa é um canal da mesa, não um turno da conversa — '
          'entregá-la não reinicia a fala do Guia',
    );
  });

  test('a question that never left is kept on the tablet', () async {
    final harness = SalaHarness(retryBackoff: const [Duration(seconds: 30)])
      ..inbox.refuses = true;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.handTap();
    notifier.conversaTap();
    notifier.conversaTap();
    await settle();

    expect(harness.inbox.questionsSent, isEmpty);
    expect(harness.recorder.deleted, isEmpty,
        reason: 'nada reenvia essa pergunta, mas apagá-la seria destruir '
            'a única cópia de algo que a equipe pediu');
  });

  test('a question that never left marks nothing pending on the hand', () async {
    final harness = SalaHarness(retryBackoff: const [Duration(seconds: 30)])
      ..inbox.refuses = true;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.handTap();
    notifier.conversaTap();
    notifier.conversaTap();
    await settle();

    expect(container.read(salaSessionProvider).questionPending, isFalse,
        reason: 'o ponto na mão é o registro de uma pergunta entregue — acendê-lo sem '
            'entrega diz a uma equipe que não lê que ela foi ouvida');
    expect(container.read(salaSessionProvider).handAck, isFalse);
  });

  test('a delivered question marks the hand pending until a reply arrives', () async {
    final harness = SalaHarness(settleDelay: const Duration(seconds: 60))
      ..room.turnIdInResponse = 'turno-1';
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.handTap();
    notifier.conversaTap();
    notifier.conversaTap();
    await settle();

    expect(harness.inbox.questionsSent, ['sessao-1']);
    expect(container.read(salaSessionProvider).questionPending, isTrue);
    expect(container.read(salaSessionProvider).hasUnheardReply, isFalse);

    harness.inbox.replies = const [HandReply(id: 'r1', audioUrl: '/voice/r1')];
    harness.room.pushCoverage(
      const CoverageEvent(turnId: 'turno-1', status: CoverageStatus.settled),
    );
    await waitFor(
      'a resposta chegar à mão',
      () => container.read(salaSessionProvider).hasUnheardReply,
    );

    expect(container.read(salaSessionProvider).questionPending, isFalse,
        reason: 'a resposta chegou — o ponto agora é o de ouvir, não o de esperar');
  });

  test('an unheard reply waits on the hand and is played on tap', () async {
    final harness = SalaHarness(
      replies: const [HandReply(id: 'r1', audioUrl: '/api/internalization-room/voice/r1')],
    );
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    expect(container.read(salaSessionProvider).hasUnheardReply, isTrue);

    notifier.handTap();
    await settle();

    expect(harness.voice.played, contains('/api/internalization-room/voice/r1'),
        reason: 'a resposta é áudio do servidor, como toda voz que vem de fora');
    expect(container.read(salaSessionProvider).hasUnheardReply, isFalse);
    expect(harness.inbox.heard, ['r1']);
  });

  test('a kept take leaves the tablet', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    await waitFor('a sala guardar a tomada', () => harness.room.takesKept.isNotEmpty);

    expect(harness.room.takesKept, ['ensaio/${KeptScope.parte(1)}'],
        reason: 'o ensaio é o produto — um tablet que quebra não pode levar a sessão junto');
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while ((await harness.takes.pending()).isNotEmpty &&
        DateTime.now().isBefore(deadline)) {
      await settle(const Duration(milliseconds: 20));
    }
    expect(await harness.takes.pending(), isEmpty);
  });

  test('a take recorded with no network waits instead of being lost', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    harness.room.reachable = false;
    notifier.takeKeep();
    while ((await harness.takes.pending()).isEmpty) {
      await settle(const Duration(milliseconds: 20));
    }

    expect(harness.room.takesKept, isEmpty);
    expect(await harness.takes.pending(), hasLength(1),
        reason: 'sem rede a tomada fica na fila, e a fila é um arquivo em disco');

    harness.room.reachable = true;
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (harness.room.takesKept.isEmpty && DateTime.now().isBefore(deadline)) {
      await harness.takes.flush();
      await settle(const Duration(milliseconds: 20));
    }

    expect(harness.room.takesKept, ['ensaio/${KeptScope.parte(1)}']);
  });

  test('a take the server has not taken yet is not counted as safe', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    harness.room.reachable = false;
    notifier.takeKeep();
    await waitFor(
      'uma tomada ficar por enviar',
      () => container.read(salaSessionProvider).unsentTakes == 1,
    );

    expect(container.read(salaSessionProvider).unsentTakes, 1,
        reason: 'a conta aparece quando a equipe guarda, mas ainda está só no tablet');

    harness.room.reachable = true;
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (container.read(salaSessionProvider).unsentTakes != 0 &&
        DateTime.now().isBefore(deadline)) {
      await harness.takes.flush();
      await notifier.refreshUnsent();
      await settle(const Duration(milliseconds: 20));
    }

    expect(container.read(salaSessionProvider).unsentTakes, 0);
  });

  test('a wheel that failed to load is not a finished book', () async {
    final harness = SalaHarness()..room.failWith = const RoomBroke('HTTP 500');
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.abrirEscolha();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.livroInteiroFeito, isFalse,
        reason: 'uma lista vazia por falha dizia à equipe que o livro inteiro '
            'já tinha sido trabalhado');
    expect(state.rodaPorLer, isTrue);
    expect(state.needsPerson, isTrue,
        reason: 'carregar a roda é uma chamada de turno: o 500 já para a sala, '
            'a mesma parada de qualquer outro turno');
  });

  test('the touch is the retry when the wheel never loaded', () async {
    final harness = SalaHarness()..room.failWith = const RoomSlow();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await settle();
    harness.room.failWith = null;

    notifier.escolhaTap();
    await settle();

    expect(container.read(salaSessionProvider).naRoda, hasLength(3),
        reason: 'sem isso a tela não tinha gesto vivo nenhum: o círculo era morto, '
            'não havia botão, e não há texto que explique o que houve');
    expect(container.read(salaSessionProvider).oferecida?.pericope, 'P01');
  });

  test('an empty wheel really does mean the book is done', () async {
    final harness = SalaHarness()..room.passages = const [];
    final container = harness.container();
    addTearDown(container.dispose);

    await container.read(salaSessionProvider.notifier).abrirEscolha();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.livroInteiroFeito, isTrue);
    expect(state.rodaPorLer, isFalse);
    expect(state.needsPerson, isTrue,
        reason: 'roda lida e vazia é livro terminado — e terminar o livro é '
            'exatamente o momento de chamar o facilitador');
  });

  test('the wheel reloads itself when the network comes back', () async {
    final harness = SalaHarness()..network.reachable = false;
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    harness.room.reachable = false;
    await notifier.abrirEscolha();
    await settle();
    expect(container.read(salaSessionProvider).offline, isTrue);

    harness.room.reachable = true;
    harness.network.reachable = true;
    harness.network.networkComesBack();
    await settle(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).naRoda, hasLength(3),
        reason: '_comeBack não conhecia a escolha: a rede voltava e a roda '
            'continuava vazia para sempre');
  });

  test('the room offers one passage at a time, by voice', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.abrirEscolha();
    await settle();

    expect(harness.room.booksAsked, ['Ruth']);
    expect(container.read(salaSessionProvider).oferecida?.pericope, 'P01');
    expect(harness.voice.played, ['/voice/p01'],
        reason: 'a equipe escolhe de ouvido: a sala diz a passagem, não a escreve');

    notifier.escolhaTap();
    await settle();

    expect(container.read(salaSessionProvider).oferecida?.pericope, 'P01',
        reason: 'o toque no círculo diz de novo; quem anda pela roda é o dedo na régua');
    expect(harness.voice.played, ['/voice/p01', '/voice/p01']);

    notifier.apontarPassagem(1);
    await settle();

    expect(harness.voice.played, ['/voice/p01', '/voice/p01'],
        reason: 'atravessar a régua com o dedo abaixado não dispara catorze nomes');

    notifier.dizerAPassagem();
    await settle();

    expect(container.read(salaSessionProvider).oferecida?.pericope, 'P02');
    expect(harness.voice.played, ['/voice/p01', '/voice/p01', '/voice/p02']);
  });

  test('the row has ends, and stops at them instead of wrapping', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await settle();

    notifier.apontarPassagem(9);
    await settle();
    expect(container.read(salaSessionProvider).oferecida?.pericope, 'P03',
        reason: 'a roda dava a volta porque o fim da lista era invisível; a régua '
            'mostra as pontas, e uma ponta que teleporta o dedo desorienta');

    notifier.apontarPassagem(-4);
    await settle();
    expect(container.read(salaSessionProvider).oferecida?.pericope, 'P01');
  });

  test('entering carries the chosen passage to the room', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await settle();
    notifier.apontarPassagem(1);
    notifier.dizerAPassagem();
    await settle();

    notifier.entrarNaOferecida();
    await settle();

    expect(harness.room.pericopesAsked, contains('P02'),
        reason: 'o cliente nunca mandava perícope e o servidor caía sempre na P01');
    expect(container.read(salaSessionProvider).stage, SalaStage.conversa);
  });

  test('a passage carried to the end stays on the wheel, marked', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await settle();
    notifier.entrarNaOferecida();
    await settle();
    await _intoConferida(harness, notifier);
    await _aprovar(notifier);

    await notifier.abrirEscolha();
    await settle();

    expect(
      container.read(salaSessionProvider).naRoda?.map((p) => p.pericope),
      ['P01', 'P02', 'P03'],
      reason: 'a passagem terminada saía da roda e a equipe não tinha como '
          'voltar ao que trabalhou — e o registro informa, não fecha a conversa',
    );
    expect(container.read(salaSessionProvider).feitas, {'P01'},
        reason: 'ficar na roda sem marca nenhuma é indistinguível de nunca ter '
            'sido tocada, e nesta sala não há palavra escrita que diga qual é');
  });

  test('a finished book reaches a person instead of dying quietly', () async {
    final harness = SalaHarness()..room.passages = const [];
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.abrirEscolha();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.livroInteiroFeito, isTrue);
    expect(state.needsPerson, isTrue,
        reason: 'um disco verde parado, mudo, recusando todo gesto era '
            'indistinguível de um app morto — e não há texto que explique');
    expect(harness.voice.assets,
        isNot(contains(fixedLineAsset('E0', testLanguage))),
        reason: 'o disco verde já mostra a parada sozinho; falar por cima dele é a '
            'mesma sala dizendo o mesmo aviso duas vezes, uma vez local e sem o servidor');

    notifier.resolveWithPerson();

    expect(container.read(salaSessionProvider).needsPerson, isFalse,
        reason: 'o toque longo tira a sala de lá, como em todo outro halt');
  });

  test('the closed necklace opens the room again on its own', () async {
    final harness = SalaHarness(fimLinger: const Duration(milliseconds: 40));
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    notifier.startRetro();
    await settle();
    notifier.cortarTrecho();
    await settle();
    notifier.retroTap();
    await settle();
    harness.playback.finishPlayback();
    await settle();
    await notifier.finishBackTranslation();
    await settle();
    await notifier.aprovarRascunhoFinal();
    await settle(const Duration(seconds: 2));

    final after = container.read(salaSessionProvider);
    expect(after.stage, SalaStage.escolha,
        reason: 'a sala reabre na escolha, não no convite: voltar ao convite '
            'refazia a mesma perícope para sempre num tablet esquecido ligado');
    expect(after.sessionId, isNull);
    expect(after.takes, 0);
  });

  test('the ensaio does not freeze on a ghost play that never ends', () async {
    final harness = SalaHarness(playbackCeiling: const Duration(milliseconds: 40));
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    notifier.ghostPlay();

    expect(container.read(salaSessionProvider).ensaio, EnsaioStatus.ghostPlaying);

    await settle(const Duration(milliseconds: 140));

    expect(container.read(salaSessionProvider).ensaio, EnsaioStatus.idle,
        reason: 'sem teto, uma reprodução interrompida deixava a tela do ensaio '
            'sem nenhum gesto vivo — nada para tocar, e nada escrito para explicar');
  });

  test('a retro clip that never ends still offers terminei', () async {
    final harness = SalaHarness(playbackCeiling: const Duration(milliseconds: 400));
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    notifier.startRetro();
    await settle(const Duration(milliseconds: 60));

    expect(container.read(salaSessionProvider).canFinishBackTranslation, isFalse);

    await settle(const Duration(milliseconds: 500));

    expect(container.read(salaSessionProvider).canFinishBackTranslation, isTrue,
        reason: 'se a conclusão do clipe se perde, a equipe capturava pedaços '
            'para sempre sem nunca poder concluir');
  });

  test('the closed room opens again on a touch, not only on its own', () async {
    final harness = SalaHarness(fimLinger: const Duration(seconds: 30));
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    notifier.startRetro();
    await settle();
    notifier.cortarTrecho();
    await settle();
    notifier.retroTap();
    await settle();
    harness.playback.finishPlayback();
    await settle();
    await notifier.finishBackTranslation();
    await settle();
    await notifier.aprovarRascunhoFinal();
    await settle(const Duration(seconds: 2));

    expect(container.read(salaSessionProvider).stage, SalaStage.fim);

    notifier.beginAgain();

    expect(container.read(salaSessionProvider).stage, SalaStage.escolha,
        reason: 'a tela do fim não tinha alvo de toque nenhum; se a corrente de '
            'temporizadores morresse, a sala ficava branca até matarem o app');
  });

  test('a verdict that lands after the room gave up does not restart it', () async {
    final harness = SalaHarness(busyCeiling: const Duration(milliseconds: 60));
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    notifier.startRetro();
    await settle();
    notifier.cortarTrecho();
    await settle();
    notifier.retroTap();
    await settle();
    harness.playback.finishPlayback();
    await settle();

    harness.voice.holdNextFetch();
    unawaited(notifier.finishBackTranslation());
    await settle(const Duration(milliseconds: 200));

    expect(container.read(salaSessionProvider).needsPerson, isTrue,
        reason: 'o cão de guarda desiste de um clipe de veredito que nunca chega: o '
            'veredito em si já está na mão, é o áudio dele que a sala espera');

    harness.voice.finishHeldFetch();
    await settle(const Duration(seconds: 2));

    final after = container.read(salaSessionProvider);
    expect(after.needsPerson, isTrue,
        reason: 'sem guarda de época, o veredito atrasado saltava a equipe para '
            'conferida e fechava o colar por cima de quem já tinha parado a sala');
    expect(after.stage, isNot(SalaStage.fim));
  });

  test('explaining for longer than the clip does not end the clip', () async {
    final harness = SalaHarness(clipGrace: const Duration(milliseconds: 60))
      ..playback.length = const Duration(milliseconds: 200);
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    notifier.startRetro();
    await settle(const Duration(milliseconds: 50));

    harness.playback.at = const Duration(milliseconds: 40);
    notifier.cortarTrecho();
    await settle(const Duration(milliseconds: 400));

    expect(container.read(salaSessionProvider).btClipEnded, isFalse,
        reason: 'o teto contava no relógio de parede e não sabia que o clipe '
            'estava pausado, então terminava a gravação no meio da explicação');

    notifier.retroTap();
    await settle();

    expect(container.read(salaSessionProvider).btClipEnded, isFalse);
    expect(container.read(salaSessionProvider).btPhase, BtPhase.playing,
        reason: 'e a escuta volta de onde parou, em vez de ficar muda para sempre');

    notifier.ouvirGravacao();
    await settle();

    expect(container.read(salaSessionProvider).btClipRodando, isTrue,
        reason: 'o que sobrou do clipe continua alcançável: dado por terminado, '
            'o áudio que ninguém ouviu não tinha mais como ser tocado');
  });

  test('asking for a person in the retro always leaves a live gesture', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await _intoFindings(harness, notifier, container);

    notifier.goEnsaio();
    notifier.startRetro();
    await settle();
    harness.room.failWith = const RoomRefused();
    // Past the thirty seconds already told back, not at nought. Entering the retro used
    // to forget every stretch and start the clip over, so a cut at nought reached the
    // room — and the room, which had forgotten nothing, ended up holding the passage
    // twice. The stretches stay now and a cut over told ground never leaves the tablet,
    // so the refusal this test is about only happens over ground nobody has told yet.
    harness.playback.at = const Duration(seconds: 40);
    notifier.cortarTrecho();
    await settle();
    notifier.retroTap();
    await settle();

    expect(container.read(salaSessionProvider).needsPerson, isTrue);
    expect(container.read(salaSessionProvider).btPhase, isNot(BtPhase.thinking),
        reason: 'em thinking o círculo é morto e não há botão — a sala ficava '
            'sem nenhum gesto vivo, e o toque longo não a tirava de lá');
  });

  test('the stretch is found by the number the room gave it', () async {
    final harness = SalaHarness()
      ..room.verdictChecked = false
      ..room.verdictFinding = BtFindingKind.missing
      ..room.verdictFindingSegmentId = 'trecho-2';
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await _intoFindings(harness, notifier, container);

    final trechos = container.read(salaSessionProvider).btTrechos;
    expect(trechos.map((t) => t.segmentId).toList(), ['trecho-1', 'trecho-2'],
        reason: 'o nome vem do servidor; derivá-lo da posição na lista '
            'desalinha assim que uma resposta se perde depois de persistir');
    notifier.ouvirVozMaterna();
    await waitFor(
      'o trecho apontado estar tocando',
      () => container.read(salaSessionProvider).btTrechoTocando,
    );
    expect(harness.playback.ranges.last, '12000-30000',
        reason: 'quem toca o trecho apontado é o toque da equipe no player de '
            'madeira; a sala parou de tocá-lo por conta própria');
  });

  test('the retro ignores taps once it has asked for a person', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await waitFor(
      'a gravação da parte terminar',
      () => container.read(salaSessionProvider).ensaio == EnsaioStatus.recorded,
    );
    notifier.takeKeep();
    // A stretch is a slice of a recording the room can name, and the name is adopted only
    // once the take lands. Entering the retro before that makes every cut arrive with
    // nothing to point at, and the room drops it instead of sending it.
    await waitFor(
      'a sala nomear a parte',
      () => container.read(salaSessionProvider).partes.last.takeId != null,
    );
    notifier.startRetro();
    await waitFor(
      'o clipe estar rodando',
      () => container.read(salaSessionProvider).btClipRodando,
    );
    harness.room.failWith = const RoomRefused();
    final capturasAntes = harness.recorder.captures;
    notifier.cortarTrecho();
    await waitFor(
      'o microfone abrir para o trecho',
      () => harness.recorder.captures == capturasAntes + 1,
    );
    notifier.retroTap();
    await waitFor(
      'a sala sair do pensando',
      () => container.read(salaSessionProvider).btPhase != BtPhase.thinking,
    );
    expect(container.read(salaSessionProvider).needsPerson, isTrue);
    final capturesBefore = harness.recorder.captures;

    notifier.retroTap();
    await settle();

    expect(harness.recorder.captures, capturesBefore,
        reason: 'a equipe falava para um buraco enquanto o círculo mostrava '
            '"chame uma pessoa"');
  });

  test('retelling one stretch keeps every other explanation', () async {
    final harness = SalaHarness()
      ..room.verdictChecked = false
      ..room.verdictFinding = BtFindingKind.missing
      ..room.verdictFindingSegmentId = 'trecho-1';
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await _intoFindings(harness, notifier, container);
    final before = container.read(salaSessionProvider);

    notifier.traduzirDeNovoEmPortugues();
    await waitFor(
      'o microfone abrir',
      () => container.read(salaSessionProvider).btPhase == BtPhase.capturing,
    );
    notifier.retroTap();
    await settle();

    final after = container.read(salaSessionProvider);
    expect(after.btTrechos.length, before.btTrechos.length,
        reason: 'traduzir um trecho de novo descartava as explicações de todos os '
            'outros e mandava a equipe reescutar a gravação do zero');
    expect(harness.room.replacesAsked, hasLength(1),
        reason: 'a sala manda o trecho apontado para ser traduzido de novo');
    expect(after.btClipEnded, isTrue,
        reason: 'e o terminei continua ali para reconferir');
  });

  test('a kept rehearsal take says which pass over the passage it is', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    await waitFor('a sala guardar a tomada', () => harness.room.takesKept.isNotEmpty);

    expect(harness.room.takePasses, [1],
        reason: 'o ensaio subia sem passada nenhuma, e o pacote nao tinha por onde '
            'dizer de qual das gravacoes aquele parte-1 era');
  });

  test('a part recorded for the first time after a resume is its own first '
      'recording', () async {
    final harness = SalaHarness();
    final gravadas = Directory.systemTemp.createTempSync('sala-ensaio-passada');
    addTearDown(() => gravadas.deleteSync(recursive: true));
    harness.emAberto.rows['Ruth/P01'] = ResumePoint(
      sessionId: 'sessao-regravada',
      stage: SalaStage.ensaio,
      takes: [
        KeptTake(
          scopeId: KeptScope.parte(1),
          path: (File('${gravadas.path}/parte-1.m4a')..writeAsBytesSync([1, 2, 3]))
              .path,
          pass: 2,
        ),
      ],
    );
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.abrirEscolha();
    await settle();
    await notifier.goConversa(pericope: 'P01');
    await settle();

    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    await waitFor('a sala guardar a tomada', () => harness.room.takesKept.isNotEmpty);

    expect(harness.room.takesKept, ['ensaio/parte-2']);
    expect(harness.room.takePasses, [1],
        reason: 'a conta é de cada parte: a parte 2 nunca foi gravada, e quantas '
            'gravações a parte 1 teve não diz nada sobre ela');
  });

  test('a room that halts for a person says so to the server', () async {
    final harness = SalaHarness()..voice.succeeds = false;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.conversaTap();
    await settle();
    for (var attempt = 0; attempt < 3; attempt++) {
      notifier.conversaTap();
      await settle();
      notifier.conversaTap();
      await settle();
    }

    expect(container.read(salaSessionProvider).needsPerson, isTrue);
    expect(harness.room.personsAsked, 1,
        reason: 'needs_person tinha consumidor no app e nenhum produtor — o '
            'facilitador nunca ficava sabendo, e uma só vez basta');
  });

  test('the room answers the moment the team stops talking', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    harness.voice.assets.clear();

    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();

    expect(harness.voice.assets.first, fixedLineAsset(instantAckLines.first, testLanguage),
        reason: 'a fala de reconhecimento existe aprovada e no pacote desde o '
            'começo, e nada nunca a tocava — a sala esperava calada');
  });

  test('the acknowledgement rotates so the room does not sound stuck', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    harness.voice.assets.clear();

    for (var turn = 0; turn < 2; turn++) {
      notifier.conversaTap();
      await settle();
      notifier.conversaTap();
      await settle();
    }

    expect(
      harness.voice.assets.where((asset) => asset.contains('/F')).toList(),
      [
        fixedLineAsset(instantAckLines[0], testLanguage),
        fixedLineAsset(instantAckLines[1], testLanguage),
      ],
    );
  });

  test(
      'a capture the guard rejects is answered in silence, never from the '
      'room', () async {
    final harness = SalaHarness()..recorder.returnsEmpty = true;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    harness.voice.assets.clear();
    final turnsBefore = harness.room.turnsSent;

    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();

    expect(harness.room.turnsSent, turnsBefore,
        reason: 'a regra existe para que um silêncio não custe nem espera nem '
            'chamada — hoje subia tudo e o servidor decidia depois');
    expect(harness.voice.assets, isEmpty,
        reason: 'nenhuma linha fixa é falada — o take que o guard reprova '
            'some em silêncio, sem pedir para repetir');
    expect(container.read(salaSessionProvider).voice, VoiceState.invite,
        reason: 'e a sala volta a convidar, pronta para ouvir de novo');
    expect(container.read(salaSessionProvider).needsPerson, isFalse,
        reason: 'um take curto não é uma pessoa chamada');
  });

  test('each pause closes a stretch, and the stretches follow the recording',
      () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    notifier.startRetro();
    await settle();

    harness.playback.at = const Duration(seconds: 12);
    notifier.cortarTrecho();
    await settle();
    notifier.retroTap();
    await settle();

    harness.playback.at = const Duration(seconds: 30);
    notifier.cortarTrecho();
    await settle();
    notifier.retroTap();
    await settle();

    expect(harness.room.chunkSpans, ['0-12000', '12000-30000'],
        reason: 'sem os limites o pedaço é só um ordinal e ninguém adiante '
            'consegue apontar o áudio que ele explica');
    final trechos = container.read(salaSessionProvider).btTrechos;
    expect(trechos.map((t) => t.to.inSeconds).toList(), [12, 30]);
  });

  test('the verdict takes the team to the part it points at', () async {
    final harness = SalaHarness()
      ..room.verdictChecked = false
      ..room.verdictFinding = BtFindingKind.missing
      ..room.verdictFindingSegmentId = 'trecho-2';
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    notifier.startRetro();
    await settle();

    harness.playback.at = const Duration(seconds: 12);
    notifier.cortarTrecho();
    await settle();
    notifier.retroTap();
    await settle();

    harness.playback.at = const Duration(seconds: 30);
    notifier.cortarTrecho();
    await settle();
    notifier.retroTap();
    await settle();

    harness.playback.finishPlayback();
    await settle();
    harness.playback.ranges.clear();
    await notifier.finishBackTranslation();
    await settle();

    expect(container.read(salaSessionProvider).btFindingSegmentId, 'trecho-2');
    expect(harness.playback.ranges, isEmpty,
        reason: 'a sala não toca o trecho na chegada: a pergunta é qual voz '
            'precisa falar de novo, e ouvir é um gesto da equipe');

    notifier.ouvirVozMaterna();
    await settle();

    expect(harness.playback.ranges, ['12000-30000'],
        reason: 'e o trecho que ela ouve é o apontado, não a passagem inteira');
  });

  test('a take that ran out of tries is said out loud, once', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await waitFor(
      'a tomada ser oferecida',
      () => container.read(salaSessionProvider).ensaio == EnsaioStatus.recorded,
    );
    harness.room.refuseTake = 'ensaio/${KeptScope.parte(1)}';
    notifier.takeKeep();

    // Waited on the thing itself — the room saying out loud that something is stuck —
    // instead of on a slice of clock: the attempts are the road, not the destination,
    // and a fixed wait flaked on the runner the day the road got longer.
    await waitFor('a sala dizer que uma tomada ficou presa', () async {
      await harness.takes.flush();
      await notifier.refreshUnsent();
      return harness.voice.assets.contains(strandedTakeAsset(testLanguage));
    });
    await notifier.refreshUnsent();

    expect(harness.voice.assets.where((a) => a == strandedTakeAsset(testLanguage)), hasLength(1),
        reason: 'a equipe precisa saber que algo ficou preso — e ouvir isso uma vez, '
            'não a cada vez que a sala refaz a conta');
  });

  test('a chunk the room refused is not counted as safe either', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await waitFor(
      'a gravação da parte terminar',
      () => container.read(salaSessionProvider).ensaio == EnsaioStatus.recorded,
    );
    notifier.takeKeep();
    // A stretch is a slice of a recording the room can name, and the name is adopted only
    // once the take lands. Entering the retro before that makes every cut arrive with
    // nothing to point at, and the room drops it instead of sending it.
    await waitFor(
      'a sala nomear a parte',
      () => container.read(salaSessionProvider).partes.last.takeId != null,
    );
    notifier.startRetro();
    await waitFor(
      'o clipe estar rodando',
      () => container.read(salaSessionProvider).btClipRodando,
    );

    harness.room.failWith = const RoomUnavailable('sem rede');
    final capturasAntes = harness.recorder.captures;
    notifier.cortarTrecho();
    await waitFor(
      'o microfone abrir para o trecho',
      () => harness.recorder.captures == capturasAntes + 1,
    );
    notifier.retroTap();
    // The refusal parks the stretch in the outbox on disk, after the room has already
    // let go of the thinking: the count is written when that copy lands, not before.
    await waitFor(
      'o trecho ficar por enviar',
      () => container.read(salaSessionProvider).unsentChunks == 1,
    );

    expect(container.read(salaSessionProvider).unsentChunks, 1,
        reason: 'o trecho subiu junto com a transcrição e falhou — a conta não pode dizer pronto');
  });

  test('a told-back piece goes to the server and nothing is voiced', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await waitFor(
      'a gravação da parte terminar',
      () => container.read(salaSessionProvider).ensaio == EnsaioStatus.recorded,
    );
    notifier.takeKeep();
    // A stretch is a slice of a recording the room can name, and the name is adopted only
    // once the take lands. Entering the retro before that makes every cut arrive with
    // nothing to point at, and the room drops it instead of sending it.
    await waitFor(
      'a sala nomear a parte',
      () => container.read(salaSessionProvider).partes.last.takeId != null,
    );
    notifier.startRetro();
    await waitFor(
      'o clipe estar rodando',
      () => container.read(salaSessionProvider).btClipRodando,
    );

    final spokenBefore = harness.voice.played.length;
    final capturasAntes = harness.recorder.captures;
    notifier.cortarTrecho();
    await waitFor(
      'o microfone abrir para o trecho',
      () => harness.recorder.captures == capturasAntes + 1,
    );
    notifier.retroTap();
    await waitFor(
      'a sala sair do pensando',
      () => container.read(salaSessionProvider).btPhase != BtPhase.thinking,
    );

    expect(harness.room.chunksSent, 1);
    expect(harness.voice.played.length, spokenBefore,
        reason: 'a retomada da gravação é o reconhecimento — nada é falado');
  });

  test('an inaudible piece is not counted', () async {
    final harness = SalaHarness()..room.chunkCaptured = false;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await waitFor(
      'a gravação da parte terminar',
      () => container.read(salaSessionProvider).ensaio == EnsaioStatus.recorded,
    );
    notifier.takeKeep();
    // A stretch is a slice of a recording the room can name, and the name is adopted only
    // once the take lands. Entering the retro before that makes every cut arrive with
    // nothing to point at, and the room drops it instead of sending it.
    await waitFor(
      'a sala nomear a parte',
      () => container.read(salaSessionProvider).partes.last.takeId != null,
    );
    notifier.startRetro();
    await waitFor(
      'o clipe estar rodando',
      () => container.read(salaSessionProvider).btClipRodando,
    );

    final capturasAntes = harness.recorder.captures;
    notifier.cortarTrecho();
    await waitFor(
      'o microfone abrir para o trecho',
      () => harness.recorder.captures == capturasAntes + 1,
    );
    notifier.retroTap();
    await waitFor(
      'a sala sair do pensando',
      () => container.read(salaSessionProvider).btPhase != BtPhase.thinking,
    );

    expect(container.read(salaSessionProvider).btTrechos, isEmpty);
    expect(container.read(salaSessionProvider).btPhase, BtPhase.playing);
  });

  test('a finding from the server opens the two honest exits', () async {
    final harness = SalaHarness()
      ..room.verdictChecked = false
      ..room.verdictFinding = BtFindingKind.addition;
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    notifier.startRetro();
    await settle();
    harness.playback.finishPlayback();
    await settle();

    await notifier.finishBackTranslation();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.btPhase, BtPhase.findings);
    expect(state.btFindings, [BtFindingKind.addition]);
    expect(state.btFindings.single.exitsByReRecording, isTrue);
    expect(harness.voice.played.last, contains('veredito'));
  });

  test('a bad device key asks for a person, not for patience', () async {
    final harness = SalaHarness()..room.failWith = const RoomRefused();
    final container = await inConversa(harness);
    addTearDown(container.dispose);

    final state = container.read(salaSessionProvider);
    expect(state.needsPerson, isTrue);
    expect(state.offline, isFalse,
        reason: 'esperar nunca conserta chave errada — não pode virar tela de offline');
    expect(harness.voice.assets,
        isNot(contains(fixedLineAsset('E0', testLanguage))),
        reason: 'o disco parado é o aviso; a chave errada nunca chegou a um turno do '
            'servidor, então não há E0 nenhum para repetir aqui');
  });

  test('a session the server no longer has is dropped, not retried forever', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    expect(container.read(salaSessionProvider).sessionId, isNotNull);

    harness.room.failWith = const SessionGone();
    container.read(salaSessionProvider.notifier).conversaTap();
    await settle();
    container.read(salaSessionProvider.notifier).conversaTap();
    await settle();

    expect(container.read(salaSessionProvider).sessionId, isNull);
  });

  test('the server asking for a person is obeyed', () async {
    final harness = SalaHarness(settleDelay: const Duration(milliseconds: 60))
      ..room.serverStatus = 'needs_person';
    final container = await inConversa(harness);
    addTearDown(container.dispose);

    await settle(const Duration(milliseconds: 300));

    expect(container.read(salaSessionProvider).needsPerson, isTrue);
  });

  test('losing the room mid-retro never leaves the screen without a gesture', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await waitFor(
      'a gravação da parte terminar',
      () => container.read(salaSessionProvider).ensaio == EnsaioStatus.recorded,
    );
    notifier.takeKeep();
    // A stretch is a slice of a recording the room can name, and the name is adopted only
    // once the take lands. Entering the retro before that makes every cut arrive with
    // nothing to point at, and the room drops it instead of sending it.
    await waitFor(
      'a sala nomear a parte',
      () => container.read(salaSessionProvider).partes.last.takeId != null,
    );
    notifier.startRetro();
    await waitFor(
      'o clipe estar rodando',
      () => container.read(salaSessionProvider).btClipRodando,
    );

    harness.room.reachable = false;
    final capturasAntes = harness.recorder.captures;
    notifier.cortarTrecho();
    await waitFor(
      'o microfone abrir para o trecho',
      () => harness.recorder.captures == capturasAntes + 1,
    );
    notifier.retroTap();
    await waitFor(
      'a sala sair do pensando',
      () => container.read(salaSessionProvider).btPhase != BtPhase.thinking,
    );

    expect(container.read(salaSessionProvider).btPhase, BtPhase.playing,
        reason: 'thinking só avança pela rede — ficaria sem toque e sem volta');
  });

  test('a take is only offered once the recorder has handed it back', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    await settle();
    harness.recorder.holdNextStop();
    notifier.ensaioTap();
    await settle();

    expect(container.read(salaSessionProvider).ensaio, EnsaioStatus.recording,
        reason: 'os três botões da tomada não podem aparecer enquanto o arquivo '
            'ainda está sendo escrito');

    notifier.takeKeep();
    await settle();
    harness.recorder.finishStop();
    await settle();

    expect(container.read(salaSessionProvider).ensaio, EnsaioStatus.recorded);

    notifier.takeKeep();
    await settle();

    expect(container.read(salaSessionProvider).takes, 1,
        reason: 'um keep rápido achava o caminho nulo e descartava a tomada em silêncio');
    expect(container.read(salaSessionProvider).partes, hasLength(1));
  });

  test('a failed take never destroys the one already kept', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    final guardada = container.read(salaSessionProvider).partes.firstOrNull;
    expect(guardada, isNotNull);

    final contadas = container.read(salaSessionProvider).takes;
    harness.recorder.returnsNothing = true;
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.partes.firstOrNull?.path, guardada!.path);
    expect(state.ensaio, EnsaioStatus.idle,
        reason: 'oferecer guardar, refazer e ouvir sobre uma tomada que não existe deixava '
            'a equipe confirmar um ensaio no vazio, do mesmo jeito que um bom');
    expect(state.takes, contadas,
        reason: 'e a conta não pode subir por uma gravação que nunca houve');
    expect(state.needsPerson, isTrue,
        reason: 'gravar a passagem inteira e não sair nada é coisa para uma pessoa olhar');
  });

  test('a take that came back empty is not a take the team can keep', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    harness.recorder.returnsEmpty = true;
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.partes, isEmpty,
        reason: 'um arquivo de zero byte existe e tem caminho, então passava como '
            'tomada, era copiado para guardadas/ e entrava no manifesto');
    expect(state.takes, 0,
        reason: 'e a conta subia por uma passagem que a equipe contou no vazio');
    expect(state.needsPerson, isTrue,
        reason: 'disco cheio ou microfone tomado é coisa para uma pessoa olhar, e a '
            'equipe só descobria na quinta recusa de upload, doze minutos depois');
  });

  test('the back-translation reaches conferida and closes the necklace', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    notifier.startRetro();
    await settle();

    notifier.cortarTrecho();
    await settle();
    notifier.retroTap();
    await settle();

    harness.playback.finishPlayback();
    await settle();
    expect(container.read(salaSessionProvider).canFinishBackTranslation, isTrue);

    await notifier.finishBackTranslation();
    await settle();
    await notifier.aprovarRascunhoFinal();
    await settle(const Duration(seconds: 2));

    expect(container.read(salaSessionProvider).stage, SalaStage.fim);
  });

  test('a cold session goes straight from a touch to the guide opening, nothing '
      'of the app before it', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);

    await container.read(salaSessionProvider.notifier).openConvite();

    expect(harness.voice.assets, isEmpty,
        reason: 'não há mais pergunta de método a fazer com uma fala fixa do app; '
            'a primeira voz na sala é a do Guia, tocada pela url que a sala mandou');
    expect(harness.voice.played, hasLength(1),
        reason: 'e essa única fala é o turno de abertura');
    expect(harness.room.calls, ['createSession', 'openSession'],
        reason: 'sessão fria pede só a abertura — nada de rodada de calibração antes');
  });

  test('a bridge mode the server still reports on a turn changes nothing: a '
      'touch at the entrada still records the next question', () async {
    final harness = SalaHarness()..room.bridgeMode = 'calibration_pending';
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.openConvite();
    notifier.conviteTap();
    await settle();

    expect(harness.recorder.captures, 1,
        reason: 'bridge_mode não é mais lido em lugar nenhum do app — o toque na '
            'entrada grava a próxima pergunta do mesmo jeito, com ou sem ele');
    expect(container.read(salaSessionProvider).voice, VoiceState.listening);
  });

  test('a touch after the panorama speaks starts recording the next question',
      () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.openConvite();
    notifier.conviteTap();
    await settle();

    expect(harness.recorder.captures, 1,
        reason: 'a sala falou o panorama e parou; antes desse fix o toque na '
            'entrada só virava a conta de madeira, sem abrir microfone nenhum');
    expect(container.read(salaSessionProvider).voice, VoiceState.listening);
  });

  test('finishing that recording opens a second panorama turn, and the bead '
      'stays offered through both', () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.openConvite();
    notifier.conviteTap();
    await settle();
    notifier.conviteTap();
    await settle();

    expect(harness.room.turnsSent, 1,
        reason: 'a pergunta gravada vira um turno de panorama, não fica presa '
            'no aparelho');
    final afterFirst = container.read(salaSessionProvider);
    expect(afterFirst.conviteStep, ConviteStep.entrada);
    expect(afterFirst.entradaOffered, isTrue,
        reason: 'a conta continua na mesa depois da 1ª resposta, não só depois '
            'da 1ª fala');

    notifier.conviteTap();
    await settle();
    notifier.conviteTap();
    await settle();

    expect(harness.room.turnsSent, 2,
        reason: 'o panorama não tem fim previsto — um segundo toque abre um '
            'segundo turno em vez de bater numa tela morta');
    expect(container.read(salaSessionProvider).entradaOffered, isTrue);
  });

  test('a run of panorama exchanges never opens a passage session on its own',
      () async {
    final harness = SalaHarness();
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.openConvite();
    for (var i = 0; i < 4; i++) {
      notifier.conviteTap();
      await settle();
      notifier.conviteTap();
      await settle();
    }

    expect(container.read(salaSessionProvider).stage, SalaStage.convite,
        reason: 'quatro idas e voltas de gravação não têm por que sair do '
            'panorama sozinhas — a passagem só nasce quando a equipe toca a conta');
    expect(harness.room.sessionIds, hasLength(1),
        reason: 'nenhuma sessão de passagem é criada por um toque no círculo');
    expect(harness.room.turnsSent, 4);
  });

  test('a panorama turn the recorder never handed back returns to the invite '
      'in silence', () async {
    final harness = SalaHarness()..recorder.returnsNothing = true;
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.openConvite();
    notifier.conviteTap();
    await settle();
    notifier.conviteTap();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.needsPerson, isFalse,
        reason: 'a mesma volta em silêncio que todo outro caminho de gravação '
            'vazia usa agora — o panorama não é uma exceção');
    expect(state.voice, VoiceState.invite);
    expect(harness.room.turnsSent, 0);
  });

  test('terminei carries how much of the clip was actually heard', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    notifier.startRetro();
    await settle();
    harness.playback.at = const Duration(seconds: 61);
    harness.playback.finishPlayback();
    await settle();
    await notifier.finishBackTranslation();
    await settle();

    expect(harness.room.playedByTakeSent, isNotEmpty);
    expect(harness.room.playedByTakeSent.last, [
      {
        'take_id': harness.room.takeIds.single,
        'played_ranges': [
          [0, 61000]
        ],
        'clip_duration_ms': 61000,
      },
    ], reason: 'o alcance tocado é evidência para o artefato do Refine: '
        'o servidor registra o que o tablet realmente deixou tocar, e diz de '
        'qual gravação está falando');
  });

  test('a line that will not play does not erase the necklace', () async {
    final harness = SalaHarness()..voice.succeeds = false;
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    await notifier.goConversa();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.coverage.total, greaterThan(0),
        reason: 'a cobertura é um fato da passagem, não do áudio: a fala que falhou '
            'deixava o fio nu, sem contas e sem o acerto de 30s agendado');
    expect(harness.room.calls, contains('fetchState'));
    expect(state.voice, VoiceState.invite);
  });

  test('the necklace divides the moment the session is born', () async {
    final harness = SalaHarness()
      ..voice.holdNextFetch()
      ..room.silentAboutCoverage = true;
    final container = harness.container();
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    unawaited(notifier.goConversa());
    await waitFor(
      'a sessão ser aberta',
      () => container.read(salaSessionProvider).sessionId != null,
    );

    expect(container.read(salaSessionProvider).coverage.total, greaterThan(0),
        reason: 'o createSession já devolve a cobertura; o colar não espera a voz');
    harness.voice.finishHeldFetch();
    await settle();
  });

  Future<void> gravaParte(SalaSessionNotifier notifier) async {
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    await settle();
  }

  test('the rehearsal is told in parts, each kept in order', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    await gravaParte(notifier);
    await gravaParte(notifier);
    await gravaParte(notifier);

    final state = container.read(salaSessionProvider);
    expect(state.takes, 3);
    expect([for (final t in state.partes) t.scopeId],
        ['parte-1', 'parte-2', 'parte-3']);
    expect(state.ensaio, EnsaioStatus.idle,
        reason: 'guardar uma parte já deixa o círculo pronto para a próxima');
    await waitFor('a sala guardar a terceira tomada', () => harness.room.takesKept.length == 3);
    expect(harness.room.takesKept,
        ['ensaio/parte-1', 'ensaio/parte-2', 'ensaio/parte-3']);
    expect(state.ensaioDone, isTrue);
  });

  test('a part still waiting for its check rides into the retro', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    await gravaParte(notifier);
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();

    expect(container.read(salaSessionProvider).ensaio, EnsaioStatus.recorded);
    notifier.startRetro();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.stage, SalaStage.retro);
    expect([for (final t in state.partes) t.scopeId], ['parte-1', 'parte-2'],
        reason: 'um pedaço gravado e ainda sem o check sumia calado no pulo '
            'para a retro');
  });

  test('a recording still running holds the door to the retro', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    await gravaParte(notifier);
    notifier.ensaioTap();
    await settle();

    notifier.startRetro();
    await settle();

    final state = container.read(salaSessionProvider);
    expect(state.stage, SalaStage.ensaio);
    expect(state.ensaio, EnsaioStatus.recording,
        reason: 'avançar no meio de uma gravação a descartaria sem gesto '
            'nenhum da equipe');
  });

  test('the ghost play walks every part in order', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    await gravaParte(notifier);
    await gravaParte(notifier);

    notifier.ghostPlay();
    await settle();
    expect(harness.playback.played, hasLength(1));
    harness.playback.finishPlayback();
    await settle();
    expect(harness.playback.played, hasLength(2),
        reason: 'a parte seguinte toca sozinha quando a anterior acaba');
    harness.playback.finishPlayback();
    await settle();
    expect(container.read(salaSessionProvider).ensaio, EnsaioStatus.idle);
  });

  test('the retro pauses at a part boundary and waits for a gesture', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    await gravaParte(notifier);
    await gravaParte(notifier);
    notifier.startRetro();
    await settle();

    harness.playback.at = const Duration(seconds: 10);
    harness.playback.finishPlayback();
    await settle();

    var state = container.read(salaSessionProvider);
    expect(state.btParteFronteira, isTrue);
    expect(state.btClipEnded, isFalse,
        reason: 'a fronteira não é o fim: terminei não pode aparecer aqui');
    expect(harness.playback.played, hasLength(1));

    notifier.ouvirGravacao();
    await settle();
    expect(harness.playback.played, hasLength(2));
    expect(container.read(salaSessionProvider).btParteFronteira, isFalse);

    harness.playback.at = const Duration(seconds: 8);
    harness.playback.finishPlayback();
    await settle();
    state = container.read(salaSessionProvider);
    expect(state.btClipEnded, isTrue);
    expect(state.canFinishBackTranslation, isTrue);
  });

  test('a part says its own length the moment it opens', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    await gravaParte(notifier);
    await gravaParte(notifier);
    harness.playback.length = const Duration(seconds: 10);
    notifier.startRetro();
    await settle();

    expect(container.read(salaSessionProvider).btParteNoArMs, 10000,
        reason: 'o comprimento só existia quando a última parte acabava, então a tela '
            'não tinha denominador justamente enquanto a equipe escutava');
  });

  test('the ends of the parts already heard reach the screen', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    await gravaParte(notifier);
    await gravaParte(notifier);
    harness.playback.length = const Duration(seconds: 10);
    harness.playback.measured = const Duration(seconds: 10);
    notifier.startRetro();
    await settle();

    expect(container.read(salaSessionProvider).btFimDasPartesMs, [10000, 20000],
        reason: 'as bordas das partes viviam só no notifier, e sem elas a tela não sabe '
            'onde uma parte acaba e a próxima começa — e chegam todas na entrada, antes '
            'de a primeira parte tocar, ou o colar fica sem as faixas das que vêm depois');

    harness.playback.finishPlayback();
    await settle();
    notifier.ouvirGravacao();
    await settle();
    harness.playback.finishPlayback();
    await settle();

    expect(container.read(salaSessionProvider).btFimDasPartesMs, [10000, 20000],
        reason: 'e tocar cada parte confirma a régua em vez de a construir');
  });

  test('pausing writes down where the rehearsal actually stopped', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    await gravaParte(notifier);
    notifier.startRetro();
    await settle();

    harness.playback.at = const Duration(seconds: 6);
    notifier.ouvirGravacao();
    await settle();

    expect(container.read(salaSessionProvider).btOuvidoMs, 6000,
        reason: 'o último trecho diz onde cortaram, não até onde escutaram — uma equipe '
            'escuta longe antes de cortar');
  });

  test('hearing a stretch again does not remeasure the part in the air', () async {
    final harness = SalaHarness()
      ..room.verdictChecked = false
      ..room.verdictFinding = BtFindingKind.missing
      ..room.verdictFindingSegmentId = 'trecho-1';
    final container = await inConversa(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    harness.playback.length = const Duration(seconds: 40);
    await _intoFindings(harness, notifier, container);
    expect(container.read(salaSessionProvider).btPhase, BtPhase.findings);
    expect(container.read(salaSessionProvider).btParteNoArMs, 0,
        reason: 'a parte acabou, então nada está no ar');

    harness.playback.length = const Duration(seconds: 12);
    notifier.ouvirVozMaterna();
    await settle();

    expect(container.read(salaSessionProvider).btParteNoArMs, 0,
        reason: 'o trecho tocado de novo é um pedaço da parte, e medir por ele reescalava '
            'o cordão inteiro no meio da retro');
  });

  test('terminei reports what was heard, not the length of the clip', () async {
    final harness = SalaHarness()..playback.length = const Duration(seconds: 10);
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    await gravaParte(notifier);
    await gravaParte(notifier);
    notifier.startRetro();
    await settle();
    harness.playback.finishPlayback();
    await settle();
    notifier.ouvirGravacao();
    await settle();
    harness.playback.finishPlayback();
    await settle();

    await notifier.finishBackTranslation();
    await settle();

    expect(harness.room.playedByTakeSent.last, [
      {
        'take_id': harness.room.takeIds[0],
        'played_ranges': [
          [0, 10000]
        ],
        'clip_duration_ms': 10000,
      },
      {
        'take_id': harness.room.takeIds[1],
        'played_ranges': [
          [0, 10000]
        ],
        'clip_duration_ms': 10000,
      },
    ], reason: 'o relatório dizia sempre "do zero até o fim", então a trava que '
        'existe para pegar exatamente isso nunca podia falhar; e cada parte é '
        'contada no relógio do próprio arquivo');
  });

  test('a part left unheard is not reported as heard', () async {
    final harness = SalaHarness()..playback.length = const Duration(seconds: 10);
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    await gravaParte(notifier);
    await gravaParte(notifier);
    notifier.startRetro();
    await settle();
    harness.playback.finishPlayback();
    await settle();

    expect(container.read(salaSessionProvider).btClipEnded, isFalse,
        reason: 'a primeira parte acabou; a gravação não');
    notifier.ouvirGravacao();
    await settle();
    harness.playback.at = const Duration(seconds: 3);
    notifier.cortarTrecho();
    await settle();
    notifier.retroTap();
    await settle();

    expect(harness.room.chunkSpans.last, '0-3000',
        reason: 'o trecho é contado no relógio do arquivo que estava tocando, '
            'e a segunda parte começa do próprio zero');
    expect(harness.room.chunkTakes.last, harness.room.takeIds[1],
        reason: 'e é a segunda gravação que ele fatia, não a primeira');
    expect(container.read(salaSessionProvider).btClipRodando, isFalse);
  });

  test('a part measures itself, not the position it stopped at', () async {
    final harness = SalaHarness()..playback.length = const Duration(seconds: 10);
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    await gravaParte(notifier);
    await gravaParte(notifier);
    notifier.startRetro();
    await settle();
    harness.playback.at = Duration.zero;
    harness.playback.finishPlayback();
    await settle();
    notifier.ouvirGravacao();
    await settle();
    harness.playback.finishPlayback();
    await settle();

    await notifier.finishBackTranslation();
    await settle();

    expect(
        [
          for (final parte in harness.room.playedByTakeSent.last)
            parte['clip_duration_ms']
        ],
        [10000, 10000],
        reason: 'lida da posição no instante em que a parte acaba, uma gravação '
            'de três partes se declarava do tamanho de uma');
  });

  test('the circle no longer cuts a stretch on its own', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    await gravaParte(notifier);
    notifier.startRetro();
    await settle();
    final captures = harness.recorder.captures;

    notifier.retroTap();
    await settle();

    expect(harness.recorder.captures, captures,
        reason: 'ouvir e cortar eram o mesmo toque, e a sala só podia adivinhar '
            'quanto a equipe tinha ouvido');
    expect(container.read(salaSessionProvider).btPhase, BtPhase.playing);
  });

  test('terminei names every part the team heard, one entry each', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    await gravaParte(notifier);
    await gravaParte(notifier);
    notifier.startRetro();
    await settle();
    harness.playback.at = const Duration(seconds: 10);
    harness.playback.finishPlayback();
    await settle();
    notifier.ouvirGravacao();
    await settle();
    harness.playback.at = const Duration(seconds: 8);
    harness.playback.finishPlayback();
    await settle();

    await notifier.finishBackTranslation();
    await settle();

    expect(harness.room.playedByTakeSent.last, [
      {
        'take_id': harness.room.takeIds[0],
        'played_ranges': [
          [0, 10000]
        ],
        'clip_duration_ms': 10000,
      },
      {
        'take_id': harness.room.takeIds[1],
        'played_ranges': [
          [0, 8000]
        ],
        'clip_duration_ms': 8000,
      },
    ]);
  });

  test('a finding in the second part plays the right stretch of it', () async {
    final harness = SalaHarness()
      ..room.verdictChecked = false
      ..room.verdictFinding = BtFindingKind.missing;
    final container = await inConversa(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    await gravaParte(notifier);
    await gravaParte(notifier);
    notifier.startRetro();
    await settle();
    harness.playback.at = const Duration(seconds: 10);
    harness.playback.finishPlayback();
    await settle();
    notifier.cortarTrecho();
    await settle();
    notifier.retroTap();
    await waitFor('o primeiro trecho chegar à sala', () => harness.room.chunksSent == 1);
    await settle();
    notifier.ouvirGravacao();
    await settle();
    harness.playback.at = const Duration(seconds: 3);
    notifier.cortarTrecho();
    await settle();
    notifier.retroTap();
    await waitFor('o segundo trecho chegar à sala', () => harness.room.chunksSent == 2);
    await settle();
    harness.playback.at = const Duration(seconds: 8);
    harness.playback.finishPlayback();
    await settle();

    harness.room.verdictFindingSegmentId = 'trecho-2';
    await notifier.finishBackTranslation();
    await settle();

    notifier.ouvirVozMaterna();
    await settle();

    expect(harness.playback.ranges, isNotEmpty);
    expect(harness.playback.ranges.last, '0-3000',
        reason: 'o trecho global 10s–13s vive na parte 2, que começa em 10s: '
            'localmente é 0–3s dentro do arquivo da parte');
    expect(harness.playback.played.last, contains('captura'),
        reason: 'e o arquivo tocado é o da parte 2');
  });

  test('the room stops touching its providers once it is gone', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();
    notifier.takeKeep();
    container.dispose();

    await settle(const Duration(milliseconds: 400));
  },
      timeout: const Timeout(Duration(seconds: 20)));

  test('a room that goes while the count is in flight touches no provider', () async {
    final harness = SalaHarness();
    final queue = QueueHeldOnGiveUps(
      room: harness.room,
      home: () async => harness.takesHome,
    );
    final container = ProviderContainer(
      overrides: [
        ...harness.overrides,
        takeUploadQueueProvider.overrideWithValue(queue),
      ],
    );
    final notifier = container.read(salaSessionProvider.notifier);
    await notifier.goConversa();
    await settle();
    notifier.goEnsaio();
    notifier.ensaioTap();
    notifier.ensaioTap();
    await settle();

    notifier.takeKeep();
    await queue.asking.future;
    container.dispose();
    queue.answer.complete();

    await settle(const Duration(milliseconds: 400));
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('a turn that comes back after the team left is not spoken', () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    harness.room.holdNextTurn();

    unawaited(notifier.goConversa(pericope: 'P01'));
    await settle();
    notifier.leaveThePassage();
    await settle();
    final saidBeforeItLanded = harness.voice.played.length;
    harness.room.finishHeldTurn();
    await settle();

    expect(harness.voice.played.skip(saidBeforeItLanded), isNot(contains(turnoUrl)),
        reason: 'a resposta chegou para uma passagem que a equipe ja tinha deixado');
  });

  test('a turn that comes back after the team left writes no coverage', () async {
    final harness = SalaHarness();
    harness.room.nextCoverage = coverage(engaged: 7, surfaced: 2);
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    harness.room.holdNextTurn();

    unawaited(notifier.goConversa(pericope: 'P01'));
    await settle();
    notifier.leaveThePassage();
    await settle();
    harness.room.finishHeldTurn();
    await settle();

    expect(container.read(salaSessionProvider).coverage.engaged, 0,
        reason: 'o colar da passagem nova recebeu o que a passagem velha apurou');
  });

  test('a spoken turn that comes back after the team left is not spoken either',
      () async {
    final harness = SalaHarness();
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);
    notifier.conversaTap();
    await settle();
    harness.room.holdNextTurn();
    notifier.conversaTap();
    await settle();

    notifier.leaveThePassage();
    await settle();
    final saidBeforeItLanded = harness.voice.played.length;
    harness.room.finishHeldTurn();
    await settle();

    expect(harness.room.calls, contains('sendTurn'),
        reason: 'sem o envio o teste nao encena a corrida que a issue nomeia');
    expect(harness.voice.played.skip(saidBeforeItLanded), isNot(contains(turnoUrl)),
        reason: 'openSession e sendTurn sao dois caminhos e a issue nomeia os dois');
  });

  test('an ordinary turn is still spoken and still fills the necklace', () async {
    final harness = SalaHarness();
    harness.room.nextCoverage = coverage(engaged: 7, surfaced: 2);
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    notifier.conversaTap();
    await settle();
    notifier.conversaTap();
    await settle();

    expect(harness.voice.played, contains(turnoUrl),
        reason: 'uma guarda mal posta cala a sala inteira, e sala muda e pior');
    expect(container.read(salaSessionProvider).coverage.engaged, 7);
  });

  test('lines the team never hears halt the room for a person', () async {
    final player = SpeakingPlayer()..stopsBeforeTheEnd = true;
    final library = Directory.systemTemp.createTempSync('sala-voz-parada');
    addTearDown(() => library.deleteSync(recursive: true));
    final harness = SalaHarness(
      voiceService: FacilitatorVoiceService(
        fetch: (_) async => Uint8List.fromList([1, 2, 3]),
        libraryDir: () async => library,
        player: player,
      ),
    );
    final container = await inConversa(harness);
    addTearDown(container.dispose);
    final notifier = container.read(salaSessionProvider.notifier);

    for (var attempt = 0; attempt < 3; attempt++) {
      notifier.conversaTap();
      await settle();
      notifier.conversaTap();
      await settle();
    }

    expect(container.read(salaSessionProvider).needsPerson, isTrue,
        reason: 'o dano da issue e os cinco contadores de saude serem zerados '
            'por uma linha que a equipe nunca ouviu');
  });
}

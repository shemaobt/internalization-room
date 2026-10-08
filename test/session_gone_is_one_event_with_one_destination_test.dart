import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_answer.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/take_upload_queue.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/facilitator_script.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/machine.dart';
import 'package:internalization_room/features/sala/domain/passagem.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';
import 'scenario_helpers.dart' show enterThePanorama, enterThePassage, settle;

const _slowerThanAnyWait = Duration(milliseconds: 500);
const _slowerThanTheLongestWait = Duration(seconds: 1);

const _livroComPanorama = [
  Passagem(
    pericope: 'panorama',
    audioUrl: '/voice/panorama',
    kind: PassagemKind.panorama,
  ),
  Passagem(pericope: 'P01', audioUrl: '/voice/p01'),
  Passagem(pericope: 'P02', audioUrl: '/voice/p02'),
];

Future<ProviderContainer> _semPassagemNaMemoria(SalaHarness harness) async {
  final container = harness.container();
  addTearDown(container.dispose);
  await container.read(salaSessionProvider.notifier).goConversa();
  await settle();
  return container;
}

Future<ProviderContainer> _naPassagem(SalaHarness harness) async {
  final container = harness.container();
  addTearDown(container.dispose);
  final sala = container.read(salaSessionProvider.notifier);
  await sala.abrirEscolha();
  await settle();
  sala.entrarNaOferecida();
  await waitFor(
    'a passagem abrir',
    () => container.read(salaSessionProvider).sessionId != null,
  );
  await settle();
  return container;
}

SalaSessionState _estado(ProviderContainer container) =>
    container.read(salaSessionProvider);

String _sessao(ProviderContainer container) => _estado(container).sessionId!;

Future<void> _naEscolha(ProviderContainer container) => waitFor(
  'a sala abrir a Escolha',
  () =>
      _estado(container).stage == SalaStage.escolha &&
      _estado(container).naRoda != null,
);

Future<void> _gravarEGuardarUmaParte(ProviderContainer container) async {
  final sala = container.read(salaSessionProvider.notifier);
  sala.goEnsaio();
  sala.ensaioTap();
  sala.ensaioTap();
  await waitFor(
    'a gravação da parte terminar',
    () => _estado(container).ensaio == EnsaioStatus.recorded,
  );
  sala.takeKeep();
  await waitFor(
    'a sala nomear a parte',
    () => _estado(container).partes.last.takeId != null,
  );
}

Future<void> _abrirACapturaDeUmTrecho(
  SalaHarness harness,
  ProviderContainer container,
) async {
  final sala = container.read(salaSessionProvider.notifier);
  await _gravarEGuardarUmaParte(container);
  sala.startRetro();
  await waitFor(
    'o clipe estar rodando',
    () => _estado(container).btClipRodando,
  );
  harness.playback.at = const Duration(seconds: 2);
  sala.cortarTrecho();
  sala.retroTap();
  await waitFor(
    'o microfone abrir para o trecho',
    () => _estado(container).btPhase == BtPhase.capturing,
  );
}

Future<PendingTake> _naFila(
  SalaHarness harness,
  String sessionId, {
  required String nome,
  String scope = 'parte-1',
}) => harness.takes.enqueue(
  harness.recorder.aFile(nome),
  sessionId: sessionId,
  kind: 'ensaio',
  scope: scope,
  passNumber: 1,
  chunkIndex: 1,
);

Future<List<PendingTake>> _daSessao(
  SalaHarness harness,
  String sessionId,
) async => [
  for (final row in await harness.takes.entries())
    if (row.sessionId == sessionId) row,
];

Future<bool> _aFilaEsvaziou(
  SalaHarness harness,
  String sessionId,
  List<PendingTake> linhas,
) async =>
    (await _daSessao(harness, sessionId)).isEmpty &&
    linhas.every((linha) => !File(linha.path).existsSync());

void _abrirOMicrofoneDaConversa(ProviderContainer container) {
  container.read(salaSessionProvider.notifier).conversaTap();
}

Future<void> _oMicrofoneAberto(ProviderContainer container) => waitFor(
  'o microfone abrir na conversa',
  () => _estado(container).voice == VoiceState.listening,
);

void main() {
  test(
    'case (a): the chunk door answers gone with no passage in progress in '
    'memory, and the room opens the Choice without calling a person',
    () async {
      final harness = SalaHarness();
      final container = await _semPassagemNaMemoria(harness);
      await _abrirACapturaDeUmTrecho(harness, container);

      harness.room.chunkAnswersFirst.add(const SessionGone());
      await confirmarATraducao(container);
      await _naEscolha(container);
      await settle();

      expect(_estado(container).stage, SalaStage.escolha);
      expect(_estado(container).needsPerson, isFalse);
      expect(harness.room.personsAsked, 0);
      expect(
        harness.room.deviceAsksReceived,
        isEmpty,
        reason:
            'nenhuma pessoa é chamada por uma sessão que o servidor esqueceu',
      );
    },
  );

  test(
    'case (b): gone with two Outbox rows of the session pending removes the '
    'rows and their files, and the Outbox tally shows nothing pending',
    () async {
      final harness = SalaHarness(
        takesOverride: (room, home) =>
            QueueThatDiscardsLate(room: room, home: () async => home)
              ..discardsAfter = _slowerThanAnyWait,
      );
      final container = await _naPassagem(harness);
      final sessao = _sessao(container);
      final primeira = await _naFila(harness, sessao, nome: 'parte-um');
      final segunda = await _naFila(
        harness,
        sessao,
        nome: 'parte-dois',
        scope: 'parte-2',
      );

      harness.room.forgetTheSession(sessao);
      _abrirOMicrofoneDaConversa(container);
      await _oMicrofoneAberto(container);
      container.read(salaSessionProvider.notifier).conversaTap();
      await _naEscolha(container);
      await waitFor(
        'as linhas e os arquivos da sessão saírem da fila',
        () => _aFilaEsvaziou(harness, sessao, [primeira, segunda]),
      );

      expect(await _daSessao(harness, sessao), isEmpty);
      expect(File(primeira.path).existsSync(), isFalse);
      expect(File(segunda.path).existsSync(), isFalse);
      expect(await harness.takes.pending(), isEmpty);
      expect(
        (await harness.takes.tally(sessionId: sessao)).parts.values,
        isNot(contains(PartFact.pending)),
        reason: 'a contagem da Outbox não mostra nada pendente',
      );
    },
  );

  test('case (c): a Resume point of a session the server deleted forgets the '
      'row and the session\'s files at takesOf, and opens the Choice with no '
      'fresh session', () async {
    final harness = SalaHarness()
      ..emAberto.forgetsTheSessionAfter = _slowerThanAnyWait;
    final aqui = harness.recorder.aFile('parte-1-guardada').path;
    final naoMaisAqui = '${harness.recorder.home.path}/parte-2-sumida.m4a';
    harness.emAberto.rows['Ruth/P01'] = ResumePoint(
      sessionId: 'sessao-apagada',
      stage: SalaStage.ensaio,
      takes: [
        KeptTake(scopeId: KeptScope.parte(1), path: aqui, takeId: 'g-1'),
        KeptTake(scopeId: KeptScope.parte(2), path: naoMaisAqui, takeId: 'g-2'),
      ],
    );
    harness.room.forgetTheSession('sessao-apagada');
    final container = harness.container();
    addTearDown(container.dispose);
    final sala = container.read(salaSessionProvider.notifier);
    await sala.abrirEscolha();
    await settle();

    await sala.goConversa(pericope: 'P01');
    await _naEscolha(container);
    await waitFor(
      'o lugar e a gravação guardada saírem do tablet',
      () async =>
          (await harness.emAberto.of('Ruth', 'P01')) == null &&
          harness.recorder.deleted.contains(aqui),
    );

    expect(harness.room.askedOfTheForgotten, contains('takesOf'));
    expect(await harness.emAberto.of('Ruth', 'P01'), isNull);
    expect(harness.recorder.deleted, contains(aqui));
    expect(
      harness.room.calls,
      isNot(contains('createSession')),
      reason: 'a retomada de uma sessão apagada não abre uma sessão nova',
    );
    expect(_estado(container).stage, SalaStage.escolha);
    expect(_estado(container).needsPerson, isFalse);
  });

  test('case (c): a Resume point of a session the server deleted, reopened in '
      'the conversation, meets gone at the session read and opens the Choice '
      'with no fresh session', () async {
    final harness = SalaHarness()
      ..emAberto.forgetsTheSessionAfter = _slowerThanAnyWait;
    harness.emAberto.rows['Ruth/P01'] = const ResumePoint(
      sessionId: 'sessao-apagada',
      stage: SalaStage.conversa,
    );
    harness.room.forgetTheSession('sessao-apagada');
    final container = harness.container();
    addTearDown(container.dispose);
    final sala = container.read(salaSessionProvider.notifier);
    await sala.abrirEscolha();
    await settle();

    await sala.goConversa(pericope: 'P01');
    await _naEscolha(container);
    await waitFor(
      'o lugar da sessão esquecida sair do tablet',
      () async => (await harness.emAberto.of('Ruth', 'P01')) == null,
    );

    expect(harness.room.askedOfTheForgotten, contains('fetchState'));
    expect(await harness.emAberto.of('Ruth', 'P01'), isNull);
    expect(harness.room.calls, isNot(contains('createSession')));
    expect(_estado(container).stage, SalaStage.escolha);
  });

  test('case (d): gone while the microphone is open in the conversation closes '
      'the microphone, discards the recording and opens the Choice', () async {
    final harness = SalaHarness(watchesWithoutAHalt: true);
    final container = await _semPassagemNaMemoria(harness);
    _abrirOMicrofoneDaConversa(container);
    await _oMicrofoneAberto(container);

    final apagadasAntes = harness.recorder.deleted.length;
    harness.room.forgetTheSession(_sessao(container));
    await _naEscolha(container);
    await settle();

    expect(_estado(container).voice, isNot(VoiceState.listening));
    expect(
      harness.recorder.deleted.skip(apagadasAntes),
      [harness.recorder.lastPath],
      reason: 'a gravação aberta é descartada',
    );
    expect(harness.room.turnsSent, 0);
    expect(_estado(container).needsPerson, isFalse);
  });

  test('case (d): gone while the microphone is open out of reach closes the '
      'microphone, discards the recording and opens the Choice', () async {
    final harness = SalaHarness(
      watchesWithoutAHalt: true,
      retryBackoff: const [Duration(seconds: 5)],
    );
    final container = await _semPassagemNaMemoria(harness);
    _abrirOMicrofoneDaConversa(container);
    await _oMicrofoneAberto(container);
    harness.room.reachable = false;
    await waitFor('a sala cair', () => _estado(container).unreachable);

    final apagadasAntes = harness.recorder.deleted.length;
    harness.room
      ..reachable = true
      ..forgetTheSession(_sessao(container));
    await _naEscolha(container);
    await settle();

    expect(_estado(container).voice, isNot(VoiceState.listening));
    expect(
      harness.recorder.deleted.skip(apagadasAntes),
      [harness.recorder.lastPath],
      reason: 'a gravação aberta é descartada, também fora de alcance',
    );
    expect(harness.room.turnsSent, 0);
    expect(_estado(container).needsPerson, isFalse);
  });

  test('invariant 1: after gone nothing of the session remains, and nothing '
      'asks the room about it again', () async {
    final harness = SalaHarness(
      retryBackoff: const [Duration(milliseconds: 40)],
    )..emAberto.forgetsTheSessionAfter = _slowerThanTheLongestWait;
    final container = await _naPassagem(harness);
    final sessao = _sessao(container);
    await _abrirACapturaDeUmTrecho(harness, container);
    final parte = _estado(container).partes.single.path;

    harness.room.chunkAnswersFirst.add(const NetworkFailed('sem rede'));
    harness.network.reachable = false;
    await confirmarATraducao(container);
    await waitFor('a sala cair', () => _estado(container).unreachable);
    final traducao = _estado(container).btTraducaoPendente!;
    final linhas = await _daSessao(harness, sessao);
    expect(linhas, isNotEmpty);
    expect(await harness.emAberto.of('Ruth', 'P01'), isNotNull);

    harness.room.forgetTheSession(sessao);
    harness.network.reachable = true;
    await _naEscolha(container);
    await waitFor(
      'o lugar, a fila e as gravações da sessão saírem do tablet',
      () async =>
          (await harness.emAberto.of('Ruth', 'P01')) == null &&
          await _aFilaEsvaziou(harness, sessao, linhas) &&
          [parte, traducao].every(harness.recorder.deleted.contains),
    );
    final perguntasNaHora = harness.room.askedOfTheForgotten.length;
    await settle(const Duration(milliseconds: 400));

    expect(await harness.emAberto.of('Ruth', 'P01'), isNull);
    expect(await _daSessao(harness, sessao), isEmpty);
    for (final linha in linhas) {
      expect(File(linha.path).existsSync(), isFalse, reason: linha.kind);
    }
    expect(harness.recorder.deleted, containsAll([parte, traducao]));
    expect(_estado(container).btTraducaoPendente, isNull);
    expect(_estado(container).partes, isEmpty);
    expect(
      harness.room.askedOfTheForgotten.length,
      perguntasNaHora,
      reason:
          'nenhum relógio do passo, nenhum pedido pendente e nenhuma chave '
          'sobrevivem: nada volta a perguntar pela sessão esquecida',
    );
  });

  test('invariant 3: a halt standing when the Watch reads gone is cleared, '
      'and no call or stop-call is made', () async {
    final harness = SalaHarness(watchesWithoutAHalt: true);
    final container = await _naPassagem(harness);
    harness.room
      ..serverStatus = 'needs_person'
      ..serverHalt = HaltKind.blocking;
    await waitFor('a parada chegar', () => _estado(container).needsPerson);

    harness.room.forgetTheSession(_sessao(container));
    await _naEscolha(container);
    await settle();

    expect(_estado(container).needsPerson, isFalse);
    expect(harness.room.personsAsked, 0);
    expect(harness.room.deviceAsksReceived, isEmpty);
    expect(harness.room.personArrivedSessions, isEmpty);
  });

  test('invariant 3: a halt standing when the call for a person answers gone '
      'is cleared, and no other call or stop-call is made', () async {
    final harness = SalaHarness()..voice.succeeds = false;
    final container = await _naPassagem(harness);
    final sala = container.read(salaSessionProvider.notifier);
    harness.room.askForAPersonFailsWith = const SessionGone();

    for (var vez = 0; vez < 3 && !_estado(container).needsPerson; vez++) {
      sala.conversaTap();
      await settle();
      sala.conversaTap();
      await settle();
    }
    await _naEscolha(container);
    await settle();

    expect(harness.room.calls, contains('askForAPerson'));
    expect(_estado(container).needsPerson, isFalse);
    expect(harness.room.deviceAsksReceived, isEmpty);
    expect(harness.room.personArrivedSessions, isEmpty);
  });

  test('invariant 3: a halt standing when a door answers gone is cleared, and '
      'no call or stop-call is made', () async {
    final harness = SalaHarness();
    final container = await _semPassagemNaMemoria(harness);
    final sala = container.read(salaSessionProvider.notifier);
    harness.room.holdNextTurn();
    sala.conversaTap();
    await _oMicrofoneAberto(container);
    sala.conversaTap();
    await waitFor('o turno sair', () => harness.room.turnsSent > 0);
    sala.haltForABrokenBuild();
    expect(_estado(container).needsPerson, isTrue);

    harness.room.failHeldTurnWith = const SessionGone();
    harness.room.finishHeldTurn();
    await _naEscolha(container);
    await settle();

    expect(_estado(container).needsPerson, isFalse);
    expect(harness.room.personsAsked, 0);
    expect(harness.room.deviceAsksReceived, isEmpty);
    expect(harness.room.personArrivedSessions, isEmpty);
  });

  test('Q1: gone from an older session\'s Outbox row removes that session\'s '
      'rows and files only, and the room stays where it is', () async {
    final harness = SalaHarness(
      takesOverride: (room, home) =>
          QueueThatDiscardsLate(room: room, home: () async => home)
            ..discardsAfter = _slowerThanAnyWait,
    );
    final container = await _naPassagem(harness);
    final sessao = _sessao(container);
    final velha = await _naFila(harness, 'sessao-velha', nome: 'parte-velha');
    final atual = await _naFila(harness, sessao, nome: 'parte-atual');
    harness.room.forgetTheSession('sessao-velha');

    await container.read(salaSessionProvider.notifier).refreshUnsent();
    await waitFor(
      'a fila e o arquivo da sessão velha saírem do tablet',
      () => _aFilaEsvaziou(harness, 'sessao-velha', [velha]),
    );

    expect(await _daSessao(harness, 'sessao-velha'), isEmpty);
    expect(File(velha.path).existsSync(), isFalse);
    expect((await _daSessao(harness, sessao)).map((row) => row.id), [atual.id]);
    expect(File(atual.path).existsSync(), isTrue);
    expect(_estado(container).stage, SalaStage.conversa);
    expect(_estado(container).sessionId, sessao);
  });

  test('Q2: a row mid-upload when gone lands is never re-added, and its file '
      'is deleted after the call ends', () async {
    final harness = SalaHarness()
      ..room.aHeldTakeAnswersAfter = _slowerThanAnyWait;
    final container = await _naPassagem(harness);
    final sessao = _sessao(container);
    final linha = await _naFila(harness, sessao, nome: 'parte-no-ar');
    harness.room.holdNextTake('parte-1');
    await container.read(salaSessionProvider.notifier).refreshUnsent();
    await harness.room.untilTakeHeld();

    harness.room.forgetTheSession(sessao);
    _abrirOMicrofoneDaConversa(container);
    await _oMicrofoneAberto(container);
    container.read(salaSessionProvider.notifier).conversaTap();
    await _naEscolha(container);
    await settle();
    expect(
      File(linha.path).existsSync(),
      isTrue,
      reason: 'a chamada ainda está no ar; o arquivo só sai quando ela acabar',
    );

    harness.room.finishHeldTake();
    await waitFor(
      'a fila e o arquivo da sessão saírem do tablet',
      () => _aFilaEsvaziou(harness, sessao, [linha]),
    );

    expect(await _daSessao(harness, sessao), isEmpty);
    expect(File(linha.path).existsSync(), isFalse);
  });

  test('Q5: out of reach, gone leaves the room out of reach at the Choice with '
      'its retry armed, and drops the queued notice', () async {
    final harness = SalaHarness(
      watchesWithoutAHalt: true,
      retryBackoff: const [Duration(milliseconds: 250)],
    );
    final container = await _naPassagem(harness);
    _abrirOMicrofoneDaConversa(container);
    await _oMicrofoneAberto(container);
    harness.network.reachable = false;
    harness.room.reachable = false;
    await waitFor('a sala cair', () => _estado(container).unreachable);

    harness.room
      ..reachable = true
      ..forgetTheSession(_sessao(container));
    await _naEscolha(container);
    final sondasNaHora = harness.network.checks;

    expect(
      _estado(container).unreachable,
      isTrue,
      reason: 'a Outbox é da sala inteira; a sessão sumida não diz que voltou',
    );
    await waitFor(
      'a volta da sala ser tentada de novo',
      () => harness.network.checks > sondasNaHora,
    );
    await settle(const Duration(milliseconds: 500));
    expect(
      harness.voice.assets,
      isNot(contains(offlineNoticeAsset(testLanguage))),
      reason: 'o aviso esperava sob o microfone e sai da fila com a sessão',
    );
  });

  test('the panorama\'s session gone opens the Choice, and the next passage '
      'is not opened after it', () async {
    final harness = SalaHarness()..room.passages = _livroComPanorama;
    final container = harness.container();
    addTearDown(container.dispose);
    final sala = container.read(salaSessionProvider.notifier);
    harness.room.forgetTheSession('sessao-1');

    await enterThePanorama(sala, () => _estado(container));
    await waitFor(
      'a sala tentar a abertura',
      () => harness.room.askedOfTheForgotten.contains('openSession'),
    );
    await _naEscolha(container);
    await settle();
    await enterThePassage(sala, () => _estado(container), 'P01');
    await waitFor(
      'a passagem abrir',
      () => _estado(container).sessionId != null,
    );

    expect(harness.room.askedOfTheForgotten, contains('openSession'));
    expect(
      harness.room.metBefore.last,
      isFalse,
      reason: 'a passagem não nomeia como anterior um panorama que sumiu',
    );
    expect(_estado(container).needsPerson, isFalse);
    expect(harness.room.personsAsked, 0);
  });

  test('a passage whose panorama the server also forgot neither halts nor '
      'calls a person, and the next pick opens a passage', () async {
    final harness = SalaHarness()..room.passages = _livroComPanorama;
    final container = harness.container();
    addTearDown(container.dispose);
    final sala = container.read(salaSessionProvider.notifier);
    await enterThePanorama(sala, () => _estado(container));
    await settle();
    await enterThePassage(sala, () => _estado(container), 'P01');
    await waitFor(
      'a passagem abrir',
      () => _estado(container).sessionId != null,
    );
    final panorama = harness.room.sessionIds.first;
    final passagem = _sessao(container);
    expect(harness.room.metBefore.last, isTrue);

    harness.room
      ..forgetTheSession(panorama)
      ..forgetTheSession(passagem);
    _abrirOMicrofoneDaConversa(container);
    await _oMicrofoneAberto(container);
    sala.conversaTap();
    await _naEscolha(container);
    await settle();
    final abertas = harness.room.sessionIds.length;
    await enterThePassage(sala, () => _estado(container), 'P01');
    await waitFor(
      'uma passagem abrir de novo',
      () => harness.room.sessionIds.length > abertas,
    );
    await settle();

    expect(_estado(container).needsPerson, isFalse);
    expect(harness.room.personsAsked, 0);
    expect(harness.room.deviceAsksReceived, isEmpty);
    expect(_estado(container).sessionId, harness.room.sessionIds.last);
    expect(harness.room.metBefore.last, isFalse);
  });

  test('a team that leaves while the creation after a gone panorama is in the '
      'air sends no second creation', () async {
    final harness = SalaHarness()..room.passages = _livroComPanorama;
    final container = harness.container();
    addTearDown(container.dispose);
    final sala = container.read(salaSessionProvider.notifier);
    await enterThePanorama(sala, () => _estado(container));
    await settle();
    await sala.abrirEscolha();
    await settle();
    harness.room
      ..forgetTheSession(harness.room.sessionIds.first)
      ..holdNextCreate();
    await enterThePassage(sala, () => _estado(container), 'P01');
    await waitFor('a criação sair', () => harness.room.createHeld);
    final criacoes = harness.room.calls
        .where((call) => call == 'createSession')
        .length;

    sala.leaveThePassage();
    await _naEscolha(container);
    harness.room.finishHeldCreate();
    await settle(const Duration(milliseconds: 300));

    expect(
      harness.room.calls.where((call) => call == 'createSession').length,
      criacoes,
      reason:
          'a equipe já saiu; uma segunda criação deixaria uma sessão fantasma',
    );
  });

  test('leaving a passage by the way out keeps the room out of reach, with '
      'its retry armed', () async {
    final harness = SalaHarness(
      retryBackoff: const [Duration(milliseconds: 250)],
    );
    final container = await _naPassagem(harness);
    final sala = container.read(salaSessionProvider.notifier);
    harness.network.reachable = false;
    harness.room.reachable = false;
    _abrirOMicrofoneDaConversa(container);
    await _oMicrofoneAberto(container);
    sala.conversaTap();
    await waitFor('a sala cair', () => _estado(container).unreachable);
    harness.room.reachable = true;

    sala.leaveThePassage();
    await waitFor(
      'a sala abrir a Escolha',
      () => _estado(container).stage == SalaStage.escolha,
    );
    final sondasNaHora = harness.network.checks;

    expect(_estado(container).unreachable, isTrue);
    await waitFor(
      'a volta da sala ser tentada de novo',
      () => harness.network.checks > sondasNaHora,
    );
  });

  test('ENG-1155: a gone at the chunk door leaves no translation copy in the '
      'Outbox and no file on disk, even with the enqueue in flight', () async {
    late QueueThatDiscardsLate fila;
    final harness = SalaHarness(
      takesOverride: (room, home) =>
          fila = QueueThatDiscardsLate(room: room, home: () async => home)
            ..discardsAfter = _slowerThanAnyWait,
    );
    final container = await _naPassagem(harness);
    await _abrirACapturaDeUmTrecho(harness, container);

    harness.room.chunkAnswersFirst.add(const SessionGone());
    await confirmarATraducao(container);
    final traducao = harness.recorder.lastPath!;
    await _naEscolha(container);
    await waitFor(
      'a sala descartar a sessão e a cópia da tradução em voo',
      () => fila.discardsDone >= 2,
    );

    final retro = [
      for (final row in await harness.takes.entries())
        if (row.kind == 'retro') row,
    ];
    expect(retro, isEmpty);
    final naPasta = Directory(
      '${harness.takesHome.path}/guardadas',
    ).listSync().map((entry) => entry.uri.pathSegments.last);
    expect(naPasta, ['fila.json']);
    expect(harness.recorder.deleted, contains(traducao));
  });
}

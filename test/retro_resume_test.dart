import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internalization_room/features/sala/data/room_repository.dart';
import 'package:internalization_room/features/sala/data/session_notifier.dart';
import 'package:internalization_room/features/sala/data/work_in_progress.dart';
import 'package:internalization_room/features/sala/domain/kept_take.dart';
import 'package:internalization_room/features/sala/domain/session_snapshot.dart';
import 'package:internalization_room/features/sala/domain/session_state.dart';

import 'fakes.dart';

Future<void> settle([Duration delay = const Duration(milliseconds: 120)]) async {
  await Future<void>.delayed(delay);
}

const _gravacao = 'gravacao-1';

const _traduzidos = BackTranslationProgress(
  segments: [
    SegmentView(
      segmentId: 'trecho-1',
      takeId: _gravacao,
      startsMs: 0,
      endsMs: 12000,
    ),
    SegmentView(
      segmentId: 'trecho-2',
      takeId: _gravacao,
      startsMs: 12000,
      endsMs: 30000,
      passNumber: 2,
    ),
  ],
);

/// A tablet that was closed part-way and is opened again on the same passage.
///
/// The rehearsal is on disk, the ledger says where they were, and the room answers with
/// whatever [contado] says it is holding for that session. With [semAudio] the ledger
/// still names the rehearsal and the tablet no longer has it.
Future<ProviderContainer> _reopen(
  SalaHarness harness, {
  required SalaStage parouEm,
  BackTranslationProgress contado = const BackTranslationProgress(),
  bool semAudio = false,
}) async {
  final gravada = File(
    '${Directory.systemTemp.createTempSync('sala-retro-retomada').path}/p1.m4a',
  )..writeAsBytesSync([1, 2, 3]);
  addTearDown(() => gravada.parent.deleteSync(recursive: true));
  if (semAudio) gravada.deleteSync();
  harness.emAberto.rows['Ruth/P01'] = ResumePoint(
    sessionId: 'sessao-antiga',
    stage: parouEm,
    takes: [
      KeptTake(
        scopeId: KeptScope.parte(1),
        path: gravada.path,
        takeId: _gravacao,
      ),
    ],
  );
  harness.room.retroSoFar = contado;
  final container = harness.container();
  addTearDown(container.dispose);
  final notifier = container.read(salaSessionProvider.notifier);
  await notifier.abrirEscolha();
  await settle();
  await notifier.goConversa(pericope: 'P01');
  await settle();
  return container;
}

void main() {
  test('a team that stopped telling back is telling back again', () async {
    final harness = SalaHarness();

    final container = await _reopen(
      harness,
      parouEm: SalaStage.retro,
      contado: _traduzidos,
    );

    final state = container.read(salaSessionProvider);
    expect(state.stage, SalaStage.retro,
        reason: 'a equipe voltava ao ensaio e gravava a passagem inteira de '
            'novo, e o servidor ficava com duas gravações e duas retros');
    expect(state.btTrechos, hasLength(2));
  });

  test('the stretches that come back are the ones the room is holding', () async {
    final harness = SalaHarness();

    final container = await _reopen(
      harness,
      parouEm: SalaStage.retro,
      contado: _traduzidos,
    );

    final state = container.read(salaSessionProvider);
    expect(
      [for (final trecho in state.btTrechos) '${trecho.from}-${trecho.to}'],
      ['0:00:00.000000-0:00:12.000000', '0:00:12.000000-0:00:30.000000'],
    );
    expect(state.btChunkPasses, [1, 2]);
    expect(
      [for (final trecho in state.btTrechos) trecho.takeId],
      [_gravacao, _gravacao],
      reason: 'cada trecho volta amarrado à gravação que ele fatia',
    );
  });

  test('a telling-back the room already checked does not start over', () async {
    final harness = SalaHarness();

    final container = await _reopen(
      harness,
      parouEm: SalaStage.retro,
      contado: const BackTranslationProgress(
        segments: [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: _gravacao,
            startsMs: 0,
            endsMs: 30000,
          ),
        ],
        checked: true,
      ),
    );

    final state = container.read(salaSessionProvider);
    expect(state.stage, SalaStage.retro);
    expect(state.btPhase, BtPhase.conferida,
        reason: 'a conferência já passou; pedir os trechos de novo é cobrar da '
            'equipe um trabalho que o servidor já tem');
    expect(state.voice, VoiceState.done);
  });

  test('with no stretch on the room, the rehearsal is still where they land',
      () async {
    final harness = SalaHarness();

    final container = await _reopen(harness, parouEm: SalaStage.retro);

    final state = container.read(salaSessionProvider);
    expect(state.stage, SalaStage.ensaio,
        reason: 'não há retro para retomar, e inventar uma seria pior que '
            'refazer o ensaio');
    expect(state.btTrechos, isEmpty);
  });

  test('a telling-back resumed without its rehearsal starts the room over',
      () async {
    final harness = SalaHarness();

    final container = await _reopen(
      harness,
      parouEm: SalaStage.retro,
      contado: _traduzidos,
      semAudio: true,
    );

    expect(harness.room.restartsAsked, ['novo-clipe'],
        reason: 'a equipe contava a passagem inteira de novo sobre trechos que '
            'a sessão ainda guardava, e o analista recebia os velhos '
            'concatenados com os novos');
    expect(container.read(salaSessionProvider).stage, SalaStage.conversa);
  });

  test('a retro nobody had told back into yet throws nothing away', () async {
    final harness = SalaHarness();

    final container = await _reopen(
      harness,
      parouEm: SalaStage.retro,
      semAudio: true,
    );

    expect(harness.room.restartsAsked, isEmpty,
        reason: 'o ponto de retomada é escrito ao entrar na retro, antes de '
            'qualquer trecho contado, então a maior parte das retomadas pedia '
            'à sala que descartasse um nada');
    expect(container.read(salaSessionProvider).stage, SalaStage.conversa);
  });

  test('a passage the room already checked comes back to the approval, not to a close',
      () async {
    final harness = SalaHarness();

    final container = await _reopen(
      harness,
      parouEm: SalaStage.retro,
      contado: const BackTranslationProgress(
        segments: [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: _gravacao,
            startsMs: 0,
            endsMs: 30000,
          ),
        ],
        checked: true,
      ),
      semAudio: true,
    );
    final notifier = container.read(salaSessionProvider.notifier);

    await settle(const Duration(seconds: 2));

    expect(harness.room.restartsAsked, isEmpty,
        reason: 'recomeçar aposenta todo trecho e desfaz o conferida: a passagem '
            'que a equipe terminou voltava a não estar terminada');
    expect(container.read(salaSessionProvider).stage, SalaStage.retro,
        reason: 'a equipe volta ao gesto que falta — deixá-la na conversa é '
            'mandá-la gravar e contar tudo de novo, e fechar sozinho é tirar '
            'dela a aprovação que ninguém deu ainda');
    expect(container.read(salaSessionProvider).btPhase, BtPhase.conferida);
    expect(harness.finished.done, isNot(contains('Ruth/P01')),
        reason: 'e a passagem não está feita: quem a fecha é a aprovação');
    expect(harness.emAberto.rows, contains('Ruth/P01'),
        reason: 'então o ponto de retomada continua de pé, para a próxima vez');

    await notifier.aprovarRascunhoFinal();
    await settle(const Duration(seconds: 2));

    expect(harness.room.releasesAsked, ['sessao-antiga'],
        reason: 'a aprovação vale para a sessão que a equipe retomou');
    expect(container.read(salaSessionProvider).stage, SalaStage.fim);
    expect(harness.finished.done, contains('Ruth/P01'));
    expect(harness.emAberto.rows, isNot(contains('Ruth/P01')));
  });

  test('a passage checked and picked back up over its own recording lands on the approval too',
      () async {
    final harness = SalaHarness();

    final container = await _reopen(
      harness,
      parouEm: SalaStage.retro,
      contado: const BackTranslationProgress(
        segments: [
          SegmentView(
            segmentId: 'trecho-1',
            takeId: _gravacao,
            startsMs: 0,
            endsMs: 30000,
          ),
        ],
        checked: true,
      ),
    );

    await settle(const Duration(seconds: 2));

    expect(container.read(salaSessionProvider).stage, SalaStage.retro,
        reason: 'a outra porta da retomada — a que encontra o ensaio no tablet '
            '— tem de pousar no mesmo lugar: duas portas para a mesma passagem '
            'não podem discordar sobre se ela acabou');
    expect(container.read(salaSessionProvider).btPhase, BtPhase.conferida);
    expect(container.read(salaSessionProvider).partes, isNotEmpty,
        reason: 'e com o ensaio de pé, que é o que a última audição pede');
    expect(harness.finished.done, isNot(contains('Ruth/P01')));

    container.read(salaSessionProvider.notifier).ouvirGravacao();
    await settle();

    expect(harness.playback.played, isNotEmpty,
        reason: 'a última audição que a fala do veredito convida tem de valer '
            'também aqui: a sala retomada nunca pôs parte nenhuma no ar, então '
            'mandar o tocador continuar é acender o halo sobre o silêncio');
    expect(harness.playback.played.last,
        container.read(salaSessionProvider).partes.first.path);
    expect(harness.playback.playedFrom.last, Duration.zero,
        reason: 'e do começo, como do outro lado da porta');
  });

  test('a restart the room refused does not open the passage anyway', () async {
    final harness = SalaHarness()..room.failRestartWith = const RoomRefused();

    final container = await _reopen(
      harness,
      parouEm: SalaStage.retro,
      contado: _traduzidos,
      semAudio: true,
    );

    expect(harness.room.calls, isNot(contains('openSession')),
        reason: 'a sessão ainda guarda os trechos, e entrar na conversa é pôr a '
            'equipe a caminho de contar a passagem por cima deles');
    expect(container.read(salaSessionProvider).needsPerson, isTrue,
        reason: 'e parar calado deixa a equipe tocando de novo sem entender por '
            'que nada acontece');
  });

  test('a telling-back the team can pick back up throws nothing away',
      () async {
    final harness = SalaHarness();

    final container = await _reopen(
      harness,
      parouEm: SalaStage.retro,
      contado: _traduzidos,
    );

    expect(harness.room.restartsAsked, isEmpty,
        reason: 'os trechos que o servidor guarda são os que a equipe está '
            'voltando para continuar, e descartá-los é mandar traduzir de novo '
            'o que já estava contado');
    expect(container.read(salaSessionProvider).stage, SalaStage.retro);
  });

  test('a team that stopped at the rehearsal still lands on the rehearsal',
      () async {
    final harness = SalaHarness();

    final container = await _reopen(
      harness,
      parouEm: SalaStage.ensaio,
      contado: _traduzidos,
    );

    final state = container.read(salaSessionProvider);
    expect(state.stage, SalaStage.ensaio,
        reason: 'o ponto de retomada é quem diz o estágio; trechos no servidor '
            'não arrastam para a retro quem parou antes dela');
    expect(state.ensaio, EnsaioStatus.idle);
  });

  test('telling one more stretch back carries on from the ones already told',
      () async {
    final harness = SalaHarness();
    final container = await _reopen(
      harness,
      parouEm: SalaStage.retro,
      contado: _traduzidos,
    );
    final notifier = container.read(salaSessionProvider.notifier);

    harness.playback.at = const Duration(seconds: 44);
    notifier.cortarTrecho();
    await settle();
    notifier.retroTap();
    await settle();

    expect(harness.room.chunkSpans, ['30000-44000'],
        reason: 'recomeçar do zero manda um segundo conjunto de trechos para a '
            'mesma passada, e o analista recebe a passagem contada duas vezes');
    expect(harness.room.chunkTakes, [_gravacao],
        reason: 'e continua sendo a mesma gravação que ele fatia');
  });

  test('cutting over ground already told back tells the room nothing', () async {
    final harness = SalaHarness();
    final container = await _reopen(
      harness,
      parouEm: SalaStage.retro,
      contado: _traduzidos,
    );
    final notifier = container.read(salaSessionProvider.notifier);

    harness.playback.at = const Duration(seconds: 8);
    notifier.cortarTrecho();
    await settle();
    notifier.retroTap();
    await settle();

    expect(harness.room.chunkSpans, isEmpty,
        reason: 'nenhum gesto da retro nasce atrás do cursor — só a mão que '
            'escreve a posição nesta linha chega a este estado —, mas a posição '
            'vem do player, e um player que responda de trás manda um trecho '
            'que termina antes de começar');

    harness.playback.at = const Duration(seconds: 44);
    notifier.cortarTrecho();
    await settle();
    notifier.retroTap();
    await settle();

    expect(harness.room.chunkSpans, ['30000-44000'],
        reason: 'o corte recusado não pode arrastar o cursor para trás e sujar '
            'todo trecho que vier depois dele');
  });
}
